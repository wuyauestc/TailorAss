import Foundation

/// Basic mode is an adapter over the same official parameter tree, not a
/// second drafting algorithm. Assert centimetres against generated geometry.
@main
struct BasicDesignRegression {
    typealias Adapter = GarmentCodeBasicDesign

    enum Failure: Error { case check(String) }

    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure.check(message) }
    }

    static func near(_ actual: Double, _ expected: Double, _ message: String,
                     tolerance: Double = 1e-7) throws {
        try require(actual.isFinite && abs(actual - expected) <= tolerance,
                    "\(message): expected \(expected), got \(actual)")
    }

    static func setting(_ value: JSONValue, _ path: [String],
                        in design: inout GarmentCodeDesignParameters) throws {
        try require(design.setValue(value, at: path), "Missing parameter \(path)")
    }

    static func select(_ style: String, catalog: GarmentCodeParameterCatalog) throws -> GarmentCodeDesignParameters {
        var design = GarmentCodeDesignParameters(catalog: catalog)
        let upper = style == "Shirt" || style == "FittedShirt"
        try setting(.string(style), ["meta", upper ? "upper" : "bottom"], in: &design)
        return design
    }

    static func control(_ field: Adapter.Field, body: GarmentCodeBodyParameters,
                        design: GarmentCodeDesignParameters) throws -> Adapter.Control {
        let overview = try Adapter.overview(body: body, design: design)
        guard let result = overview.controls.first(where: { $0.field == field }) else {
            throw Failure.check("Missing editable \(field) for selected style: \(overview.notices)")
        }
        try require(result.valueCM.isFinite && result.rangeCM.lowerBound.isFinite &&
                    result.rangeCM.upperBound.isFinite && result.rangeCM.lowerBound <= result.rangeCM.upperBound,
                    "Invalid centimetre presentation")
        return result
    }

    static func rejected(_ cm: Double, field: Adapter.Field, body: GarmentCodeBodyParameters,
                         design: GarmentCodeDesignParameters) throws {
        var candidate = design
        let original = candidate.jsonValue
        var failed = false
        do { try Adapter.setLength(cm: cm, for: field, body: body, design: &candidate) }
        catch { failed = true }
        try require(failed, "Invalid / unsupported centimetre edit \(field)=\(cm) was accepted")
        try require(candidate.jsonValue == original, "Rejected centimetre edit partially mutated design")
    }

    static func height(_ panel: GarmentCodePanelGeometry) throws -> Double {
        let ys = panel.edges.flatMap { [$0.start.y, $0.end.y] }
        guard let minY = ys.min(), let maxY = ys.max() else { throw Failure.check("Empty panel") }
        return maxY - minY
    }

    static func measure(_ style: String, file: GarmentCodePatternFile) throws -> Double {
        let panels = try file.geometryPanels()
        if style == "Shirt" {
            guard let back = panels["right_btorso"], let center = back.edges.last else {
                throw Failure.check("Missing ordinary Shirt back center seam")
            }
            try near(center.start.x, center.end.x, "Back center seam must remain vertical")
            try require(center.curvature == nil, "Back center must be a straight measurement")
            return abs(center.start.y - center.end.y)
        }
        guard let front = panels[style == "Pants" ? "pant_f_r" : "skirt_front"] else {
            throw Failure.check("Missing \(style) front panel")
        }
        if style == "SkirtCircle" {
            let sides = front.edges.filter { $0.curvature == nil }
            try require(sides.count == 2, "Uncut circle skirt should have two radial side seams")
            try near(sides[0].length(), sides[1].length(), "Circle skirt radial sides")
            return sides[0].length()
        }
        return try height(front)
    }

    static func parameterPath(_ style: String) -> [String] {
        switch style {
        case "Shirt": ["shirt", "length"]
        case "Skirt2": ["skirt", "length"]
        case "SkirtCircle": ["flare-skirt", "length"]
        case "PencilSkirt": ["pencil-skirt", "length"]
        default: ["pants", "length"]
        }
    }

    static func editedOnly(_ before: GarmentCodeDesignParameters,
                           after: GarmentCodeDesignParameters, path: [String]) throws {
        var expected = before
        guard let changed = after.value(at: path) else { throw Failure.check("Edit lost its original parameter") }
        try setting(changed, path, in: &expected)
        try require(expected.jsonValue == after.jsonValue,
                    "Basic centimetre edit changed unrelated advanced parameters")
    }

    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try GarmentCodeParameterCatalog.load(from: root.appendingPathComponent(
            "TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        struct BodyFixture: Decodable { let body: [String: Double] }
        let female = try JSONDecoder().decode(BodyFixture.self, from: Data(contentsOf: root.appendingPathComponent(
            "Tests/NativePattern/Fixtures/meta-grid-female.json")))
        let bodies = [GarmentCodeBodyParameters(values: catalog.body), GarmentCodeBodyParameters(values: female.body)]
        let styles = ["Shirt", "Skirt2", "SkirtCircle", "PencilSkirt", "Pants"]
        var physicalCases = 0

        for body in bodies {
            let originalBody = body.values
            for style in styles {
                let field: Adapter.Field = style == "Shirt" ? .upperLength : .lowerLength
                var design = try select(style, catalog: catalog)
                if style == "Shirt" {
                    // This makes a naive length*waist_line implementation fail.
                    try setting(.number(0.28), ["collar", "bc_depth"], in: &design)
                    try setting(.string("VNeckHalf"), ["collar", "b_collar"], in: &design)
                }
                let originalDesign = design.jsonValue
                let initial = try control(field, body: body, design: design)
                try require(!initial.title.isEmpty && !initial.detail.isEmpty, "Centimetre inputs need a measurement definition")
                for _ in 0..<3 {
                    _ = try Adapter.overview(body: body, design: design)
                    _ = Adapter.customParameterPaths(design: design, catalog: catalog)
                }
                try require(design.jsonValue == originalDesign && body.values == originalBody,
                            "Reading/switching presentation changed source configuration")

                for target in [45.0, 65.0, 85.0] {
                    var edited = design
                    let available = try control(field, body: body, design: edited)
                    try require(available.rangeCM.contains(target), "Expected \(style) target \(target) within permitted range")
                    try Adapter.setLength(cm: target, for: field, body: body, design: &edited)
                    try editedOnly(design, after: edited, path: parameterPath(style))
                    try near(try control(field, body: body, design: edited).valueCM, target, "Centimetre readback")
                    let file = try GarmentCodeNativeGenerator.generate(body: body, design: edited)
                    try near(try measure(style, file: file), target, "\(style) actual pattern measurement")
                    try require(body.values == originalBody, "Basic edit changed body measurements")
                    physicalCases += 1
                }
                for invalid in [Double.nan, .infinity, -.infinity, -1, 0,
                                initial.rangeCM.lowerBound - 1, initial.rangeCM.upperBound + 1] {
                    try rejected(invalid, field: field, body: body, design: design)
                }
                for boundary in [initial.rangeCM.lowerBound, initial.rangeCM.upperBound] {
                    var boundaryDesign = design
                    try Adapter.setLength(cm: boundary, for: field, body: body, design: &boundaryDesign)
                    try require(boundaryDesign.validationMessages().isEmpty,
                                "Centimetre boundary roundoff escaped original parameter bounds for \(style)")
                    try near(try control(field, body: body, design: boundaryDesign).valueCM,
                             boundary, "Boundary readback")
                }
            }
        }

        // A centimetre goal can be reapplied to new measurements without
        // inventing a new solver, preserving every non-length design value.
        for style in styles {
            let field: Adapter.Field = style == "Shirt" ? .upperLength : .lowerLength
            var design = try select(style, catalog: catalog)
            try Adapter.setLength(cm: 65, for: field, body: bodies[0], design: &design)
            let oldDesign = design
            try Adapter.setLength(cm: 65, for: field, body: bodies[1], design: &design)
            try editedOnly(oldDesign, after: design, path: parameterPath(style))
            try near(try measure(style, file: GarmentCodeNativeGenerator.generate(body: bodies[1], design: design)),
                     65, "\(style) retained centimetres after body change")
            physicalCases += 1
        }

        // Waistband height is separate from skirt-body length; an attached
        // waistband must not make a 65 cm skirt-body input silently longer.
        for body in bodies {
            for band in ["StraightWB", "FittedWB"] {
                for target in [3.0, 5.0, 8.0] {
                    var design = try select("Skirt2", catalog: catalog)
                    try setting(.string(band), ["meta", "wb"], in: &design)
                    try Adapter.setLength(cm: 65, for: .lowerLength, body: body, design: &design)
                    let beforeBandEdit = design
                    try Adapter.setLength(cm: target, for: .waistbandHeight, body: body, design: &design)
                    try editedOnly(beforeBandEdit, after: design, path: ["waistband", "width"])
                    try near(try control(.waistbandHeight, body: body, design: design).valueCM, target, "Waistband height readback")
                    let file = try GarmentCodeNativeGenerator.generate(body: body, design: design)
                    try near(try measure("Skirt2", file: file), 65, "Skirt-body length excludes waistband")
                    let panels = try file.geometryPanels()
                    for name in ["wb_front", "wb_back"] {
                        guard let panel = panels[name] else { throw Failure.check("Missing attached waistband") }
                        if band == "StraightWB" {
                            try near(try height(panel), target, "Straight waistband actual depth")
                        } else {
                            let sides = panel.edges.filter { $0.curvature == nil }
                            try require(sides.count == 2, "Fitted waistband must have two radial side seams")
                            for side in sides { try near(side.length(), target, "Fitted waistband actual radial depth") }
                        }
                    }
                    physicalCases += 1
                }
            }
        }

        // Existing advanced work remains untouched when basic mode cannot
        // honestly express a component's dimensions.
        for style in ["FittedShirt", "AsymmSkirtCircle", "SkirtLevels", "GodetSkirt", "SkirtManyPanels"] {
            let design = try select(style, catalog: catalog)
            let field: Adapter.Field = style == "FittedShirt" ? .upperLength : .lowerLength
            let original = design.jsonValue
            let overview = try Adapter.overview(body: bodies[0], design: design)
            try require(!overview.controls.contains { $0.field == field } && !overview.notices.isEmpty,
                        "Unsupported \(style) showed an ineffective centimetre control")
            try require(design.jsonValue == original, "Unsupported overview reset existing design")
            try rejected(65, field: field, body: bodies[0], design: design)
        }
        var asymmetric = try select("Shirt", catalog: catalog)
        try setting(.bool(true), ["left", "enable_asym"], in: &asymmetric)
        try rejected(65, field: .upperLength, body: bodies[0], design: asymmetric)
        var collar = try select("Shirt", catalog: catalog)
        try setting(.string("Turtle"), ["collar", "component", "style"], in: &collar)
        try rejected(65, field: .upperLength, body: bodies[0], design: collar)
        var cuff = try select("Pants", catalog: catalog)
        try setting(.string("CuffBand"), ["pants", "cuff", "type"], in: &cuff)
        try rejected(65, field: .lowerLength, body: bodies[0], design: cuff)
        var diagonalHem = try select("PencilSkirt", catalog: catalog)
        try setting(.number(5), ["pencil-skirt", "low_angle"], in: &diagonalHem)
        try rejected(65, field: .lowerLength, body: bodies[0], design: diagonalHem)
        var saturatedNeck = try select("Shirt", catalog: catalog)
        try setting(.number(0.5), ["shirt", "length"], in: &saturatedNeck)
        try setting(.number(2), ["collar", "bc_depth"], in: &saturatedNeck)
        let saturated = try Adapter.overview(body: bodies[0], design: saturatedNeck)
        try require(!saturated.controls.contains { $0.field == .upperLength } &&
                    saturated.notices.contains { $0.contains("限幅") },
                    "Saturated back-neck mapping pretended to be uniquely editable")
        try rejected(65, field: .upperLength, body: bodies[0], design: saturatedNeck)
        try require(Adapter.customParameterPaths(design: saturatedNeck, catalog: catalog, body: bodies[0])
            .contains(["shirt", "length"]),
                    "A saturated, hidden custom shirt length was incorrectly considered represented")

        // MetaGarment forces a natural-waist lower component below a fitted
        // bodice. Basic mode must measure that effective configuration rather
        // than the inactive lower-rise value left in the user's parameter tree.
        for body in bodies {
            for style in ["Skirt2", "PencilSkirt", "Pants"] {
                var composed = try select("FittedShirt", catalog: catalog)
                try setting(.string(style), ["meta", "bottom"], in: &composed)
                let group = parameterPath(style)[0]
                try setting(.number(0.65), [group, "rise"], in: &composed)
                let prior = composed
                try Adapter.setLength(cm: 65, for: .lowerLength, body: body, design: &composed)
                try editedOnly(prior, after: composed, path: parameterPath(style))
                try require(composed.value(at: [group, "rise"]) == .number(0.65),
                            "Basic mode normalized a preserved advanced rise")
                let file = try GarmentCodeNativeGenerator.generate(body: body, design: composed)
                try near(try measure(style, file: file), 65, "Fitted-bodice combination effective lower length")
                physicalCases += 1
            }
        }

        var custom = try select("Shirt", catalog: catalog)
        try setting(.number(0.65), ["sleeve", "length"], in: &custom)
        try setting(.number(1.2), ["pants", "width"], in: &custom)
        try setting(.number(1.12), ["left", "shirt", "width"], in: &custom)
        var paths = Adapter.customParameterPaths(design: custom, catalog: catalog)
        try require(!paths.contains(["sleeve", "length"]) && !paths.contains(["pants", "width"]) &&
                    !paths.contains(["left", "shirt", "width"]), "Inactive advanced parameters triggered customization state")
        try setting(.bool(false), ["sleeve", "sleeveless"], in: &custom)
        paths = Adapter.customParameterPaths(design: custom, catalog: catalog)
        try require(paths.contains(["sleeve", "length"]), "Active custom sleeve length was hidden without a notice")
        let beforeLength = custom
        try Adapter.setLength(cm: 65, for: .upperLength, body: bodies[0], design: &custom)
        try editedOnly(beforeLength, after: custom, path: ["shirt", "length"])
        let customFile = try GarmentCodeNativeGenerator.generate(body: bodies[0], design: custom)
        try near(try measure("Shirt", file: customFile), 65, "Sleeved Shirt actual back-center length")
        physicalCases += 1
        paths = Adapter.customParameterPaths(design: custom, catalog: catalog)
        try require(!paths.contains(["shirt", "length"]) && !paths.contains(["meta", "upper"]),
                    "Basic-visible fields were incorrectly labelled hidden customization")

        var inactiveHood = try select("Shirt", catalog: catalog)
        try setting(.string("Turtle"), ["collar", "component", "style"], in: &inactiveHood)
        try setting(.number(1.4), ["collar", "component", "hood_length"], in: &inactiveHood)
        paths = Adapter.customParameterPaths(design: inactiveHood, catalog: catalog)
        try require(!paths.contains(["collar", "component", "hood_length"]),
                    "Inactive hood dimension was labelled as a standing-collar customization")
        var cuffs = try select("Shirt", catalog: catalog)
        try setting(.bool(false), ["sleeve", "sleeveless"], in: &cuffs)
        try setting(.string("CuffBand"), ["sleeve", "cuff", "type"], in: &cuffs)
        try setting(.number(1.4), ["sleeve", "cuff", "skirt_flare"], in: &cuffs)
        paths = Adapter.customParameterPaths(design: cuffs, catalog: catalog)
        try require(!paths.contains(["sleeve", "cuff", "skirt_flare"]),
                    "Inactive skirt cuff shape was labelled as a band-cuff customization")
        try setting(.string("CuffBandSkirt"), ["sleeve", "cuff", "type"], in: &cuffs)
        paths = Adapter.customParameterPaths(design: cuffs, catalog: catalog)
        try require(paths.contains(["sleeve", "cuff", "skirt_flare"]),
                    "Active band-skirt cuff customization was lost")

        // Sleeve presence is represented by the basic switch for ordinary
        // Shirt, not for the fitted-bodice branch that remains advanced-only.
        var fittedSleeve = try select("FittedShirt", catalog: catalog)
        try setting(.bool(false), ["sleeve", "sleeveless"], in: &fittedSleeve)
        try require(Adapter.customParameterPaths(design: fittedSleeve, catalog: catalog, body: bodies[0])
            .contains(["sleeve", "sleeveless"]),
                    "Fitted-bodice custom sleeve presence was hidden without a notice")
        var ordinarySleeve = try select("Shirt", catalog: catalog)
        try setting(.bool(false), ["sleeve", "sleeveless"], in: &ordinarySleeve)
        try require(!Adapter.customParameterPaths(design: ordinarySleeve, catalog: catalog, body: bodies[0])
            .contains(["sleeve", "sleeveless"]),
                    "The visible ordinary-Shirt sleeve switch was labelled hidden customization")

        // Whether an input can honestly represent pants.length depends on the
        // current body, not just the selected cuff/style parameters.
        var shortPants = try select("Pants", catalog: catalog)
        try setting(.number(0.25), ["pants", "length"], in: &shortPants)
        var highCrotchValues = catalog.body
        highCrotchValues["crotch_hip_diff"] = 20
        let highCrotch = GarmentCodeBodyParameters(values: highCrotchValues)
        let shortOverview = try Adapter.overview(body: highCrotch, design: shortPants)
        try require(!shortOverview.controls.contains { $0.field == .lowerLength },
                    "The short-pants regression did not actually suppress its basic control")
        try require(Adapter.customParameterPaths(design: shortPants, catalog: catalog, body: highCrotch)
            .contains(["pants", "length"]),
                    "Body-specific hidden short-pants length was incorrectly considered represented")
        try require(!Adapter.customParameterPaths(design: shortPants, catalog: catalog, body: bodies[0])
            .contains(["pants", "length"]),
                    "Customization ignored the explicit body instead of checking actual basic controls")
        try require(Adapter.customParameterPaths(design: shortPants, catalog: catalog) ==
                    Adapter.customParameterPaths(design: shortPants, catalog: catalog, body: bodies[0]),
                    "Default custom-parameter metadata body is not the catalog body")

        var invalidBody = catalog.body
        invalidBody["height"] = .nan
        try rejected(65, field: .lowerLength, body: .init(values: invalidBody),
                     design: select("Skirt2", catalog: catalog))
        var zeroHip = catalog.body
        zeroHip["hips_line"] = 0
        var bandOnly = GarmentCodeDesignParameters(catalog: catalog)
        try setting(.string("StraightWB"), ["meta", "wb"], in: &bandOnly)
        try rejected(5, field: .waistbandHeight, body: .init(values: zeroHip), design: bandOnly)

        print("PASS: basic centimetre adapter; \(physicalCases) actual generated-pattern measurements across two bodies; shared advanced configuration, atomic invalid-input rejection, active customization notices, waistband exclusions and unsupported-style safety")
    }
}
