import SwiftUI
import PDFKit

/// Export settings and a preview of the actual file that will be shared.
/// Canvas selection, pan and zoom are deliberately not export inputs.
struct GarmentCodePDFExportView: View {
    let document: GarmentCodePatternFile
    @Binding var settings: GarmentCodeDraftingSettings

    @Environment(\.dismiss) private var dismiss
    @State private var plan: GarmentCodePrintPlan?
    @State private var format: GarmentCodePDFFormat = .fullSize
    @State private var showSeams = true
    @State private var isPreparing = true
    @State private var isGenerating = false
    @State private var preparationError: String?
    @State private var exportError: String?
    @State private var generated: GeneratedPDF?
    @State private var editingDrafting = false
    @State private var annotationWarnings: [String] = []

    private struct GeneratedPDF {
        let url: URL
        let format: GarmentCodePDFFormat
        let pageCount: Int
        let includesAllowance: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if let generated {
                    preview(generated)
                } else if let plan {
                    settings(plan)
                } else if isPreparing {
                    ProgressView("正在准备纸样排版…")
                } else {
                    ContentUnavailableView {
                        Label("无法准备 PDF", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(preparationError ?? "请返回检查纸样后重试。")
                    } actions: {
                        Button("重试") { preparePlan() }
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(generated == nil ? "导出纸样 PDF" : "PDF 预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(isGenerating)
                }
            }
            .task { if plan == nil && preparationError == nil { preparePlan() } }
            .alert("PDF 生成失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("确定", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "请重试。")
            }
            .interactiveDismissDisabled(isGenerating)
            .sheet(isPresented: $editingDrafting) {
                GarmentCodeDraftingEditorView(document: document, settings: $settings)
            }
            .onChange(of: settings) { _, _ in
                generated = nil
                preparePlan()
            }
            .onChange(of: showSeams) { _, _ in updateAnnotationWarnings() }
        }
    }

    private func settings(_ plan: GarmentCodePrintPlan) -> some View {
        Form {
            Section {
                Label(settings.addSeamAllowance ? "原尺寸 1:1 · 逐边缝份" : "原尺寸 1:1 · 不含缝份", systemImage: "ruler")
                    .font(.appHeadline)
                Text(settings.addSeamAllowance
                     ? "实线为裁剪线，虚线为原始制版线；对折边与零缝份边两线重合。导出不受二维预览缩放、平移或筛选影响。"
                     : "导出当前全部裁片，不受预览缩放、平移和筛选影响。尚未添加缝份，请自行补足后裁布。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }

            Section("制作设置") {
                Button("编辑缝份、布纹与定位标记", systemImage: "scissors") { editingDrafting = true }
                Text("制作设置仅在当前纸样预览中保留，打印 PDF 会保留制作结果；官方纸样 JSON 不包含这些附加设置。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
                let warnings = plan.warnings + annotationWarnings
                if !warnings.isEmpty {
                    DisclosureGroup("制作提醒（\(warnings.count) 项）") {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.appCaption).foregroundStyle(Color.appSubText)
                        }
                    }
                }
            }

            Section("导出格式") {
                Picker("PDF 类型", selection: $format) {
                    ForEach(GarmentCodePDFFormat.allCases) { item in
                        Text(item == .fullSize ? "整张 1:1" : "A4 分页拼接").tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if format == .fullSize {
                    LabeledContent("页数", value: "1 页")
                    LabeledContent("纸张大小", value: sizeDescription(plan.boardSizeCM))
                    Text("全部裁片排在一张自定义尺寸的大纸上，适合交给支持原尺寸输出的绘图仪或打印店。")
                        .font(.appCaption).foregroundStyle(Color.appSubText)
                } else {
                    LabeledContent("PDF 总页数", value: "\(plan.tiles.count + 1) 页")
                    LabeledContent("拼接布局", value: "\(plan.rows) 行 × \(plan.columns) 列")
                    LabeledContent("拼接纸张", value: "A4 · 21 × 29.7 cm")
                    LabeledContent("每页纸样区域", value: "19 × 26.7 cm")
                    LabeledContent("相邻页重叠", value: "1 cm")
                    Text("包含 1 页缩略总览与校准说明，以及 \(plan.tiles.count) 页原尺寸拼接纸样。按行列页码摆放，对齐重叠区和拼接标记后固定。总览页不能用来裁布。")
                        .font(.appCaption).foregroundStyle(Color.appSubText)
                }
            }

            Section("纸样标注") {
                Toggle("显示接缝颜色与编号", isOn: $showSeams)
                    .tint(Color.appAccent)
                Text("同组接缝保留相同颜色和编号。关闭后接缝使用黑白线；已设置的制作标记、裁片名称、校准标记和打印比例不变。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }

            Section("打印前请确认") {
                Label("选择「实际大小」或 100% 比例打印", systemImage: "1.magnifyingglass")
                Label("关闭「适应页面」及自动缩放", systemImage: "arrow.down.right.and.arrow.up.left")
                Label("先量校准框：长和宽都应为 10 cm", systemImage: "checkmark.square")
                Text("请先打印校准页，用尺核对实际尺寸。确认比例后再打印全部纸样；正式裁布前核对逐边设置、省道与折边转角，并先做试样。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }

            Section {
                Button(action: generate) {
                    HStack {
                        Spacer()
                        if isGenerating { ProgressView().tint(.white) }
                        Label(isGenerating ? "正在生成 PDF…" : "生成 PDF 预览",
                              systemImage: "doc.richtext")
                        Spacer()
                    }
                }
                .listRowBackground(Color.appAccent)
                .foregroundStyle(.white)
            }
        }
        .font(.appBody)
        .scrollContentBackground(.hidden)
        .disabled(isGenerating)
    }

    private func preview(_ generated: GeneratedPDF) -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(generated.format.title) · \(generated.pageCount) 页")
                    .font(.appHeadline)
                Text(generated.includesAllowance
                     ? "原尺寸 1:1 · 实线裁剪线 / 虚线制版线。请复核制作提醒，按实际大小 / 100% 打印。"
                     : "原尺寸 1:1 · 不含缝份。预览可缩放，打印请选择实际大小 / 100%。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            GarmentCodePDFDocumentPreview(url: generated.url)
                .accessibilityLabel("纸样 PDF 预览，可缩放浏览。预览缩放不会改变打印尺寸。")

            ShareLink(item: generated.url, preview: SharePreview(generated.format.title)) {
                Label("分享或保存 PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .padding(.horizontal)

            Button("返回导出设置") { self.generated = nil }
                .font(.appBody)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
    }

    private func sizeDescription(_ size: CGSize) -> String {
        String(format: "%.1f × %.1f cm", size.width, size.height)
    }

    private func preparePlan() {
        isPreparing = true
        preparationError = nil
        do {
            plan = try GarmentCodePrintPlan(document: document, drafting: settings)
        } catch {
            plan = nil
            preparationError = error.localizedDescription
        }
        updateAnnotationWarnings()
        isPreparing = false
    }

    private func updateAnnotationWarnings() {
        annotationWarnings = plan.map {
            GarmentCodePDFExporter.annotationWarnings(plan: $0, showSeams: showSeams,
                                                       stitches: document.pattern.stitches)
        } ?? []
    }

    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        exportError = nil
        let options = GarmentCodePDFOptions(format: format, showSeams: showSeams, drafting: settings)
        Task { @MainActor in
            // Let SwiftUI present progress before the bounded native renderer.
            await Task.yield()
            defer { isGenerating = false }
            do {
                let url = try GarmentCodePDFExporter.export(document: document, options: options)
                guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                    throw NSError(domain: "GarmentCodePDF", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "生成的 PDF 无法预览，请重试。"])
                }
                generated = GeneratedPDF(url: url, format: options.format, pageCount: pdf.pageCount,
                                         includesAllowance: options.drafting.addSeamAllowance)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

private struct GarmentCodePDFDocumentPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = UIColor(white: 0.92, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.autoScales = true
        }
    }
}
