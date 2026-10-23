import SwiftUI
import CoreGraphics

/// Edits a local copy. The source JSON and the caller's settings remain intact
/// until a complete, validated manufacture preview has been built successfully.
struct GarmentCodeDraftingEditorView: View {
    let document: GarmentCodePatternFile
    @Binding private var settings: GarmentCodeDraftingSettings
    @Environment(\.dismiss) private var dismiss
    @State private var working: GarmentCodeDraftingSettings
    @State private var selectedName: String
    @State private var selectedEdge = -1
    @State private var previewPlan: GarmentCodePrintPlan?
    @State private var previewIsCurrent = false
    @State private var validationError: String?
    @State private var showingValidationError = false
    @State private var isChecking = false

    init(document: GarmentCodePatternFile,
         settings: Binding<GarmentCodeDraftingSettings>, selectedPanel: String? = nil) {
        self.document = document
        self._settings = settings
        self._working = State(initialValue: settings.wrappedValue)
        let names = Self.panelNames(document)
        self._selectedName = State(initialValue: selectedPanel.flatMap { names.contains($0) ? $0 : nil } ?? names.first ?? "")
    }

    private static func panelNames(_ document: GarmentCodePatternFile) -> [String] {
        var seen: Set<String> = []
        return ((document.pattern.panelOrder ?? []) + document.pattern.panels.keys.sorted())
            .filter { document.pattern.panels[$0] != nil && seen.insert($0).inserted }
    }

    private var names: [String] { Self.panelNames(document) }
    private var guide: GarmentCodeSeamGuide { .init(stitches: document.pattern.stitches) }
    private var sourcePanel: GarmentCodePanel? { document.pattern.panels[selectedName] }
    private var displayedPanel: GarmentCodePrintPlan.Panel? {
        previewPlan?.panels.first { $0.name == selectedName }
    }

    var body: some View {
        NavigationStack {
            Form {
                overviewSection
                allowanceSection
                panelSection
                previewSection
                edgesSection
                grainlineSection
                notchesSection
                checksSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("缝份与制版标记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isChecking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { checkAndApply() }.disabled(isChecking)
                }
            }
            .interactiveDismissDisabled(isChecking)
            .alert("制作设置未通过", isPresented: $showingValidationError) {
                Button("返回修改", role: .cancel) { }
            } message: {
                Text(validationError ?? "请检查制作设置后重试。")
            }
            .onChange(of: working) { _, _ in
                previewIsCurrent = false
                validationError = nil
            }
            .onChange(of: selectedName) { _, _ in selectedEdge = -1 }
            .task {
                guard previewPlan == nil else { return }
                updatePreview()
            }
        }
    }

    private var overviewSection: some View {
        Section {
            Text("制作设置不会修改原始制版线或纸样 JSON。应用后，打印 PDF 使用这些缝份、数量和标记设置。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
            Text("实线为新增裁剪线，虚线为原始制版线。请先做试样，确认后再裁正式面料。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private var allowanceSection: some View {
        Section("全局缝份") {
            Toggle("生成缝份与裁剪线", isOn: $working.addSeamAllowance)
                .tint(Color.appAccent)
            widthField("普通接缝宽度", value: $working.standardAllowanceCM)
            widthField("下摆折边宽度", value: $working.hemAllowanceCM)
            Text("宽度范围 0～5 cm。未单独设置的边跟随全局宽度；下摆位置须在下面逐边指定，不会自动猜测。关闭缝份不会删除逐边设置。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
            Text("同片省道边默认不加缝份，保留原始边界。本版不进行折省后的省帽修形，省道附近请人工复核。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private var panelSection: some View {
        Section("当前裁片") {
            Picker("选择裁片", selection: $selectedName) {
                ForEach(names, id: \.self) { name in
                    Text(GarmentCodeChinese.panel(name)).tag(name)
                }
            }
            Stepper(value: panelBinding(\.cutQuantity), in: 1...20) {
                Text("裁剪数量：\(working.panelSettings(selectedName).cutQuantity) 片")
            }
            Text("数量用于标注，不会自动复制裁片或生成镜像。已有左右片仍是独立裁片，请确认用布方向。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
            Button("恢复当前片设置", role: .destructive) {
                working.panels.removeValue(forKey: selectedName)
            }
        }
    }

    private var previewSection: some View {
        Section("当前片制作预览") {
            if let panel = displayedPanel {
                DraftingPanelCanvas(panel: panel, selectedEdge: selectedEdge)
                    .frame(height: 250)
                    .accessibilityLabel("\(GarmentCodeChinese.panel(panel.name))制作预览。边编号对应下方逐边设置。")
            } else {
                ContentUnavailableView("暂无制作预览", systemImage: "square.dashed",
                                       description: Text("检查设置后更新预览。"))
                    .frame(height: 180)
            }
            if let sourcePanel {
                Picker("预览高亮边", selection: $selectedEdge) {
                    Text("全部轮廓").tag(-1)
                    ForEach(sourcePanel.edges.indices, id: \.self) { index in
                        Text("第 \(index + 1) 边").tag(index)
                    }
                }
            }
            Label(previewIsCurrent ? "预览已更新" : "设置已更改，请更新预览",
                  systemImage: previewIsCurrent ? "checkmark.circle" : "arrow.clockwise")
                .font(.appCaption).foregroundStyle(previewIsCurrent ? Color.secondary : Color.appAccent)
            Button {
                updatePreview()
            } label: {
                HStack {
                    if isChecking { ProgressView() }
                    Text(isChecking ? "正在检查制作设置…" : "检查并更新制作预览")
                }
            }
            .disabled(isChecking)
            Text("边上的数字是第几条边，不是接缝组编号。密集编号会避让或省略，可选择高亮边确认位置；完成时会重新检查整套设置。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    @ViewBuilder
    private var edgesSection: some View {
        if let sourcePanel {
            Section("逐边设置") {
                ForEach(sourcePanel.edges.indices, id: \.self) { index in
                    edgeRow(index, edge: sourcePanel.edges[index])
                }
            }
        }
    }

    private func edgeRow(_ index: Int, edge: GarmentCodeEdge) -> some View {
        let groups = guide.groups(for: .init(panel: selectedName, edge: index))
        let treatment = working.treatment(panel: selectedName, edge: index, stitches: document.pattern.stitches)
        let canFold = edge.curvature == nil && groups.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(index + 1) 边").font(.appHeadline)
                Spacer()
                Text(groups.isEmpty ? "未配对" : groups.map(\.label).joined(separator: "、"))
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }
            Picker("边的用途", selection: edgeKindBinding(index)) {
                ForEach(GarmentCodeDraftingSettings.EdgeKind.allCases.filter {
                    $0 != .fold || canFold || treatment.kind == .fold
                }) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            if treatment.kind == .seam || treatment.kind == .hem {
                Toggle("单独设置此边宽度", isOn: edgeCustomEnabledBinding(index))
                    .tint(Color.appAccent)
                if treatment.customWidthCM != nil {
                    widthField("此边宽度", value: edgeCustomWidthBinding(index))
                } else {
                    Text("跟随全局：\(working.widthCM(for: treatment), specifier: "%.2f") cm")
                        .font(.appCaption).foregroundStyle(Color.appSubText)
                }
            }
            if treatment.kind == .fold {
                Text("对折边不加缝份，打印对折标记；须为整片轮廓的直线支撑边，完成时会检查。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }
        }
        .padding(.vertical, 5)
    }

    private var grainlineSection: some View {
        Section("当前片布纹线") {
            Toggle("手动设置布纹方向", isOn: grainEnabledBinding)
                .tint(Color.appAccent)
            Text("不会根据裁片形状自动推断布纹。角度按原始裁片坐标计算：0° 为横向，90° 为竖向；逆时针为正。请按面料与设计意图手动确认。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
            if working.panelSettings(selectedName).grainline != nil {
                HStack {
                    Text("布纹角度")
                    Spacer()
                    TextField("布纹角度", value: grainBinding(\.angleDegrees),
                              format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing).frame(width: 90)
                    Text("°").foregroundStyle(Color.appSubText)
                }
                grainSlider("水平位置", value: grainBinding(\.centerXRatio), range: 0...1)
                grainSlider("垂直位置", value: grainBinding(\.centerYRatio), range: 0...1)
                grainSlider("长度比例", value: grainBinding(\.lengthRatio), range: 0.1...0.9)
                Text("位置以裁片包围框比例表示，0 为原始坐标最小端、1 为最大端；预览可能上下翻转。布纹线须位于片内，无法容纳时会提示，请调整位置或缩短。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }
        }
    }

    private var notchesSection: some View {
        Section("配对定位标记") {
            Toggle("生成配对刀口 / 定位标记", isOn: $working.showNotches)
                .tint(Color.appAccent)
            Text("仅为可可靠匹配的等长接缝生成定位标记。不等长、抽褶接缝及省道须人工确认，不会强行等分为剪口。没有缝份时只作定位线，不要剪入片身。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    @ViewBuilder
    private var checksSection: some View {
        if let validationError {
            Section("检查未通过") {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(.appBody).foregroundStyle(.red)
            }
        }
        if let plan = previewPlan, !plan.warnings.isEmpty {
            Section("制作提醒") {
                ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.appCaption).foregroundStyle(Color.appSubText)
                }
            }
        }
    }

    private func widthField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text("cm").foregroundStyle(Color.appSubText)
        }
    }

    private func grainSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(Color.appSubText)
            }
            Slider(value: value, in: range).tint(Color.appAccent)
                .accessibilityLabel(title)
        }
    }

    private func panelBinding<Value>(_ keyPath: WritableKeyPath<GarmentCodeDraftingSettings.PanelSettings, Value>) -> Binding<Value> {
        Binding(get: { working.panelSettings(selectedName)[keyPath: keyPath] }, set: { newValue in
            var value = working.panelSettings(selectedName)
            value[keyPath: keyPath] = newValue
            working.panels[selectedName] = value
        })
    }

    private func edgeKindBinding(_ edge: Int) -> Binding<GarmentCodeDraftingSettings.EdgeKind> {
        Binding(get: { working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches).kind }, set: { kind in
            var treatment = working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches)
            treatment.kind = kind
            treatment.customWidthCM = nil
            working.setTreatment(treatment, panel: selectedName, edge: edge)
        })
    }

    private func edgeCustomEnabledBinding(_ edge: Int) -> Binding<Bool> {
        Binding(get: { working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches).customWidthCM != nil }, set: { enabled in
            var treatment = working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches)
            treatment.customWidthCM = enabled ? working.widthCM(for: treatment) : nil
            working.setTreatment(treatment, panel: selectedName, edge: edge)
        })
    }

    private func edgeCustomWidthBinding(_ edge: Int) -> Binding<Double> {
        Binding(get: {
            let treatment = working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches)
            return working.widthCM(for: treatment)
        }, set: { width in
            var treatment = working.treatment(panel: selectedName, edge: edge, stitches: document.pattern.stitches)
            treatment.customWidthCM = width
            working.setTreatment(treatment, panel: selectedName, edge: edge)
        })
    }

    private var grainEnabledBinding: Binding<Bool> {
        Binding(get: { working.panelSettings(selectedName).grainline != nil }, set: { enabled in
            var panel = working.panelSettings(selectedName)
            panel.grainline = enabled ? .init() : nil
            working.panels[selectedName] = panel
        })
    }

    private func grainBinding(_ keyPath: WritableKeyPath<GarmentCodeDraftingSettings.Grainline, Double>) -> Binding<Double> {
        Binding(get: { (working.panelSettings(selectedName).grainline ?? .init())[keyPath: keyPath] }, set: { newValue in
            var panel = working.panelSettings(selectedName)
            var grainline = panel.grainline ?? .init()
            grainline[keyPath: keyPath] = newValue
            panel.grainline = grainline
            working.panels[selectedName] = panel
        })
    }

    private func updatePreview() {
        guard !isChecking else { return }
        isChecking = true
        validationError = nil
        defer { isChecking = false }
        do {
            try working.validate(document: document)
            previewPlan = try GarmentCodePrintPlan(document: document, drafting: working)
            previewIsCurrent = true
        } catch {
            previewIsCurrent = false
            validationError = error.localizedDescription
            showingValidationError = true
        }
    }

    private func checkAndApply() {
        updatePreview()
        guard previewIsCurrent, validationError == nil else { return }
        settings = working
        dismiss()
    }
}

private struct DraftingPanelCanvas: View {
    let panel: GarmentCodePrintPlan.Panel
    let selectedEdge: Int

    var body: some View {
        Canvas { context, size in
            let source = panel.cutPathCM.map { panel.boundsCM.union($0.boundingBoxOfPath) } ?? panel.boundsCM
            let bounds = source.insetBy(dx: -1.5, dy: -1.5)
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                              tx: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                                              ty: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
            if let original = panel.pathCM.copy(using: &transform) {
                context.stroke(Path(original), with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let cut = panel.cutPathCM?.copy(using: &transform) {
                context.stroke(Path(cut), with: .color(Color.appAccent), lineWidth: 1.8)
            }
            for mark in panel.markingPathsCM {
                if let rendered = mark.copy(using: &transform) {
                    context.stroke(Path(rendered), with: .color(.primary), lineWidth: 1)
                }
            }
            if panel.edgePathsCM.indices.contains(selectedEdge),
               let selected = panel.edgePathsCM[selectedEdge].copy(using: &transform) {
                context.stroke(Path(selected), with: .color(.blue), lineWidth: 3)
            }
            var occupied: [CGRect] = []
            let order = panel.edgeMidpointsCM.indices.sorted {
                ($0 == selectedEdge ? 0 : 1, $0) < ($1 == selectedEdge ? 0 : 1, $1)
            }
            for index in order {
                let midpoint = panel.edgeMidpointsCM[index]
                let point = midpoint.applying(transform)
                let positions = [CGPoint(x: point.x + 10, y: point.y - 9),
                                 CGPoint(x: point.x - 10, y: point.y + 9),
                                 CGPoint(x: point.x + 10, y: point.y + 12)]
                guard let position = positions.first(where: { position in
                    let rect = CGRect(x: position.x - 10, y: position.y - 9, width: 20, height: 18)
                    return CGRect(origin: .zero, size: size).contains(rect) && !occupied.contains(where: { $0.intersects(rect) })
                }) else { continue }
                let rect = CGRect(x: position.x - 10, y: position.y - 9, width: 20, height: 18)
                occupied.append(rect)
                let badge = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(badge, with: .color(.white))
                context.stroke(badge, with: .color(index == selectedEdge ? .blue : .secondary), lineWidth: 0.5)
                context.draw(Text("\(index + 1)").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(index == selectedEdge ? Color.blue : Color.primary), at: position)
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
