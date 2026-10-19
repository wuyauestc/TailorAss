import Foundation

/// Read-only view model for the official PyGarment BasicPattern JSON structure.
/// The original JSON data is retained and exported unchanged by the import flow.
struct GarmentCodePatternFile: Decodable {
    let pattern: GarmentCodePattern
    let properties: [String: JSONValue]?

    /// Import through this entry point so malformed geometry never reaches the canvas.
    static func validatedImport(from data: Data) throws -> GarmentCodePatternFile {
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validateForPreview()
        return document
    }

    func validateForPreview() throws {
        func reject(_ message: String) throws {
            throw GarmentCodePatternImportError.invalidGeometry(message)
        }
        guard !pattern.panels.isEmpty else {
            return try reject("该 JSON 没有可显示的 pattern.panels")
        }
        if let units = properties?["units_in_meter"] {
            guard let value = units.numberValue, value.isFinite, value > 0 else {
                return try reject("units_in_meter 必须是大于 0 的有限数值")
            }
        }
        for (name, panel) in panels {
            guard panel.vertices.count >= 2, panel.edges.count >= 2 else {
                return try reject("裁片 \(name)：闭合轮廓至少需要 2 个顶点和 2 条边")
            }
            for (index, vertex) in panel.vertices.enumerated() {
                guard vertex.count == 2, vertex.allSatisfy(\.isFinite) else {
                    return try reject("裁片 \(name)：顶点 \(index) 必须包含两个有限坐标")
                }
            }
            for (index, edge) in panel.edges.enumerated() {
                guard edge.endpoints.count == 2,
                      edge.endpoints.allSatisfy({ panel.vertices.indices.contains($0) }) else {
                    return try reject("裁片 \(name)：边 \(index) 的顶点引用无效")
                }
                let start = panel.vertices[edge.endpoints[0]]
                let end = panel.vertices[edge.endpoints[1]]
                let length = hypot(end[0] - start[0], end[1] - start[1])
                guard length.isFinite, length > 0 else {
                    return try reject("裁片 \(name)：边 \(index) 的端点重合或距离无效")
                }
                let next = panel.edges[(index + 1) % panel.edges.count]
                guard next.endpoints.count == 2, edge.endpoints[1] == next.endpoints[0] else {
                    return try reject("裁片 \(name)：边 \(index) 未与下一条边组成连续闭合轮廓")
                }
                if let curvature = edge.curvature, !curvature.isValidForPreview {
                    return try reject("裁片 \(name)：边 \(index) 的曲线类型或控制参数无效")
                }
            }
        }
        for (index, stitch) in pattern.stitches.enumerated() {
            guard stitch.sides.count == 2 else {
                return try reject("接缝 \(index) 必须引用两条边")
            }
            for side in stitch.sides {
                guard let panel = pattern.panels[side.panel], panel.edges.indices.contains(side.edge) else {
                    return try reject("接缝 \(index) 引用了不存在的裁片或边")
                }
            }
        }
    }

    var unitsInMeter: Double {
        properties?["units_in_meter"]?.numberValue ?? 100
    }

    var panels: [(name: String, panel: GarmentCodePanel)] {
        pattern.panels.keys.sorted().compactMap { key in
            pattern.panels[key].map { (key, $0) }
        }
    }

    var stitchCount: Int { pattern.stitches.count }

    func edgeIsStitched(panel: String, edge: Int) -> Bool {
        pattern.stitches.contains { stitch in
            stitch.sides.contains { $0.panel == panel && $0.edge == edge }
        }
    }
}

enum GarmentCodePatternImportError: LocalizedError {
    case invalidGeometry(String)

    var errorDescription: String? {
        switch self {
        case let .invalidGeometry(message): message
        }
    }
}

struct GarmentCodePattern: Decodable {
    let panels: [String: GarmentCodePanel]
    let stitches: [GarmentCodeStitch]
}

struct GarmentCodePanel: Decodable {
    let vertices: [[Double]]
    let edges: [GarmentCodeEdge]
    let label: String?

    var displayName: String? { label }
}

struct GarmentCodeEdge: Decodable {
    let endpoints: [Int]
    let label: String?
    let curvature: GarmentCodeCurvature?
}

struct GarmentCodeCurvature: Decodable {
    let type: String
    let params: [[Double]]?

    // Circle arcs use a flat [radius, large-arc-flag, right-flag] tuple.
    private let circleParams: [Double]?

    enum CodingKeys: String, CodingKey { case type, params }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        if type == "circle" {
            circleParams = try values.decode([Double].self, forKey: .params)
            params = nil
        } else {
            params = try values.decode([[Double]].self, forKey: .params)
            circleParams = nil
        }
    }

    var circle: (radius: Double, largeArc: Bool, right: Bool)? {
        guard let values = circleParams, values.count == 3 else { return nil }
        return (values[0], values[1] != 0, values[2] != 0)
    }

    var isValidForPreview: Bool {
        switch type {
        case "circle":
            guard let values = circleParams, values.count == 3 else { return false }
            return values.allSatisfy(\.isFinite) && values[0] > 0 &&
                [0.0, 1.0].contains(values[1]) && [0.0, 1.0].contains(values[2])
        case "quadratic", "cubic":
            guard let params, params.count == (type == "quadratic" ? 1 : 2) else { return false }
            return params.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) }
        default:
            return false
        }
    }
}

struct GarmentCodeStitch: Decodable {
    let sides: [GarmentCodeStitchSide]

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        var result: [GarmentCodeStitchSide] = []
        while !values.isAtEnd {
            if let side = try? values.decode(GarmentCodeStitchSide.self) {
                result.append(side)
            } else {
                _ = try values.decode(String.self) // optional right_wrong marker
            }
        }
        sides = result
    }
}

struct GarmentCodeStitchSide: Decodable {
    let panel: String
    let edge: Int
}

/// Small JSON value decoder for official pattern properties we don't interpret yet.
enum JSONValue: Decodable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let object = try? value.decode([String: JSONValue].self) { self = .object(object) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }
}

/// First-pass GarmentCode configurator selections. Values mirror the upstream
/// `design.meta` enum names; the UI must not treat them as local geometry types.
enum GarmentCodeConfigurator {
    enum Option: String, CaseIterable, Identifiable, Codable {
        case shirt = "Shirt"
        case fittedShirt = "FittedShirt"
        case straightWaistband = "StraightWB"
        case fittedWaistband = "FittedWB"
        case circleSkirt = "SkirtCircle"
        case asymmetricCircleSkirt = "AsymmSkirtCircle"
        case godetSkirt = "GodetSkirt"
        case pants = "Pants"
        case twoPanelSkirt = "Skirt2"
        case manyPanelSkirt = "SkirtManyPanels"
        case pencilSkirt = "PencilSkirt"
        case levelsSkirt = "SkirtLevels"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shirt: "衬衫 / 上衣"
            case .fittedShirt: "合体上衣"
            case .straightWaistband: "直腰带"
            case .fittedWaistband: "合体腰带"
            case .circleSkirt: "圆裙"
            case .asymmetricCircleSkirt: "不对称圆裙"
            case .godetSkirt: "喇叭裙（Godet）"
            case .pants: "裤子"
            case .twoPanelSkirt: "两片裙"
            case .manyPanelSkirt: "多片裙"
            case .pencilSkirt: "铅笔裙"
            case .levelsSkirt: "层叠裙"
            }
        }
    }

    static let uppers: [Option] = [.fittedShirt, .shirt]
    static let waistbands: [Option] = [.straightWaistband, .fittedWaistband]
    static let bottoms: [Option] = [.circleSkirt, .asymmetricCircleSkirt, .godetSkirt,
                                    .pants, .twoPanelSkirt, .manyPanelSkirt,
                                    .pencilSkirt, .levelsSkirt]
}

struct GarmentDesignSpec: Codable, Hashable {
    var upper: GarmentCodeConfigurator.Option? = nil
    var waistband: GarmentCodeConfigurator.Option? = nil
    var bottom: GarmentCodeConfigurator.Option? = nil

    // MARK: 身体参数
    var heightCm = 168.0
    var bustCm = 92.0
    var waistCm = 76.0
    var hipCm = 98.0
    var shoulderWidthCm = 39.0
    var neckCircCm = 36.0
    var wristCircCm = 16.0
    var armLengthCm = 58.0
    var backLengthCm = 42.0
    var frontLengthCm = 40.0
    var riseCm = 24.0
    var thighCircCm = 56.0
    var kneeCircCm = 36.0
    var calfCircCm = 34.0
    var ankleCircCm = 22.0
    var bicepCircCm = 28.0
    var elbowCircCm = 24.0

    // MARK: 上衣参数
    var easeCm = 8.0
    var upperLengthCm = 58.0
    var collarWidthCm = 4.0
    var collarLengthCm = 40.0
    var buttonPlacketWidthCm = 2.0
    var hemCurveCm = 0.0
    var sideSlitCm = 0.0
    var dartPositionCm = 12.0
    var dartWidthCm = 2.0
    var dartLengthCm = 10.0

    // MARK: 袖片参数
    var sleeveLengthCm = 58.0
    var sleeveOpeningCm = 26.0
    var capHeightCm = 12.0
    var capWidthCm = 0.0
    var sleeveEaseCm = 2.0
    var sleevePitchCm = 0.0
    var cuffWidthCm = 5.0
    var cuffLengthCm = 24.0
    var placketLengthCm = 10.0
    var placketWidthCm = 1.5

    // MARK: 腰带参数
    var waistbandWidthCm = 5.0

    // MARK: 下装参数
    var skirtLengthCm = 70.0
    var pantsLengthCm = 100.0
    var flare = 1.4
    var panelCount = 6
    var godetCount = 6
    var frontAsymmetryCm = 12.0
    var tierCount = 3
    var hipDepthCm = 20.0
    var ventLengthCm = 15.0
    var ventWidthCm = 3.0
    var zipperLengthCm = 18.0
    var crotchDepthCm = 24.0
    var kneeWidthCm = 22.0
    var legOpeningCm = 18.0
    var flyLengthCm = 16.0
    var fullnessRatio = 1.0
    var pocketDepthCm = 15.0
    var pocketWidthCm = 12.0

    var selectedComponentNames: [String] {
        [upper?.title, waistband?.title, bottom?.title].compactMap { $0 }
    }

    /// 默认规格（M 码参考值）：衬衫 + 直腰带 + 圆裙
    static let `default`: GarmentDesignSpec = {
        var spec = GarmentDesignSpec()
        spec.upper = .shirt
        spec.waistband = .straightWaistband
        spec.bottom = .circleSkirt
        return spec
    }()

    /// 随机规格：随机组件组合 + 合理范围内随机参数
    static func random() -> GarmentDesignSpec {
        let uppers: [GarmentCodeConfigurator.Option?] = [.shirt, .fittedShirt, nil]
        let waistbands: [GarmentCodeConfigurator.Option?] = [.straightWaistband, .fittedWaistband, nil]
        let bottoms: [GarmentCodeConfigurator.Option?] = GarmentCodeConfigurator.bottoms + [nil]

        // 至少选一个组件
        var spec = GarmentDesignSpec()
        spec.upper = uppers.randomElement()!
        spec.waistband = waistbands.randomElement()!
        spec.bottom = bottoms.randomElement()!
        if spec.upper == nil && spec.waistband == nil && spec.bottom == nil {
            spec.upper = .shirt
        }

        spec.heightCm = Double.random(in: 150...185)
        spec.bustCm = Double.random(in: 75...115)
        spec.waistCm = Double.random(in: 55...95)
        spec.hipCm = Double.random(in: 78...120)
        spec.shoulderWidthCm = Double.random(in: 35...48)
        spec.neckCircCm = Double.random(in: 32...42)
        spec.wristCircCm = Double.random(in: 14...19)
        spec.armLengthCm = Double.random(in: 50...65)
        spec.backLengthCm = Double.random(in: 38...48)
        spec.frontLengthCm = Double.random(in: 36...46)
        spec.riseCm = Double.random(in: 20...28)
        spec.thighCircCm = Double.random(in: 48...65)
        spec.kneeCircCm = Double.random(in: 32...42)
        spec.calfCircCm = Double.random(in: 30...40)
        spec.ankleCircCm = Double.random(in: 19...26)
        spec.bicepCircCm = Double.random(in: 24...34)
        spec.elbowCircCm = Double.random(in: 20...28)

        spec.easeCm = Double.random(in: 2...18)
        spec.upperLengthCm = Double.random(in: 35...75)
        spec.collarWidthCm = Double.random(in: 2...6)
        spec.collarLengthCm = Double.random(in: 35...45)
        spec.buttonPlacketWidthCm = Double.random(in: 1...3)
        spec.hemCurveCm = Double.random(in: 0...3)
        spec.sideSlitCm = Double.random(in: 0...8)
        spec.dartPositionCm = Double.random(in: 8...16)
        spec.dartWidthCm = Double.random(in: 1...3)
        spec.dartLengthCm = Double.random(in: 8...14)

        spec.sleeveLengthCm = Double.random(in: 0...75)
        spec.sleeveOpeningCm = Double.random(in: 20...36)
        spec.capHeightCm = Double.random(in: 8...16)
        spec.capWidthCm = Double.random(in: 0...3)
        spec.sleeveEaseCm = Double.random(in: 0...5)
        spec.sleevePitchCm = Double.random(in: -2...2)
        spec.cuffWidthCm = Double.random(in: 3...8)
        spec.cuffLengthCm = Double.random(in: 20...30)
        spec.placketLengthCm = Double.random(in: 8...14)
        spec.placketWidthCm = Double.random(in: 1...2)

        spec.waistbandWidthCm = Double.random(in: 3...8)

        spec.skirtLengthCm = Double.random(in: 40...90)
        spec.pantsLengthCm = Double.random(in: 80...125)
        spec.flare = Double.random(in: 1.0...2.2)
        spec.panelCount = Int.random(in: 4...16)
        spec.godetCount = Int.random(in: 4...12)
        spec.frontAsymmetryCm = Double.random(in: 4...18)
        spec.tierCount = Int.random(in: 2...5)
        spec.hipDepthCm = Double.random(in: 16...24)
        spec.ventLengthCm = Double.random(in: 10...20)
        spec.ventWidthCm = Double.random(in: 2...5)
        spec.zipperLengthCm = Double.random(in: 15...22)
        spec.crotchDepthCm = Double.random(in: 20...28)
        spec.kneeWidthCm = Double.random(in: 18...26)
        spec.legOpeningCm = Double.random(in: 14...22)
        spec.flyLengthCm = Double.random(in: 12...20)
        spec.fullnessRatio = Double.random(in: 0.7...1.5)
        spec.pocketDepthCm = Double.random(in: 12...18)
        spec.pocketWidthCm = Double.random(in: 10...15)
        return spec
    }
}

struct NativePatternDocument: Codable, Identifiable {
    let format: String
    let generator: String
    let disclaimer: String
    let units: String
    let design: GarmentDesignSpec
    let pieces: [GeneratedPatternPiece]
    let seams: [GeneratedPatternSeam]

    var id: String { format }
}

enum NativeGarmentPatternGenerator {
    static func validationMessages(for spec: GarmentDesignSpec) -> [String] {
        var checks: [(String, Double, ClosedRange<Double>)] = [
            ("身高", spec.heightCm, 120...220), ("胸围", spec.bustCm, 50...180),
            ("腰围", spec.waistCm, 40...180), ("臀围", spec.hipCm, 50...190)
        ]
        if spec.upper != nil {
            checks += [("肩宽", spec.shoulderWidthCm, 25...65), ("上衣长度", spec.upperLengthCm, 25...120),
                       ("袖长", spec.sleeveLengthCm, 0...90), ("松量", spec.easeCm, 0...40)]
        }
        if spec.waistband != nil { checks.append(("腰头宽度", spec.waistbandWidthCm, 1...20)) }
        if spec.bottom != nil {
            checks.append((spec.bottom == .pants ? "裤长" : "裙长",
                           spec.bottom == .pants ? spec.pantsLengthCm : spec.skirtLengthCm, 10...150))
        }
        if spec.bottom == .manyPanelSkirt && !(4...16).contains(spec.panelCount) {
            return ["裙片数应在 4–16 之间"]
        }
        if spec.bottom == .godetSkirt && !(4...12).contains(spec.godetCount) {
            return ["喇叭插片数应在 4–12 之间"]
        }
        if spec.bottom == .levelsSkirt && !(2...6).contains(spec.tierCount) {
            return ["裙层数应在 2–6 之间"]
        }
        if !(0.7...3).contains(spec.flare) { return ["裙摆扩展比例应在 0.7–3.0 之间"] }
        if spec.upper == nil && spec.waistband == nil && spec.bottom == nil {
            return ["至少选择一个上衣、腰带或下装款式"]
        }
        return checks.compactMap { name, value, range in
            range.contains(value) ? nil : "\(name)应在 \(range.lowerBound)–\(range.upperBound) cm 之间"
        }
    }

    static func generate(_ spec: GarmentDesignSpec) -> NativePatternDocument {
        var pieces: [GeneratedPatternPiece] = []
        var seams: [GeneratedPatternSeam] = []
        if let upper = spec.upper { addUpper(upper, spec: spec, pieces: &pieces, seams: &seams) }
        if let waistband = spec.waistband { addWaistband(waistband, spec: spec, pieces: &pieces) }
        if let bottom = spec.bottom { addBottom(bottom, spec: spec, pieces: &pieces, seams: &seams) }
        return NativePatternDocument(
            format: "tailorass.native-pattern/1",
            generator: "TailorAss.NativeGarmentPatternGenerator/1",
            disclaimer: "TailorAss 原生参数化纸样初版；不是 GarmentCode 输出。仅供设计验证与试样，正式裁剪前须由专业打版人员核验尺寸、松量、缝份和接缝匹配。",
            units: "cm",
            design: spec,
            pieces: pieces,
            seams: seams
        )
    }

    static func validationMessages(for document: NativePatternDocument) -> [String] {
        guard !document.pieces.isEmpty else { return ["没有生成任何裁片"] }
        var issues: [String] = []
        if Set(document.pieces.map(\.id)).count != document.pieces.count {
            issues.append("裁片 ID 重复")
        }
        let pieces = Dictionary(document.pieces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for piece in document.pieces {
            let vertices = piece.vertices
            guard vertices.count >= 3, piece.edges.count == vertices.count else {
                issues.append("\(piece.name)：顶点至少 3 个且边数必须与顶点数相同")
                continue
            }
            guard Set(vertices.map(\.id)).count == vertices.count,
                  Set(piece.edges.map(\.id)).count == piece.edges.count,
                  vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                issues.append("\(piece.name)：顶点/边 ID 重复或坐标无效")
                continue
            }
            let byID = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) })
            var points: [(Double, Double)] = []
            var area2 = 0.0
            var brokenEdge = false
            for index in piece.edges.indices {
                let edge = piece.edges[index]
                guard edge.fromVertex == vertices[index].id,
                      edge.toVertex == vertices[(index + 1) % vertices.count].id,
                      let from = byID[edge.fromVertex], let to = byID[edge.toVertex] else {
                    brokenEdge = true
                    continue
                }
                if hypot(to.x - from.x, to.y - from.y) < 1e-6 { brokenEdge = true }
                points.append((from.x, from.y))
                area2 += from.x * to.y - to.x * from.y
            }
            if brokenEdge { issues.append("\(piece.name)：边引用断裂或存在零长度边") }
            if abs(area2) < 1e-6 { issues.append("\(piece.name)：轮廓面积为零") }
            if points.count == vertices.count && hasSelfIntersection(points) {
                issues.append("\(piece.name)：轮廓存在自相交")
            }
        }

        for seam in document.seams {
            guard let pieceA = pieces[seam.pieceA], let pieceB = pieces[seam.pieceB],
                  let edgeA = pieceA.edges.first(where: { $0.id == seam.edgeA }),
                  let edgeB = pieceB.edges.first(where: { $0.id == seam.edgeB }) else {
                issues.append("接缝 \(seam.type)：引用了不存在的裁片或边")
                continue
            }
            guard let lengthA = edgeLength(edgeA, in: pieceA), let lengthB = edgeLength(edgeB, in: pieceB) else {
                issues.append("接缝 \(seam.type)：边端点引用无效")
                continue
            }
            if abs(lengthA - lengthB) > max(0.2, max(lengthA, lengthB) * 0.02) {
                issues.append("接缝 \(seam.type)：两侧边长不匹配（\(lengthA.formatted(.number.precision(.fractionLength(1)))) cm / \(lengthB.formatted(.number.precision(.fractionLength(1)))) cm）")
            }
        }
        return issues
    }

    /// 边长：曲线边取弧长（采样累加），直线边取弦长
    private static func edgeLength(_ edge: PatternEdge, in piece: GeneratedPatternPiece) -> Double? {
        guard let from = piece.vertices.first(where: { $0.id == edge.fromVertex }),
              let to = piece.vertices.first(where: { $0.id == edge.toVertex }) else { return nil }
        return EdgeGeometry.length(from: (from.x, from.y), to: (to.x, to.y), curve: edge.curve)
    }

    private static func hasSelfIntersection(_ points: [(Double, Double)]) -> Bool {
        guard points.count >= 4 else { return false }
        func orientation(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double {
            (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
        }
        func onSegment(_ a: (Double, Double), _ b: (Double, Double), _ point: (Double, Double)) -> Bool {
            point.0 >= min(a.0, b.0) - 1e-8 && point.0 <= max(a.0, b.0) + 1e-8 &&
            point.1 >= min(a.1, b.1) - 1e-8 && point.1 <= max(a.1, b.1) + 1e-8
        }
        for first in points.indices {
            let a = points[first], b = points[(first + 1) % points.count]
            for second in (first + 1)..<points.count {
                if second == first || second == (first + 1) % points.count || (second + 1) % points.count == first { continue }
                let c = points[second], d = points[(second + 1) % points.count]
                let abC = orientation(a, b, c), abD = orientation(a, b, d)
                let cdA = orientation(c, d, a), cdB = orientation(c, d, b)
                if (abC * abD < -1e-8 && cdA * cdB < -1e-8) ||
                    (abs(abC) < 1e-8 && onSegment(a, b, c)) ||
                    (abs(abD) < 1e-8 && onSegment(a, b, d)) ||
                    (abs(cdA) < 1e-8 && onSegment(c, d, a)) ||
                    (abs(cdB) < 1e-8 && onSegment(c, d, b)) { return true }
            }
        }
        return false
    }

    private static func addUpper(_ style: GarmentCodeConfigurator.Option, spec: GarmentDesignSpec,
                                 pieces: inout [GeneratedPatternPiece], seams: inout [GeneratedPatternSeam]) {
        let ease = spec.easeCm
        let bustQuarter = (spec.bustCm + ease) / 4
        let hipQuarter = (spec.hipCm + ease) / 4
        let shoulderHalf = spec.shoulderWidthCm / 2
        // 领宽：优先用颈围计算，其次用肩宽比例
        let neckWidth = min(10, max(spec.neckCircCm / 6, spec.shoulderWidthCm * 0.24))
        let neckDepth = style == .fittedShirt ? 7.0 : 9.0
        let armhole = spec.upperLengthCm * 0.34
        for (name, chest, hip, back) in [("前身片", bustQuarter, hipQuarter, false),
                                         ("后身片", bustQuarter, hipQuarter, true)] {
            let necklineDepth = back ? max(2.5, neckDepth * 0.45) : neckDepth
            let pieceUpper = pieceUpperCurved(
                id: "upper-\(back ? "back" : "front")",
                name: name, type: back ? "upperBack" : "upperFront",
                back: back, shoulderHalf: shoulderHalf, neckWidth: neckWidth,
                necklineDepth: necklineDepth, armhole: armhole, chest: chest,
                hip: hip, length: spec.upperLengthCm, fitted: style == .fittedShirt,
                collarWidth: spec.collarWidthCm, hemCurve: spec.hemCurveCm,
                sideSlit: spec.sideSlitCm, dartWidth: spec.dartWidthCm
            )
            pieces.append(pieceUpper)
        }
        // 侧缝：找前后片中 role=="side" 的所有 edge（可能多条），只取最后一条（下摆前的那条）
        // 简化：取每条裁片里第一条 role=="side" 的 edge ID
        if let frontSide = pieces.first(where: { $0.id == "upper-front" })?.edges.first(where: { $0.role == "side" })?.id,
           let backSide = pieces.first(where: { $0.id == "upper-back" })?.edges.first(where: { $0.role == "side" })?.id {
            seams.append(GeneratedPatternSeam(pieceA: "upper-front", edgeA: frontSide,
                                              pieceB: "upper-back", edgeB: backSide,
                                              type: "side-seam", samplingDensity: 16))
        }
        if spec.sleeveLengthCm > 0 {
            // 袖山宽度：用上臂围 + 袖肥松量
            let cap = max(12, (spec.bicepCircCm + spec.sleeveEaseCm) * 0.72)
            pieces.append(pieceSleeveCurved(
                id: "sleeve", name: "袖片", cap: cap, capHeight: spec.capHeightCm,
                armholeTop: armhole, length: spec.sleeveLengthCm, opening: spec.sleeveOpeningCm,
                cuffWidth: spec.cuffWidthCm, quantity: 2
            ))
        }
    }

    // MARK: - 曲线化裁片生成

    /// 曲线边规格（bulge 为边中点偏移量 cm；正值向左法线凸。本生成器的轮廓均为 CCW，
    /// 左法线即裁片内侧，所以正值 = 向裁片内部凹/收腰，负值 = 向外凸）。
    private enum EdgeSpec {
        case straight
        case bulge(Double)
        case quadratic(u: Double, v: Double)
        case cubic(c1: (Double, Double), c2: (Double, Double))
        case arc(sagitta: Double)
    }

    /// 由 EdgeSpec 生成局部坐标曲线（GarmentCode §3.2.3）
    private static func makeCurvature(spec: EdgeSpec, chordLength L: Double) -> EdgeCurvature? {
        guard L > 1e-9 else { return nil }
        switch spec {
        case .straight:
            return nil
        case .bulge(let offset):
            // quadratic 控制点在 (0.5, 2*offset/L)，曲线中点偏移恰为 offset
            return EdgeCurvature(kind: .quadratic, c1: [0.5, 2 * offset / L])
        case .quadratic(let u, let v):
            return EdgeCurvature(kind: .quadratic, c1: [u, v])
        case .cubic(let c1, let c2):
            return EdgeCurvature(kind: .cubic, c1: [c1.0, c1.1], c2: [c2.0, c2.1])
        case .arc(let sagitta):
            return EdgeCurvature(kind: .arc, sagitta: sagitta)
        }
    }

    /// 生成前/后身片：7 锚点 + 每边曲线规格。领口/袖窿内凹，侧缝合体款收腰。
    private static func pieceUpperCurved(id: String, name: String, type: String,
                                         back: Bool, shoulderHalf: Double, neckWidth: Double,
                                         necklineDepth: Double, armhole: Double, chest: Double,
                                         hip: Double, length: Double, fitted: Bool,
                                         collarWidth: Double, hemCurve: Double,
                                         sideSlit: Double, dartWidth: Double) -> GeneratedPatternPiece {
        // 领宽影响领口曲线深度
        let necklineBulge = (back ? 1.5 : 2.8) * (1 + collarWidth * 0.1)
        // A 颈中心 → B 颈侧 → C 肩点 → D 袖窿中点 → E 腋下 → F 侧缝下摆 → G 中缝下摆
        let anchors: [(Double, Double)] = [
            (0, necklineDepth),                     // A
            (neckWidth, 0),                         // B
            (shoulderHalf, 2.5),                    // C
            (shoulderHalf + 1.5, armhole * 0.55),   // D
            (chest, armhole),                       // E
            (hip, length),                          // F
            (0, length)                             // G
        ]
        let specs: [EdgeSpec] = [
            .bulge(necklineBulge),      // 领口：向裁片内侧凹，领宽越大越深
            .straight,                  // 肩线
            .bulge(1.2),                // 袖窿上半：内凹
            .bulge(1.5),                // 袖窿下半：内凹
            .bulge(fitted ? 1.5 : 0.4), // 侧缝：合体款收腰
            .bulge(-hemCurve),          // 下摆：下摆弧度（正值向下凸）
            .straight                   // 中缝
        ]
        let roles = ["neckline", "shoulder", "armhole", "armhole", "side", "hem", "center"]
        return polygonCurved(id: id, name: name, type: type, quantity: 1,
                             points: anchors, roles: roles, specs: specs)
    }

    /// 生成袖片：5 锚点，袖山两段 quadratic 外凸，袖口微弧。
    private static func pieceSleeveCurved(id: String, name: String, cap: Double, capHeight: Double,
                                          armholeTop: Double, length: Double, opening: Double,
                                          cuffWidth: Double, quantity: Int) -> GeneratedPatternPiece {
        // 袖山高度影响袖山凸出程度
        let capBulge = capHeight * 0.375  // 转换系数：12cm 高度 → 4.5cm 凸出
        // 袖口宽度影响袖口弧度
        let cuffBulge = 1.5 * (1 + cuffWidth * 0.05)
        let anchors: [(Double, Double)] = [
            (0, length),                // 袖口左
            (0, armholeTop - 3),        // 袖山左底
            (cap * 0.5, 0),             // 袖山顶
            (cap, armholeTop - 3),      // 袖山右底
            (opening / 2, length)       // 袖口右
        ]
        let specs: [EdgeSpec] = [
            .straight,          // 左袖缝
            .bulge(capBulge),   // 袖山左半：外凸
            .bulge(capBulge),   // 袖山右半：外凸
            .straight,          // 右袖缝
            .bulge(cuffBulge)   // 袖口：微弧
        ]
        let roles = ["sleeveSeam", "sleeveCap", "sleeveCap", "sleeveSeam", "cuff"]
        return polygonCurved(id: id, name: name, type: "sleeve", quantity: quantity,
                             points: anchors, roles: roles, specs: specs)
    }

    private static func addWaistband(_ style: GarmentCodeConfigurator.Option, spec: GarmentDesignSpec,
                                     pieces: inout [GeneratedPatternPiece]) {
        let waist = spec.waistCm + (style == .fittedWaistband ? 2 : 4)
        pieces.append(polygon(id: "waistband", name: style == .fittedWaistband ? "合体腰头" : "直腰头",
                              type: "waistband", quantity: 2,
                              points: [(0, 0), (waist / 2, 0), (waist / 2, spec.waistbandWidthCm), (0, spec.waistbandWidthCm)],
                              roles: ["top", "side", "bottom", "side"]))
    }

    private static func addBottom(_ style: GarmentCodeConfigurator.Option, spec: GarmentDesignSpec,
                                  pieces: inout [GeneratedPatternPiece], seams: inout [GeneratedPatternSeam]) {
        let waist = spec.waistCm + spec.easeCm
        let hip = spec.hipCm + spec.easeCm
        let length = style == .pants ? spec.pantsLengthCm : spec.skirtLengthCm
        switch style {
        case .circleSkirt, .asymmetricCircleSkirt:
            // 完整度比例影响圆裙的展开角度
            let baseAngles: [Double] = style == .circleSkirt ? [180.0, 180.0] : [160.0, 200.0]
            let angles = baseAngles.map { $0 * spec.fullnessRatio }
            for (index, angle) in angles.enumerated() {
                let inner = waist / (2 * .pi)
                let outer = inner + length + (index == 0 && style == .asymmetricCircleSkirt ? spec.frontAsymmetryCm : 0)
                pieces.append(sector(id: "skirt-\(index)", name: index == 0 ? "前裙片" : "后裙片",
                                     innerRadius: inner, outerRadius: outer, degrees: angle,
                                     quantity: 1, type: "circleSkirt"))
            }
            if style == .circleSkirt {
                // 两片扇形的侧缝互连：取各自两条 role=="side" 的边
                if let piece0 = pieces.first(where: { $0.id == "skirt-0" }),
                   let piece1 = pieces.first(where: { $0.id == "skirt-1" }),
                   let a0 = piece0.edges.first(where: { $0.role == "side" })?.id,
                   let a1 = piece0.edges.last(where: { $0.role == "side" })?.id,
                   let b0 = piece1.edges.first(where: { $0.role == "side" })?.id,
                   let b1 = piece1.edges.last(where: { $0.role == "side" })?.id {
                    seams += [GeneratedPatternSeam(pieceA: "skirt-0", edgeA: a0, pieceB: "skirt-1", edgeB: b0, type: "side-seam-left", samplingDensity: 24),
                              GeneratedPatternSeam(pieceA: "skirt-0", edgeA: a1, pieceB: "skirt-1", edgeB: b1, type: "side-seam-right", samplingDensity: 24)]
                }
            }
        case .pants:
            for back in [false, true] {
                let top = hip / 4
                // 用裆深参数控制裤裆深度
                let crotch = top * (back ? 0.42 : 0.30) * (spec.crotchDepthCm / 24.0)
                // 用膝围参数控制膝部宽度
                let leg = max(18, spec.kneeWidthCm * 1.2)
                // 用脚口参数控制脚口宽度
                let hemWidth = spec.legOpeningCm / 2
                let points: [(Double, Double)] = [(0, 0), (top, 0), (top + crotch, length * 0.24),
                                                  (leg, length * 0.72), (hemWidth, length), (0, length),
                                                  (0, length * 0.72)]
                pieces.append(polygonCurved(id: back ? "pants-back" : "pants-front",
                                            name: back ? "后裤片" : "前裤片",
                                            type: back ? "pantsBack" : "pantsFront", quantity: 2,
                                            points: points,
                                            roles: ["waist", "crotch", "inseam", "inseam", "hem", "outseam", "outseam"],
                                            specs: [.straight, .bulge(back ? 3.2 : 2.2),
                                                    .straight, .straight, .straight, .straight, .straight]))
            }
        case .godetSkirt:
            addTrapezoidSkirt(spec: spec, pieces: &pieces, seams: &seams, panelCount: 2)
            for index in 0..<spec.godetCount {
                let half = max(6, length * 0.16)
                pieces.append(polygon(id: "godet-\(index)", name: "喇叭插片 \(index + 1)", type: "godet", quantity: 1,
                                      points: [(0, 0), (8, 0), (8 + half, length * 0.34), (-half, length * 0.34)],
                                      roles: ["insertTop", "insertSeam", "hem", "insertSeam"]))
            }
        case .twoPanelSkirt:
            addTrapezoidSkirt(spec: spec, pieces: &pieces, seams: &seams, panelCount: 2)
        case .manyPanelSkirt:
            addTrapezoidSkirt(spec: spec, pieces: &pieces, seams: &seams, panelCount: spec.panelCount)
        case .pencilSkirt:
            for (index, name) in ["前裙片", "后裙片"].enumerated() {
                let top = waist / 2
                // 用臀深参数控制臀部位置
                let hipLine = spec.hipDepthCm
                // 用省宽影响臀部曲线
                let hipBulge = -1.2 * (1 + spec.dartWidthCm * 0.2)
                pieces.append(polygonCurved(id: "pencil-\(index)", name: name, type: "pencilSkirt", quantity: 1,
                                            points: [(0, 0), (top, 0), (hip / 2, hipLine), (hip / 2 * spec.flare, length), (0, length)],
                                            roles: ["waist", "side", "side", "hem", "side"],
                                            specs: [.straight, .bulge(hipBulge), .straight, .straight, .straight]))
            }
            // 两侧缝合：取每片的第一条 role=="side" edge
            if let s0 = pieces.first(where: { $0.id == "pencil-0" })?.edges.first(where: { $0.role == "side" })?.id,
               let s1 = pieces.first(where: { $0.id == "pencil-1" })?.edges.first(where: { $0.role == "side" })?.id {
                seams.append(GeneratedPatternSeam(pieceA: "pencil-0", edgeA: s0, pieceB: "pencil-1", edgeB: s1, type: "side-seam", samplingDensity: 20))
            }
        case .levelsSkirt:
            let tierLength = length / Double(spec.tierCount)
            var top = waist
            for index in 0..<spec.tierCount {
                let bottom = top * 1.45
                pieces.append(polygon(id: "tier-\(index)", name: "第 \(index + 1) 层裙片", type: "skirtTier", quantity: 2,
                                      points: [(0, 0), (top / 2, 0), (bottom / 2, tierLength), (0, tierLength)],
                                      roles: ["top", "side", "hem", "side"]))
                top = bottom
            }
        default: break
        }
    }

    private static func addTrapezoidSkirt(spec: GarmentDesignSpec,
                                          pieces: inout [GeneratedPatternPiece],
                                          seams: inout [GeneratedPatternSeam], panelCount: Int) {
        let waist = (spec.waistCm + spec.easeCm) / Double(panelCount)
        let hem = waist * spec.flare
        for index in 0..<panelCount {
            pieces.append(polygon(id: "skirt-panel-\(index)", name: "裙片 \(index + 1)", type: "skirtPanel", quantity: 1,
                                  points: [(0, 0), (waist, 0), ((waist + hem) / 2, spec.skirtLengthCm),
                                           (-(hem - waist) / 2, spec.skirtLengthCm)],
                                  roles: ["waist", "side", "hem", "side"]))
        }
        for index in 0..<panelCount {
            let next = (index + 1) % panelCount
            let panelA = pieces.first(where: { $0.id == "skirt-panel-\(index)" })!
            let panelB = pieces.first(where: { $0.id == "skirt-panel-\(next)" })!
            // panel i 的第一条 "side"（左边）→ 连 panel i+1 的最后一条 "side"（右边）
            if let aSide = panelA.edges.first(where: { $0.role == "side" })?.id,
               let bSide = panelB.edges.last(where: { $0.role == "side" })?.id {
                seams.append(GeneratedPatternSeam(pieceA: "skirt-panel-\(index)", edgeA: aSide,
                                                   pieceB: "skirt-panel-\(next)", edgeB: bSide,
                                                   type: "side-seam", samplingDensity: 20))
            }
        }
    }

    /// 扇形裁片（圆裙）：外弧和内弧各拆成 ≤90° 的 arc 边，不再逐点离散
    private static func sector(id: String, name: String, innerRadius: Double, outerRadius: Double,
                               degrees: Double, quantity: Int, type: String) -> GeneratedPatternPiece {
        let segmentCount = max(1, Int(ceil(degrees / 90)))
        let step = degrees / Double(segmentCount)
        let start = -degrees / 2
        func point(_ r: Double, _ deg: Double) -> (Double, Double) {
            let rad = deg * .pi / 180
            return (r * cos(rad), r * sin(rad))
        }
        // 顶点顺序：外弧 O0→...→On，接内弧 In→...→I0，再闭合回 O0
        var anchors: [(Double, Double)] = (0...segmentCount).map { point(outerRadius, start + step * Double($0)) }
        anchors += (0...segmentCount).reversed().map { point(innerRadius, start + step * Double($0)) }

        var specs: [EdgeSpec] = []
        var roles: [String] = []
        // 外弧（hem）
        for i in 0..<segmentCount {
            specs.append(.arc(sagitta: arcSagitta(center: (0, 0), from: anchors[i], to: anchors[i + 1])))
            roles.append("hem")
        }
        // 右侧缝（On → In）
        specs.append(.straight)
        roles.append("side")
        // 内弧（waist，反向）
        for i in 0..<segmentCount {
            let from = segmentCount + 1 + i
            specs.append(.arc(sagitta: arcSagitta(center: (0, 0), from: anchors[from], to: anchors[from + 1])))
            roles.append("waist")
        }
        // 左侧缝（I0 → O0）
        specs.append(.straight)
        roles.append("side")

        return polygonCurved(id: id, name: name, type: type, quantity: quantity,
                             points: anchors, roles: roles, specs: specs)
    }

    /// 计算圆弧的有向矢高比（sagitta / chordLength），正值向左法线凸
    private static func arcSagitta(center c: (Double, Double), from a: (Double, Double), to b: (Double, Double)) -> Double {
        let ex = b.0 - a.0, ey = b.1 - a.1
        let L = hypot(ex, ey)
        guard L > 1e-9 else { return 0 }
        let r = hypot(a.0 - c.0, a.1 - c.1)
        let midVec = ((a.0 + b.0) / 2 - c.0, (a.1 + b.1) / 2 - c.1)
        let mLen = hypot(midVec.0, midVec.1)
        guard mLen > 1e-9 else { return 0 }
        let arcMid = (c.0 + midVec.0 / mLen * r, c.1 + midVec.1 / mLen * r)
        let chordMid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
        let leftN = (-ey / L, ex / L)
        return ((arcMid.0 - chordMid.0) * leftN.0 + (arcMid.1 - chordMid.1) * leftN.1) / L
    }

    private static func polygonCurved(id: String, name: String, type: String, quantity: Int,
                                      points: [(Double, Double)], roles: [String],
                                      specs: [EdgeSpec]) -> GeneratedPatternPiece {
        let minX = points.map(\.0).min() ?? 0, minY = points.map(\.1).min() ?? 0
        let vertices = points.enumerated().map { index, point in
            PatternVertex(id: "\(id)-v\(index)", x: point.0 - minX, y: point.1 - minY)
        }
        let edges = vertices.indices.map { index in
            let from = vertices[index]
            let to = vertices[(index + 1) % vertices.count]
            let chord = hypot(to.x - from.x, to.y - from.y)
            let spec = specs.indices.contains(index) ? specs[index] : .straight
            return PatternEdge(id: "\(id)-e\(index)", fromVertex: from.id,
                               toVertex: to.id,
                               role: roles.indices.contains(index) ? roles[index] : "seam",
                               curve: makeCurvature(spec: spec, chordLength: chord))
        }
        return GeneratedPatternPiece(id: id, name: name, type: type, units: "cm", cutQuantity: quantity,
                                     grainlineDegrees: 90, vertices: vertices, edges: edges)
    }

    private static func polygon(id: String, name: String, type: String, quantity: Int,
                                points: [(Double, Double)], roles: [String]) -> GeneratedPatternPiece {
        polygonCurved(id: id, name: name, type: type, quantity: quantity,
                      points: points, roles: roles, specs: Array(repeating: .straight, count: points.count))
    }
}

struct GeneratedPatternPiece: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let units: String
    let cutQuantity: Int
    let grainlineDegrees: Double
    let vertices: [PatternVertex]
    let edges: [PatternEdge]
}

struct PatternVertex: Codable {
    let id: String
    let x: Double
    let y: Double
}

struct PatternEdge: Codable {
    let id: String
    let fromVertex: String
    let toVertex: String
    let role: String
    /// 曲线信息（nil = 直线边）。控制点存局部坐标，平移/旋转/缩放自动跟随（GarmentCode §3.2.3）
    var curve: EdgeCurvature? = nil
}

/// 曲线边描述（GarmentCode 局部坐标系约定）：
/// 以 起点→终点 为单位横轴、左法线为纵轴，坐标值以边长为单位。
/// - quadratic: c1 = [u, v]
/// - cubic: c1/c2 = [u, v]
/// - arc: sagitta = 弧中点到弦的有向距离 / 弦长（正值向左法线凸）
struct EdgeCurvature: Codable {
    enum Kind: String, Codable { case quadratic, cubic, arc }
    let kind: Kind
    var c1: [Double]? = nil
    var c2: [Double]? = nil
    var sagitta: Double? = nil
}

/// 曲线边几何工具：局部坐标（以边长为单位、左法线为纵轴）与绝对坐标互转、采样、弧长。
/// 采样点均含起点和终点。
enum EdgeGeometry {
    typealias Point = (Double, Double)

    /// 局部坐标 → 绝对坐标
    static func absolute(_ local: Point, from a: Point, to b: Point) -> Point {
        let ex = b.0 - a.0, ey = b.1 - a.1
        return (a.0 + local.0 * ex - local.1 * ey,
                a.1 + local.0 * ey + local.1 * ex)
    }

    /// 采样曲线边。steps 为每边的采样段数（至少 2）。
    static func sample(from a: Point, to b: Point, curve: EdgeCurvature?, steps: Int = 24) -> [Point] {
        let n = max(2, steps)
        guard let curve else { return [a, b] }
        switch curve.kind {
        case .quadratic:
            guard let c1 = curve.c1, c1.count == 2 else { return [a, b] }
            let c = absolute((c1[0], c1[1]), from: a, to: b)
            return (0...n).map { i in
                let t = Double(i) / Double(n)
                let u = 1 - t
                return (u*u*a.0 + 2*u*t*c.0 + t*t*b.0,
                        u*u*a.1 + 2*u*t*c.1 + t*t*b.1)
            }
        case .cubic:
            guard let c1 = curve.c1, c1.count == 2, let c2 = curve.c2, c2.count == 2 else { return [a, b] }
            let p1 = absolute((c1[0], c1[1]), from: a, to: b)
            let p2 = absolute((c2[0], c2[1]), from: a, to: b)
            return (0...n).map { i in
                let t = Double(i) / Double(n)
                let u = 1 - t
                return (u*u*u*a.0 + 3*u*u*t*p1.0 + 3*u*t*t*p2.0 + t*t*t*b.0,
                        u*u*u*a.1 + 3*u*u*t*p1.1 + 3*u*t*t*p2.1 + t*t*t*b.1)
            }
        case .arc:
            guard let s = curve.sagitta, abs(s) > 1e-9 else { return [a, b] }
            return sampleArc(from: a, to: b, sagitta: s, steps: n)
        }
    }

    /// 圆弧采样。sagitta = 弧中点到弦的有向距离 / 弦长（正值向左法线凸）。
    static func sampleArc(from a: Point, to b: Point, sagitta s: Double, steps: Int) -> [Point] {
        let ex = b.0 - a.0, ey = b.1 - a.1
        let L = hypot(ex, ey)
        guard L > 1e-9 else { return [a, b] }
        let h = s * L                     // 有向矢高
        let w = L / 2                     // 半弦长
        let k = (h * h - w * w) / (2 * h) // 圆心沿左法线距弦中点
        let leftN = (-ey / L, ex / L)
        let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
        let center = (mid.0 + leftN.0 * k, mid.1 + leftN.1 * k)
        let v0 = (a.0 - center.0, a.1 - center.1)
        let v1 = (b.0 - center.0, b.1 - center.1)
        let short = atan2(v0.0 * v1.1 - v0.1 * v1.0, v0.0 * v1.0 + v0.1 * v1.1)
        let long = short - (short >= 0 ? 2 * Double.pi : -2 * Double.pi)
        let arcMid = (mid.0 + leftN.0 * h, mid.1 + leftN.1 * h)
        func midPoint(_ sweep: Double) -> Point {
            let half = sweep / 2
            let c = cos(half), sn = sin(half)
            return (center.0 + v0.0 * c - v0.1 * sn,
                    center.1 + v0.0 * sn + v0.1 * c)
        }
        let sweep: Double
        if abs(h) > w {
            // 大弧（> 半圆）必须取长弧
            sweep = long
        } else {
            // 短弧应经过预期弧顶；数值上取中点更靠近 arcMid 的那条
            let dShort = hypot(midPoint(short).0 - arcMid.0, midPoint(short).1 - arcMid.1)
            let dLong = hypot(midPoint(long).0 - arcMid.0, midPoint(long).1 - arcMid.1)
            sweep = dShort <= dLong ? short : long
        }
        return (0...steps).map { i in
            let t = sweep * Double(i) / Double(steps)
            let c = cos(t), sn = sin(t)
            return (center.0 + v0.0 * c - v0.1 * sn,
                    center.1 + v0.0 * sn + v0.1 * c)
        }
    }

    /// 曲线弧长（采样累加近似）
    static func length(from a: Point, to b: Point, curve: EdgeCurvature?) -> Double {
        guard let curve else { return hypot(b.0 - a.0, b.1 - a.1) }
        let pts = sample(from: a, to: b, curve: curve, steps: 32)
        var total = 0.0
        for i in 1..<pts.count {
            total += hypot(pts[i].0 - pts[i-1].0, pts[i].1 - pts[i-1].1)
        }
        return total
    }
}

struct GeneratedPatternSeam: Codable {
    let pieceA: String
    let edgeA: String
    let pieceB: String
    let edgeB: String
    let type: String
    let samplingDensity: Int
}
