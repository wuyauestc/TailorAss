import Foundation

/// Presentation-only centimetre adapters for the existing GarmentCode programs.
/// Reading this model never resets parameters. An edit changes exactly one
/// original parameter, preserving hidden professional settings and provenance.
enum GarmentCodeBasicDesign {
    enum Field: String, CaseIterable, Identifiable, Hashable {
        case upperLength, lowerLength, waistbandHeight
        var id: String { rawValue }
    }

    struct Control: Identifiable {
        let field: Field
        let title: String
        let detail: String
        let valueCM: Double
        let rangeCM: ClosedRange<Double>
        var id: Field { field }
    }

    struct Overview {
        let controls: [Control]
        let notices: [String]
    }

    enum InputError: LocalizedError {
        case invalidBody(String), unavailable, invalidLength(String)
        var errorDescription: String? {
            switch self {
            case let .invalidBody(name): "请先填写有效的“\(name)”，再设置厘米长度。"
            case .unavailable: "当前款式或组件无法用这个基础长度编辑，请在高级模式调整。"
            case let .invalidLength(message): message
            }
        }
    }

    private struct Mapping {
        let field: Field
        let path: [String]
        let title: String
        let detail: String
        let scale: Double
        let offset: Double
        let current: Double
        let range: ClosedRange<Double>
        let parameterRange: ClosedRange<Double>

        var control: Control {
            .init(field: field, title: title, detail: detail,
                  valueCM: current, rangeCM: range)
        }
    }

    static func overview(body: GarmentCodeBodyParameters,
                         design: GarmentCodeDesignParameters) throws -> Overview {
        let result = try mappings(body: body, design: design)
        return .init(controls: result.values.map(\.control), notices: result.notices)
    }

    static func setLength(cm: Double, for field: Field,
                          body: GarmentCodeBodyParameters,
                          design: inout GarmentCodeDesignParameters) throws {
        guard cm.isFinite else {
            throw InputError.invalidLength("长度必须是有效的厘米数。")
        }
        let result = try mappings(body: body, design: design)
        guard let mapping = result.values.first(where: { $0.field == field }) else {
            throw InputError.unavailable
        }
        guard mapping.range.contains(cm) else {
            let lower = String(format: "%.2f", ceil(mapping.range.lowerBound * 100) / 100)
            let upper = String(format: "%.2f", floor(mapping.range.upperBound * 100) / 100)
            throw InputError.invalidLength("\(mapping.title)须在 \(lower)～\(upper) cm 之间；不会自动截短或拉长。")
        }
        let ratio = (cm - mapping.offset) / mapping.scale
        guard ratio.isFinite,
              ratio >= mapping.parameterRange.lowerBound - 1e-10,
              ratio <= mapping.parameterRange.upperBound + 1e-10 else {
            throw InputError.invalidLength("长度无法换算，请检查人体尺寸。")
        }
        // The centimetre input has already passed strict range validation.
        // Snap only inverse-arithmetic roundoff at the original ratio boundary.
        let boundedRatio = min(mapping.parameterRange.upperBound,
                               max(mapping.parameterRange.lowerBound, ratio))
        var candidate = design
        guard candidate.setValue(.number(boundedRatio), at: mapping.path) else {
            throw InputError.unavailable
        }
        // Only the explicitly edited parameter is written back. In particular,
        // moving between modes must not normalize any existing custom value.
        design = candidate
    }

    /// Hidden *active* custom settings deserve an explicit indicator in basic
    /// mode. Inactive future components are retained but do not create a badge.
    static func customParameterPaths(design: GarmentCodeDesignParameters,
                                     catalog: GarmentCodeParameterCatalog,
                                     body: GarmentCodeBodyParameters? = nil) -> [[String]] {
        let represented = representedPaths(design,
            body: body ?? GarmentCodeBodyParameters(values: catalog.body))
        var output: [[String]] = []
        func visit(_ node: GarmentCodeParameterNode, path: [String]) {
            if node.hasValueKey, node.type != nil, isActive(path, design: design),
               !represented.contains(path.joined(separator: ".")),
               (node.value ?? .null) != (catalog.node(at: path)?.value ?? .null) {
                output.append(path)
            }
            for key in node.children.keys.sorted() {
                if let child = node.children[key] { visit(child, path: path + [key]) }
            }
        }
        for key in design.design.keys.sorted() {
            if let node = design.design[key] { visit(node, path: [key]) }
        }
        return output
    }

    private static func mappings(body: GarmentCodeBodyParameters,
                                 design: GarmentCodeDesignParameters) throws
        -> (values: [Mapping], notices: [String]) {
        var values: [Mapping] = [], notices: [String] = []
        let upper = option(design, ["meta", "upper"])
        let bottom = option(design, ["meta", "bottom"])

        if upper == "Shirt" {
            if simpleShirt(design) {
                let waistLine = try positive(body, "waist_line", title: "颈根至腰线垂直高度")
                let bustLine = try positive(body, "_bust_line", title: "胸高")
                let depth = try number(design, ["collar", "bc_depth"]) * bustLine
                let ratio = try number(design, ["shirt", "length"])
                let base = ratio * waistLine
                if depth.isFinite, depth >= 0, base - depth > 1 + 1e-8 {
                    values.append(try mapping(field: .upperLength, path: ["shirt", "length"],
                        title: "后中衣长", detail: "从后领口缝线中心沿后中线垂直量至衣摆，不含领片、缝份和折边余量；不是肩颈点衣长。",
                        scale: waistLine, offset: -depth, minimum: 1.01, design: design))
                } else {
                    notices.append("后领深已触及衣身长度限幅，无法唯一换算后中衣长；请在高级模式调整领深或衣长。")
                }
            } else {
                notices.append("不对称上衣或带独立领片／帽片的款式保留高级设置；本页不替它们猜测统一衣长，请到高级模式调整。")
            }
        } else if upper == "FittedShirt" {
            notices.append("合体上衣按人体前后腰节与省道制版，不使用宽松上衣的衣长倍率；本版请在高级模式调整其结构。")
        }

        let hipLine: Double
        let legLength: Double
        if bottom != nil {
            hipLine = try positive(body, "hips_line", title: "腰线至臀线高度")
            legLength = try positive(body, "_leg_length", title: "派生腿长（请核对身高、头高和腰臀高度）")
        } else { hipLine = 0; legLength = 0 }

        func lower(_ group: String, title: String, detail: String,
                   minimum: Double = 5, forceNaturalWaist: Bool = false,
                   clampAtFive: Bool = false) throws {
            let rise = forceNaturalWaist && upper == "FittedShirt"
                ? 1 : try number(design, [group, "rise"])
            guard rise.isFinite, (0...1).contains(rise) else {
                throw InputError.invalidLength("请先在高级模式修正下装腰位。")
            }
            values.append(try mapping(field: .lowerLength, path: [group, "length"],
                title: title, detail: detail, scale: legLength,
                offset: rise * hipLine, minimum: minimum,
                clampCurrentAtFive: clampAtFive, design: design))
        }

        switch bottom {
        case "Skirt2":
            try lower("skirt", title: "裙身长度", detail: "从裙身腰口基准线垂直量至未开衩的下摆基准线，不含腰头、缝份和折边余量。", forceNaturalWaist: true, clampAtFive: true)
        case "SkirtCircle":
            try lower("flare-skirt", title: "裙身长度", detail: "从圆裙腰口沿半径方向量至未开衩的下摆；不是裁片包围框高度。不含腰头、缝份和折边余量。", clampAtFive: true)
        case "PencilSkirt":
            if (design.value(at: ["pencil-skirt", "low_angle"])?.numberValue ?? 0) == 0,
               option(design, ["pencil-skirt", "style_side_cut"]) == nil {
                let rise = upper == "FittedShirt" ? 1 : try number(design, ["pencil-skirt", "rise"])
                try lower("pencil-skirt", title: "前片垂直裙身长",
                    detail: "从前片腰口基准线垂直量至未开衩的下摆基准线，不沿弯曲侧缝量。后片保留原版型腰臀修正；不含腰头、缝份和折边余量。",
                    minimum: rise * hipLine + 0.01, forceNaturalWaist: true)
            } else {
                notices.append("倾斜下摆或装饰切口的铅笔裙没有统一的垂直裙长，本页保留原设置，请到高级模式调整。")
            }
        case "Pants":
            if option(design, ["pants", "cuff", "type"]) == nil {
                let rise = upper == "FittedShirt" ? 1 : try number(design, ["pants", "rise"])
                let crotchDifference = try positive(body, "crotch_hip_diff", title: "臀线至裆底高度")
                let minimum = rise * hipLine + crotchDifference * 1.5
                let current = rise * hipLine + (try number(design, ["pants", "length"])) * legLength
                if current + 1e-8 >= minimum {
                    try lower("pants", title: "前片垂直裤身长",
                        detail: "从前片腰口基准线垂直量至裤脚基准线，不沿弯曲侧缝量；后片保留原版型腰臀修正。不含腰头、裤口组件、缝份和折边余量。",
                        minimum: minimum, forceNaturalWaist: true)
                } else {
                    notices.append("当前短裤结构已产生额外裤脚高度偏移，不能按统一垂直裤长换算，请到高级模式调整。")
                }
            } else {
                notices.append("带独立裤口组件的裤装保留原设置，基础模式暂不换算含组件的总裤长，请到高级模式调整。")
            }
        case .some:
            notices.append("当前复杂裙型的接层、不对称或插片长度保留高级设置；基础模式暂不换算统一裙长。")
        case nil: break
        }

        if option(design, ["meta", "wb"]) != nil {
            let hips = try positive(body, "hips_line", title: "腰线至臀线高度")
            values.append(try mapping(field: .waistbandHeight, path: ["waistband", "width"],
                title: "腰头高度", detail: "腰头上下口之间的制版高度；弧形腰头沿直侧边量，不含缝份。修改不会自动扣减上衣或裙裤的组件长度。",
                scale: hips, offset: 0, minimum: 0.01, design: design))
        }
        if upper != nil, bottom != nil {
            notices.append("这里分别设置上衣与裙裤组件长度，不代表组合后的成衣总长；腰头高度也单独计算。")
        }
        return (values, notices)
    }

    private static func mapping(field: Field, path: [String], title: String, detail: String,
                                scale: Double, offset: Double, minimum: Double,
                                clampCurrentAtFive: Bool = false,
                                design: GarmentCodeDesignParameters) throws -> Mapping {
        guard scale.isFinite, scale > 0, offset.isFinite, minimum.isFinite,
              let node = node(design, path), let range = node.range, range.count == 2,
              let a = range[0].numberValue, let b = range[1].numberValue,
              a.isFinite, b.isFinite else { throw InputError.unavailable }
        let low = max(minimum, min(a, b) * scale + offset)
        let high = max(a, b) * scale + offset
        guard low.isFinite, high.isFinite, low <= high else {
            throw InputError.invalidLength("当前人体尺寸与\(title)范围无法匹配，请先核对人体测量值。")
        }
        let current = max(clampCurrentAtFive ? 5 : -.infinity,
                          try number(design, path) * scale + offset)
        guard current.isFinite else { throw InputError.invalidLength("\(title)无法换算，请核对人体与高级参数。") }
        return .init(field: field, path: path, title: title, detail: detail,
                     scale: scale, offset: offset, current: current, range: low...high,
                     parameterRange: min(a, b)...max(a, b))
    }

    private static func positive(_ body: GarmentCodeBodyParameters, _ key: String,
                                 title: String) throws -> Double {
        guard let value = body[key], value.isFinite, value > 0 else { throw InputError.invalidBody(title) }
        return value
    }

    private static func number(_ design: GarmentCodeDesignParameters, _ path: [String]) throws -> Double {
        guard let value = design.value(at: path)?.numberValue, value.isFinite else {
            throw InputError.invalidLength("高级参数包含无效数值，请先修正后再设置长度。")
        }
        return value
    }

    private static func node(_ design: GarmentCodeDesignParameters,
                             _ path: [String]) -> GarmentCodeParameterNode? {
        guard let key = path.first else { return nil }
        return path.dropFirst().reduce(design.design[key]) { $0?.children[$1] }
    }

    private static func option(_ design: GarmentCodeDesignParameters, _ path: [String]) -> String? {
        guard case let .string(value)? = design.value(at: path), !value.isEmpty else { return nil }
        return value
    }

    private static func simpleShirt(_ design: GarmentCodeDesignParameters) -> Bool {
        design.value(at: ["left", "enable_asym"]) != .bool(true) &&
            option(design, ["collar", "component", "style"]) == nil
    }

    private static func representedPaths(_ design: GarmentCodeDesignParameters,
                                          body: GarmentCodeBodyParameters) -> Set<String> {
        // Only fields that actually have an editor are represented. A depth-
        // saturated neckline or a very short custom pant must remain visibly
        // customized when its centimetre editor is unavailable.
        var paths = Set((try? mappings(body: body, design: design).values.map {
            $0.path.joined(separator: ".")
        }) ?? [])
        if option(design, ["meta", "upper"]) == "Shirt" {
            paths.insert("sleeve.sleeveless")
        }
        return paths
    }

    private static func isActive(_ path: [String], design: GarmentCodeDesignParameters) -> Bool {
        guard let root = path.first else { return false }
        let upper = option(design, ["meta", "upper"])
        let bottom = option(design, ["meta", "bottom"])
        let strapless = upper == "FittedShirt" && design.value(at: ["shirt", "strapless"]) == .bool(true)
        switch root {
        case "meta": return false
        case "waistband": return option(design, ["meta", "wb"]) != nil
        case "shirt":
            guard upper != nil else { return false }
            return upper == "FittedShirt" ? path.last == "strapless" : path.last != "strapless"
        case "left":
            guard upper != nil else { return false }
            if path == ["left", "enable_asym"] { return true }
            return design.value(at: ["left", "enable_asym"]) == .bool(true)
        case "collar":
            guard upper != nil, !strapless else { return false }
            if path.count > 2, path[1] == "component", path.last != "style" {
                switch option(design, ["collar", "component", "style"]) {
                case "Hood2Panels": return ["hood_depth", "hood_length"].contains(path.last ?? "")
                case "Turtle": return path.last == "depth"
                case "SimpleLapel": return ["depth", "lapel_standing"].contains(path.last ?? "")
                default: return false
                }
            }
            if let key = path.last {
                let front = key.hasPrefix("f_") || key.hasPrefix("fc_")
                let style = option(design, ["collar", front ? "f_collar" : "b_collar"])
                if key.contains("bezier") { return style == "Bezier2NeckHalf" || style == "CurvyNeckHalf" }
                if key == "fc_angle" || key == "bc_angle" { return style == "TrapezoidNeckHalf" || style == "CircleArcNeckHalf" }
                if key.contains("flip_curve") { return ["Bezier2NeckHalf", "CurvyNeckHalf", "CircleArcNeckHalf"].contains(style ?? "") }
            }
            return true
        case "sleeve":
            guard upper != nil, !strapless else { return false }
            if ["sleeveless", "armhole_shape", "connecting_width", "smoothing_coeff"].contains(path.last ?? "") { return true }
            guard design.value(at: ["sleeve", "sleeveless"]) != .bool(true) else { return false }
            if path.count > 2, path[1] == "cuff", path.last != "type" {
                return cuffFieldActive(path, design: design)
            }
            if path.last == "standing_shoulder_len" { return design.value(at: ["sleeve", "standing_shoulder"]) == .bool(true) }
            return true
        case "skirt":
            return bottom == "Skirt2" || (bottom == "GodetSkirt" && option(design, ["godet-skirt", "base"]) == "Skirt2") ||
                (bottom == "SkirtLevels" && [option(design, ["levels-skirt", "base"]), option(design, ["levels-skirt", "level"])].contains("Skirt2"))
        case "flare-skirt":
            if ["SkirtCircle", "AsymmSkirtCircle", "SkirtManyPanels"].contains(bottom ?? "") {
                if path.contains("skirt-many-panels") { return bottom == "SkirtManyPanels" }
                if path.contains("asymm") { return bottom == "AsymmSkirtCircle" }
                if path.contains("cut"), path.last != "add" { return design.value(at: ["flare-skirt", "cut", "add"]) == .bool(true) }
                return true
            }
            return bottom == "SkirtLevels" && [option(design, ["levels-skirt", "base"]), option(design, ["levels-skirt", "level"])].contains("SkirtCircle")
        case "pencil-skirt":
            return bottom == "PencilSkirt" || (bottom == "GodetSkirt" && option(design, ["godet-skirt", "base"]) == "PencilSkirt") ||
                (bottom == "SkirtLevels" && [option(design, ["levels-skirt", "base"]), option(design, ["levels-skirt", "level"])].contains("PencilSkirt"))
        case "godet-skirt": return bottom == "GodetSkirt"
        case "levels-skirt": return bottom == "SkirtLevels"
        case "pants":
            guard bottom == "Pants" else { return false }
            if path.count > 2, path[1] == "cuff", path.last != "type" {
                return cuffFieldActive(path, design: design)
            }
            return true
        default: return false
        }
    }

    private static func cuffFieldActive(_ path: [String],
                                        design: GarmentCodeDesignParameters) -> Bool {
        guard let root = path.first, let type = option(design, [root, "cuff", "type"]) else { return false }
        switch path.last {
        case "skirt_fraction": return type == "CuffBandSkirt"
        case "skirt_flare", "skirt_ruffle": return type == "CuffSkirt" || type == "CuffBandSkirt"
        default: return true
        }
    }
}
