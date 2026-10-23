import Foundation

/// Read-only view model for the official PyGarment BasicPattern JSON structure.
/// The original JSON data is retained and exported unchanged by the import flow.
struct GarmentCodePatternFile: Codable {
    let pattern: GarmentCodePattern
    let parameters: [String: JSONValue]?
    let parameterOrder: [String]?
    let properties: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case pattern, parameters, parameterOrder = "parameter_order", properties
    }

    init(pattern: GarmentCodePattern,
         parameters: [String: JSONValue]? = nil,
         parameterOrder: [String]? = nil,
         properties: [String: JSONValue]? = nil) {
        self.pattern = pattern
        self.parameters = parameters
        self.parameterOrder = parameterOrder
        self.properties = properties
    }

    /// Build the official pattern-specification envelope from the mutable
    /// pattern-only geometry model. Geometry is normalized to relative curve
    /// coordinates at this boundary, as BasicPattern does before serialization.
    init(geometry: [String: GarmentCodePanelGeometry],
         stitches: [GarmentCodeStitch],
         parameters: [String: JSONValue] = [:],
         parameterOrder: [String] = []) throws {
        guard !geometry.isEmpty else { throw GarmentCodePatternImportError.invalidGeometry("纸样至少需要一个裁片") }
        var panels: [String: GarmentCodePanel] = [:]
        for name in geometry.keys.sorted() {
            guard var panel = geometry[name], panel.isClosed,
                  panel.edges.count >= 2,
                  panel.edges.allSatisfy({ $0.start.x.isFinite && $0.start.y.isFinite &&
                      $0.end.x.isFinite && $0.end.y.isFinite && $0.length() > 1e-9 }) else {
                throw GarmentCodePatternImportError.invalidGeometry("裁片 \(name) 不是有效闭合轮廓")
            }
            // PyGarment Panel.assembly() sets the local pivot to the first
            // edge start, subtracting Python int() (truncate toward zero) from
            // all 2D vertices. Keep this serialization convention even though
            // the app intentionally omits the associated 3D placement.
            if let pivot = panel.edges.first?.start {
                panel.translate(by: .init(x: -Double(Int(pivot.x)), y: -Double(Int(pivot.y))))
            }
            panels[name] = GarmentCodePanel(vertices: panel.serializedVertices(),
                                            edges: panel.serializedEdges(),
                                            label: panel.label,
                                            translation: [0, 0, 0], rotation: [0, 0, 0])
        }
        let document = GarmentCodePatternFile(
            pattern: GarmentCodePattern(panels: panels, stitches: stitches,
                                        panelOrder: geometry.keys.sorted()),
            parameters: parameters,
            parameterOrder: parameterOrder,
            properties: ["curvature_coords": .string("relative"),
                         "tailorass_generator": .object([
                            "upstream_commit": .string("d449629979028123a5c4dc9e732a2ec19b7fce31"),
                            "port_version": .string("swift-pattern-only-2"),
                            "tangent_solver": .string("native-simplex-v1"),
                            "includes_3d_placement": .bool(false)]),
                         "normalize_panel_translation": .bool(false),
                         "normalized_edge_loops": .bool(true),
                         "units_in_meter": .number(100)]
        )
        try document.validateForPreview()
        self = document
    }

    /// Import through this entry point so malformed geometry never reaches the canvas.
    static func validatedImport(from data: Data) throws -> GarmentCodePatternFile {
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validateForPreview()
        // Validate normalization before presenting a sheet. Otherwise an invalid
        // coordinate mode or unit conversion becomes a silently empty canvas.
        _ = try document.geometryPanels()
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
        if let coordinates = properties?["curvature_coords"] {
            guard case let .string(value) = coordinates,
                  ["relative", "absolute"].contains(value) else {
                return try reject("curvature_coords 必须是 relative 或 absolute")
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

    /// Normalize official panel data to the app's 2D centimeter/relative-curve
    /// representation using BasicPattern's declared pattern properties.
    func geometryPanels() throws -> [String: GarmentCodePanelGeometry] {
        let unitScale: Double
        if let units = properties?["units_in_meter"]?.numberValue {
            guard units.isFinite, units > 0 else {
                throw GarmentCodePatternImportError.invalidGeometry("units_in_meter 必须是大于 0 的有限数值")
            }
            unitScale = 100 / units
        } else {
            unitScale = 1
        }
        let curvatureCoordinates: String
        if case let .string(value)? = properties?["curvature_coords"] {
            curvatureCoordinates = value
        } else {
            curvatureCoordinates = "relative"
        }
        return try Dictionary(uniqueKeysWithValues: panels.map { name, panel in
            (name, try GarmentCodePanelGeometry(id: name, panel: panel,
                                                curvatureCoordinates: curvatureCoordinates,
                                                unitScale: unitScale))
        })
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

struct GarmentCodePattern: Codable {
    let panels: [String: GarmentCodePanel]
    let stitches: [GarmentCodeStitch]
    let panelOrder: [String]?

    enum CodingKeys: String, CodingKey { case panels, stitches, panelOrder = "panel_order" }

    init(panels: [String: GarmentCodePanel], stitches: [GarmentCodeStitch], panelOrder: [String]? = nil) {
        self.panels = panels
        self.stitches = stitches
        self.panelOrder = panelOrder
    }
}

struct GarmentCodePanel: Codable, Hashable {
    let vertices: [[Double]]
    let edges: [GarmentCodeEdge]
    let label: String?
    let translation: [Double]?
    let rotation: [Double]?

    init(vertices: [[Double]], edges: [GarmentCodeEdge], label: String?,
         translation: [Double]? = nil, rotation: [Double]? = nil) {
        self.vertices = vertices
        self.edges = edges
        self.label = label
        self.translation = translation
        self.rotation = rotation
    }

    var displayName: String? { label }
}

struct GarmentCodeEdge: Codable, Hashable {
    let endpoints: [Int]
    let label: String?
    let curvature: GarmentCodeCurvature?
}

struct GarmentCodeCurvature: Codable, Hashable {
    let type: String
    let params: [[Double]]?

    // Circle arcs use a flat [radius, large-arc-flag, right-flag] tuple.
    private let circleParams: [Double]?

    enum CodingKeys: String, CodingKey { case type, params }

    init(type: String, params: [[Double]]) {
        self.type = type
        self.params = params
        self.circleParams = nil
    }

    init(circleRadius radius: Double, largeArc: Bool, right: Bool) {
        type = "circle"
        circleParams = [radius, largeArc ? 1 : 0, right ? 1 : 0]
        params = nil
    }

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

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(type, forKey: .type)
        if let circleParams { try values.encode(circleParams, forKey: .params) }
        else { try values.encode(params ?? [], forKey: .params) }
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

struct GarmentCodeStitch: Codable, Hashable {
    let sides: [GarmentCodeStitchSide]
    let rightWrong: Bool

    init(sides: [GarmentCodeStitchSide], rightWrong: Bool = false) {
        self.sides = sides
        self.rightWrong = rightWrong
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        var result: [GarmentCodeStitchSide] = []
        var wrongSide = false
        while !values.isAtEnd {
            if let side = try? values.decode(GarmentCodeStitchSide.self) {
                result.append(side)
            } else {
                let marker = try values.decode(String.self)
                if marker == "right_wrong" { wrongSide = true }
            }
        }
        sides = result
        rightWrong = wrongSide
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        for side in sides { try values.encode(side) }
        if rightWrong { try values.encode("right_wrong") }
    }
}

struct GarmentCodeStitchSide: Codable, Hashable {
    let panel: String
    let edge: Int
}

/// Small JSON value decoder for official pattern properties we don't interpret yet.
enum JSONValue: Codable, Equatable {
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

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .number(number): try value.encode(number)
        case let .string(string): try value.encode(string)
        case let .bool(bool): try value.encode(bool)
        case let .object(object): try value.encode(object)
        case let .array(array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }
}

/// A typed view over the checked-in upstream design/body parameter catalog.
/// This keeps GarmentCode's parameter names, defaults and selectable ranges
/// available to the Swift configurator without translating them into local,
/// unrelated centimeter controls.
struct GarmentCodeParameterCatalog: Decodable {
    let design: [String: GarmentCodeParameterNode]
    let body: [String: Double]
    let bodyDerivedFormulas: [String: String]?

    static func load(from url: URL) throws -> GarmentCodeParameterCatalog {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func node(at path: [String]) -> GarmentCodeParameterNode? {
        guard let first = path.first, let node = design[first] else { return nil }
        return path.dropFirst().reduce(Optional(node)) { current, key in current?.children[key] }
    }

    var garmentOptions: (upper: [String], waistband: [String], bottom: [String]) {
        func strings(_ path: [String]) -> [String] {
            guard let values = node(at: path)?.range else { return [] }
            return values.compactMap { value in
                guard case let .string(name) = value else { return nil }
                return name
            }
        }
        return (strings(["meta", "upper"]), strings(["meta", "wb"]), strings(["meta", "bottom"]))
    }
}

struct GarmentCodeParameterNode: Decodable {
    var value: JSONValue?
    private(set) var hasValueKey = false
    var range: [JSONValue]?
    var type: String?
    var defaultProbability: Double?
    var children: [String: GarmentCodeParameterNode]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        hasValueKey = container.contains(DynamicCodingKey("v"))
        value = try container.decodeIfPresent(JSONValue.self, forKey: DynamicCodingKey("v"))
        range = try container.decodeIfPresent([JSONValue].self, forKey: DynamicCodingKey("range"))
        type = try? container.decode(String.self, forKey: DynamicCodingKey("type"))
        defaultProbability = try container.decodeIfPresent(Double.self, forKey: DynamicCodingKey("default_prob"))
        var nested: [String: GarmentCodeParameterNode] = [:]
        for key in container.allKeys where !["v", "range", "default_prob"].contains(key.stringValue) &&
            !(key.stringValue == "type" && type != nil) {
            nested[key.stringValue] = try container.decode(GarmentCodeParameterNode.self, forKey: key)
        }
        children = nested
    }

    /// Convert the edited node tree back to the exact nested design-parameter
    /// shape expected by GarmentCode's `parameters` field.
    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [:]
        if hasValueKey { object["v"] = value ?? .null }
        if let range { object["range"] = .array(range) }
        if let type { object["type"] = .string(type) }
        if let defaultProbability { object["default_prob"] = .number(defaultProbability) }
        for (key, child) in children { object[key] = child.jsonValue }
        return .object(object)
    }

    mutating func setValue(_ newValue: JSONValue, at path: ArraySlice<String>) -> Bool {
        guard let key = path.first else {
            value = newValue
            hasValueKey = true
            return true
        }
        guard var child = children[key], child.setValue(newValue, at: path.dropFirst()) else { return false }
        children[key] = child
        return true
    }

    func value(at path: ArraySlice<String>) -> JSONValue? {
        guard let key = path.first else { return value }
        return children[key]?.value(at: path.dropFirst())
    }
}

struct GarmentCodeDesignParameters {
    var design: [String: GarmentCodeParameterNode]

    init(catalog: GarmentCodeParameterCatalog) { design = catalog.design }

    func value(at path: [String]) -> JSONValue? {
        guard let root = path.first else { return nil }
        return design[root]?.value(at: path.dropFirst())
    }

    var jsonValue: JSONValue {
        .object(design.mapValues(\.jsonValue))
    }

    mutating func setValue(_ value: JSONValue, at path: [String]) -> Bool {
        guard let root = path.first, var node = design[root], node.setValue(value, at: path.dropFirst()) else { return false }
        design[root] = node
        return true
    }

    func validationMessages(parameterName: ([String]) -> String = { $0.joined(separator: ".") }) -> [String] {
        var errors: [String] = []
        func visit(_ node: GarmentCodeParameterNode, path: [String]) {
            if let type = node.type, let range = node.range, let value = node.value {
                if type == "float" || type == "int" {
                    guard range.count == 2,
                          let lower = range[0].numberValue, let upper = range[1].numberValue,
                          let number = value.numberValue, number.isFinite,
                          number >= min(lower, upper), number <= max(lower, upper) else {
                        errors.append("\(parameterName(path)) 超出允许范围")
                        return
                    }
                    if type == "int", number.rounded() != number {
                        errors.append("\(parameterName(path)) 必须是整数")
                        return
                    }
                } else if !(type == "select_null" && value == .null) && !range.contains(value) {
                    errors.append("\(parameterName(path)) 不是允许的选项")
                }
            }
            for key in node.children.keys.sorted() {
                if let child = node.children[key] { visit(child, path: path + [key]) }
            }
        }
        for key in design.keys.sorted() {
            if let node = design[key] { visit(node, path: [key]) }
        }
        return errors
    }
}

/// BodyParameters.eval_dependencies translated from assets/bodies/body_params.py.
struct GarmentCodeBodyParameters: Codable {
    private(set) var values: [String: Double]

    init(values: [String: Double]) {
        self.values = values
        evaluateDependencies()
    }

    subscript(_ key: String) -> Double? { values[key] }

    mutating func set(_ value: Double, for key: String) {
        values[key] = value
        evaluateDependencies(changed: key)
    }

    private mutating func evaluateDependencies(changed key: String? = nil) {
        func changed(_ names: String...) -> Bool { key == nil || names.contains(key!) }
        if changed("height", "head_l", "waist_line", "hips_line"),
           let height = values["height"], let head = values["head_l"],
           let waistLine = values["waist_line"], let hipLine = values["hips_line"] {
            values["_waist_level"] = height - head - waistLine
            values["_leg_length"] = values["_waist_level"]! - hipLine
        }
        if changed("shoulder_w"), let shoulder = values["shoulder_w"] {
            values["_base_sleeve_balance"] = shoulder - 2
        }
        if changed("bust_line", "vert_bust_line"), let bustLine = values["bust_line"] {
            values["_bust_line"] = values["vert_bust_line"].map { (2 / 3) * $0 + (1 / 3) * bustLine } ?? bustLine
        }
        if changed("hip_inclination"), let inclination = values["hip_inclination"] {
            values["_hip_inclination"] = inclination / 2
        }
        if changed("shoulder_incl"), let inclination = values["shoulder_incl"] {
            values["_shoulder_incl"] = inclination
        }
        if changed("armscye_depth"), let depth = values["armscye_depth"] {
            values["_armscye_depth"] = depth + 2.5
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
