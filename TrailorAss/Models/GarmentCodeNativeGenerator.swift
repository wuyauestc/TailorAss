import Foundation

/// Pattern-only dispatcher for the pinned GarmentCode program ports.
/// Unsupported programs fail explicitly instead of falling back to the old
/// approximate generator.
enum GarmentCodeNativeGenerator {
    static func generate(body: GarmentCodeBodyParameters,
                         design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard design.validationMessages().isEmpty else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        if case let .string(upper)? = design.value(at: ["meta", "upper"]), !upper.isEmpty {
            let upperPattern: GarmentCodePatternFile
            switch upper {
            case "Shirt":
                upperPattern = try GarmentCodePrograms.shirt(body: body, design: design)
            case "FittedShirt":
                upperPattern = try GarmentCodePrograms.fittedShirt(body: body, design: design)
            default:
                throw GarmentCodeProgramError.unsupportedParameter("meta.upper=\(upper)")
            }
            guard case let .string(bottom)? = design.value(at: ["meta", "bottom"]), !bottom.isEmpty else {
                if case let .string(beltName)? = design.value(at: ["meta", "wb"]), !beltName.isEmpty {
                    guard beltName == "StraightWB" || beltName == "FittedWB" else {
                        throw GarmentCodeProgramError.unsupportedParameter("meta.wb=\(beltName)")
                    }
                    let belt = try GarmentCodePrograms.waistband(body: body, design: design)
                    return try composeUpperWaistband(upper: upperPattern, belt: belt,
                                                     upperName: upper, waistband: beltName,
                                                     body: body, design: design)
                }
                return withProvenance(upperPattern, body: body, design: design)
            }
            var lowerDesign = design
            if upper == "FittedShirt",
               ["SkirtCircle", "AsymmSkirtCircle", "SkirtManyPanels"].contains(bottom) {
                _ = lowerDesign.setValue(.number(1), at: ["flare-skirt", "rise"])
            }
            let lowerPattern: GarmentCodePatternFile
            switch bottom {
            case "SkirtCircle":
                lowerPattern = try GarmentCodePrograms.circleSkirt(body: body, design: lowerDesign)
            case "AsymmSkirtCircle":
                lowerPattern = try GarmentCodePrograms.asymmetricCircleSkirt(body: body, design: lowerDesign)
            case "Skirt2":
                if upper == "FittedShirt" {
                    _ = lowerDesign.setValue(.number(1), at: ["skirt", "rise"])
                }
                lowerPattern = try GarmentCodePrograms.twoPanelSkirt(body: body, design: lowerDesign)
            case "SkirtManyPanels":
                lowerPattern = try GarmentCodePrograms.manyPanelSkirt(body: body, design: lowerDesign)
            case "Pants":
                if upper == "FittedShirt" {
                    _ = lowerDesign.setValue(.number(1), at: ["pants", "rise"])
                }
                lowerPattern = try GarmentCodePrograms.pants(body: body, design: lowerDesign)
            case "PencilSkirt":
                if upper == "FittedShirt" {
                    _ = lowerDesign.setValue(.number(1), at: ["pencil-skirt", "rise"])
                }
                lowerPattern = try GarmentCodePrograms.pencilSkirt(body: body, design: lowerDesign)
            case "GodetSkirt":
                if upper == "FittedShirt" {
                    let base = lowerDesign.value(at: ["godet-skirt", "base"])
                    let path = base == .string("PencilSkirt") ? ["pencil-skirt", "rise"] : ["skirt", "rise"]
                    _ = lowerDesign.setValue(.number(1), at: path)
                }
                lowerPattern = try GarmentCodePrograms.godetSkirt(body: body, design: lowerDesign)
            case "SkirtLevels":
                lowerPattern = try GarmentCodePrograms.skirtLevels(
                    body: body, design: lowerDesign,
                    requestedRise: upper == "FittedShirt" ? 1 : nil)
            default:
                throw GarmentCodeProgramError.unsupportedParameter("meta.upper + meta.bottom=\(bottom)")
            }
            let belt: GarmentCodePatternFile?
            if case let .string(beltName)? = design.value(at: ["meta", "wb"]), !beltName.isEmpty {
                guard beltName == "StraightWB" || beltName == "FittedWB" else {
                    throw GarmentCodeProgramError.unsupportedParameter("meta.wb=\(beltName)")
                }
                let risePath: [String]
                switch bottom {
                case "PencilSkirt": risePath = ["pencil-skirt", "rise"]
                case "SkirtCircle", "AsymmSkirtCircle", "SkirtManyPanels": risePath = ["flare-skirt", "rise"]
                case "SkirtLevels": risePath = ["levels-skirt", "rise"]
                case "Pants": risePath = ["pants", "rise"]
                case "GodetSkirt":
                    risePath = lowerDesign.value(at: ["godet-skirt", "base"]) == .string("PencilSkirt")
                        ? ["pencil-skirt", "rise"] : ["skirt", "rise"]
                default: risePath = ["skirt", "rise"]
                }
                let rise = upper == "FittedShirt" ? 1 : lowerDesign.value(at: risePath)?.numberValue
                belt = try GarmentCodePrograms.waistband(body: body, design: design, rise: rise)
            } else {
                belt = nil
            }
            return try composeUpperLower(upper: upperPattern, lower: lowerPattern, belt: belt,
                                         upperName: upper, body: body, design: design)
        }
        guard case let .string(bottom)? = design.value(at: ["meta", "bottom"]),
              bottom != "" else {
            if case let .string(waistband)? = design.value(at: ["meta", "wb"]),
               waistband == "StraightWB" || waistband == "FittedWB" {
                let file = try GarmentCodePrograms.waistband(body: body, design: design)
                return withProvenance(file, body: body, design: design)
            }
            throw GarmentCodeProgramError.wrongProgram("请选择一个已移植的衣服款式")
        }

        let lower: GarmentCodePatternFile
        switch bottom {
        case "SkirtCircle":
            lower = try GarmentCodePrograms.circleSkirt(body: body, design: design)
        case "AsymmSkirtCircle":
            lower = try GarmentCodePrograms.asymmetricCircleSkirt(body: body, design: design)
        case "Skirt2":
            lower = try GarmentCodePrograms.twoPanelSkirt(body: body, design: design)
        case "SkirtManyPanels":
            lower = try GarmentCodePrograms.manyPanelSkirt(body: body, design: design)
        case "Pants":
            lower = try GarmentCodePrograms.pants(body: body, design: design)
        case "PencilSkirt":
            lower = try GarmentCodePrograms.pencilSkirt(body: body, design: design)
        case "GodetSkirt":
            lower = try GarmentCodePrograms.godetSkirt(body: body, design: design)
        case "SkirtLevels":
            lower = try GarmentCodePrograms.skirtLevels(body: body, design: design)
        default:
            throw GarmentCodeProgramError.unsupportedParameter("meta.bottom=\(bottom)")
        }

        guard case let .string(waistband)? = design.value(at: ["meta", "wb"]),
              waistband == "StraightWB" || waistband == "FittedWB" else {
            return withProvenance(lower, body: body, design: design)
        }

        let risePath: [String]
        switch bottom {
        case "SkirtCircle", "AsymmSkirtCircle", "SkirtManyPanels":
            risePath = ["flare-skirt", "rise"]
        case "PencilSkirt":
            risePath = ["pencil-skirt", "rise"]
        case "SkirtLevels":
            risePath = ["levels-skirt", "rise"]
        case "Pants":
            risePath = ["pants", "rise"]
        case "GodetSkirt":
            risePath = design.value(at: ["godet-skirt", "base"]) == .string("PencilSkirt")
                ? ["pencil-skirt", "rise"] : ["skirt", "rise"]
        default:
            risePath = ["skirt", "rise"]
        }
        let rise = design.value(at: risePath)?.numberValue
        let belt = try GarmentCodePrograms.waistband(body: body, design: design, rise: rise)
        var panels = try lower.geometryPanels()
        if bottom == "SkirtManyPanels" {
            return try composeManyPanelSkirt(lower: lower, belt: belt, panels: panels,
                                             body: body, design: design, waistband: waistband)
        }
        if ["SkirtLevels", "PencilSkirt", "GodetSkirt"].contains(bottom) {
            return try composeLabeledSkirtWaistband(lower: lower, belt: belt, panels: panels,
                                                    body: body, design: design, waistband: waistband)
        }
        if bottom == "Pants" {
            return try composePantsWaistband(lower: lower, belt: belt, panels: panels,
                                             body: body, design: design, waistband: waistband)
        }
        for panelName in panels.keys {
            panels[panelName]?.edges.indices.forEach { index in
                if panels[panelName]?.edges[index].label == "lower_interface" {
                    panels[panelName]?.edges[index].label = nil
                }
            }
        }
        panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, beltPanel in beltPanel })
        let joins = try waistbandJoins(bottom: bottom, waistband: waistband,
                                       design: design)
        let lowerStitchesFirst = bottom == "SkirtCircle" ||
            (bottom == "AsymmSkirtCircle" && waistband == "FittedWB")
        let componentStitches = lowerStitchesFirst
            ? lower.pattern.stitches + belt.pattern.stitches
            : belt.pattern.stitches + lower.pattern.stitches
        return try GarmentCodePatternFile(
            geometry: panels,
            stitches: componentStitches + joins,
            parameters: provenance(body: body, design: design),
            parameterOrder: ["design", "body"]
        )
    }

    static func provenance(body: GarmentCodeBodyParameters,
                           design: GarmentCodeDesignParameters) -> [String: JSONValue] {
        ["design": design.jsonValue,
         "body": .object(body.values.mapValues(JSONValue.number))]
    }

    private static func withProvenance(_ file: GarmentCodePatternFile,
                                       body: GarmentCodeBodyParameters,
                                       design: GarmentCodeDesignParameters) -> GarmentCodePatternFile {
        GarmentCodePatternFile(pattern: file.pattern,
                               parameters: provenance(body: body, design: design),
                               parameterOrder: ["design", "body"],
                               properties: file.properties)
    }

    private static func composeUpperWaistband(upper: GarmentCodePatternFile,
                                               belt: GarmentCodePatternFile,
                                               upperName: String,
                                               waistband: String,
                                               body: GarmentCodeBodyParameters,
                                               design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard let waist = body["waist"], let backWaist = body["waist_back_width"],
              waist > backWaist, backWaist > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        var panels = try upper.geometryPanels()
        panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, replacement in replacement })
        let previousStitches = try captureStitchIDs([upper, belt], in: panels)
        func edge(_ panel: String, _ index: Int) throws -> GarmentCodeGeometryEdge {
            guard let edges = panels[panel]?.edges, edges.indices.contains(index) else {
                throw GarmentCodeGeometryError.invalidPanel(panel)
            }
            return edges[index]
        }
        let upperFront: [(String, Int)]
        let upperBack: [(String, Int)]
        if upperName == "FittedShirt" {
            let frontCount = panels["right_ftorso"]?.edges.count ?? 0
            let backCount = panels["left_btorso"]?.edges.count ?? 0
            upperFront = [("right_ftorso", frontCount - 4), ("right_ftorso", frontCount - 1),
                          ("left_ftorso", 0), ("left_ftorso", 3)]
            upperBack = backWaist >= (body["back_width"] ?? .infinity)
                ? [("left_btorso", backCount - 1), ("right_btorso", 0)]
                : [("left_btorso", backCount - 7), ("left_btorso", backCount - 4),
                         ("left_btorso", backCount - 1),
                         ("right_btorso", 0), ("right_btorso", 3), ("right_btorso", 6)]
        } else {
            upperFront = [("right_ftorso", (panels["right_ftorso"]?.edges.count ?? 0) - 1),
                          ("left_ftorso", 0)]
            upperBack = [("left_btorso", (panels["left_btorso"]?.edges.count ?? 0) - 1),
                         ("right_btorso", 0)]
        }
        func references(_ locations: [(String, Int)], denominator: Double) throws -> [GarmentCodeInterfaceEdgeReference] {
            try locations.map { name, index in
                let selected = try edge(name, index)
                let ruffle = upperName == "FittedShirt" ? 1 : selected.length() / denominator
                return .init(panel: name, edge: selected.id, ruffle: ruffle)
            }
        }
        var upperInterface = GarmentCodeInterface(edges:
            try references(upperFront, denominator: (waist - backWaist) / 2) +
                references(upperBack, denominator: backWaist / 2))
        let fittedBelt = waistband == "FittedWB"
        let frontTop = fittedBelt ? 3 : 2
        let backTop = fittedBelt ? 0 : 1
        let frontEdge = try edge("wb_front", frontTop)
        let backEdge = try edge("wb_back", backTop)
        var beltTop = GarmentCodeInterface(edges: [
            .init(panel: "wb_front", edge: frontEdge.id, reversed: true,
                  ruffle: frontEdge.length() / (waist - backWaist)),
            .init(panel: "wb_back", edge: backEdge.id, reversed: true,
                  ruffle: backEdge.length() / backWaist)
        ])
        let joins = try GarmentCodeStitchingRule.assemble(&upperInterface, &beltTop, panels: &panels)
        let stitches = try resolveStitchIDs(previousStitches, in: panels)
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches + joins,
                                          parameters: provenance(body: body, design: design),
                                          parameterOrder: ["design", "body"])
    }

    private static func composeUpperLower(upper: GarmentCodePatternFile,
                                          lower: GarmentCodePatternFile,
                                          belt: GarmentCodePatternFile?,
                                          upperName: String,
                                          body: GarmentCodeBodyParameters,
                                          design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard let waist = body["waist"], let backWaist = body["waist_back_width"],
              waist > backWaist, backWaist > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        var panels = try upper.geometryPanels()
        panels.merge(try lower.geometryPanels(), uniquingKeysWith: { _, replacement in replacement })
        if let belt {
            panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, replacement in replacement })
        }
        let previousStitches = try captureStitchIDs([upper] + (belt.map { [$0] } ?? []) + [lower], in: panels)
        func ref(_ panel: String, _ index: Int,
                 reversed: Bool = false, ruffle: Double = 1) throws -> GarmentCodeInterfaceEdgeReference {
            guard let edges = panels[panel]?.edges, edges.indices.contains(index) else {
                throw GarmentCodeGeometryError.invalidPanel(panel)
            }
            return .init(panel: panel, edge: edges[index].id, reversed: reversed, ruffle: ruffle)
        }
        let upperFrontIndices: [(String, Int)]
        let upperBackIndices: [(String, Int)]
        if upperName == "FittedShirt" {
            guard let frontEdgeCount = panels["right_ftorso"]?.edges.count,
                  let backEdgeCount = panels["left_btorso"]?.edges.count,
                  frontEdgeCount >= 4, backEdgeCount >= 5 else {
                throw GarmentCodeGeometryError.invalidPanel("fitted torso")
            }
            // Collar and strapless projections change the number of top
            // edges; the darted lower interface keeps its order at the end
            // of these two contours.
            upperFrontIndices = [("right_ftorso", frontEdgeCount - 4),
                                 ("right_ftorso", frontEdgeCount - 1),
                                 ("left_ftorso", 0), ("left_ftorso", 3)]
            upperBackIndices = backWaist >= (body["back_width"] ?? .infinity)
                ? [("left_btorso", backEdgeCount - 1), ("right_btorso", 0)]
                : [("left_btorso", backEdgeCount - 7),
                                ("left_btorso", backEdgeCount - 4),
                                ("left_btorso", backEdgeCount - 1),
                                ("right_btorso", 0), ("right_btorso", 3), ("right_btorso", 6)]
        } else {
            upperFrontIndices = [("right_ftorso", panels["right_ftorso"]!.edges.count - 1),
                                 ("left_ftorso", 0)]
            upperBackIndices = [("left_btorso", panels["left_btorso"]!.edges.count - 1),
                                ("right_btorso", 0)]
        }
        let manyPanelCount = design.value(at: ["meta", "bottom"]) == .string("SkirtManyPanels")
            ? Int(design.value(at: ["flare-skirt", "skirt-many-panels", "n_panels"])?.numberValue ?? 0) : 0
        let isPants = design.value(at: ["meta", "bottom"]) == .string("Pants")
        let lowerFront: [GarmentCodeInterfaceEdgeReference]
        let lowerBack: [GarmentCodeInterfaceEdgeReference]
        let manyPanelTop: [GarmentCodeInterfaceEdgeReference]
        if manyPanelCount > 0 {
            lowerFront = []
            lowerBack = []
            manyPanelTop = try (0..<manyPanelCount).flatMap { index in
                try interfaceReferences(panel: "skirt_panel_\(index)", label: "lower_interface", panels: panels)
            }
        } else if isPants {
            lowerFront = []
            lowerBack = []
            manyPanelTop = []
        } else {
            lowerFront = Array(try interfaceReferences(panel: "skirt_front", label: "lower_interface", panels: panels).reversed())
            lowerBack = try interfaceReferences(panel: "skirt_back", label: "lower_interface", panels: panels)
            manyPanelTop = []
        }
        func length(_ refs: [(String, Int)]) throws -> Double {
            try refs.reduce(0) { total, item in
                guard let edges = panels[item.0]?.edges, edges.indices.contains(item.1) else {
                    throw GarmentCodeGeometryError.invalidPanel(item.0)
                }
                return total + edges[item.1].length()
            }
        }
        let frontBodyWaist = waist - backWaist
        // Tee.Torso* assigns the gather coefficient to each half-panel
        // independently. A left/right asymmetric shirt therefore cannot use
        // one aggregate coefficient for the full front or back interface.
        let upperFrontRuffles = try upperFrontIndices.map { item in
            upperName == "FittedShirt" ? 1 : try length([item]) / (frontBodyWaist / 2)
        }
        let upperBackRuffles = try upperBackIndices.map { item in
            upperName == "FittedShirt" ? 1 : try length([item]) / (backWaist / 2)
        }
        let lowerFrontRuffle = manyPanelCount > 0 || isPants ? 1 : try interfaceLength(lowerFront, in: panels) / frontBodyWaist
        let lowerBackRuffle = manyPanelCount > 0 || isPants ? 1 : try interfaceLength(lowerBack, in: panels) / backWaist
        let upperRefs = try zip(upperFrontIndices, upperFrontRuffles).map { item, ruffle in
            try ref(item.0, item.1, ruffle: ruffle)
        } + zip(upperBackIndices, upperBackRuffles).map { item, ruffle in
            try ref(item.0, item.1, ruffle: ruffle)
        }
        var pantsTop: [GarmentCodeInterfaceEdgeReference] = []
        if isPants {
            for (panelName, reverseOrder, denominator) in [
                ("pant_f_r", true, frontBodyWaist / 2),
                ("pant_f_l", true, frontBodyWaist / 2),
                ("pant_b_l", true, backWaist / 2),
                ("pant_b_r", true, backWaist / 2)
            ] {
                let segment = try interfaceReferences(panel: panelName, label: "lower_interface", panels: panels)
                let ruffle = try interfaceLength(segment, in: panels) / denominator
                pantsTop += (reverseOrder ? Array(segment.reversed()) : segment).map {
                    .init(panel: $0.panel, edge: $0.edge, reversed: true, ruffle: ruffle)
                }
            }
        }
        let lowerRefs: [GarmentCodeInterfaceEdgeReference] = pantsTop + manyPanelTop.map {
            GarmentCodeInterfaceEdgeReference(panel: $0.panel, edge: $0.edge, reversed: true)
        } + lowerFront.map {
            GarmentCodeInterfaceEdgeReference(panel: $0.panel, edge: $0.edge,
                                               reversed: true, ruffle: lowerFrontRuffle)
        } + lowerBack.reversed().map {
            GarmentCodeInterfaceEdgeReference(panel: $0.panel, edge: $0.edge,
                                               reversed: true, ruffle: lowerBackRuffle)
        }
        var upperInterface = GarmentCodeInterface(edges: upperRefs)
        var joins: [GarmentCodeStitch] = []
        if belt != nil {
            let fittedBelt = design.value(at: ["meta", "wb"]) == .string("FittedWB")
            let frontTop = fittedBelt ? 3 : 2
            let backTop = fittedBelt ? 0 : 1
            let frontBottom = fittedBelt ? 1 : 0
            let backBottom = fittedBelt ? 2 : 3
            let frontTopRuffle = panels["wb_front"]!.edges[frontTop].length() / frontBodyWaist
            let backTopRuffle = panels["wb_back"]!.edges[backTop].length() / backWaist
            let frontBottomRuffle = panels["wb_front"]!.edges[frontBottom].length() / frontBodyWaist
            let backBottomRuffle = panels["wb_back"]!.edges[backBottom].length() / backWaist
            var beltBottom = GarmentCodeInterface(edges: [
                try ref("wb_front", frontBottom, ruffle: frontBottomRuffle),
                try ref("wb_back", backBottom, ruffle: backBottomRuffle)
            ])
            var beltTop = GarmentCodeInterface(edges: [
                try ref("wb_front", frontTop, reversed: true, ruffle: frontTopRuffle),
                try ref("wb_back", backTop, reversed: true, ruffle: backTopRuffle)
            ])
            let upperJoins = try GarmentCodeStitchingRule.assemble(&upperInterface, &beltTop, panels: &panels)
            let upperJoinIDs = try captureStitchIDs(upperJoins, in: panels)
            var lowerInterface = GarmentCodeInterface(edges: lowerRefs)
            let lowerJoins = try GarmentCodeStitchingRule.assemble(&beltBottom, &lowerInterface, panels: &panels)
            joins = try resolveStitchIDs(upperJoinIDs, in: panels) + lowerJoins
            for name in ["skirt_front", "skirt_back", "pant_f_r", "pant_f_l", "pant_b_l", "pant_b_r"] +
                (0..<manyPanelCount).map({ "skirt_panel_\($0)" }) {
                panels[name]?.edges.indices.forEach { index in
                    if panels[name]?.edges[index].label == "lower_interface" {
                        panels[name]?.edges[index].label = nil
                    }
                }
            }
        } else {
            var lowerInterface = GarmentCodeInterface(edges: lowerRefs)
            joins = try GarmentCodeStitchingRule.assemble(&upperInterface, &lowerInterface,
                                                            panels: &panels)
        }
        let stitches = try resolveStitchIDs(previousStitches, in: panels)
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches + joins,
                                          parameters: provenance(body: body, design: design),
                                          parameterOrder: ["design", "body"])
    }

    private static func waistbandJoins(bottom: String, waistband: String,
                                       design: GarmentCodeDesignParameters) throws -> [GarmentCodeStitch] {
        let beltFront = waistband == "StraightWB" ? 0 : 1
        let beltBack = waistband == "StraightWB" ? 3 : 2
        switch bottom {
        case "SkirtCircle", "AsymmSkirtCircle":
            let addsFrontCut = design.value(at: ["flare-skirt", "cut", "add"]) == .bool(true) &&
                (design.value(at: ["flare-skirt", "cut", "place"])?.numberValue ?? 0) > 0
            let frontTop = addsFrontCut ? 6 : 3
            let backTop = 0
            return [
                .init(sides: [.init(panel: "wb_front", edge: beltFront), .init(panel: "skirt_front", edge: frontTop)]),
                .init(sides: [.init(panel: "wb_back", edge: beltBack), .init(panel: "skirt_back", edge: backTop)])
            ]
        case "Skirt2":
            let hasBottomCut = (design.value(at: ["skirt", "bottom_cut"])?.numberValue ?? 0) > 0
            return [
                .init(sides: [.init(panel: "wb_front", edge: beltFront), .init(panel: "skirt_front", edge: hasBottomCut ? 3 : 2)]),
                .init(sides: [.init(panel: "wb_back", edge: beltBack), .init(panel: "skirt_back", edge: hasBottomCut ? 2 : 1)])
            ]
        default:
            throw GarmentCodeProgramError.unsupportedParameter("\(bottom)+\(waistband) 组合接口")
        }
    }

    private static func composeManyPanelSkirt(lower: GarmentCodePatternFile,
                                              belt: GarmentCodePatternFile,
                                              panels lowerPanels: [String: GarmentCodePanelGeometry],
                                              body: GarmentCodeBodyParameters,
                                              design: GarmentCodeDesignParameters,
                                              waistband: String) throws -> GarmentCodePatternFile {
        guard let waist = body["waist"], let backWaist = body["waist_back_width"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        guard let lowerPanelsCount = design.value(at: ["flare-skirt", "skirt-many-panels", "n_panels"])?.numberValue,
              lowerPanelsCount.isFinite else {
            throw GarmentCodeProgramError.missingDesignParameter("flare-skirt.skirt-many-panels.n_panels")
        }
        guard lowerPanelsCount.rounded() == lowerPanelsCount else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let count = Int(lowerPanelsCount)
        var panels = lowerPanels
        for name in panels.keys {
            panels[name]?.edges.indices.forEach { index in
                if panels[name]?.edges[index].label == "lower_interface" {
                    panels[name]?.edges[index].label = nil
                }
            }
        }
        panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, beltPanel in beltPanel })

        let frontBeltEdge = waistband == "StraightWB" ? 0 : 1
        let backBeltEdge = waistband == "StraightWB" ? 3 : 2
        guard let frontBelt = panels["wb_front"], frontBelt.edges.indices.contains(frontBeltEdge),
              let backBelt = panels["wb_back"], backBelt.edges.indices.contains(backBeltEdge) else {
            throw GarmentCodeGeometryError.invalidPanel("waistband")
        }
        let frontProportion = waist - backWaist
        guard frontProportion > 0, backWaist > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        var beltInterface = GarmentCodeInterface(edges: [
            .init(panel: "wb_front", edge: frontBelt.edges[frontBeltEdge].id,
                  ruffle: frontBelt.edges[frontBeltEdge].length() / frontProportion),
            .init(panel: "wb_back", edge: backBelt.edges[backBeltEdge].id,
                  ruffle: backBelt.edges[backBeltEdge].length() / backWaist)
        ])
        var skirtInterfaceEdges: [GarmentCodeInterfaceEdgeReference] = []
        for index in 0..<count {
            let name = "skirt_panel_\(index)"
            guard let panel = panels[name], panel.edges.indices.contains(2) else {
                throw GarmentCodeGeometryError.invalidPanel(name)
            }
            skirtInterfaceEdges.append(.init(panel: name, edge: panel.edges[2].id,
                                             reversed: true))
        }
        var skirtInterface = GarmentCodeInterface(edges: skirtInterfaceEdges)

        let capturedStitches = try captureStitchIDs([lower, belt], in: panels)
        let attachment = try GarmentCodeStitchingRule.assemble(&beltInterface, &skirtInterface,
                                                                panels: &panels)
        let componentStitches = try resolveStitchIDs(capturedStitches, in: panels)
        return try GarmentCodePatternFile(
            geometry: panels,
            stitches: componentStitches + attachment,
            parameters: provenance(body: body, design: design),
            parameterOrder: ["design", "body"]
        )
    }

    private static func composeLabeledSkirtWaistband(lower: GarmentCodePatternFile,
                                                     belt: GarmentCodePatternFile,
                                                     panels lowerPanels: [String: GarmentCodePanelGeometry],
                                                     body: GarmentCodeBodyParameters,
                                                     design: GarmentCodeDesignParameters,
                                                     waistband: String) throws -> GarmentCodePatternFile {
        guard let waist = body["waist"], let backWaist = body["waist_back_width"],
              waist > backWaist, backWaist > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        var panels = lowerPanels
        panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, beltPanel in beltPanel })
        let records = try captureStitchIDs([belt, lower], in: panels)
        let frontTopReferences = Array(try interfaceReferences(panel: "skirt_front", label: "lower_interface",
                                                                panels: panels).reversed())
        let backTopReferences = Array(try interfaceReferences(panel: "skirt_back", label: "lower_interface",
                                                               panels: panels).reversed())
        let frontBottomEdge = waistband == "StraightWB" ? 0 : 1
        let backBottomEdge = waistband == "StraightWB" ? 3 : 2
        let frontBand = panels["wb_front"]
        let backBand = panels["wb_back"]
        guard let frontBand, frontBand.edges.indices.contains(frontBottomEdge),
              let backBand, backBand.edges.indices.contains(backBottomEdge) else {
            throw GarmentCodeGeometryError.invalidPanel("waistband")
        }
        let frontBodyWidth = waist - backWaist
        let frontInterfaceLength = try interfaceLength(frontTopReferences, in: panels)
        let backInterfaceLength = try interfaceLength(backTopReferences, in: panels)
        let frontRuffle = frontInterfaceLength / frontBodyWidth
        let backRuffle = backInterfaceLength / backWaist
        var beltFront = GarmentCodeInterface(edges: [
            .init(panel: "wb_front", edge: frontBand.edges[frontBottomEdge].id,
                  ruffle: frontBand.edges[frontBottomEdge].length() / frontBodyWidth)
        ])
        var skirtFront = GarmentCodeInterface(edges: frontTopReferences.map {
            .init(panel: $0.panel, edge: $0.edge, reversed: $0.reversed,
                  ruffle: frontRuffle)
        })
        var beltBack = GarmentCodeInterface(edges: [
            .init(panel: "wb_back", edge: backBand.edges[backBottomEdge].id,
                  ruffle: backBand.edges[backBottomEdge].length() / backWaist)
        ])
        var skirtBack = GarmentCodeInterface(edges: backTopReferences.map {
            .init(panel: $0.panel, edge: $0.edge, reversed: $0.reversed,
                  ruffle: backRuffle)
        })
        let frontJoin = try GarmentCodeStitchingRule.assemble(&beltFront, &skirtFront, panels: &panels)
        let backJoin = try GarmentCodeStitchingRule.assemble(&beltBack, &skirtBack, panels: &panels)
        for name in panels.keys where name == "skirt_front" || name == "skirt_back" {
            panels[name]?.edges.indices.forEach { index in
                if panels[name]?.edges[index].label == "lower_interface" {
                    panels[name]?.edges[index].label = nil
                }
            }
        }
        let componentStitches = try resolveStitchIDs(records, in: panels)
        return try GarmentCodePatternFile(
            geometry: panels,
            stitches: componentStitches + frontJoin + backJoin,
            parameters: provenance(body: body, design: design),
            parameterOrder: ["design", "body"]
        )
    }

    private static func composePantsWaistband(lower: GarmentCodePatternFile,
                                               belt: GarmentCodePatternFile,
                                               panels lowerPanels: [String: GarmentCodePanelGeometry],
                                               body: GarmentCodeBodyParameters,
                                               design: GarmentCodeDesignParameters,
                                               waistband: String) throws -> GarmentCodePatternFile {
        guard let waist = body["waist"], let backWaist = body["waist_back_width"],
              waist > backWaist, backWaist > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        var panels = lowerPanels
        panels.merge(try belt.geometryPanels(), uniquingKeysWith: { _, replacement in replacement })
        let previousStitches = try captureStitchIDs([belt, lower], in: panels)
        let frontWidth = waist - backWaist
        let frontBandIndex = waistband == "FittedWB" ? 1 : 0
        let backBandIndex = waistband == "FittedWB" ? 2 : 3
        guard let frontPanel = panels["wb_front"], frontPanel.edges.indices.contains(frontBandIndex),
              let backPanel = panels["wb_back"], backPanel.edges.indices.contains(backBandIndex) else {
            throw GarmentCodeGeometryError.invalidPanel("waistband")
        }
        let frontBand = frontPanel.edges[frontBandIndex]
        let backBand = backPanel.edges[backBandIndex]
        var beltBottom = GarmentCodeInterface(edges: [
            .init(panel: "wb_front", edge: frontBand.id,
                  ruffle: frontBand.length() / frontWidth),
            .init(panel: "wb_back", edge: backBand.id,
                  ruffle: backBand.length() / backWaist)
        ])
        var pantsEdges: [GarmentCodeInterfaceEdgeReference] = []
        for (panelName, reverseOrder, denominator) in [
            ("pant_f_r", true, frontWidth / 2),
            ("pant_f_l", true, frontWidth / 2),
            ("pant_b_l", true, backWaist / 2),
            ("pant_b_r", true, backWaist / 2)
        ] {
            let refs = try interfaceReferences(panel: panelName, label: "lower_interface", panels: panels)
            let ruffle = try interfaceLength(refs, in: panels) / denominator
            pantsEdges += (reverseOrder ? Array(refs.reversed()) : refs).map {
                .init(panel: $0.panel, edge: $0.edge, reversed: true, ruffle: ruffle)
            }
        }
        var pantsTop = GarmentCodeInterface(edges: pantsEdges)
        let joins = try GarmentCodeStitchingRule.assemble(&beltBottom, &pantsTop, panels: &panels)
        for name in ["pant_f_r", "pant_f_l", "pant_b_l", "pant_b_r"] {
            panels[name]?.edges.indices.forEach { index in
                if panels[name]?.edges[index].label == "lower_interface" {
                    panels[name]?.edges[index].label = nil
                }
            }
        }
        let componentStitches = try resolveStitchIDs(previousStitches, in: panels)
        return try GarmentCodePatternFile(geometry: panels, stitches: componentStitches + joins,
                                          parameters: provenance(body: body, design: design),
                                          parameterOrder: ["design", "body"])
    }

    private static func interfaceReferences(panel panelName: String,
                                            label: String,
                                            panels: [String: GarmentCodePanelGeometry]) throws -> [GarmentCodeInterfaceEdgeReference] {
        guard let panel = panels[panelName] else { throw GarmentCodeGeometryError.invalidPanel(panelName) }
        let refs = panel.edges.filter { $0.label == label }
        guard !refs.isEmpty else { throw GarmentCodeGeometryError.invalidPanel(panelName) }
        return refs.map { edge in
            .init(panel: panelName, edge: edge.id)
        }
    }

    private static func interfaceLength(_ references: [GarmentCodeInterfaceEdgeReference],
                                        in panels: [String: GarmentCodePanelGeometry]) throws -> Double {
        try references.reduce(0) { length, reference in
            guard let panel = panels[reference.panel],
                  let edge = panel.edges.first(where: { $0.id == reference.edge }) else {
                throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
            }
            return length + edge.length()
        }
    }

    private struct StitchIDRecord {
        var sides: [(panel: String, edgeID: String)]
        var rightWrong: Bool
    }

    private static func captureStitchIDs(_ files: [GarmentCodePatternFile],
                                         in panels: [String: GarmentCodePanelGeometry]) throws -> [StitchIDRecord] {
        try captureStitchIDs(files.flatMap { $0.pattern.stitches }, in: panels)
    }

    private static func captureStitchIDs(_ stitches: [GarmentCodeStitch],
                                         in panels: [String: GarmentCodePanelGeometry]) throws -> [StitchIDRecord] {
        try stitches.map { stitch in
            let sides = try stitch.sides.map { side -> (panel: String, edgeID: String) in
                guard let panel = panels[side.panel], panel.edges.indices.contains(side.edge) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(side.panel, "\(side.edge)")
                }
                return (side.panel, panel.edges[side.edge].id)
            }
            return StitchIDRecord(sides: sides, rightWrong: stitch.rightWrong)
        }
    }

    private static func resolveStitchIDs(_ records: [StitchIDRecord],
                                         in panels: [String: GarmentCodePanelGeometry]) throws -> [GarmentCodeStitch] {
        try records.map { record in
            let sides = try record.sides.map { reference -> GarmentCodeStitchSide in
                guard let panel = panels[reference.panel],
                      let index = panel.edges.firstIndex(where: { $0.id == reference.edgeID }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edgeID)
                }
                return .init(panel: reference.panel, edge: index)
            }
            return .init(sides: sides, rightWrong: record.rightWrong)
        }
    }
}
