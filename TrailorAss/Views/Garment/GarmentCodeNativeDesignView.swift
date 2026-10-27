import SwiftUI
import UniformTypeIdentifiers

private struct GarmentCodeDesignGroup: Identifiable {
    let group: String
    let title: String
    var id: String { group }
}

private struct GarmentCodePreviewPresentation: Identifiable {
    let id = UUID()
    let document: GarmentCodePatternFile
    let rawJSON: String
    let exportURL: URL
    let contourIssues: [String]
}

/// GarmentCode-style parameter-first workflow. Controls are sourced from the
/// pinned parameter catalog; no local prototype dimensions are used here.
struct GarmentCodeNativeDesignView: View {
    private enum EditingMode: String, CaseIterable, Identifiable {
        case basic = "基础", advanced = "高级"
        var id: String { rawValue }
    }
    private enum InputFocus: Hashable {
        case length(GarmentCodeBasicDesign.Field), body(String)
    }
    @State private var catalog: GarmentCodeParameterCatalog?
    @State private var design: GarmentCodeDesignParameters?
    @State private var bodyValues: [String: Double] = [:]
    @State private var validation: [String] = []
    @State private var previewPresentation: GarmentCodePreviewPresentation?
    @State private var importingPattern = false
    @State private var mode: EditingMode = .basic
    @State private var editingBody = false
    @State private var basicLengthDrafts: [GarmentCodeBasicDesign.Field: String] = [:]
    @State private var basicInputIssues: [String] = []
    @State private var showingValidation = false
    @FocusState private var inputFocus: InputFocus?

    var body: some View {
        Group {
            if let catalog, design != nil {
                Form {
                    modeIntroduction
                    if mode == .basic { basicBodySection }
                    Section("款式组件") {
                        parameterGroup("meta", title: "款式选择")
                    }
                    if mode == .basic {
                        basicLengthsSection
                        basicUpperOptions
                        advancedCustomizationSection(catalog)
                    } else {
                        ForEach(activeGroups(catalog: catalog)) { item in
                            Section(item.title) { parameterGroup(item.group, title: item.title) }
                        }
                        Section("人体尺寸") { bodyMeasurementFields }
                    }
                    Section {
                        Button("导入纸样 JSON 文件") { importingPattern = true }
                        Button("恢复默认参数") { resetParameters(catalog) }
                            .frame(maxWidth: .infinity)
                    }
                    if !validation.isEmpty {
                        Section("生成检查未通过") {
                            ForEach(validation, id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            }
                        }
                    }
                    if mode == .basic, !basicInputIssues.isEmpty {
                        Section("长度输入需修正") {
                            ForEach(basicInputIssues, id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            }
                            Button("放弃长度输入，恢复当前参数显示") {
                                inputFocus = nil
                                basicLengthDrafts = [:]
                                basicInputIssues = []
                                validation = []
                            }
                        }
                    }
                    Section {
                        Button(action: generate) {
                            Label("生成 2D 纸样", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity)
                        }
                        .listRowBackground(Color.appAccent)
                        .foregroundStyle(.white)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.appBackground)
                .navigationTitle("纸样设计")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Link(destination: GarmentCodeHelp.url(for: .home)) {
                            Label("帮助", systemImage: "questionmark.circle")
                        }
                        .accessibilityLabel("纸样设计图文帮助，打开网站")
                        .accessibilityHint("当前为私有预览，需要网站所有者账号登录")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("编辑模式", selection: Binding(get: { mode }, set: { changeMode($0) })) {
                                ForEach(EditingMode.allCases) { item in
                                    Text("\(item.rawValue)模式").tag(item)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(mode.rawValue)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                        .accessibilityLabel("切换纸样设计模式，当前\(mode.rawValue)模式")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起键盘") { inputFocus = nil }
                    }
                }
            } else if !validation.isEmpty {
                ContentUnavailableView {
                    Label("参数目录无法加载", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(validation.joined(separator: "\n"))
                } actions: {
                    Button("重试") {
                        validation = []
                        catalog = nil
                        loadCatalog()
                    }
                }
            } else {
                ProgressView("正在加载款式参数…")
                    .task { loadCatalog() }
            }
        }
        .sheet(item: $previewPresentation) { presentation in
            GarmentCodePatternPreviewView(document: presentation.document,
                                          rawJSON: presentation.rawJSON,
                                          exportURL: presentation.exportURL,
                                          contourIssues: presentation.contourIssues)
        }
        .sheet(isPresented: $editingBody) { bodyEditor }
        .alert("请检查输入", isPresented: $showingValidation) {
            Button("返回修改", role: .cancel) { }
        } message: {
            Text(validation.joined(separator: "\n"))
        }
        .onChange(of: validation) { _, issues in
            if !issues.isEmpty, catalog != nil { showingValidation = true }
        }
        .task { if catalog == nil { loadCatalog() } }
        .fileImporter(isPresented: $importingPattern, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let document = try GarmentCodePatternFile.validatedImport(from: data)
                try present(document, data: data)
            } catch is DecodingError {
                validation = ["文件格式不正确，请选择兼容的纸样 JSON 文件。"]
            } catch {
                validation = ["导入失败：\(error.localizedDescription)"]
            }
        }
    }

    private var modeIntroduction: some View {
        Section {
            Text(mode == .basic
                 ? "选择款式，核对人体尺寸，再用厘米调整长度。未展开的设计沿用当前参数，可在右上角切换高级模式。"
                 : "完整 GarmentCode 参数。基础与高级共用同一份款式及人体数据，切换不会恢复默认。")
                .font(.appBody).foregroundStyle(Color.appSubText)
            Link(destination: GarmentCodeHelp.url(for: mode == .basic ? .basic : .parameters)) {
                Label(mode == .basic ? "基础模式图文帮助" : "查看版型与参数说明", systemImage: "book.closed")
            }
            Text("帮助网站目前仅供你私有预览，打开后需使用拥有访问权限的账号登录。不会上传当前量体或设计数据。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private var basicBodySection: some View {
        Section("人体尺寸") {
            HStack {
                ForEach(["bust", "waist", "hips"], id: \.self) { key in
                    VStack(spacing: 4) {
                        Text(GarmentCodeChinese.body[key]?.title ?? key).font(.appCaption)
                        Text("\((bodyValues[key] ?? 0).formatted(.number.precision(.fractionLength(0...1)))) cm")
                            .font(.appBody)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button("编辑全部人体尺寸（\(bodyKeys.count) 项）", systemImage: "person.crop.rectangle") {
                inputFocus = nil
                editingBody = true
            }
            let different = bodyKeys.filter { bodyValues[$0] != catalog?.body[$0] }.count
            Label(different == 0
                  ? "当前为示例人体尺寸，仅供测试。正式制版前请逐项量体并核对。"
                  : "已有 \(different) 项与示例不同；其余数值仍与示例一致，请逐项核对，不会按身高自动估算。",
                  systemImage: "exclamationmark.circle")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private var bodyMeasurementFields: some View {
        Group {
            ForEach(bodyKeys, id: \.self) { key in bodyField(key) }
            Text("腿长、腰线离地高度等派生尺寸，会根据上面的测量值自动计算。两种模式共用全部量体数据。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private var bodyEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Text("请按每项说明量体。未修改的示例数值不代表你的个人尺寸；程序不会根据身高猜测其余围度。修改会同步到基础和高级模式。")
                        .font(.appCaption).foregroundStyle(Color.appSubText)
                }
                Section("完整量体数据") { bodyMeasurementFields }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground)
            .navigationTitle("人体尺寸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { inputFocus = nil; editingBody = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { inputFocus = nil }
                }
            }
        }
    }

    private var basicOverviewResult: Result<GarmentCodeBasicDesign.Overview, Error> {
        Result {
            guard let design else { throw basicError("参数尚未加载。") }
            return try GarmentCodeBasicDesign.overview(body: .init(values: bodyValues), design: design)
        }
    }

    private var basicLengthsSection: some View {
        Section("厘米尺寸") {
            switch basicOverviewResult {
            case let .success(overview):
                ForEach(overview.controls) { control in basicLengthField(control) }
                ForEach(overview.notices, id: \.self) { notice in
                    Text(notice).font(.appCaption).foregroundStyle(Color.appSubText)
                }
                if overview.controls.isEmpty {
                    if overview.notices.isEmpty {
                        Text("请先选择上衣、下装或腰头。")
                            .font(.appCaption).foregroundStyle(Color.appSubText)
                    } else {
                        Button("前往高级参数") { changeMode(.advanced) }
                    }
                }
            case let .failure(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.appCaption).foregroundStyle(.red)
            }
            Text("长度按各字段标注的起止位置量取，不含缝份和下摆折边余量；不同款式的量法不能混用。")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private func basicLengthField(_ control: GarmentCodeBasicDesign.Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title)
                Spacer()
                TextField(control.title, text: Binding(get: {
                    basicLengthDrafts[control.field] ?? lengthText(control.valueCM)
                }, set: { text in
                    basicLengthDrafts[control.field] = text
                    refreshBasicDrafts()
                }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 95)
                .focused($inputFocus, equals: .length(control.field))
                Text("cm").font(.appCaption).foregroundStyle(Color.appSubText)
            }
            Text(control.detail).font(.appCaption).foregroundStyle(Color.appSubText)
            Text("范围：\(lengthText(ceil(control.rangeCM.lowerBound * 1_000) / 1_000))～\(lengthText(floor(control.rangeCM.upperBound * 1_000) / 1_000)) cm")
                .font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    @ViewBuilder
    private var basicUpperOptions: some View {
        if let design, selected(design, ["meta", "upper"]) == "Shirt" {
            Section("上衣基础选项") {
                Picker("宽松程度", selection: Binding(get: {
                    regularEaseValue(design.value(at: ["shirt", "width"])?.numberValue) ?? -1
                }, set: { value in
                    if value > 0 { setDesignValue(.number(value), at: ["shirt", "width"]) }
                })) {
                    ForEach([1.05, 1.15, 1.25], id: \.self) { ratio in
                        let title = ratio == 1.05 ? "常规" : ratio == 1.15 ? "宽松" : "更宽松"
                        Text("\(title)（胸围加 \(lengthText((bodyValues["bust"] ?? 0) * (ratio - 1))) cm）").tag(ratio)
                    }
                    if regularEaseValue(design.value(at: ["shirt", "width"])?.numberValue) == nil {
                        Text("高级自定义（保留）").tag(-1.0)
                    }
                }
                Toggle("添加袖子", isOn: Binding(get: {
                    design.value(at: ["sleeve", "sleeveless"]) == .bool(false)
                }, set: { enabled in
                    setDesignValue(.bool(!enabled), at: ["sleeve", "sleeveless"])
                }))
                .tint(Color.appAccent)
                Text("仅在选取选项时修改该参数，不重设领口、袖口或其他高级设计。有袖时保留当前袖长，精调请切换高级。宽松选项不代表已验证个人合体。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            }
        }
    }

    private func advancedCustomizationSection(_ catalog: GarmentCodeParameterCatalog) -> some View {
        let paths = design.map { design in
            GarmentCodeBasicDesign.customParameterPaths(design: design, catalog: catalog,
                                                       body: .init(values: bodyValues)).filter {
                !($0 == ["shirt", "width"] && selected(design, ["meta", "upper"]) == "Shirt" &&
                  regularEaseValue(design.value(at: $0)?.numberValue) != nil)
            }
        } ?? []
        return Section("设计参数保留") {
            if paths.isEmpty {
                Text("其他款式参数沿用默认或基础选项；需要调整领口、袖型、腰位、裙摆等细节时，可切换高级。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
            } else {
                Label("已使用高级自定义（\(paths.count) 项）", systemImage: "slider.horizontal.3")
                Text("这些设置会继续用于生成，切换模式不会覆盖。")
                    .font(.appCaption).foregroundStyle(Color.appSubText)
                DisclosureGroup("查看保留的参数") {
                    ForEach(paths, id: \.self) { path in
                        Text(GarmentCodeChinese.parameter(path)?.title ?? "自定义设计参数")
                            .font(.appCaption)
                    }
                }
            }
            Button("查看高级参数") { changeMode(.advanced) }
        }
    }

    private func regularEaseValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return [1.05, 1.15, 1.25].first { abs($0 - value) < 1e-9 }
    }

    private func lengthText(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)).grouping(.never))
    }

    private func basicError(_ message: String) -> NSError {
        NSError(domain: "GarmentCodeBasicInput", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func projectedBasicDesign() throws -> GarmentCodeDesignParameters {
        guard var updated = design else { throw basicError("参数尚未加载。") }
        let body = GarmentCodeBodyParameters(values: bodyValues)
        let overview = try GarmentCodeBasicDesign.overview(body: body, design: updated)
        let available = Set(overview.controls.map(\.field))
        guard Set(basicLengthDrafts.keys).isSubset(of: available) else {
            throw basicError("人体或组件变化后，已填写的长度暂时无法可靠换算。请修正人体数据，或明确放弃长度输入后再使用高级参数；不会忽略该长度直接生成。")
        }
        for control in overview.controls {
            guard let draft = basicLengthDrafts[control.field] else { continue }
            let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ".")
            guard let value = Double(normalized), value.isFinite else {
                throw basicError("“\(control.title)”必须是有效的厘米数。")
            }
            try GarmentCodeBasicDesign.setLength(cm: value, for: control.field, body: body, design: &updated)
        }
        return updated
    }

    private func refreshBasicDrafts() {
        validation = []
        do {
            design = try projectedBasicDesign()
            basicInputIssues = []
        } catch {
            basicInputIssues = [error.localizedDescription]
        }
    }

    private func changeMode(_ newMode: EditingMode) {
        guard newMode != mode else { return }
        if mode == .basic, !basicLengthDrafts.isEmpty {
            refreshBasicDrafts()
            if !basicInputIssues.isEmpty {
                validation = basicInputIssues + ["请先修正当前长度，再切换模式；其他设计参数未被重置。"]
                return
            }
        }
        inputFocus = nil
        basicInputIssues = []
        validation = []
        mode = newMode
    }

    private func setDesignValue(_ value: JSONValue, at path: [String]) {
        if mode == .basic, !basicInputIssues.isEmpty {
            validation = basicInputIssues + ["请先修正长度，再修改款式选项。"]
            return
        }
        _ = design?.setValue(value, at: path)
        if mode == .advanced {
            // Explicit professional edits become authoritative. A pure mode
            // switch, however, retains centimetre targets for later body edits.
            basicLengthDrafts = [:]
            basicInputIssues = []
        } else if path.first == "meta" {
            // Adding a waistband must not lose an independently entered skirt
            // length. Only a replacement of that component drops its target.
            switch path.last {
            case "upper": basicLengthDrafts.removeValue(forKey: .upperLength)
            case "bottom": basicLengthDrafts.removeValue(forKey: .lowerLength)
            case "wb": basicLengthDrafts.removeValue(forKey: .waistbandHeight)
            default: break
            }
        }
        validation = []
        if mode == .basic { refreshBasicDrafts() }
    }

    private var bodyKeys: [String] {
        guard let catalog else { return [] }
        let keys = catalog.body.keys.filter { !$0.hasPrefix("_") }
        return GarmentCodeChinese.bodyOrder.filter { keys.contains($0) } +
            keys.filter { !GarmentCodeChinese.bodyOrder.contains($0) }.sorted()
    }

    private func loadCatalog() {
        guard catalog == nil else { return }
        do {
            guard let url = Bundle.main.url(forResource: "GarmentCodeParameterCatalog", withExtension: "json") else {
                throw NSError(domain: "GarmentCodeCatalog", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "官方参数目录未包含在 App 中"])
            }
            let loaded = try GarmentCodeParameterCatalog.load(from: url)
            catalog = loaded
            design = GarmentCodeDesignParameters(catalog: loaded)
            bodyValues = loaded.body
        } catch {
            validation = ["无法加载 GarmentCode 参数：\(error.localizedDescription)"]
        }
    }

    private func resetParameters(_ catalog: GarmentCodeParameterCatalog) {
        inputFocus = nil
        design = GarmentCodeDesignParameters(catalog: catalog)
        bodyValues = catalog.body
        basicLengthDrafts = [:]
        basicInputIssues = []
        validation = []
        previewPresentation = nil
    }

    private func activeGroups(catalog: GarmentCodeParameterCatalog) -> [GarmentCodeDesignGroup] {
        guard let design else { return [] }
        let upper = selected(design, ["meta", "upper"])
        let waistband = selected(design, ["meta", "wb"])
        let bottom = selected(design, ["meta", "bottom"])
        var groups: [String] = []
        if upper != nil { groups += ["shirt", "collar", "sleeve", "left"] }
        if waistband != nil { groups.append("waistband") }
        switch bottom {
        case "SkirtCircle", "AsymmSkirtCircle": groups.append("flare-skirt")
        case "SkirtManyPanels": groups.append("flare-skirt")
        case "Skirt2": groups.append("skirt")
        case "GodetSkirt":
            groups.append("godet-skirt")
            groups.append(selected(design, ["godet-skirt", "base"]) == "PencilSkirt"
                          ? "pencil-skirt" : "skirt")
        case "Pants": groups.append("pants")
        case "PencilSkirt": groups.append("pencil-skirt")
        case "SkirtLevels":
            groups.append("levels-skirt")
            for style in [selected(design, ["levels-skirt", "base"]),
                          selected(design, ["levels-skirt", "level"])] {
                switch style {
                case "PencilSkirt": groups.append("pencil-skirt")
                case "Skirt2": groups.append("skirt")
                case "SkirtCircle", "AsymmSkirtCircle": groups.append("flare-skirt")
                default: break
                }
            }
        default: break
        }
        let titles: [String: String] = ["shirt": "上衣", "collar": "领口与领部组件", "sleeve": "袖子与袖口",
            "left": "左侧独立设置", "waistband": "腰头", "skirt": "双片裙", "flare-skirt": "圆裙与拼接裙",
            "godet-skirt": "三角插片裙", "pencil-skirt": "铅笔裙", "levels-skirt": "层叠裙", "pants": "裤装"]
        var seen: Set<String> = []
        return groups.filter { seen.insert($0).inserted && catalog.design[$0] != nil }
            .map { GarmentCodeDesignGroup(group: $0, title: titles[$0] ?? $0) }
    }

    private func selected(_ design: GarmentCodeDesignParameters, _ path: [String]) -> String? {
        guard case let .string(value)? = design.value(at: path), !value.isEmpty else { return nil }
        return value
    }

    @ViewBuilder
    private func parameterGroup(_ group: String, title: String) -> some View {
        if let node = design?.design[group] {
            ForEach(node.children.keys.sorted(), id: \.self) { key in
                if let child = node.children[key] {
                    parameterField(path: [group, key], node: child)
                }
            }
        } else {
            Text("此款式暂无可配置参数").foregroundStyle(Color.appSubText)
        }
    }

    @ViewBuilder
    private func parameterField(path: [String], node: GarmentCodeParameterNode) -> some View {
        if node.type != nil, node.hasValueKey, let design {
            OfficialGarmentCodeParameterField(
                path: path, node: node,
                value: Binding(get: { design.value(at: path) ?? .null }, set: { value in
                    setDesignValue(value, at: path)
                })
            )
        } else if !node.children.isEmpty {
            ForEach(node.children.keys.sorted(), id: \.self) { key in
                if let child = node.children[key] {
                    recursiveParameterField(path: path + [key], node: child)
                }
            }
        }
    }

    private func recursiveParameterField(path: [String], node: GarmentCodeParameterNode) -> AnyView {
        if node.type != nil, node.hasValueKey, let design {
            return AnyView(OfficialGarmentCodeParameterField(
                path: path, node: node,
                value: Binding(get: { design.value(at: path) ?? .null }, set: { value in
                    setDesignValue(value, at: path)
                })
            ))
        }
        return AnyView(ForEach(node.children.keys.sorted(), id: \.self) { key in
            if let child = node.children[key] {
                recursiveParameterField(path: path + [key], node: child)
            }
        })
    }

    private func bodyField(_ key: String) -> some View {
        let field = GarmentCodeChinese.body[key] ?? .init(key, "人体测量值。", "cm")
        let binding = Binding<Double>(get: { bodyValues[key] ?? 0 }, set: { newValue in
            bodyValues[key] = newValue
            validation = []
            if mode == .basic, !basicLengthDrafts.isEmpty {
                refreshBasicDrafts()
            } else if mode == .advanced {
                basicLengthDrafts = [:]
                basicInputIssues = []
            }
        })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.title)
                Spacer()
                TextField(field.title, value: binding, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(maxWidth: 130)
                    .focused($inputFocus, equals: .body(key))
                Text(field.unit).font(.appCaption).foregroundStyle(Color.appSubText)
            }
            Text(field.detail).font(.appCaption).foregroundStyle(Color.appSubText)
        }
    }

    private func generate() {
        inputFocus = nil
        if mode == .basic {
            refreshBasicDrafts()
            if !basicInputIssues.isEmpty { validation = basicInputIssues; return }
        }
        guard let design else { return }
        let body = GarmentCodeBodyParameters(values: bodyValues)
        var issues = design.validationMessages { GarmentCodeChinese.parameter($0)?.title ?? "设计参数" }
        for key in bodyValues.keys.sorted() {
            if let value = bodyValues[key], !value.isFinite {
                issues.append("“\(GarmentCodeChinese.body[key]?.title ?? "人体尺寸")”必须是有效数值")
            }
        }
        guard issues.isEmpty else { validation = issues; return }
        do {
            let document = try GarmentCodeNativeGenerator.generate(body: body, design: design)
            let contourReport = try GarmentCodeContourDiagnostics.inspect(document)
            let contourIssues = GarmentCodeContourDiagnostics.messages(contourReport, document: document)
            guard contourIssues.isEmpty else { validation = contourIssues; return }
            let data = try JSONEncoder.garmentCodeEncoder.encode(document)
            try present(document, data: data)
        } catch let error as GarmentCodeProgramError {
            switch error {
            case .unsupportedParameter: validation = ["所选款式不支持此参数组合，请调整款式或组件后重试。"]
            case let .missingDesignParameter(name):
                validation = ["缺少“\(GarmentCodeChinese.parameter(name.components(separatedBy: "."))?.title ?? "设计参数")”"]
            case .wrongProgram: validation = ["请先选择要生成的服装款式。"]
            default: validation = [error.localizedDescription]
            }
        } catch let error as GarmentCodeGeometryError {
            switch error {
            case let .invalidPanel(name): validation = ["“\(GarmentCodeChinese.panel(name))”无法形成有效的闭合轮廓，请调整尺寸。"]
            case let .invalidPanelVertex(name, _): validation = ["“\(GarmentCodeChinese.panel(name))”的轮廓坐标无效，请调整尺寸。"]
            case let .invalidInterfaceEdge(name, _): validation = ["“\(GarmentCodeChinese.panel(name))”的接缝边无效，请调整款式组合。"]
            case .zeroLengthInterface: validation = ["连接边长度为零，请检查尺寸与款式参数。"]
            case .unmatchedStitching: validation = ["裁片接缝无法匹配，请调整相关款式参数。"]
            }
        } catch {
            validation = [error.localizedDescription]
        }
    }

    /// Keep imported bytes intact, including upstream fields this viewer does not interpret.
    private func present(_ document: GarmentCodePatternFile, data: Data) throws {
        let contourReport = try GarmentCodeContourDiagnostics.inspect(document)
        let contourIssues = GarmentCodeContourDiagnostics.messages(contourReport, document: document)
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GarmentCode-pattern-\(UUID().uuidString).json")
        try data.write(to: exportURL, options: .atomic)
        validation = []
        previewPresentation = GarmentCodePreviewPresentation(
            document: document, rawJSON: String(decoding: data, as: UTF8.self), exportURL: exportURL,
            contourIssues: contourIssues)
    }

}

private struct GarmentCodePatternPreviewView: View {
    private enum DrapeDestination: String, Identifiable {
        case wholeGarment, legacyPreview
        var id: String { rawValue }
    }
    let document: GarmentCodePatternFile
    let rawJSON: String
    let exportURL: URL
    let contourIssues: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedName: String?
    @State private var showSeams = true
    @State private var selectedSeamID: Int?
    @State private var seamsExpanded = true
    @State private var exportingPDF = false
    @State private var editingDrafting = false
    @State private var drapeDestination: DrapeDestination?
    @State private var drafting = GarmentCodeDraftingSettings()
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var liveZoom: CGFloat = 1
    @GestureState private var livePan: CGSize = .zero

    private struct Piece: Identifiable {
        let name: String
        let points: [GarmentCodePoint]
        let edges: [[GarmentCodePoint]]
        var id: String { name }
        var minX: Double { points.map(\.x).min() ?? 0 }
        var maxX: Double { points.map(\.x).max() ?? 0 }
        var minY: Double { points.map(\.y).min() ?? 0 }
        var maxY: Double { points.map(\.y).max() ?? 0 }
        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
        var area: Double {
            guard points.count > 2 else { return 0 }
            return abs(points.indices.reduce(0.0) { total, index in
                let next = points[(index + 1) % points.count]
                return total + points[index].x * next.y - next.x * points[index].y
            }) / 2
        }
    }

    private struct Placement {
        let piece: Piece
        let origin: CGPoint
    }

    private struct Layout {
        let placements: [Placement]
        let origin: CGPoint
        let scale: CGFloat
    }

    private var pieces: [Piece] {
        guard let geometry = try? document.geometryPanels() else { return [] }
        // Imported panel_order may be partial or contain duplicate names.
        // It affects presentation only and must never hide physical pieces.
        var seen: Set<String> = []
        let names = ((document.pattern.panelOrder ?? []) + geometry.keys.sorted())
            .filter { seen.insert($0).inserted }
        return names.compactMap { name in
            guard let panel = geometry[name] else { return nil }
            let edges = panel.edges.map { $0.sample(maxSegmentLength: 0.75) }
            let points = edges.flatMap { Array($0.dropLast()) }
            guard points.count >= 3 else { return nil }
            return Piece(name: name, points: points, edges: edges)
        }
    }

    private var selectedPiece: Piece? { pieces.first { $0.name == selectedName } }
    private var seamGuide: GarmentCodeSeamGuide { .init(stitches: document.pattern.stitches) }
    private var selectedSeam: GarmentCodeSeamGuide.Group? {
        selectedSeamID.flatMap { seamGuide.group(id: $0) }
    }
    private var visibleSeams: [GarmentCodeSeamGuide.Group] {
        selectedName.map { seamGuide.groups(forPanel: $0) } ?? seamGuide.groups
    }
    // Dark, distinguishable colors on the white pattern canvas. Numbers remain
    // unique when this palette repeats or colors cannot be distinguished.
    private static let seamPalette: [Color] = [
        Color(red: 0, green: 0.45, blue: 0.70), Color(red: 0.80, green: 0.28, blue: 0),
        Color(red: 0, green: 0.49, blue: 0.35), Color(red: 0.53, green: 0.28, blue: 0.65),
        Color(red: 0.70, green: 0.09, blue: 0.29), Color(red: 0, green: 0.47, blue: 0.55),
        Color(red: 0.49, green: 0.35, blue: 0), Color(red: 0.22, green: 0.30, blue: 0.63)
    ]
    private func seamColor(_ id: Int) -> Color { Self.seamPalette[id % Self.seamPalette.count] }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 10) {
                        if !contourIssues.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("裁片轮廓需要修改", systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                Text(contourIssues.joined(separator: "\n"))
                                Text("可查看并保存原始 JSON；修正后再打印或生成 3D。")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                        }
                        HStack {
                            Text("\(pieces.count) 片 · cm").font(.appCaption)
                            Spacer()
                            Button { zoom = max(0.5, zoom / 1.5) } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }.accessibilityLabel("缩小纸样")
                            Button { zoom = min(12, zoom * 1.5) } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }.accessibilityLabel("放大纸样")
                            Button("适配全图") { zoom = 1; pan = .zero }
                        }
                        .padding(.horizontal)
                        HStack {
                            Toggle("显示接缝", isOn: $showSeams)
                                .fixedSize().disabled(seamGuide.groups.isEmpty)
                                .tint(Color.appAccent)
                                .accessibilityHint("同一接缝的两条边显示相同颜色和编号")
                            Spacer()
                            Button("缝份与标记", systemImage: "scissors") { editingDrafting = true }
                                .disabled(!contourIssues.isEmpty)
                        }
                        .font(.caption)
                        .padding(.horizontal)
                        .onChange(of: showSeams) { _, visible in
                            if !visible { selectedSeamID = nil }
                        }
                        GeometryReader { proxy in
                            Canvas { context, size in drawPieces(in: &context, size: size) }
                                .background(Color.white)
                                .contentShape(Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .gesture(SpatialTapGesture().onEnded { value in
                                    select(at: value.location, size: proxy.size)
                                })
                                .simultaneousGesture(DragGesture(minimumDistance: 4)
                                    .updating($livePan) { value, state, _ in state = value.translation }
                                    .onEnded { value in
                                        pan.width += value.translation.width
                                        pan.height += value.translation.height
                                    })
                                .simultaneousGesture(MagnificationGesture()
                                    .updating($liveZoom) { value, state, _ in state = value }
                                    .onEnded { zoom = min(12, max(0.5, zoom * $0)) })
                        }
                        .frame(height: max(220, min(420, viewport.size.height * 0.45)))
                        .padding(.horizontal)
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(pieces) { piece in
                                    Button(GarmentCodeChinese.panel(piece.name)) {
                                        selectedName = piece.name
                                        selectedSeamID = nil
                                    }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .tint(selectedName == piece.name ? Color.appAccent : .secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        Group {
                            if let piece = selectedPiece {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(GarmentCodeChinese.panel(piece.name)).font(.headline)
                                    Text("宽 \(piece.width, specifier: "%.2f") cm × 高 \(piece.height, specifier: "%.2f") cm · 1 片")
                                    Text("近似面积 \(piece.area, specifier: "%.1f") cm²")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(showSeams ? "点选彩色边或接缝列表，高亮对应的两条边" : "双指缩放、拖动平移，点选裁片查看尺寸")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .frame(height: 64)
                        .padding(.horizontal)
                        if showSeams && !seamGuide.groups.isEmpty {
                            seamList
                        }
                        DisclosureGroup("查看 JSON 数据") {
                            ScrollView {
                                Text(rawJSON).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 150)
                        }.padding(.horizontal)
                        Menu {
                            exportActions
                        } label: {
                            Label("导出纸样", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("2D 纸样预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("参数") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 14) {
                        Menu {
                            Button("整衣 3D（实验）", systemImage: "tshirt") {
                                drapeDestination = .wholeGarment
                            }
                            Button("裙装与腰头预览", systemImage: "cube") {
                                drapeDestination = .legacyPreview
                            }
                        } label: {
                            Label("3D", systemImage: "cube")
                        }.disabled(!contourIssues.isEmpty)
                        .accessibilityLabel("打开 3D 预览菜单")
                        Menu {
                            exportActions
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $exportingPDF) {
            GarmentCodePDFExportView(document: document, settings: $drafting)
        }
        .sheet(isPresented: $editingDrafting) {
            GarmentCodeDraftingEditorView(document: document, settings: $drafting, selectedPanel: selectedName)
        }
        .sheet(item: $drapeDestination) { destination in
            switch destination {
            case .wholeGarment:
                GarmentCodeJointDrapeView(document: document)
            case .legacyPreview:
                GarmentCodeDrapeView(document: document)
            }
        }
    }

    @ViewBuilder
    private var exportActions: some View {
        Button("缝份与制版标记", systemImage: "scissors") { editingDrafting = true }
            .disabled(!contourIssues.isEmpty)
        Button("导出纸样 PDF", systemImage: "doc.richtext") { exportingPDF = true }
            .disabled(!contourIssues.isEmpty)
        ShareLink(item: exportURL, preview: SharePreview("GarmentCode 纸样 JSON")) {
            Label("导出纸样 JSON", systemImage: "curlybraces")
        }
    }

    private func layout(size: CGSize) -> Layout {
        let all = pieces
        let ratio = max(0.25, Double(size.width / max(size.height, 1)))
        let columns = max(1, min(all.count, Int(sqrt(Double(all.count) * ratio).rounded())))
        let rows = max(1, Int(ceil(Double(all.count) / Double(columns))))
        let cellWidth = (all.map(\.width).max() ?? 1) + 16
        let cellHeight = (all.map(\.height).max() ?? 1) + 18
        let width = cellWidth * Double(columns)
        let height = cellHeight * Double(rows)
        let fit = min(max(1, size.width - 24) / width, max(1, size.height - 40) / height)
        let scale = fit * min(12, max(0.5, zoom * liveZoom))
        let origin = CGPoint(x: (size.width - width * scale) / 2 + pan.width + livePan.width,
                             y: (size.height - height * scale) / 2 + pan.height + livePan.height)
        let placements = all.enumerated().map { index, piece in
            Placement(piece: piece, origin: CGPoint(
                x: Double(index % columns) * cellWidth + (cellWidth - piece.width) / 2,
                y: Double(index / columns) * cellHeight + 4))
        }
        return Layout(placements: placements, origin: origin, scale: scale)
    }

    private func piecePath(_ placement: Placement, layout: Layout) -> Path {
        var path = Path()
        for (index, point) in placement.piece.points.enumerated() {
            let position = screenPoint(point, placement: placement, layout: layout)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        return path
    }

    private func screenPoint(_ point: GarmentCodePoint, placement: Placement, layout: Layout) -> CGPoint {
        CGPoint(x: layout.origin.x + (placement.origin.x + point.x - placement.piece.minX) * layout.scale,
                y: layout.origin.y + (placement.origin.y + placement.piece.maxY - point.y) * layout.scale)
    }

    private func edgePath(_ points: [GarmentCodePoint], placement: Placement, layout: Layout) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = screenPoint(point, placement: placement, layout: layout)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }

    private func select(at location: CGPoint, size: CGSize) {
        let layout = layout(size: size)
        let guide = seamGuide
        if showSeams {
            var paths: [(edge: GarmentCodeSeamGuide.EdgeKey, points: [GarmentCodePoint])] = []
            for placement in layout.placements {
                for (index, points) in placement.piece.edges.enumerated() {
                    let key = GarmentCodeSeamGuide.EdgeKey(panel: placement.piece.name, edge: index)
                    guard !guide.groups(for: key).isEmpty else { continue }
                    let screen = points.map {
                        let p = screenPoint($0, placement: placement, layout: layout)
                        return GarmentCodePoint(x: p.x, y: p.y)
                    }
                    paths.append((key, screen))
                }
            }
            if let edge = GarmentCodeSeamGuide.closestEdge(
                to: .init(x: location.x, y: location.y), paths: paths, tolerance: 12) {
                let groups = guide.groups(for: edge)
                if let current = groups.firstIndex(where: { $0.id == selectedSeamID }) {
                    selectedSeamID = groups.count == 1 ? nil : groups[(current + 1) % groups.count].id
                } else { selectedSeamID = groups.first?.id }
                selectedName = edge.panel
                seamsExpanded = true
                return
            }
        }
        selectedSeamID = nil
        selectedName = layout.placements.reversed().first {
            piecePath($0, layout: layout).contains(location)
        }?.piece.name
    }

    private var seamList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let selectedSeam {
                    Text("已高亮：接缝 \(selectedSeam.number)").font(.caption.weight(.semibold))
                        .foregroundStyle(seamColor(selectedSeam.id))
                    Spacer()
                    Button("取消高亮") { selectedSeamID = nil }.font(.caption)
                } else {
                    Text("点选一组接缝查看配对边").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 24)
            DisclosureGroup("接缝（\(visibleSeams.count) 组）", isExpanded: $seamsExpanded) {
                if visibleSeams.isEmpty {
                    Text("当前裁片没有接缝").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(visibleSeams) { group in
                                Button {
                                    selectedSeamID = selectedSeamID == group.id ? nil : group.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(group.label).font(.caption.weight(.semibold))
                                            .padding(.horizontal, 7).padding(.vertical, 5)
                                            .background(seamColor(group.id).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                                        Text(group.sides.map {
                                            "\(GarmentCodeChinese.panel($0.panel)) · 第 \($0.edge + 1) 边"
                                        }.joined(separator: " ↔ "))
                                            .font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        if selectedSeamID == group.id { Image(systemName: "checkmark.circle.fill") }
                                    }
                                    .foregroundStyle(seamColor(group.id))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .background(selectedSeamID == group.id ? seamColor(group.id).opacity(0.08) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("接缝 \(group.number)：" + group.sides.map {
                                    "\(GarmentCodeChinese.panel($0.panel))第 \($0.edge + 1) 边"
                                }.joined(separator: "，与"))
                                .accessibilityValue(selectedSeamID == group.id ? "已高亮" : "未高亮")
                            }
                        }
                    }
                    .frame(height: min(124, CGFloat(visibleSeams.count) * 52))
                }
            }
            .font(.caption)
        }
        .padding(.horizontal)
    }

    private func drawPieces(in context: inout GraphicsContext, size: CGSize) {
        let layout = layout(size: size)
        let guide = seamGuide
        let selectedSeam = selectedSeamID.flatMap { guide.group(id: $0) }
        var numberRects: [CGRect] = []
        guard layout.scale.isFinite, layout.scale > 0 else { return }
        for placement in layout.placements {
            let selected = selectedName == placement.piece.name
            let paired = selectedSeam?.sides.contains { $0.panel == placement.piece.name } == true
            let path = piecePath(placement, layout: layout)
            if paired, let selectedSeam {
                context.fill(path, with: .color(seamColor(selectedSeam.id).opacity(0.08)))
            } else if selected { context.fill(path, with: .color(Color.appAccent.opacity(0.10))) }
            let baseColor = showSeams ? Color.gray.opacity(selectedSeam == nil ? 0.55 : 0.25) : Color.appAccent
            context.stroke(path, with: .color(baseColor), lineWidth: selected && !showSeams ? 2.5 : 1.2)
            if showSeams {
                for (index, points) in placement.piece.edges.enumerated() {
                    let groups = guide.groups(for: .init(panel: placement.piece.name, edge: index))
                    let activeGroup = groups.first(where: { $0.id == selectedSeamID })
                    let displayedGroups = activeGroup.map { [$0] } ?? groups
                    for (offset, group) in displayedGroups.enumerated() {
                        let active = selectedSeamID == group.id
                        let color = seamColor(group.id)
                        // Unusual imported data can reference one edge from
                        // several seams. Alternate their colors, not just the
                        // first group; tapping the edge cycles those groups.
                        let shared = displayedGroups.count > 1
                        context.stroke(edgePath(points, placement: placement, layout: layout),
                                       with: .color(color.opacity(selectedSeamID == nil || active ? 1 : 0.2)),
                                       style: StrokeStyle(lineWidth: active ? 3.5 : 2, lineCap: shared ? .butt : .round,
                                                          lineJoin: .round,
                                                          dash: shared ? [10, CGFloat(displayedGroups.count - 1) * 10] : [],
                                                          dashPhase: CGFloat(offset) * 10))
                        if selectedSeamID == nil || active {
                            drawSeamNumber(group, points: points, placement: placement, layout: layout,
                                           active: active, fraction: Double(offset + 1) / Double(displayedGroups.count + 1),
                                           bounds: CGRect(origin: .zero, size: size), occupied: &numberRects, in: &context)
                        }
                    }
                }
            }
            context.draw(Text(GarmentCodeChinese.panel(placement.piece.name)).font(.system(size: 10)).foregroundStyle(.secondary),
                         at: CGPoint(
                            x: layout.origin.x + (placement.origin.x + placement.piece.width / 2) * layout.scale,
                            y: layout.origin.y + (placement.origin.y + placement.piece.height) * layout.scale + 9))
        }
        let rulerCM = pow(10, floor(log10(80 / layout.scale)))
        let rulerWidth = rulerCM * layout.scale
        var ruler = Path()
        ruler.move(to: CGPoint(x: 14, y: size.height - 17))
        ruler.addLine(to: CGPoint(x: 14 + rulerWidth, y: size.height - 17))
        for x in [14.0, 14 + rulerWidth] {
            ruler.move(to: CGPoint(x: x, y: size.height - 21))
            ruler.addLine(to: CGPoint(x: x, y: size.height - 13))
        }
        context.stroke(ruler, with: .color(.secondary), lineWidth: 1)
        context.draw(Text("\(rulerCM.formatted()) cm").font(.system(size: 10)),
                     at: CGPoint(x: 14 + rulerWidth / 2, y: size.height - 29))
    }

    private func drawSeamNumber(_ group: GarmentCodeSeamGuide.Group, points: [GarmentCodePoint],
                                placement: Placement, layout: Layout, active: Bool,
                                fraction: Double,
                                bounds: CGRect, occupied: inout [CGRect],
                                in context: inout GraphicsContext) {
        guard points.count >= 2 else { return }
        let screen = points.map { screenPoint($0, placement: placement, layout: layout) }
        let length = zip(screen, screen.dropFirst()).reduce(0.0) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        // Tiny darts retain colored edges; their numbers become visible when
        // selected or zoomed, avoiding unreadable clusters at fit-to-page scale.
        guard active || length >= 24 else { return }
        var remaining = length * fraction
        var middle = screen[0], tangent = CGVector(dx: 1, dy: 0)
        for (a, b) in zip(screen, screen.dropFirst()) {
            let segmentLength = hypot(b.x - a.x, b.y - a.y)
            if remaining <= segmentLength, segmentLength > 0 {
                let t = remaining / segmentLength
                middle = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                tangent = CGVector(dx: (b.x - a.x) / segmentLength, dy: (b.y - a.y) / segmentLength)
                break
            }
            remaining -= segmentLength
        }
        let color = seamColor(group.id)
        let label = Text("\(group.number)").font(.system(size: 11, weight: .semibold))
            .foregroundStyle(active ? Color.white : color)
        let measured = context.resolve(label).measure(in: CGSize(width: 100, height: 24))
        var labelRect: CGRect?
        for distance in [10.0, -10, 22, -22, 34, -34] {
            let position = CGPoint(x: middle.x - tangent.dy * distance, y: middle.y + tangent.dx * distance)
            let candidate = CGRect(x: position.x - (measured.width + 8) / 2, y: position.y - 9,
                                   width: measured.width + 8, height: 18)
            guard bounds.insetBy(dx: 2, dy: 2).contains(candidate),
                  !occupied.contains(where: { $0.intersects(candidate.insetBy(dx: -2, dy: -2)) }) else { continue }
            labelRect = candidate
            break
        }
        // The full list remains available when a densely packed overview has
        // no room for a badge; zooming in reveals the omitted numbers.
        guard let rect = labelRect else { return }
        occupied.append(rect)
        let badge = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(badge, with: .color(active ? color : Color.white.opacity(0.96)))
        context.stroke(badge, with: .color(color), lineWidth: 0.8)
        context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

private struct OfficialGarmentCodeParameterField: View {
    let path: [String]
    let node: GarmentCodeParameterNode
    @Binding var value: JSONValue

    private var field: GarmentCodeChinese.Field {
        GarmentCodeChinese.parameter(path) ?? .init("设计参数", "调整此项以改变裁片造型。")
    }
    private var title: String { field.title }

    var body: some View {
        if node.type == "bool" {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(title, isOn: Binding(get: {
                    if case let .bool(enabled) = value { return enabled }
                    return false
                }, set: { value = .bool($0) }))
                guidance
            }
        } else if node.type == "select" || node.type == "select_null" {
            let range = node.range ?? []
            let options = node.type == "select_null" && !range.contains(.null)
                ? range + [.null] : range
            VStack(alignment: .leading, spacing: 2) {
                Picker(title, selection: Binding(get: {
                    String(options.firstIndex(of: value) ?? 0)
                }, set: { index in
                    if let index = Int(index), options.indices.contains(index) { value = options[index] }
                })) {
                    ForEach(options.indices, id: \.self) { index in
                        let option = options[index]
                        Text(GarmentCodeChinese.option(option, path: path)).tag(String(index))
                    }
                }
                guidance
            }
        } else if value.numberValue != nil {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                    Spacer()
                    TextField(title, value: Binding(get: { value.numberValue ?? 0 }, set: { value = .number($0) }),
                              format: .number.precision(.fractionLength(node.type == "int" ? 0...0 : 0...3)))
                        .keyboardType((node.range?.contains { ($0.numberValue ?? 0) < 0 } ?? false)
                                      ? .numbersAndPunctuation : .decimalPad)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 130)
                    if !field.unit.isEmpty { Text(field.unit).font(.appCaption).foregroundStyle(Color.appSubText) }
                }
                guidance
            }
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.detail)
            if ["float", "int"].contains(node.type ?? ""), let range = node.range, range.count == 2,
               let lower = range[0].numberValue, let upper = range[1].numberValue {
                Text("范围：\(min(lower, upper).formatted())～\(max(lower, upper).formatted())\(field.unit)")
            }
        }
        .font(.appCaption).foregroundStyle(Color.appSubText)
    }
}

private extension JSONEncoder {
    static var garmentCodeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
