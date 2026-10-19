import SwiftUI
import UniformTypeIdentifiers

struct PatternDesignView: View {
    @State private var design = GarmentDesignSpec()
    @State private var generated: NativePatternDocument?
    @State private var validationMessages: [String] = []
    @State private var showingOfficialPreview = false
    @State private var showingOfficialImporter = false
    @State private var officialDocument: GarmentCodePatternFile?
    @State private var officialJSON = ""

    var body: some View {
        Form {
            Section {
                Text("先选择需要组合的款式组件，再设置相应参数。组件名称和选项对应 GarmentCode 的官方 configurator。")
                    .font(.appBody)
                    .foregroundColor(.appSubText)
            }

            Section("上衣") {
                configuratorPicker("上衣款式", selection: $design.upper, options: GarmentCodeConfigurator.uppers)
                if design.upper != nil {
                    measurementField("衣身松量", value: \.easeCm, help: "胸围/臀围的宽松量，越大越宽松")
                    measurementField("上衣长度", value: \.upperLengthCm, help: "从肩颈点到下摆的垂直长度")
                    measurementField("领宽", value: \.collarWidthCm, help: "领口横向宽度，影响领口曲线深度")
                    measurementField("领长", value: \.collarLengthCm, help: "领口纵向深度，V领/圆领的关键参数")
                    measurementField("门襟宽", value: \.buttonPlacketWidthCm, help: "前中门襟贴边的宽度")
                    measurementField("下摆弧度", value: \.hemCurveCm, help: "下摆弯曲程度，正值为弧形下摆")
                    measurementField("侧开衩", value: \.sideSlitCm, help: "侧缝下摆开衩高度")
                    measurementField("省位", value: \.dartPositionCm, help: "腰省距前中的水平距离")
                    measurementField("省宽", value: \.dartWidthCm, help: "腰省收量，越大越收腰")
                    measurementField("省长", value: \.dartLengthCm, help: "腰省纵向长度")
                }
            }

            Section("袖片") {
                if design.upper != nil {
                    measurementField("袖长（0 为无袖）", value: \.sleeveLengthCm, help: "从肩点到袖口的垂直长度")
                    measurementField("袖口围", value: \.sleeveOpeningCm, help: "袖口一周的围度")
                    measurementField("袖山高度", value: \.capHeightCm, help: "袖山最高点到底线的距离，影响袖山凸出程度")
                    measurementField("袖山宽度", value: \.capWidthCm, help: "袖山底部横向宽度")
                    measurementField("袖肥松量", value: \.sleeveEaseCm, help: "袖山宽度在上臂围基础上的加放量")
                    measurementField("袖山 pitch", value: \.sleevePitchCm, help: "袖山前后偏移量，正值向前")
                    measurementField("克夫宽度", value: \.cuffWidthCm, help: "袖口克夫（袖头）的宽度")
                    measurementField("克夫长度", value: \.cuffLengthCm, help: "袖口克夫的长度/围度")
                    measurementField("袖衩长", value: \.placketLengthCm, help: "袖口开衩的长度")
                    measurementField("袖衩宽", value: \.placketWidthCm, help: "袖口开衩的宽度")
                } else {
                    Text("选择上衣款式后可编辑袖片参数")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                }
            }

            Section("腰带 / 腰头") {
                configuratorPicker("腰带款式", selection: $design.waistband, options: GarmentCodeConfigurator.waistbands)
                if design.waistband != nil {
                    measurementField("腰头宽度", value: \.waistbandWidthCm, help: "腰头上边缘到下边缘的宽度")
                }
            }

            Section("下装") {
                configuratorPicker("裙装或裤装", selection: $design.bottom, options: GarmentCodeConfigurator.bottoms)
                if design.bottom != nil {
                    if design.bottom == .pants {
                        measurementField("裤长", value: \.pantsLengthCm, help: "从腰头到脚口的垂直长度")
                        measurementField("裆深", value: \.crotchDepthCm, help: "腰头到裆底的垂直深度")
                        measurementField("膝围", value: \.kneeWidthCm, help: "膝盖位置的横向宽度")
                        measurementField("脚口", value: \.legOpeningCm, help: "裤脚开口的宽度")
                        measurementField("门襟长", value: \.flyLengthCm, help: "前中门襟拉链/纽扣长度")
                        measurementField("省宽", value: \.dartWidthCm, help: "腰部省量，越大越收腰")
                    } else {
                        measurementField("裙长", value: \.skirtLengthCm, help: "从腰头到下摆的垂直长度")
                        if design.bottom == .asymmetricCircleSkirt {
                            measurementField("前后不对称差", value: \.frontAsymmetryCm, help: "前片比后片短的长度差")
                        }
                        if design.bottom == .circleSkirt || design.bottom == .asymmetricCircleSkirt {
                            measurementField("完整度比例", value: \.fullnessRatio, help: "圆裙展开程度，1.0=标准圆裙，>1更蓬松")
                            measurementField("下摆弧度", value: \.hemCurveCm, help: "下摆弯曲程度")
                        }
                        if design.bottom == .manyPanelSkirt || design.bottom == .twoPanelSkirt {
                            measurementField("裙摆扩展比例", value: \.flare, help: "裙摆比腰围大的倍数，越大越蓬松")
                        }
                        if design.bottom == .manyPanelSkirt {
                            Picker("裙片数", selection: $design.panelCount) {
                                ForEach(4...16, id: \.self) { Text("\($0) 片").tag($0) }
                            }
                            Text("裙片数量，越多裙摆越圆润")
                                .font(.appCaption)
                                .foregroundColor(.appSubText)
                        }
                        if design.bottom == .godetSkirt {
                            Picker("喇叭插片数", selection: $design.godetCount) {
                                ForEach([4, 6, 8, 10, 12], id: \.self) { Text("\($0) 片").tag($0) }
                            }
                            Text("裙摆插入的喇叭形插片数量")
                                .font(.appCaption)
                                .foregroundColor(.appSubText)
                        }
                        if design.bottom == .levelsSkirt {
                            Picker("裙层数", selection: $design.tierCount) {
                                ForEach(2...6, id: \.self) { Text("\($0) 层").tag($0) }
                            }
                            Text("层叠裙的层数")
                                .font(.appCaption)
                                .foregroundColor(.appSubText)
                        }
                        if design.bottom == .pencilSkirt {
                            measurementField("臀深", value: \.hipDepthCm, help: "腰头到臀部最宽处的垂直距离")
                            measurementField("开衩长", value: \.ventLengthCm, help: "后中或侧缝开衩长度")
                            measurementField("开衩宽", value: \.ventWidthCm, help: "开衩重叠量")
                            measurementField("省宽", value: \.dartWidthCm, help: "腰省收量，影响臀部贴合度")
                            measurementField("省长", value: \.dartLengthCm, help: "腰省纵向长度")
                            measurementField("省位", value: \.dartPositionCm, help: "腰省距侧缝的距离")
                            measurementField("拉链长", value: \.zipperLengthCm, help: "后中拉链长度")
                        }
                    }
                }
            }

            Section("人体尺寸（cm）") {
                measurementField("身高", value: \.heightCm, help: "总体身高，用于比例参考")
                measurementField("胸围", value: \.bustCm, help: "胸部最丰满处一周围度")
                measurementField("腰围", value: \.waistCm, help: "腰部最细处一周围度")
                measurementField("臀围", value: \.hipCm, help: "臀部最宽处一周围度")
                if design.upper != nil {
                    measurementField("肩宽", value: \.shoulderWidthCm, help: "左右肩峰之间的直线距离")
                    measurementField("颈围", value: \.neckCircCm, help: "颈部根部一周围度，影响领口大小")
                    measurementField("臂长", value: \.armLengthCm, help: "从肩点到手腕的长度")
                    measurementField("背长", value: \.backLengthCm, help: "后颈点到腰线的垂直长度")
                    measurementField("前长", value: \.frontLengthCm, help: "前颈点到腰线的垂直长度")
                    measurementField("上臂围", value: \.bicepCircCm, help: "上臂最粗处一周围度，影响袖肥")
                    measurementField("肘围", value: \.elbowCircCm, help: "肘部一周围度")
                    measurementField("腕围", value: \.wristCircCm, help: "手腕一周围度，影响袖口大小")
                }
                if design.bottom == .pants {
                    measurementField("裆深", value: \.riseCm, help: "腰线到裆底的垂直距离")
                    measurementField("大腿围", value: \.thighCircCm, help: "大腿最粗处一周围度")
                    measurementField("膝围", value: \.kneeCircCm, help: "膝盖一周围度")
                    measurementField("小腿围", value: \.calfCircCm, help: "小腿最粗处一周围度")
                    measurementField("踝围", value: \.ankleCircCm, help: "脚踝一周围度")
                }
            }

            Section {
                Button(action: loadBundledOfficialSample) {
                    Label("打开官方 T-shirt 样例预览", systemImage: "tshirt")
                        .frame(maxWidth: .infinity)
                }
                Button { showingOfficialImporter = true } label: {
                    Label("导入 GarmentCode 纸样 JSON", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
                Text("生成器使用 TailorAss 原生 Swift 几何，不调用 GarmentCode。官方样例仅用于对照；导入功能用于查看并原样导出官方 JSON。")
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }

            Section {
                HStack {
                    Button {
                        design = .random()
                        validationMessages = []
                        generated = nil
                    } label: {
                        Label("随机", systemImage: "dice")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        design = .default
                        validationMessages = []
                        generated = nil
                    } label: {
                        Label("默认", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section {
                Button {
                    let issues = NativeGarmentPatternGenerator.validationMessages(for: design)
                    guard issues.isEmpty else {
                        validationMessages = issues
                        return
                    }
                    let document = NativeGarmentPatternGenerator.generate(design)
                    let geometryIssues = NativeGarmentPatternGenerator.validationMessages(for: document)
                    validationMessages = geometryIssues
                    guard geometryIssues.isEmpty else { return }
                    generated = document
                } label: {
                    Label("生成 2D 纸样", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.appAccent)
                .foregroundStyle(.white)
            }

            if !validationMessages.isEmpty {
                Section("生成检查未通过") {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.appBody)
                            .foregroundStyle(.red)
                    }
                }
            }

        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("纸样设计")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingOfficialPreview) {
            if let officialDocument {
                GarmentCodePatternPreviewView(document: officialDocument, rawJSON: officialJSON)
            }
        }
        .sheet(item: $generated) { document in
            PatternDraftPreviewView(document: document)
        }
        .fileImporter(isPresented: $showingOfficialImporter, allowedContentTypes: [.json]) { result in
            importOfficialPattern(result)
        }
    }

    private func importOfficialPattern(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try presentOfficialPattern(Data(contentsOf: url))
        } catch {
            validationMessages = ["无法读取 GarmentCode JSON：\(error.localizedDescription)"]
        }
    }

    private func loadBundledOfficialSample() {
        do {
            guard let url = Bundle.main.url(forResource: "GarmentCodeTShirtSample", withExtension: "json") else {
                throw NSError(domain: "GarmentCodeSample", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "内置官方样例未打包进 App"])
            }
            try presentOfficialPattern(Data(contentsOf: url))
        } catch {
            validationMessages = ["无法打开内置官方样例：\(error.localizedDescription)"]
        }
    }

    private func presentOfficialPattern(_ data: Data) throws {
        let decoded = try GarmentCodePatternFile.validatedImport(from: data)
        officialDocument = decoded
        officialJSON = String(decoding: data, as: UTF8.self)
        showingOfficialPreview = true
        validationMessages = []
    }

    private func measurementField(_ title: String, value: WritableKeyPath<GarmentDesignSpec, Double>, help: String? = nil) -> some View {
        let binding = Binding<Double>(
            get: { design[keyPath: value] },
            set: { design[keyPath: value] = $0 }
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: binding, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("cm").foregroundColor(.appSubText)
            }
            if let help {
                Text(help)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
        }
    }

    private func configuratorPicker(_ title: String,
                                    selection: Binding<GarmentCodeConfigurator.Option?>,
                                    options: [GarmentCodeConfigurator.Option]) -> some View {
        Picker(title, selection: selection) {
            Text("不添加").tag(nil as GarmentCodeConfigurator.Option?)
            ForEach(options) { option in
                Text(option.title).tag(option as GarmentCodeConfigurator.Option?)
            }
        }
    }

}

private struct GarmentCodePatternPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let document: GarmentCodePatternFile
    let rawJSON: String
    @State private var showingFileExporter = false
    @State private var resetToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GarmentCode 纸样")
                            .font(.appTitle)
                        Text("官方 JSON · \(document.panels.count) 个裁片 · \(document.stitchCount) 组缝合 · 单位 \(document.unitsInMeter == 100 ? "cm" : "1 m = \(document.unitsInMeter, specifier: "%.0f") 单位")")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }

                    VStack(spacing: 0) {
                        HStack {
                            Text("2D 裁片预览").font(.appHeadline)
                            Spacer()
                            Button("重置视图") { resetToken += 1 }
                                .font(.appCaption)
                        }
                        .padding(.horizontal, 12).padding(.top, 10)
                        GarmentCodePatternCanvas(document: document, resetToken: resetToken)
                            .frame(height: 360)
                            .padding(10)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))

                    ForEach(document.panels, id: \.name) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.panel.displayName ?? entry.name).font(.appHeadline)
                            Text("\(entry.panel.vertices.count) 个顶点 · \(entry.panel.edges.count) 条边 · \(document.stitchCount(for: entry.name)) 条缝合边")
                                .font(.appCaption).foregroundColor(.appSubText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                    }

                    Text("此视图读取并保留官方 JSON 的 panel、曲线和 stitch 数据；当前只用于 2D 查看/原样导出，不会修改或重算上游纸样。")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))

                    ShareLink(item: rawJSON) {
                        Label("分享官方 JSON", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("官方纸样")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFileExporter = true
                    } label: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .fileExporter(isPresented: $showingFileExporter,
                          document: JSONTextDocument(text: rawJSON),
                          contentType: .json,
                          defaultFilename: "garmentcode-pattern-specification.json") { _ in }
        }
    }
}

private extension GarmentCodePatternFile {
    func stitchCount(for panelName: String) -> Int {
        pattern.stitches.reduce(0) { count, stitch in
            count + stitch.sides.filter { $0.panel == panelName }.count
        }
    }
}

private struct GarmentCodePatternCanvas: View {
    let document: GarmentCodePatternFile
    let resetToken: Int

    var body: some View {
        Canvas { context, size in
            let panels = document.panels.compactMap { entry -> (String, String, [[CGPoint]], CGRect)? in
                let edgePoints = entry.panel.edges.compactMap { edge -> [CGPoint]? in
                    guard edge.endpoints.count == 2,
                          entry.panel.vertices.indices.contains(edge.endpoints[0]),
                          entry.panel.vertices.indices.contains(edge.endpoints[1]) else { return nil }
                    let start = entry.panel.vertices[edge.endpoints[0]]
                    let end = entry.panel.vertices[edge.endpoints[1]]
                    return sampledPoints(start: start, end: end, curvature: edge.curvature)
                }
                let all = edgePoints.flatMap { $0 }
                guard edgePoints.count == entry.panel.edges.count,
                      edgePoints.allSatisfy({ $0.count >= 2 }),
                      all.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
                let bounds = CGRect(x: all.map(\.x).min() ?? 0, y: all.map(\.y).min() ?? 0,
                                    width: max(0.1, (all.map(\.x).max() ?? 1) - (all.map(\.x).min() ?? 0)),
                                    height: max(0.1, (all.map(\.y).max() ?? 1) - (all.map(\.y).min() ?? 0)))
                return (entry.name, entry.panel.displayName ?? entry.name, edgePoints, bounds)
            }
            guard !panels.isEmpty else { return }

            let gap: CGFloat = 12
            let totalWidth = panels.reduce(CGFloat.zero) { $0 + $1.3.width } + gap * CGFloat(panels.count - 1)
            let maxHeight = panels.map { $0.3.height }.max() ?? 1
            let scale = min((size.width - 24) / max(totalWidth, 1), (size.height - 44) / max(maxHeight, 1))
            guard scale.isFinite, scale > 0 else { return }
            var offsetX = (size.width - totalWidth * scale) / 2

            for (name, label, edges, bounds) in panels {
                var panelPath = Path()
                var hasFirstPoint = false
                for points in edges where points.count > 1 {
                    for (pointIndex, point) in points.enumerated() {
                        let mapped = CGPoint(x: offsetX + (point.x - bounds.minX) * scale,
                                             y: 22 + (bounds.maxY - point.y) * scale)
                        if !hasFirstPoint {
                            panelPath.move(to: mapped)
                            hasFirstPoint = true
                        } else if pointIndex != 0 {
                            panelPath.addLine(to: mapped)
                        }
                    }
                }
                panelPath.closeSubpath()
                context.fill(panelPath, with: .color(Color.appAccent.opacity(0.06)))

                for (edgeIndex, points) in edges.enumerated() where points.count > 1 {
                    var path = Path()
                    for (index, point) in points.enumerated() {
                        let mapped = CGPoint(x: offsetX + (point.x - bounds.minX) * scale,
                                             y: 22 + (bounds.maxY - point.y) * scale)
                        if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
                    }
                    let stitched = document.edgeIsStitched(panel: name, edge: edgeIndex)
                    context.stroke(path,
                                   with: .color(stitched ? Color.appAccent : Color.appText.opacity(0.78)),
                                   style: StrokeStyle(lineWidth: stitched ? 2.2 : 1.35,
                                                      lineCap: .round, lineJoin: .round,
                                                      dash: stitched ? [] : [3, 2]))
                }
                let labelText = Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.appText)
                context.draw(labelText, at: CGPoint(x: offsetX + bounds.width * scale / 2,
                                                    y: min(size.height - 8, 22 + bounds.height * scale + 13)))
                offsetX += (bounds.width + gap) * scale
            }
        }
        .accessibilityLabel("GarmentCode 官方曲线纸样预览")
        .id(resetToken)
    }

    private func sampledPoints(start: [Double], end: [Double], curvature: GarmentCodeCurvature?) -> [CGPoint] {
        guard start.count == 2, end.count == 2,
              start.allSatisfy(\.isFinite), end.allSatisfy(\.isFinite) else { return [] }
        let a = CGPoint(x: start[0], y: start[1])
        let b = CGPoint(x: end[0], y: end[1])
        guard let curvature else { return [a, b] }
        if curvature.type == "circle", let arc = curvature.circle {
            return sampleArc(from: a, to: b, radius: arc.radius, largeArc: arc.largeArc, sweep: !arc.right)
        }
        guard let controls = curvature.params else { return [a, b] }
        let controlPoints = controls.map { relativePoint($0, from: a, to: b) }
        guard controlPoints.count == 1 || controlPoints.count == 2 else { return [a, b] }
        return (0...24).map { step in
            let t = CGFloat(step) / 24
            if controlPoints.count == 1 {
                let c = controlPoints[0], u = 1 - t
                return CGPoint(x: u*u*a.x + 2*u*t*c.x + t*t*b.x,
                               y: u*u*a.y + 2*u*t*c.y + t*t*b.y)
            }
            let c1 = controlPoints[0], c2 = controlPoints[1], u = 1 - t
            return CGPoint(x: u*u*u*a.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*b.x,
                           y: u*u*u*a.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*b.y)
        }
    }

    private func relativePoint(_ relative: [Double], from start: CGPoint, to end: CGPoint) -> CGPoint {
        guard relative.count == 2 else { return start }
        let dx = end.x - start.x, dy = end.y - start.y
        return CGPoint(x: start.x + relative[0] * dx - relative[1] * dy,
                       y: start.y + relative[0] * dy + relative[1] * dx)
    }

    private func sampleArc(from start: CGPoint, to end: CGPoint, radius: Double,
                          largeArc: Bool, sweep: Bool) -> [CGPoint] {
        let rx = abs(radius)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let chordSq = dx * dx + dy * dy
        guard rx > 0, chordSq > 0 else { return [start, end] }
        let correctedRadius = max(rx, sqrt(chordSq))
        let radiusSquared = correctedRadius * correctedRadius
        let numerator = max(0, radiusSquared * radiusSquared - radiusSquared * chordSq)
        let denominator = max(1e-12, radiusSquared * chordSq)
        let sign = (largeArc == sweep) ? -1.0 : 1.0
        let coefficient = sign * sqrt(numerator / denominator)
        let cxPrime = coefficient * correctedRadius * dy / correctedRadius
        let cyPrime = coefficient * -correctedRadius * dx / correctedRadius
        let center = CGPoint(x: (start.x + end.x) / 2 + cxPrime,
                             y: (start.y + end.y) / 2 + cyPrime)
        let ux = (start.x - center.x) / correctedRadius
        let uy = (start.y - center.y) / correctedRadius
        let vx = (end.x - center.x) / correctedRadius
        let vy = (end.y - center.y) / correctedRadius
        let startAngle = atan2(uy, ux)
        var delta = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(12, Int(abs(delta) * 16))
        return (0...segments).map { step in
            let angle = startAngle + delta * Double(step) / Double(segments)
            return CGPoint(x: center.x + correctedRadius * cos(angle),
                           y: center.y + correctedRadius * sin(angle))
        }
    }
}

private struct PatternDraftPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let document: NativePatternDocument
    @State private var exportText = ""
    @State private var showingFileExporter = false
    @State private var selectedPieceID: String?
    @State private var canvasResetToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("TailorAss 原生纸样")
                        .font(.appTitle)
                        .foregroundColor(.appText)

                    Text("\(document.design.selectedComponentNames.joined(separator: " + ")) · \(document.pieces.count) 个裁片 · \(document.seams.count) 组已校验接缝 · 单位 cm")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)

                    VStack(spacing: 0) {
                        HStack {
                            Text("2D 裁片").font(.appHeadline)
                            Spacer()
                            Button("重置视图") { canvasResetToken += 1 }
                                .font(.appCaption)
                        }
                        .padding(.horizontal, 12).padding(.top, 10)
                        PatternPieceCanvas(pieces: document.pieces, selectedPieceID: selectedPieceID,
                                           resetToken: canvasResetToken)
                            .frame(height: 300)
                            .padding(10)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))

                    ForEach(document.pieces) { piece in
                        Button {
                            selectedPieceID = piece.id
                        } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(piece.name).font(.appHeadline)
                                Text("裁剪 \(piece.cutQuantity) 片 · \(Int(pieceWidth(piece))) × \(Int(pieceHeight(piece))) cm")
                                    .font(.appCaption).foregroundColor(.appSubText)
                            }
                            Spacer()
                            Text("\(piece.vertices.count) 点")
                                .font(.appCaption).foregroundColor(.appSubText)
                        }
                        .padding(12)
                        .background(selectedPieceID == piece.id ? Color.appAccent.opacity(0.12) : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                        }
                        .buttonStyle(.plain)
                    }

                    if !document.seams.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已建模接缝关系（未覆盖全部拼接接口）").font(.appHeadline)
                            ForEach(document.seams.indices, id: \.self) { index in
                                let seam = document.seams[index]
                                Text("\(seam.pieceA) / \(seam.edgeA) ↔ \(seam.pieceB) / \(seam.edgeB) · \(seam.type)")
                                    .font(.appCaption)
                                    .foregroundColor(.appSubText)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                    }

                    Text(document.disclaimer)
                        .font(.appCaption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))

                    if !exportText.isEmpty {
                        Button {
                            showingFileExporter = true
                        } label: {
                            Label("导出 JSON 文件", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appAccent)
                        ShareLink(item: exportText) {
                            Label("分享 JSON 文本", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("纸样预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFileExporter = true
                    } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(exportText.isEmpty)
                }
            }
            .fileExporter(isPresented: $showingFileExporter,
                          document: JSONTextDocument(text: exportText),
                          contentType: .json,
                          defaultFilename: "tailorass-native-pattern.json") { _ in }
            .onAppear(perform: encodeDocument)
        }
    }

    private func pieceWidth(_ piece: GeneratedPatternPiece) -> Double {
        (piece.vertices.map(\.x).max() ?? 0) - (piece.vertices.map(\.x).min() ?? 0)
    }

    private func pieceHeight(_ piece: GeneratedPatternPiece) -> Double {
        (piece.vertices.map(\.y).max() ?? 0) - (piece.vertices.map(\.y).min() ?? 0)
    }

    private func encodeDocument() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(document) {
            exportText = String(decoding: data, as: UTF8.self)
        }
    }
}

private struct JSONTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct PatternPieceCanvas: View {
    let pieces: [GeneratedPatternPiece]
    let selectedPieceID: String?
    let resetToken: Int
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        Canvas { context, size in
            guard !pieces.isEmpty else { return }
            let gap: CGFloat = 6
            let widths = pieces.map { CGFloat($0.vertices.map(\.x).max() ?? 0) }
            let heights = pieces.map { CGFloat($0.vertices.map(\.y).max() ?? 0) }
            let totalWidth = widths.reduce(0, +) + gap * CGFloat(max(0, pieces.count - 1))
            let maxHeight = heights.max() ?? 1
            let scale = min((size.width - 24) / max(totalWidth, 1), (size.height - 40) / max(maxHeight, 1))
            guard scale > 0 else { return }
            var xOffset = (size.width - totalWidth * scale) / 2

            for (index, piece) in pieces.enumerated() {
                let vertexByID = Dictionary(uniqueKeysWithValues: piece.vertices.map { ($0.id, $0) })
                // 按边采样（曲线边用 EdgeGeometry.sample，跳过每边起点避免重复）
                var outline: [CGPoint] = []
                for edge in piece.edges {
                    guard let from = vertexByID[edge.fromVertex], let to = vertexByID[edge.toVertex] else { continue }
                    let pts = EdgeGeometry.sample(from: (from.x, from.y), to: (to.x, to.y), curve: edge.curve)
                    outline += pts.dropFirst().map { CGPoint(x: xOffset + $0.0 * scale, y: 20 + $0.1 * scale) }
                }
                var path = Path()
                if let first = outline.first {
                    path.move(to: first)
                    for pt in outline.dropFirst() { path.addLine(to: pt) }
                }
                path.closeSubpath()
                let isSelected = selectedPieceID == piece.id
                context.fill(path, with: .color(Color.appAccent.opacity(isSelected ? 0.30 : 0.14)))
                context.stroke(path, with: .color(isSelected ? .red : .appAccent), lineWidth: isSelected ? 2.5 : 1.5)
                let label = Text(piece.name.replacingOccurrences(of: "（原型示意）", with: ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.appText)
                context.draw(label, at: CGPoint(x: xOffset + widths[index] * scale / 2,
                                                y: min(size.height - 8, 20 + heights[index] * scale + 12)))
                xOffset += (widths[index] + gap) * scale
            }
        }
        .scaleEffect(clampedZoom(zoom * magnification))
        .offset(pan)
        .clipped()
        .simultaneousGesture(
            MagnificationGesture()
                .updating($magnification) { value, state, _ in state = value }
                .onEnded { value in zoom = clampedZoom(zoom * value) }
        )
        .simultaneousGesture(
            DragGesture().onChanged { value in
                pan = CGSize(width: dragStart.width + value.translation.width,
                             height: dragStart.height + value.translation.height)
            }.onEnded { _ in dragStart = pan }
        )
        .onChange(of: resetToken) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) { zoom = 1; pan = .zero; dragStart = .zero }
        }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.65), 3)
    }
}
