import Foundation

/// Bezier paths extracted from the fixed upstream SIGGRAPH SVG. The resource
/// stores edge-local controls at one centimetre height, so arbitrary garment
/// widths can be reconstructed without an SVG parser in the iOS app.
enum GarmentCodeSiggraphShape {
    private struct EdgeRecord: Decodable {
        let start: [Double]
        let end: [Double]
        let controls: [[Double]]
    }

    private struct RecordFile: Decodable {
        let sourceCommit: String
        let targetHeightCm: Double
        let left: [[EdgeRecord]]
        let right: [[EdgeRecord]]

        enum CodingKeys: String, CodingKey {
            case sourceCommit = "source_commit"
            case targetHeightCm = "target_height_cm"
            case left, right
        }
    }

    static func load(width: Double) throws
        -> (left: [[GarmentCodeGeometryEdge]], right: [[GarmentCodeGeometryEdge]]) {
        guard width.isFinite, width > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let repoResource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/GarmentCodeSiggraphShape.json")
        let resource = Bundle.main.url(forResource: "GarmentCodeSiggraphShape", withExtension: "json")
            ?? repoResource
        let file = try JSONDecoder().decode(RecordFile.self, from: Data(contentsOf: resource))
        guard file.sourceCommit == "d449629979028123a5c4dc9e732a2ec19b7fce31",
              file.targetHeightCm == 1,
              file.left.count == 4, file.right.count == 4 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        func edges(_ records: [[EdgeRecord]], side: String) throws -> [[GarmentCodeGeometryEdge]] {
            try records.enumerated().map { sequenceIndex, sequence in
                try sequence.enumerated().map { edgeIndex, item in
                    guard item.start.count == 2, item.end.count == 2,
                          (1...2).contains(item.controls.count),
                          item.controls.allSatisfy({ $0.count == 2 }) else {
                        throw GarmentCodeProgramError.invalidMeasurements
                    }
                    return GarmentCodeGeometryEdge(
                        id: "siggraph-\(side)-\(sequenceIndex)-\(edgeIndex)",
                        start: .init(x: item.start[0] * width, y: item.start[1] * width),
                        end: .init(x: item.end[0] * width, y: item.end[1] * width),
                        curvature: .init(type: item.controls.count == 1 ? "quadratic" : "cubic",
                                         params: item.controls))
                }
            }
        }
        return (try edges(file.left, side: "left"),
                try edges(file.right, side: "right"))
    }
}

/// Pattern-only garment program ports from the pinned GarmentCode revision.
/// Each program consumes the upstream design tree and BodyParameters values,
/// then returns the official BasicPattern JSON envelope.
enum GarmentCodePrograms {
    /// Pattern-only port of the plain `Shirt` torso, including the default
    /// projected CircleNeckHalf and ArmholeCurve. The upper component's other
    /// sleeve, collar, asymmetry and fitted branches are ported separately.
    static func shirt(body: GarmentCodeBodyParameters,
                      design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "upper"]) == "Shirt" else {
            throw GarmentCodeProgramError.wrongProgram("meta.upper 必须选择 Shirt")
        }
        if design.value(at: ["left", "enable_asym"]) == .bool(true) {
            return try asymmetricUpper(body: body, design: design, fitted: false)
        }
        if selectedOption(design, path: ["collar", "component", "style"]) == "Hood2Panels" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "f_collar"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachHood(to: shirt(body: body, design: torsoDesign), body: body, design: design)
        }
        if selectedOption(design, path: ["collar", "component", "style"]) == "SimpleLapel" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachSimpleLapel(to: shirt(body: body, design: torsoDesign),
                                         design: design)
        }
        if selectedOption(design, path: ["collar", "component", "style"]) == "Turtle" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "f_collar"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachTurtleCollar(to: shirt(body: body, design: torsoDesign), design: design)
        }
        let sleeveless = design.value(at: ["sleeve", "sleeveless"]) == .bool(true)
        guard sleeveless || design.value(at: ["sleeve", "sleeveless"]) == .bool(false),
              (design.value(at: ["collar", "component", "style"]) == nil ||
               design.value(at: ["collar", "component", "style"]) == .null),
              design.value(at: ["left", "enable_asym"]) == .bool(false) else {
            throw GarmentCodeProgramError.unsupportedParameter("Shirt collar/asymmetry")
        }
        guard let bust = body["bust"], let backWidth = body["back_width"],
              let shoulderWidth = body["shoulder_w"], let waistLine = body["waist_line"],
              let shoulderAngle = body["_shoulder_incl"], let armscyeDepth = body["_armscye_depth"],
              let sleeveBalance = body["_base_sleeve_balance"], let neckWidth = body["neck_w"],
              let bustLine = body["_bust_line"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let widthRatio = try number(design, path: ["shirt", "width"])
        let flare = try number(design, path: ["shirt", "flare"])
        let lengthRatio = try number(design, path: ["shirt", "length"])
        let sleeveWidthRatio = try number(design, path: ["sleeve", "connecting_width"])
        let collarWidthRatio = try number(design, path: ["collar", "width"])
        let frontDepthRatio = try number(design, path: ["collar", "fc_depth"])
        let backDepthRatio = try number(design, path: ["collar", "bc_depth"])
        guard bust > backWidth, widthRatio > 0, flare > 0, lengthRatio > 0,
              armscyeDepth > 0, shoulderWidth > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let tangent = tan(shoulderAngle * .pi / 180)
        let frontBodyWidth = (bust - backWidth) / 2
        let naturalFrontFraction = frontBodyWidth / bust
        let frontWidth = naturalFrontFraction * widthRatio * bust
        let backPanelWidth = backWidth / 2 * widthRatio
        let frontLength = lengthRatio * waistLine -
            tangent * ((naturalFrontFraction - (0.5 - naturalFrontFraction)) * bust)
        let backLength = lengthRatio * waistLine
        let shoulderEdgeLength = min(frontWidth, backPanelWidth) * hypot(1, tangent)
        let connectingWidth = min(armscyeDepth * (1 + sleeveWidthRatio), shoulderEdgeLength - 1)
        let maximumCollarWidth = sleeveBalance - 2
        let collarWidth = collarWidthRatio >= 0
            ? interpolate(neckWidth, maximumCollarWidth, collarWidthRatio)
            : interpolate(0, neckWidth, 1 + collarWidthRatio)
        let halfCollar = collarWidth / 2
        guard frontLength > 1, backLength > 1, connectingWidth > 0,
              collarWidth > 0, halfCollar < min(frontWidth, backPanelWidth) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let frontDepth = min(frontDepthRatio * bustLine, frontLength - 1) +
            tangent * (frontWidth - halfCollar)
        let backDepth = min(backDepthRatio * bustLine, backLength - 1) +
            tangent * (backPanelWidth - halfCollar)
        let rightFront = try plainShirtPanel(name: "right_ftorso", front: true,
                                             topWidth: frontWidth, bottomWidth: frontWidth * flare,
                                             length: frontLength, shoulderTangent: tangent,
                                             connectingWidth: connectingWidth,
                                             sleeveBalance: sleeveBalance / 2,
                                             halfCollar: halfCollar, collarDepth: frontDepth,
                                             collarWidth: collarWidth, armholeLabel: "right_armhole",
                                             collarLabel: "right_collar")
        let rightBack = try plainShirtPanel(name: "right_btorso", front: false,
                                            topWidth: backPanelWidth, bottomWidth: backPanelWidth * flare,
                                            length: backLength, shoulderTangent: tangent,
                                            connectingWidth: connectingWidth,
                                            sleeveBalance: sleeveBalance / 2,
                                            halfCollar: halfCollar, collarDepth: backDepth,
                                            collarWidth: collarWidth, armholeLabel: "right_armhole",
                                            collarLabel: "right_collar")
        let stitches: [GarmentCodeStitch] = [
            .init(sides: [.init(panel: "right_ftorso", edge: 2), .init(panel: "right_btorso", edge: 3)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 4), .init(panel: "right_btorso", edge: 1)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 3), .init(panel: "left_btorso", edge: 2)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 1), .init(panel: "left_btorso", edge: 4)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 0), .init(panel: "left_ftorso", edge: 5)]),
            .init(sides: [.init(panel: "right_btorso", edge: 5), .init(panel: "left_btorso", edge: 0)])
        ]
        var upperDesign = design
        if !sleeveless {
            let cuffType = selectedOption(design, path: ["sleeve", "cuff", "type"])
            guard cuffType == nil || ["CuffBand", "CuffSkirt", "CuffBandSkirt"].contains(cuffType!) else {
                throw GarmentCodeProgramError.unsupportedParameter("Shirt sleeve cuff type")
            }
            _ = upperDesign.setValue(.string("ArmholeCurve"), at: ["sleeve", "armhole_shape"])
        }
        let torso = try finishUpperNeckline(front: rightFront, back: rightBack,
                                            design: upperDesign, baseStitches: stitches)
        guard !sleeveless else { return torso }
        let frontWidthAtArmhole = frontWidth + connectingWidth * (frontWidth * (flare - 1) / frontLength)
        let backWidthAtArmhole = backPanelWidth + connectingWidth * (backPanelWidth * (flare - 1) / backLength)
        return try attachSleeves(to: torso, body: body, design: design,
                                 frontWidth: frontWidthAtArmhole,
                                 backWidth: backWidthAtArmhole,
                                 connectingWidth: connectingWidth)
    }

    private static func asymmetricUpper(body: GarmentCodeBodyParameters,
                                        design: GarmentCodeDesignParameters,
                                        fitted: Bool) throws -> GarmentCodePatternFile {
        guard let leftParameters = design.design["left"],
              var leftShirt = leftParameters.children["shirt"],
              var leftCollar = leftParameters.children["collar"],
              let leftSleeve = leftParameters.children["sleeve"],
              let rightShirt = design.design["shirt"],
              let rightCollar = design.design["collar"] else {
            throw GarmentCodeProgramError.missingDesignParameter("left")
        }
        var rightDesign = design
        _ = rightDesign.setValue(.bool(false), at: ["left", "enable_asym"])
        _ = rightDesign.setValue(.null, at: ["collar", "component", "style"])
        var leftDesign = rightDesign
        leftShirt.children["length"] = rightShirt.children["length"]
        leftCollar.children["fc_depth"] = rightCollar.children["fc_depth"]
        leftCollar.children["bc_depth"] = rightCollar.children["bc_depth"]
        leftCollar.children["component"] = rightDesign.design["collar"]?.children["component"]
        leftDesign.design["shirt"] = leftShirt
        leftDesign.design["collar"] = leftCollar
        leftDesign.design["sleeve"] = leftSleeve
        let rightPattern = try fitted
            ? fittedShirt(body: body, design: rightDesign)
            : shirt(body: body, design: rightDesign)
        let leftPattern = try fitted
            ? fittedShirt(body: body, design: leftDesign)
            : shirt(body: body, design: leftDesign)
        let rightPanels = try rightPattern.geometryPanels()
        let leftPanels = try leftPattern.geometryPanels()
        var panels: [String: GarmentCodePanelGeometry] = [:]
        // Sleeve cuffs use upstream's sl_<side>_ prefix, unlike torso/sleeve
        // panels. Preserve the entire half-component, including its cuffs.
        func belongs(_ name: String, to side: String) -> Bool {
            name.hasPrefix("\(side)_") || name.hasPrefix("sl_\(side)_")
        }
        for (name, panel) in rightPanels where belongs(name, to: "right") { panels[name] = panel }
        for (name, panel) in leftPanels where belongs(name, to: "left") { panels[name] = panel }
        var stitches = rightPattern.pattern.stitches.filter { stitch in
            stitch.sides.allSatisfy { belongs($0.panel, to: "right") }
        }
        stitches += leftPattern.pattern.stitches.filter { stitch in
            stitch.sides.allSatisfy { belongs($0.panel, to: "left") }
        }
        guard let rightFrontCount = panels["right_ftorso"]?.edges.count,
              let rightBackCount = panels["right_btorso"]?.edges.count,
              let leftFrontCount = panels["left_ftorso"]?.edges.count else {
            throw GarmentCodeGeometryError.invalidPanel("asymmetric upper")
        }
        _ = rightFrontCount
        stitches += [
            .init(sides: [.init(panel: "right_ftorso", edge: 0),
                          .init(panel: "left_ftorso", edge: leftFrontCount - 1)]),
            .init(sides: [.init(panel: "right_btorso", edge: rightBackCount - 1),
                          .init(panel: "left_btorso", edge: 0)])
        ]
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    private static func plainShirtPanel(name: String, front: Bool,
                                        topWidth: Double, bottomWidth: Double, length: Double,
                                        shoulderTangent: Double, connectingWidth: Double,
                                        sleeveBalance: Double, halfCollar: Double,
                                        collarDepth: Double, collarWidth: Double,
                                        armholeLabel: String, collarLabel: String) throws -> GarmentCodePanelGeometry {
        // cut_corner projects the ArmholeCurve shortcut onto the inclined side
        // and shoulder. Both underlying edges are straight, so the two
        // projection parameters have an exact two-equation solution.
        let sideDeltaX = bottomWidth - topWidth
        let armholeInclination = topWidth + connectingWidth * sideDeltaX / length - sleeveBalance
        let shoulderSpan = topWidth
        let determinant = sideDeltaX * shoulderTangent * shoulderSpan - shoulderSpan * length
        guard abs(determinant) > 1e-10 else { throw GarmentCodeProgramError.invalidMeasurements }
        let sideRemainder = (armholeInclination * shoulderTangent * shoulderSpan -
                             shoulderSpan * connectingWidth) / determinant
        let shoulderFraction = (sideDeltaX * connectingWidth - length * armholeInclination) / determinant
        guard (0...1).contains(sideRemainder), (0...1).contains(shoulderFraction) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let sidePoint = GarmentCodePoint(x: -topWidth - sideDeltaX * sideRemainder,
                                         y: length * (1 - sideRemainder))
        let shoulderPoint = GarmentCodePoint(x: -topWidth + shoulderSpan * shoulderFraction,
                                             y: length + shoulderTangent * shoulderSpan * shoulderFraction)
        let neckOuter = GarmentCodePoint(x: -halfCollar,
                                         y: length + shoulderTangent * (topWidth - halfCollar))
        let neckInner = GarmentCodePoint(x: 0, y: neckOuter.y - collarDepth)
        let bottomOuter = GarmentCodePoint(x: -bottomWidth, y: 0)
        let radius = collarDepth / 2 + collarWidth * collarWidth / (8 * collarDepth)
        guard radius.isFinite, radius > 0,
              shoulderPoint.x < neckOuter.x - 1e-6,
              sidePoint.y > 0, neckInner.y > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let edges: [GarmentCodeGeometryEdge]
        if front {
            edges = [
                .init(id: "\(name)-inside", start: .zero, end: neckInner),
                .init(id: "\(name)-collar", start: neckInner, end: neckOuter,
                      curvature: .init(circleRadius: radius, largeArc: false, right: false), label: collarLabel),
                .init(id: "\(name)-shoulder", start: neckOuter, end: shoulderPoint),
                .init(id: "\(name)-armhole", start: shoulderPoint, end: sidePoint,
                      curvature: .init(type: "cubic", params: [[0.5, 0.2], [0.8, 0.35]]), label: armholeLabel),
                .init(id: "\(name)-outside", start: sidePoint, end: bottomOuter),
                .init(id: "\(name)-bottom", start: bottomOuter, end: .zero)
            ]
        } else {
            edges = [
                .init(id: "\(name)-bottom", start: .zero, end: bottomOuter),
                .init(id: "\(name)-outside", start: bottomOuter, end: sidePoint),
                .init(id: "\(name)-armhole", start: sidePoint, end: shoulderPoint,
                      curvature: .init(type: "cubic", params: [[0.2, -0.35], [0.5, -0.2]]), label: armholeLabel),
                .init(id: "\(name)-shoulder", start: shoulderPoint, end: neckOuter),
                .init(id: "\(name)-collar", start: neckOuter, end: neckInner,
                      curvature: .init(circleRadius: radius, largeArc: false, right: true), label: collarLabel),
                .init(id: "\(name)-inside", start: neckInner, end: .zero)
            ]
        }
        return .init(id: name, label: "body", edges: edges)
    }

    private static func mirrorShirtPanel(_ panel: GarmentCodePanelGeometry,
                                         name: String) -> GarmentCodePanelGeometry {
        let axisStart = GarmentCodePoint.zero
        let axisEnd = GarmentCodePoint(x: 0, y: 1)
        let edges = panel.edges.reversed().enumerated().map { index, edge in
            var mirrored = edge.reversed().reflected(acrossLineFrom: axisStart, to: axisEnd)
            mirrored.id = "\(name)-e\(index)"
            mirrored.label = edge.label?.replacingOccurrences(of: "right_", with: "left_")
            return mirrored
        }
        return .init(id: name, label: panel.label, edges: edges)
    }

    /// `BodiceFrontHalf` and `BodiceBackHalf` from the pinned upper-garment
    /// program. The torso panels are fitted by side and waist darts before
    /// the sleeve and collar corners are projected.
    static func fittedShirt(body: GarmentCodeBodyParameters,
                            design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "upper"]) == "FittedShirt" else {
            throw GarmentCodeProgramError.wrongProgram("meta.upper 必须选择 FittedShirt")
        }
        if design.value(at: ["left", "enable_asym"]) == .bool(true) {
            return try asymmetricUpper(body: body, design: design, fitted: true)
        }
        let strapless = design.value(at: ["shirt", "strapless"]) == .bool(true)
        let sleeveless = design.value(at: ["sleeve", "sleeveless"]) == .bool(true)
        if !strapless && selectedOption(design, path: ["collar", "component", "style"]) == "Hood2Panels" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "f_collar"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachHood(to: fittedShirt(body: body, design: torsoDesign), body: body, design: design)
        }
        if !strapless && selectedOption(design, path: ["collar", "component", "style"]) == "SimpleLapel" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachSimpleLapel(to: fittedShirt(body: body, design: torsoDesign),
                                         design: design)
        }
        if !strapless && selectedOption(design, path: ["collar", "component", "style"]) == "Turtle" {
            var torsoDesign = design
            _ = torsoDesign.setValue(.null, at: ["collar", "component", "style"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "f_collar"])
            _ = torsoDesign.setValue(.string("CircleNeckHalf"), at: ["collar", "b_collar"])
            return try attachTurtleCollar(to: fittedShirt(body: body, design: torsoDesign), design: design)
        }
        guard (strapless || sleeveless || design.value(at: ["sleeve", "sleeveless"]) == .bool(false)),
              (strapless || design.value(at: ["collar", "component", "style"]) == nil ||
               design.value(at: ["collar", "component", "style"]) == .null),
              design.value(at: ["left", "enable_asym"]) == .bool(false) else {
            throw GarmentCodeProgramError.unsupportedParameter("FittedShirt sleeve/collar/asymmetry/strapless")
        }
        guard let bust = body["bust"], let backWidth = body["back_width"],
              let waist = body["waist"], let backWaist = body["waist_back_width"],
              let shoulderWidth = body["shoulder_w"], let waistLine = body["waist_line"],
              let waistOverBustLine = body["waist_over_bust_line"],
              let shoulderAngle = body["_shoulder_incl"], let armscyeDepth = body["_armscye_depth"],
              let sleeveBalance = body["_base_sleeve_balance"], let neckWidth = body["neck_w"],
              let bustLine = body["_bust_line"], let bustPoints = body["bust_points"],
              let bumPoints = body["bum_points"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let sleeveWidthRatio = try number(design, path: ["sleeve", "connecting_width"])
        let collarWidthRatio = try number(design, path: ["collar", "width"])
        let frontDepthRatio = try number(design, path: ["collar", "fc_depth"])
        let backDepthRatio = try number(design, path: ["collar", "bc_depth"])
        let tangent = tan(shoulderAngle * .pi / 180)
        let frontWidth = (bust - backWidth) / 2
        let rearWidth = backWidth / 2
        let shoulderHalf = shoulderWidth / 2
        let frontLength = waistOverBustLine - tangent * (frontWidth - shoulderHalf)
        let rearLength = waistLine - tangent * (rearWidth - shoulderHalf)
        let connectingWidth = min(armscyeDepth * (1 + sleeveWidthRatio),
                                  hypot(frontWidth - shoulderHalf, frontLength) - 1)
        let maximumCollarWidth = sleeveBalance - 2
        let collarWidth = collarWidthRatio >= 0
            ? interpolate(neckWidth, maximumCollarWidth, collarWidthRatio)
            : interpolate(0, neckWidth, 1 + collarWidthRatio)
        let halfCollar = collarWidth / 2
        guard frontWidth > shoulderHalf, rearWidth > shoulderHalf,
              connectingWidth > 0, halfCollar > 0, halfCollar < shoulderHalf else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        // BodiceHalf.eval_dep_params limits depth using the actual inside
        // edge before projection, not the side-seam length. Front shoulder
        // narrowing changes its top width; the back starts above y=0.
        let frontDepthLimit = frontLength + tangent * frontWidth - tangent * shoulderHalf - 1
        let backDepthLimit = rearLength - tangent * rearWidth / 4 - 1
        let frontDepth = min(frontDepthRatio * bustLine, frontDepthLimit) +
            tangent * (shoulderHalf - halfCollar)
        let backDepth = min(backDepthRatio * bustLine, backDepthLimit) +
            tangent * (rearWidth - halfCollar)
        let rightFront = try fittedShirtFrontPanel(
            name: "right_ftorso", width: frontWidth, waist: (waist - backWaist) / 2,
            shoulderHalf: shoulderHalf, shoulderTangent: tangent,
            length: frontLength, waistLine: waistLine, bustLine: bustLine,
            backWidth: rearWidth, bustPoint: bustPoints / 2,
            connectingWidth: connectingWidth, sleeveBalance: sleeveBalance / 2,
            halfCollar: halfCollar, collarWidth: collarWidth, collarDepth: frontDepth)
        let rightBack = try fittedShirtBackPanel(
            name: "right_btorso", width: rearWidth, waist: backWaist / 2,
            shoulderHalf: shoulderHalf, shoulderTangent: tangent,
            length: rearLength, waistLine: waistLine, bustLine: bustLine,
            bumPoint: bumPoints / 2, connectingWidth: connectingWidth,
            sleeveBalance: sleeveBalance / 2, halfCollar: halfCollar,
            collarWidth: collarWidth, collarDepth: backDepth)
        if strapless {
            return try finishFittedStrapless(front: rightFront, back: rightBack,
                                              frontWidth: frontWidth, backWidth: rearWidth,
                                              shoulderHalf: shoulderHalf,
                                              frontLength: frontLength, backLength: rearLength,
                                              shoulderTangent: tangent,
                                              connectingWidth: connectingWidth,
                                              sleeveBalance: sleeveBalance / 2)
        }
        if !sleeveless {
            let cuffType = selectedOption(design, path: ["sleeve", "cuff", "type"])
            guard cuffType == nil || ["CuffBand", "CuffSkirt", "CuffBandSkirt"].contains(cuffType!) else {
                throw GarmentCodeProgramError.unsupportedParameter("FittedShirt sleeve cuff type")
            }
        }
        let stitches: [GarmentCodeStitch] = [
            .init(sides: [.init(panel: "right_ftorso", edge: 5), .init(panel: "right_ftorso", edge: 6)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 9), .init(panel: "right_ftorso", edge: 10)]),
            .init(sides: [.init(panel: "right_btorso", edge: 1), .init(panel: "right_btorso", edge: 2)]),
            .init(sides: [.init(panel: "right_btorso", edge: 4), .init(panel: "right_btorso", edge: 5)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 6), .init(panel: "left_ftorso", edge: 5)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 2), .init(panel: "left_ftorso", edge: 1)]),
            .init(sides: [.init(panel: "left_btorso", edge: 11), .init(panel: "left_btorso", edge: 10)]),
            .init(sides: [.init(panel: "left_btorso", edge: 8), .init(panel: "left_btorso", edge: 7)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 2), .init(panel: "right_btorso", edge: 10)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 7), .init(panel: "right_btorso", edge: 7)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 4), .init(panel: "right_btorso", edge: 8)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 9), .init(panel: "left_btorso", edge: 2)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 4), .init(panel: "left_btorso", edge: 5)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 7), .init(panel: "left_btorso", edge: 4)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 0), .init(panel: "left_ftorso", edge: 11)]),
            .init(sides: [.init(panel: "right_btorso", edge: 12), .init(panel: "left_btorso", edge: 0)])
        ]
        var upperDesign = design
        if !sleeveless {
            _ = upperDesign.setValue(.string("ArmholeCurve"), at: ["sleeve", "armhole_shape"])
        }
        let torso = try finishUpperNeckline(front: rightFront, back: rightBack,
                                            design: upperDesign,
                                            baseStitches: fittedBackStitches(stitches,
                                                originalCount: 13, actualCount: rightBack.edges.count))
        guard !sleeveless else { return torso }
        let sideUpper = rightFront.edges[5].start
        let sideTop = GarmentCodePoint(x: -shoulderHalf,
                                       y: frontLength + tangent * (frontWidth - shoulderHalf))
        let frontWidthAtArmhole = shoulderHalf + connectingWidth *
            (sideTop.x - sideUpper.x) / (sideTop.y - sideUpper.y)
        return try attachSleeves(to: torso, body: body, design: design,
                                 frontWidth: frontWidthAtArmhole,
                                 backWidth: rearWidth,
                                 connectingWidth: connectingWidth)
    }

    private static func finishFittedStrapless(front originalFront: GarmentCodePanelGeometry,
                                              back originalBack: GarmentCodePanelGeometry,
                                              frontWidth: Double, backWidth: Double,
                                              shoulderHalf: Double,
                                              frontLength: Double, backLength: Double,
                                              shoulderTangent: Double,
                                              connectingWidth: Double,
                                              sleeveBalance: Double) throws -> GarmentCodePatternFile {
        let backOutDepth = connectingWidth - shoulderTangent * (backWidth - sleeveBalance)
        let backOuter = GarmentCodePoint(x: -backWidth, y: backLength - backOutDepth)
        let backSideIndex = originalBack.edges.count - 6
        let backOutsideLength = originalBack.edges[backSideIndex].length() +
            originalBack.edges[backSideIndex].end.distance(to: backOuter)
        let frontOutsideLowerLength = originalFront.edges[7].length()
        let frontUpperLength = backOutsideLength - frontOutsideLowerLength
        let frontSideUpper = originalFront.edges[4].end
        let frontSideTop = GarmentCodePoint(
            x: -shoulderHalf,
            y: frontLength + shoulderTangent * (frontWidth - shoulderHalf))
        let frontUpperVector = frontSideTop - frontSideUpper
        guard frontUpperLength > 0, frontUpperLength < frontUpperVector.length,
              backOuter.y > originalBack.edges[backSideIndex].end.y else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let frontOuter = frontSideUpper + frontUpperVector.normalized * frontUpperLength
        let frontInside = originalFront.edges[0].end
        let backInside = originalBack.edges[originalBack.edges.count - 1].start
        var front = originalFront
        front.edges = [originalFront.edges[0],
                       .init(id: "right_ftorso-strapless", start: frontInside,
                             end: frontOuter, label: "strapless_top"),
                       .init(id: "right_ftorso-outside-upper", start: frontOuter,
                             end: frontSideUpper)] + Array(originalFront.edges[5...])
        var back = originalBack
        back.edges = Array(originalBack.edges[0...backSideIndex]) + [
            .init(id: "right_btorso-outside-upper", start: originalBack.edges[backSideIndex].end,
                  end: backOuter),
            .init(id: "right_btorso-strapless", start: backOuter,
                  end: backInside, label: "strapless_top"),
            .init(id: "right_btorso-inside", start: backInside,
                  end: originalBack.edges[0].start)
        ]
        let leftFront = mirrorShirtPanel(front, name: "left_ftorso")
        let leftBack = mirrorShirtPanel(back, name: "left_btorso")
        let stitches: [GarmentCodeStitch] = [
            .init(sides: [.init(panel: "right_ftorso", edge: 3), .init(panel: "right_ftorso", edge: 4)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 7), .init(panel: "right_ftorso", edge: 8)]),
            .init(sides: [.init(panel: "right_btorso", edge: 1), .init(panel: "right_btorso", edge: 2)]),
            .init(sides: [.init(panel: "right_btorso", edge: 4), .init(panel: "right_btorso", edge: 5)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 6), .init(panel: "left_ftorso", edge: 5)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 2), .init(panel: "left_ftorso", edge: 1)]),
            .init(sides: [.init(panel: "left_btorso", edge: 9), .init(panel: "left_btorso", edge: 8)]),
            .init(sides: [.init(panel: "left_btorso", edge: 6), .init(panel: "left_btorso", edge: 5)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 5), .init(panel: "right_btorso", edge: 7)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 2), .init(panel: "right_btorso", edge: 8)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 4), .init(panel: "left_btorso", edge: 3)]),
            .init(sides: [.init(panel: "left_ftorso", edge: 7), .init(panel: "left_btorso", edge: 2)]),
            .init(sides: [.init(panel: "right_ftorso", edge: 0), .init(panel: "left_ftorso", edge: 9)]),
            .init(sides: [.init(panel: "right_btorso", edge: 10), .init(panel: "left_btorso", edge: 0)])
        ]
        return try GarmentCodePatternFile(
            geometry: Dictionary(uniqueKeysWithValues: [front, back, leftFront, leftBack].map { ($0.id, $0) }),
            stitches: fittedBackStitches(stitches, originalCount: 11, actualCount: back.edges.count))
    }

    /// The optional two back darts add six edges. Preserve the official
    /// seam references when the body requires an undarted back waist.
    private static func fittedBackStitches(_ stitches: [GarmentCodeStitch],
                                           originalCount: Int,
                                           actualCount: Int) -> [GarmentCodeStitch] {
        guard actualCount == originalCount - 6 else { return stitches }
        return stitches.compactMap { stitch in
            var sides: [GarmentCodeStitchSide] = []
            for side in stitch.sides {
                var index = side.edge
                if side.panel == "right_btorso" {
                    if (1...6).contains(index) { return nil }
                    if index >= 7 { index -= 6 }
                } else if side.panel == "left_btorso" {
                    if ((originalCount - 7)...(originalCount - 2)).contains(index) { return nil }
                    if index == originalCount - 1 { index -= 6 }
                }
                sides.append(.init(panel: side.panel, edge: index))
            }
            return .init(sides: sides, rightWrong: stitch.rightWrong)
        }
    }

    private static func attachHood(to torso: GarmentCodePatternFile,
                                   body: GarmentCodeBodyParameters,
                                   design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        var panels = try torso.geometryPanels()
        guard let front = panels["right_ftorso"], let back = panels["right_btorso"],
              let frontNeck = front.edges.first(where: { $0.label == "right_collar" }),
              let backNeck = back.edges.first(where: { $0.label == "right_collar" }),
              let headLength = body["head_l"] else {
            throw GarmentCodeGeometryError.invalidPanel("Hood2Panels")
        }
        let halfWidth = abs(frontNeck.end.x - frontNeck.start.x)
        let frontDepth = abs(frontNeck.end.y - frontNeck.start.y)
        let backDepth = abs(backNeck.end.y - backNeck.start.y)
        let hoodLength = headLength * (try number(design, path: ["collar", "component", "hood_length"]))
        let hoodDepth = halfWidth * (try number(design, path: ["collar", "component", "hood_depth"]))
        guard halfWidth > 0, frontDepth > 0, backDepth > 0,
              hoodLength > 0, hoodDepth > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let backStart = GarmentCodePoint(x: -halfWidth, y: -backDepth)
        let center = GarmentCodePoint.zero
        let backSource = GarmentCodeGeometryEdge(id: "right_hood-e0", start: backStart,
                                                  end: center,
                                                  curvature: .init(type: "cubic", params: [[0.3, -0.2], [0.6, 0.2]]))
        let backBottom = try GarmentCodeGeometryEdge.cubicMatchingTangents(
            backSource, targetStartTangent: .init(x: 1, y: 0),
            targetEndTangent: .init(x: 1, y: 0), targetLength: backNeck.length())
        let frontSource = GarmentCodeGeometryEdge(id: "right_hood-e1", start: backBottom.end,
                                                   end: .init(x: halfWidth, y: -frontDepth),
                                                   curvature: .init(type: "cubic", params: [[0.3, 0.2], [0.6, -0.2]]))
        let frontBottom = try GarmentCodeGeometryEdge.cubicMatchingTangents(
            frontSource, targetStartTangent: .init(x: 1, y: 0),
            targetEndTangent: .init(x: 1, y: 0), targetLength: frontNeck.length())
        let topY = hoodLength + halfWidth / 2
        let frontTop = GarmentCodePoint(x: halfWidth * 1.2, y: topY)
        let backTop = GarmentCodePoint(x: halfWidth * 1.2 - hoodDepth, y: topY)
        let rightHood = GarmentCodePanelGeometry(id: "right_hood", label: "body", edges: [
            backBottom,
            frontBottom,
            .init(id: "right_hood-e2", start: frontBottom.end, end: frontTop),
            .init(id: "right_hood-e3", start: frontTop, end: backTop),
            .init(id: "right_hood-e4", start: backTop, end: backStart,
                  curvature: .init(type: "quadratic", params: [[0.2, -0.5]]))
        ])
        panels[rightHood.id] = rightHood
        panels["left_hood"] = mirrorShirtPanel(rightHood, name: "left_hood")
        func neckline(_ name: String) throws -> Int {
            guard let index = panels[name]?.edges.firstIndex(where: { $0.label?.hasSuffix("_collar") == true }) else {
                throw GarmentCodeGeometryError.invalidPanel(name)
            }
            return index
        }
        var stitches = torso.pattern.stitches
        stitches += [
            .init(sides: [.init(panel: "right_ftorso", edge: try neckline("right_ftorso")),
                          .init(panel: "right_hood", edge: 1)]),
            .init(sides: [.init(panel: "right_btorso", edge: try neckline("right_btorso")),
                          .init(panel: "right_hood", edge: 0)]),
            .init(sides: [.init(panel: "left_ftorso", edge: try neckline("left_ftorso")),
                          .init(panel: "left_hood", edge: 3)]),
            .init(sides: [.init(panel: "left_btorso", edge: try neckline("left_btorso")),
                          .init(panel: "left_hood", edge: 4)]),
            .init(sides: [.init(panel: "right_hood", edge: 3),
                          .init(panel: "left_hood", edge: 1)]),
            .init(sides: [.init(panel: "right_hood", edge: 4),
                          .init(panel: "left_hood", edge: 0)])
        ]
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    private static func attachTurtleCollar(to torso: GarmentCodePatternFile,
                                           design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        var panels = try torso.geometryPanels()
        let depth = try number(design, path: ["collar", "component", "depth"])
        guard depth > 0,
              let front = panels["right_ftorso"], let back = panels["right_btorso"],
              let frontNeck = front.edges.first(where: { $0.label == "right_collar" }),
              let backNeck = back.edges.first(where: { $0.label == "right_collar" }) else {
            throw GarmentCodeGeometryError.invalidPanel("Turtle")
        }
        let frontBand = straightBandPanel(name: "right_collar_front", width: frontNeck.length(),
                                          depth: depth, reverseForPanelNormal: true)
        let backBand = straightBandPanel(name: "right_collar_back", width: backNeck.length(),
                                         depth: depth, reverseForPanelNormal: false)
        panels[frontBand.id] = frontBand
        panels[backBand.id] = backBand
        panels["left_collar_front"] = mirrorShirtPanel(frontBand, name: "left_collar_front")
        panels["left_collar_back"] = mirrorShirtPanel(backBand, name: "left_collar_back")
        func neckline(_ name: String) throws -> Int {
            guard let index = panels[name]?.edges.firstIndex(where: { $0.label?.hasSuffix("_collar") == true }) else {
                throw GarmentCodeGeometryError.invalidPanel(name)
            }
            return index
        }
        var stitches = torso.pattern.stitches
        stitches += [
            .init(sides: [.init(panel: "right_collar_front", edge: 3), .init(panel: "right_collar_back", edge: 0)]),
            .init(sides: [.init(panel: "right_ftorso", edge: try neckline("right_ftorso")),
                          .init(panel: "right_collar_front", edge: 0)]),
            .init(sides: [.init(panel: "right_btorso", edge: try neckline("right_btorso")),
                          .init(panel: "right_collar_back", edge: 3)]),
            .init(sides: [.init(panel: "left_collar_front", edge: 0), .init(panel: "left_collar_back", edge: 3)]),
            .init(sides: [.init(panel: "left_ftorso", edge: try neckline("left_ftorso")),
                          .init(panel: "left_collar_front", edge: 3)]),
            .init(sides: [.init(panel: "left_btorso", edge: try neckline("left_btorso")),
                          .init(panel: "left_collar_back", edge: 0)]),
            .init(sides: [.init(panel: "right_collar_front", edge: 1), .init(panel: "left_collar_front", edge: 2)]),
            .init(sides: [.init(panel: "right_collar_back", edge: 2), .init(panel: "left_collar_back", edge: 1)])
        ]
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    /// Pattern-only port of `collars.SimpleLapel` for the official default
    /// CircleNeckHalf back projection. Unlike Turtle, the lapel front is a
    /// curved triangular panel and its back follows a circular neckline arc.
    private static func attachSimpleLapel(to torso: GarmentCodePatternFile,
                                          design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        var panels = try torso.geometryPanels()
        let depth = try number(design, path: ["collar", "component", "depth"])
        guard depth > 0,
              let front = panels["right_ftorso"], let back = panels["right_btorso"],
              let frontNeck = front.edges.first(where: { $0.label == "right_collar" }),
              let backNeck = back.edges.first(where: { $0.label == "right_collar" }) else {
            throw GarmentCodeProgramError.unsupportedParameter(
                "SimpleLapel requires intact front and back collar interfaces")
        }
        let frontLength = frontNeck.length()
        let backLength = backNeck.length()
        let standing = design.value(at: ["collar", "component", "lapel_standing"]) == .bool(true)
        guard standing || (backNeck.curvature?.circle != nil && backNeck.curvature?.circle?.largeArc == false) else {
            throw GarmentCodeProgramError.unsupportedParameter(
                "SimpleLapel curved back requires the official CircleNeckHalf neckline")
        }
        guard frontLength > 0, backLength > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let frontVertices = [GarmentCodePoint.zero,
                             .init(x: depth, y: -frontLength),
                             .init(x: depth, y: 0)]
        let rightFront = GarmentCodePanelGeometry(id: "right_collar_front", label: "body", edges: [
            .init(id: "right_collar_front-e0", start: frontVertices[0], end: frontVertices[1],
                  curvature: .init(type: "quadratic", params: [[0.3, -0.2]])),
            .init(id: "right_collar_front-e1", start: frontVertices[1], end: frontVertices[2]),
            .init(id: "right_collar_front-e2", start: frontVertices[2], end: frontVertices[0])
        ])
        let leftFront = mirrorShirtPanel(rightFront, name: "left_collar_front")
        let backPanel: GarmentCodePanelGeometry
        if standing {
            backPanel = straightBandPanel(name: "right_collar_back", width: backLength,
                                          depth: depth, reverseForPanelNormal: false)
        } else {
            guard let backCircle = backNeck.curvature?.circle else {
                throw GarmentCodeGeometryError.invalidPanel("right_btorso neckline arc")
            }
            var curved = circleArcPanel(name: "right_collar_back", topRadius: backCircle.radius,
                                        length: depth, angle: backLength / backCircle.radius,
                                        reverseForPanelNormal: false)
            curved.label = "body"
            backPanel = curved
        }
        let leftBack = mirrorShirtPanel(backPanel, name: "left_collar_back")
        panels[rightFront.id] = rightFront
        panels[leftFront.id] = leftFront
        panels[backPanel.id] = backPanel
        panels[leftBack.id] = leftBack

        func edge(_ panelName: String, label: String) throws -> Int {
            guard let index = panels[panelName]?.edges.firstIndex(where: { $0.label == label }) else {
                throw GarmentCodeGeometryError.invalidPanel(panelName)
            }
            return index
        }
        let leftFrontNeck = try edge("left_ftorso", label: "left_collar")
        let leftBackNeck = try edge("left_btorso", label: "left_collar")
        let rightFrontNeck = try edge("right_ftorso", label: "right_collar")
        let rightBackNeck = try edge("right_btorso", label: "right_collar")
        var stitches = torso.pattern.stitches
        if standing {
            stitches += [
                .init(sides: [.init(panel: "right_collar_front", edge: 2),
                              .init(panel: "right_collar_back", edge: 0)], rightWrong: true),
                .init(sides: [.init(panel: "right_ftorso", edge: rightFrontNeck),
                              .init(panel: "right_collar_front", edge: 1)], rightWrong: true),
                .init(sides: [.init(panel: "right_btorso", edge: rightBackNeck),
                              .init(panel: "right_collar_back", edge: 3)]),
                .init(sides: [.init(panel: "left_collar_front", edge: 0),
                              .init(panel: "left_collar_back", edge: 3)], rightWrong: true),
                .init(sides: [.init(panel: "left_ftorso", edge: leftFrontNeck),
                              .init(panel: "left_collar_front", edge: 1)], rightWrong: true),
                .init(sides: [.init(panel: "left_btorso", edge: leftBackNeck),
                              .init(panel: "left_collar_back", edge: 0)]),
                .init(sides: [.init(panel: "right_collar_back", edge: 2),
                              .init(panel: "left_collar_back", edge: 1)])
            ]
        } else {
            stitches += [
                .init(sides: [.init(panel: "left_collar_front", edge: 0),
                              .init(panel: "left_collar_back", edge: 0)]),
                .init(sides: [.init(panel: "left_ftorso", edge: leftFrontNeck),
                              .init(panel: "left_collar_front", edge: 1)], rightWrong: true),
                .init(sides: [.init(panel: "left_btorso", edge: leftBackNeck),
                              .init(panel: "left_collar_back", edge: 3)], rightWrong: true),
                .init(sides: [.init(panel: "right_collar_front", edge: 2),
                              .init(panel: "right_collar_back", edge: 3)]),
                .init(sides: [.init(panel: "right_ftorso", edge: rightFrontNeck),
                              .init(panel: "right_collar_front", edge: 1)], rightWrong: true),
                .init(sides: [.init(panel: "right_btorso", edge: rightBackNeck),
                              .init(panel: "right_collar_back", edge: 0)], rightWrong: true),
                .init(sides: [.init(panel: "right_collar_back", edge: 1),
                              .init(panel: "left_collar_back", edge: 2)])
            ]
        }
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    private static func projectShirtArmhole(sideStart: GarmentCodePoint,
                                            sideEnd: GarmentCodePoint,
                                            shoulderEnd: GarmentCodePoint,
                                            inclination: Double,
                                            connectingWidth: Double) throws -> (GarmentCodePoint, GarmentCodePoint) {
        let side = sideEnd - sideStart, shoulder = shoulderEnd - sideEnd
        let determinant = side.x * shoulder.y - side.y * shoulder.x
        guard abs(determinant) > 1e-10 else { throw GarmentCodeProgramError.invalidMeasurements }
        let remaining = (inclination * shoulder.y - connectingWidth * shoulder.x) / determinant
        let shoulderFraction = (side.x * connectingWidth - side.y * inclination) / determinant
        guard (0...1).contains(remaining), (0...1).contains(shoulderFraction) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        return (sideEnd - side * remaining, sideEnd + shoulder * shoulderFraction)
    }

    private static func fittedShirtFrontPanel(name: String, width: Double, waist: Double,
                                              shoulderHalf: Double, shoulderTangent: Double,
                                              length: Double, waistLine: Double, bustLine: Double,
                                              backWidth: Double, bustPoint: Double,
                                              connectingWidth: Double, sleeveBalance: Double,
                                              halfCollar: Double, collarWidth: Double,
                                              collarDepth: Double) throws -> GarmentCodePanelGeometry {
        let chestLineFromHem = waistLine - bustLine
        let backAdjustment = shoulderTangent * (backWidth - shoulderHalf)
        let bodyFrontBackDifference = width - backWidth
        let sideLength = waistLine - backAdjustment - shoulderTangent * bodyFrontBackDifference
        let sideDartWidth = length - sideLength
        let sideDartSideLength = 0.75 * (width - bustPoint)
        let bottomDartWidth = (width - waist) * 2 / 3
        let bottomDartSideLength = 0.9 * chestLineFromHem
        guard sideDartWidth > 0, bottomDartWidth > 0,
              sideDartSideLength > sideDartWidth / 2,
              bottomDartSideLength > bottomDartWidth / 2 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let sideDartPerpendicular = sqrt(sideDartSideLength * sideDartSideLength -
                                         pow(sideDartWidth / 2, 2))
        let bottomDartPerpendicular = sqrt(bottomDartSideLength * bottomDartSideLength -
                                           pow(bottomDartWidth / 2, 2))
        let sideLower = GarmentCodePoint(x: -width, y: chestLineFromHem)
        let sideMiddle = GarmentCodePoint(x: -width + sideDartPerpendicular,
                                          y: chestLineFromHem + sideDartWidth / 2)
        let sideUpper = GarmentCodePoint(x: -width, y: chestLineFromHem + sideDartWidth)
        let sideTop = GarmentCodePoint(x: -shoulderHalf,
                                       y: length + shoulderTangent * (width - shoulderHalf))
        let shoulderEnd = GarmentCodePoint(x: 0, y: length + shoulderTangent * width)
        let frontWidthAtArmhole = shoulderHalf + connectingWidth *
            (sideTop.x - sideUpper.x) / (sideTop.y - sideUpper.y)
        let (armholeSide, armholeShoulder) = try projectShirtArmhole(
            sideStart: sideUpper, sideEnd: sideTop, shoulderEnd: shoulderEnd,
            inclination: frontWidthAtArmhole - sleeveBalance, connectingWidth: connectingWidth)
        let neckOuter = GarmentCodePoint(x: -halfCollar,
                                         y: shoulderEnd.y - shoulderTangent * halfCollar)
        let neckInner = GarmentCodePoint(x: 0, y: neckOuter.y - collarDepth)
        let mouthCenter = bustPoint + bottomDartWidth / 2
        let bottomMouthLeft = GarmentCodePoint(x: -(mouthCenter + bottomDartWidth / 2), y: 0)
        let bottomMouthRight = GarmentCodePoint(x: -(mouthCenter - bottomDartWidth / 2), y: 0)
        let bottomApex = GarmentCodePoint(x: -mouthCenter, y: bottomDartPerpendicular)
        let outerBottom = GarmentCodePoint(x: -(waist + bottomDartWidth), y: 0)
        let radius = collarDepth / 2 + collarWidth * collarWidth / (8 * collarDepth)
        let points: [GarmentCodePoint] = [.zero, neckInner, neckOuter, armholeShoulder,
            armholeSide, sideUpper, sideMiddle, sideLower, outerBottom,
            bottomMouthLeft, bottomApex, bottomMouthRight]
        var edges = (0..<points.count).map { index in
            GarmentCodeGeometryEdge(id: "\(name)-e\(index)", start: points[index],
                                    end: points[(index + 1) % points.count])
        }
        edges[1].curvature = .init(circleRadius: radius, largeArc: false, right: false)
        edges[1].label = "right_collar"
        edges[3].curvature = .init(type: "cubic", params: [[0.5, 0.2], [0.8, 0.35]])
        edges[3].label = "right_armhole"
        return .init(id: name, label: "body", edges: edges)
    }

    private static func fittedShirtBackPanel(name: String, width: Double, waist: Double,
                                             shoulderHalf: Double, shoulderTangent: Double,
                                             length: Double, waistLine: Double, bustLine: Double,
                                             bumPoint: Double, connectingWidth: Double,
                                             sleeveBalance: Double, halfCollar: Double,
                                             collarWidth: Double, collarDepth: Double) throws -> GarmentCodePanelGeometry {
        let shoulderInclination = shoulderTangent * width
        let bottomStart = GarmentCodePoint(x: 0, y: shoulderInclination / 4)
        let bottomEnd = GarmentCodePoint(x: -max(width, waist), y: 0)
        let bottom = GarmentCodeGeometryEdge.quadraticFromTangents(
            id: "\(name)-bottom", start: bottomStart, end: bottomEnd,
            startTangent: .init(x: -1, y: 0))
        let waistDifference = width - waist
        var bottomEdges = [bottom]
        if waistDifference > 0 {
            let sideAdjustment = waistDifference < 4 ? 0 : waistDifference / 6
            let dartWidth = (waistDifference - sideAdjustment) / 2
            let dartSideLength = length - bustLine
            let separation = bumPoint * 0.5
            let farOffset = bumPoint + separation / 2 + dartWidth * 1.5
            let nearOffset = bumPoint - separation / 2 + dartWidth / 2
            guard dartWidth > 0, dartSideLength > dartWidth / 2 else {
                throw GarmentCodeProgramError.invalidMeasurements
            }
            let far = try insertFittedBackDart(on: bottom, centerDistance: farOffset,
                                               mouthWidth: dartWidth, sideLength: dartSideLength * 0.9,
                                               idPrefix: "\(name)-far-dart")
            let near = try insertFittedBackDart(on: far.before, centerDistance: nearOffset,
                                                mouthWidth: dartWidth, sideLength: dartSideLength,
                                                idPrefix: "\(name)-near-dart")
            var farAfter = far.after
            farAfter.moveEndpoints(to: farAfter.start,
                                   newEnd: .init(x: bottomEnd.x + sideAdjustment, y: bottomEnd.y))
            bottomEdges = [near.before, near.left, near.right, near.after,
                           far.left, far.right, farAfter]
        }
        let outerBottom = bottomEdges[bottomEdges.count - 1].end
        let outsideMiddle = GarmentCodePoint(x: -width, y: waistLine - bustLine)
        let outsideTop = GarmentCodePoint(x: -width, y: length)
        let shoulderEnd = GarmentCodePoint(x: 0, y: length + shoulderInclination)
        let (armholeSide, armholeShoulder) = try projectShirtArmhole(
            sideStart: outsideMiddle, sideEnd: outsideTop, shoulderEnd: shoulderEnd,
            inclination: width - sleeveBalance, connectingWidth: connectingWidth)
        let neckOuter = GarmentCodePoint(x: -halfCollar,
                                         y: shoulderEnd.y - shoulderTangent * halfCollar)
        let neckInner = GarmentCodePoint(x: 0, y: neckOuter.y - collarDepth)
        let radius = collarDepth / 2 + collarWidth * collarWidth / (8 * collarDepth)
        var edges = bottomEdges + [
                     GarmentCodeGeometryEdge(id: "\(name)-outside-lower", start: outerBottom, end: outsideMiddle),
                     GarmentCodeGeometryEdge(id: "\(name)-outside-upper", start: outsideMiddle, end: armholeSide),
                     GarmentCodeGeometryEdge(id: "\(name)-armhole", start: armholeSide, end: armholeShoulder,
                                             curvature: .init(type: "cubic", params: [[0.2, -0.35], [0.5, -0.2]]),
                                             label: "right_armhole"),
                     GarmentCodeGeometryEdge(id: "\(name)-shoulder", start: armholeShoulder, end: neckOuter),
                     GarmentCodeGeometryEdge(id: "\(name)-collar", start: neckOuter, end: neckInner,
                                             curvature: .init(circleRadius: radius, largeArc: false, right: true),
                                             label: "right_collar"),
                     GarmentCodeGeometryEdge(id: "\(name)-inside", start: neckInner, end: bottomStart)]
        for index in edges.indices { edges[index].id = "\(name)-e\(index)" }
        return .init(id: name, label: "body", edges: edges)
    }

    private static func insertFittedBackDart(on edge: GarmentCodeGeometryEdge,
                                             centerDistance: Double, mouthWidth: Double,
                                             sideLength: Double, idPrefix: String) throws ->
        (before: GarmentCodeGeometryEdge, left: GarmentCodeGeometryEdge,
         right: GarmentCodeGeometryEdge, after: GarmentCodeGeometryEdge) {
        let edgeLength = edge.length()
        guard centerDistance > mouthWidth / 2,
              centerDistance < edgeLength - mouthWidth / 2,
              sideLength > mouthWidth / 2 else { throw GarmentCodeProgramError.invalidMeasurements }
        var lower = 0.0, upper = 1.0
        for _ in 0..<50 {
            let midpoint = (lower + upper) / 2
            if edge.split(at: midpoint).0.length() < centerDistance { lower = midpoint }
            else { upper = midpoint }
        }
        let centerT = (lower + upper) / 2
        let center = edge.point(at: centerT)
        func objective(_ forward: Double, _ backward: Double) -> Double {
            let first = edge.point(at: centerT - backward)
            let last = edge.point(at: centerT + forward)
            return pow(first.distance(to: last) - mouthWidth, 2) +
                pow(first.distance(to: center) - last.distance(to: center), 2)
        }
        var forward = 0.1, backward = 0.1, step = 0.1
        var error = objective(forward, backward)
        for _ in 0..<1000 where step > 1e-11 {
            var bestForward = forward, bestBackward = backward, bestError = error
            for df in [-step, 0, step] { for db in [-step, 0, step] where df != 0 || db != 0 {
                let proposedForward = min(1 - centerT, max(0, forward + df))
                let proposedBackward = min(centerT, max(0, backward + db))
                let proposedError = objective(proposedForward, proposedBackward)
                if proposedError < bestError {
                    bestForward = proposedForward
                    bestBackward = proposedBackward
                    bestError = proposedError
                }
            }}
            if bestError < error {
                forward = bestForward; backward = bestBackward; error = bestError
            } else { step *= 0.5 }
        }
        guard error < 1e-4 else { throw GarmentCodeProgramError.invalidMeasurements }
        let firstT = centerT - backward, lastT = centerT + forward
        let firstPoint = edge.point(at: firstT), lastPoint = edge.point(at: lastT)
        let direction = (lastPoint - firstPoint).normalized
        let depth = sqrt(sideLength * sideLength - pow(mouthWidth / 2, 2))
        let dartApex = (firstPoint + lastPoint) * 0.5 - direction.leftNormal * depth
        let beforePoints = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: 0, upper: firstT)
        let afterPoints = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: lastT, upper: 1)
        let before = GarmentCodeGeometryEdge(id: "\(idPrefix)-before", start: edge.start, end: firstPoint,
                                             curvature: GarmentCodeGeometryEdge.curvature(for: beforePoints))
        let after = GarmentCodeGeometryEdge(id: "\(idPrefix)-after", start: lastPoint, end: edge.end,
                                            curvature: GarmentCodeGeometryEdge.curvature(for: afterPoints))
        return (before,
                .init(id: "\(idPrefix)-left", start: firstPoint, end: dartApex),
                .init(id: "\(idPrefix)-right", start: dartApex, end: lastPoint),
                after)
    }

    private static func finishUpperNeckline(front originalFront: GarmentCodePanelGeometry,
                                            back originalBack: GarmentCodePanelGeometry,
                                            design: GarmentCodeDesignParameters,
                                            baseStitches: [GarmentCodeStitch]) throws -> GarmentCodePatternFile {
        var front = originalFront, back = originalBack
        guard let frontCollarIndex = front.edges.firstIndex(where: { $0.label == "right_collar" }),
              let backCollarIndex = back.edges.firstIndex(where: { $0.label == "right_collar" }),
              let frontArmholeIndex = front.edges.firstIndex(where: { $0.label == "right_armhole" }),
              let backArmholeIndex = back.edges.firstIndex(where: { $0.label == "right_armhole" }) else {
            throw GarmentCodeGeometryError.invalidPanel("upper neckline")
        }
        let frontReplacement = try projectedNecklineEdges(
            base: front.edges[frontCollarIndex], design: design, front: true)
        let backReplacement = try projectedNecklineEdges(
            base: back.edges[backCollarIndex], design: design, front: false)
        let frontArmhole = try projectedArmholeEdges(
            base: front.edges[frontArmholeIndex], design: design, front: true)
        let backArmhole = try projectedArmholeEdges(
            base: back.edges[backArmholeIndex], design: design, front: false)
        for (index, replacement) in [(frontCollarIndex, frontReplacement),
                                     (frontArmholeIndex, frontArmhole)].sorted(by: { $0.0 > $1.0 }) {
            front.edges.replaceSubrange(index...index, with: replacement)
        }
        for (index, replacement) in [(backCollarIndex, backReplacement),
                                     (backArmholeIndex, backArmhole)].sorted(by: { $0.0 > $1.0 }) {
            back.edges.replaceSubrange(index...index, with: replacement)
        }
        let frontExtra = frontReplacement.count - 1
        let backExtra = backReplacement.count - 1
        let frontArmholeExtra = frontArmhole.count - 1
        let backArmholeExtra = backArmhole.count - 1
        func remap(_ side: GarmentCodeStitchSide) -> GarmentCodeStitchSide {
            let isFront = side.panel.hasSuffix("ftorso")
            let isLeft = side.panel.hasPrefix("left_")
            let oldCount = isFront ? originalFront.edges.count : originalBack.edges.count
            let collarIndex = isFront ? frontCollarIndex : backCollarIndex
            let extra = isFront ? frontExtra : backExtra
            let armholeIndex = isFront ? frontArmholeIndex : backArmholeIndex
            let armholeExtra = isFront ? frontArmholeExtra : backArmholeExtra
            let rightOldIndex = isLeft ? oldCount - 1 - side.edge : side.edge
            let rightNewIndex = rightOldIndex +
                (rightOldIndex > collarIndex ? extra : 0) +
                (rightOldIndex > armholeIndex ? armholeExtra : 0)
            let newIndex = isLeft ? oldCount + extra + armholeExtra - 1 - rightNewIndex : rightNewIndex
            return .init(panel: side.panel, edge: newIndex)
        }
        let stitches = baseStitches.map { stitch in
            GarmentCodeStitch(sides: stitch.sides.map(remap), rightWrong: stitch.rightWrong)
        }
        let leftFront = mirrorShirtPanel(front, name: "left_ftorso")
        let leftBack = mirrorShirtPanel(back, name: "left_btorso")
        return try GarmentCodePatternFile(
            geometry: Dictionary(uniqueKeysWithValues: [front, back, leftFront, leftBack].map { ($0.id, $0) }),
            stitches: stitches)
    }

    /// Pattern-only assembly of the default, unruffled sleeve. This follows
    /// `Sleeve`, `SleevePanel`, `even_armhole_openings`, and the two bodice
    /// `cut_corner` calls in the pinned PyGarment implementation.
    private static func attachSleeves(to torso: GarmentCodePatternFile,
                                      body: GarmentCodeBodyParameters,
                                      design: GarmentCodeDesignParameters,
                                      frontWidth: Double,
                                      backWidth: Double,
                                      connectingWidth: Double) throws -> GarmentCodePatternFile {
        guard let sleeveBalance = body["_base_sleeve_balance"].map({ $0 / 2 }),
              let armLength = body["arm_length"], let wrist = body["wrist"],
              let shoulderInclination = body["_shoulder_incl"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let sleeveAngle = try number(design, path: ["sleeve", "sleeve_angle"]) * .pi / 180
        let restAngle = max(sleeveAngle, shoulderInclination * .pi / 180)
        let shoulderAngle = shoulderInclination * .pi / 180
        let standingRequested = design.value(at: ["sleeve", "standing_shoulder"]) == .bool(true)
        let standingActive = standingRequested && restAngle > shoulderAngle + 5 * .pi / 180
        let standingLength = standingActive
            ? try number(design, path: ["sleeve", "standing_shoulder_len"]) : 0
        let openingMix = try number(design, path: ["sleeve", "opening_dir_mix"])
        let lengthRatio = try number(design, path: ["sleeve", "length"])
        let endWidthRatio = try number(design, path: ["sleeve", "end_width"])
        let connectRuffle = try number(design, path: ["sleeve", "connect_ruffle"])
        guard connectRuffle > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let cuffType = selectedOption(design, path: ["sleeve", "cuff", "type"])
        let cuffLength: Double
        if cuffType != nil {
            let requested = try number(design, path: ["sleeve", "cuff", "cuff_len"]) * armLength
            cuffLength = min(requested, lengthRatio * armLength * 0.7)
        } else {
            cuffLength = 0
        }
        let frontInclination = frontWidth - sleeveBalance
        let backInclination = backWidth - sleeveBalance
        let frontCurve = try GarmentCodeSleeveGeometry.armholeCurve(
            id: "right-front-sleeve-opening", inclination: frontInclination,
            width: connectingWidth, restAngle: restAngle, bottomAngleMix: openingMix)
        let backCurve = try GarmentCodeSleeveGeometry.armholeCurve(
            id: "right-back-sleeve-opening", inclination: backInclination,
            width: connectingWidth, restAngle: restAngle, bottomAngleMix: openingMix)
        let openings: (front: [GarmentCodeGeometryEdge], back: [GarmentCodeGeometryEdge])
        if abs(frontWidth - backWidth) > 1e-10 {
            openings = try GarmentCodeSleeveGeometry.evenOpenings(
                front: frontCurve.opening, back: backCurve.opening)
        } else {
            openings = (frontCurve.opening, backCurve.opening)
        }
        let rightFrontSleeve = try GarmentCodeSleeveGeometry.panel(
            id: "right_sleeve_f", opening: openings.front, endWidthRatio: endWidthRatio,
            sleeveLengthRatio: lengthRatio, armLength: armLength, wristCircumference: wrist,
            connectRuffle: connectRuffle, lengthShift: -cuffLength,
            standingShoulder: standingActive, standingLength: standingLength,
            standingAngle: restAngle - shoulderAngle)
        var rightBackSleeve = try GarmentCodeSleeveGeometry.panel(
            id: "right_sleeve_b", opening: openings.back, endWidthRatio: endWidthRatio,
            sleeveLengthRatio: lengthRatio, armLength: armLength, wristCircumference: wrist,
            connectRuffle: connectRuffle, lengthShift: -cuffLength,
            standingShoulder: standingActive, standingLength: standingLength,
            standingAngle: restAngle - shoulderAngle)
        // PyGarment `Panel.autonorm()` reverses the back half's edge loop
        // after its default sleeve placement; preserve that canonical order
        // in the pattern-only panel too.
        rightBackSleeve.reverse()
        let leftFrontSleeve = mirrorShirtPanel(rightFrontSleeve, name: "left_sleeve_f")
        let leftBackSleeve = mirrorShirtPanel(rightBackSleeve, name: "left_sleeve_b")

        var panels = try torso.geometryPanels()
        let stitches = torso.pattern.stitches
        var bodiceInterfaces: [String: [String]] = [:]
        for side in ["right", "left"] {
            for front in [true, false] {
                let panelName = "\(side)_\(front ? "ftorso" : "btorso")"
                guard let panel = panels[panelName],
                      let armhole = panel.edges.first(where: { $0.label == "\(side)_armhole" }) else {
                    throw GarmentCodeGeometryError.invalidPanel(panelName)
                }
                // The torso pattern already contains the projected armhole
                // cut. GarmentCode's stitch assembly subdivides this edge to
                // match the redistributed sleeve opening; applying a second
                // corner cut here would project the same interface twice.
                bodiceInterfaces[panelName] = [armhole.id]
            }
        }

        panels[rightFrontSleeve.id] = rightFrontSleeve
        panels[rightBackSleeve.id] = rightBackSleeve
        panels[leftFrontSleeve.id] = leftFrontSleeve
        panels[leftBackSleeve.id] = leftBackSleeve

        // Save base seam references by stable edge id before the interface
        // matcher subdivides openings to a common seam partition.
        let baseStitchIDs: [[(String, String)]] = try stitches.map { stitch in
            try stitch.sides.map { side in
                guard let panel = panels[side.panel], panel.edges.indices.contains(side.edge) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(side.panel, "\(side.edge)")
                }
                return (side.panel, panel.edges[side.edge].id)
            }
        }
        var addedStitchIDs: [[(String, String)]] = []

        func openingIDs(_ panel: GarmentCodePanelGeometry, side: String, front: Bool) -> [String] {
            if front {
                let index = side == "left" && !standingActive ? 1 : 2
                return panel.edges.indices.contains(index) ? [panel.edges[index].id] : []
            }
            if panel.edges.count == (standingActive ? 5 : 4) {
                let index = side == "right" ? (standingActive ? 2 : 1) : 2
                return [panel.edges[index].id]
            }
            let indices = side == "right" ? (standingActive ? [2, 3] : [1, 2]) : [3, 2]
            return indices.compactMap { panel.edges.indices.contains($0) ? panel.edges[$0].id : nil }
        }
        func makeInterface(_ panel: String, _ edgeIDs: [String]) -> GarmentCodeInterface {
            GarmentCodeInterface(edges: edgeIDs.map {
                GarmentCodeInterfaceEdgeReference(panel: panel, edge: $0)
            })
        }
        for side in ["right", "left"] {
            var bodyReferences: [GarmentCodeInterfaceEdgeReference] = []
            var sleeveReferences: [GarmentCodeInterfaceEdgeReference] = []
            for isFront in [true, false] {
                let torsoName = "\(side)_\(isFront ? "ftorso" : "btorso")"
                let sleeveName = "\(side)_sleeve_\(isFront ? "f" : "b")"
                guard let sleevePanel = panels[sleeveName],
                      let bodyIDs = bodiceInterfaces[torsoName] else {
                    throw GarmentCodeGeometryError.invalidPanel(sleeveName)
                }
                let sleeveIDs = openingIDs(sleevePanel, side: side, front: isFront)
                bodyReferences += bodyIDs.map {
                    GarmentCodeInterfaceEdgeReference(panel: torsoName, edge: $0,
                                                       reversed: isFront != (side == "left"))
                }
                sleeveReferences += sleeveIDs.map {
                    GarmentCodeInterfaceEdgeReference(panel: sleeveName, edge: $0,
                                                       reversed: !isFront, ruffle: connectRuffle)
                }
            }
            var bodiceInterface = GarmentCodeInterface(edges: bodyReferences)
            var openingInterface = GarmentCodeInterface(edges: sleeveReferences)
            let joins = try GarmentCodeStitchingRule.assemble(
                &openingInterface, &bodiceInterface, panels: &panels)
            // The armhole label selects the source interface before assembly;
            // the serialized projected fragments are unlabeled upstream.
            for reference in bodiceInterface.edges {
                guard reference.edge.contains("-s") else { continue }
                guard var panel = panels[reference.panel],
                      let edgeIndex = panel.edges.firstIndex(where: { $0.id == reference.edge }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
                }
                panel.edges[edgeIndex].label = nil
                panels[reference.panel] = panel
            }
            addedStitchIDs += try joins.map { join in
                try join.sides.map { side in
                    guard let panel = panels[side.panel], panel.edges.indices.contains(side.edge) else {
                        throw GarmentCodeGeometryError.invalidInterfaceEdge(side.panel, "\(side.edge)")
                    }
                    return (side.panel, panel.edges[side.edge].id)
                }
            }
            let frontName = "\(side)_sleeve_f", backName = "\(side)_sleeve_b"
            guard let frontPanel = panels[frontName], let backPanel = panels[backName],
                  !frontPanel.edges.isEmpty, !backPanel.edges.isEmpty else {
                throw GarmentCodeGeometryError.invalidPanel(frontName)
            }
            let frontTop = side == "right" ? frontPanel.edges.last! : frontPanel.edges.first!
            let backTop = side == "right" ? backPanel.edges.first! : backPanel.edges.last!
            let frontBottomIndex = side == "right" ? 1 : frontPanel.edges.count - 2
            let backBottomIndex = side == "right" ? backPanel.edges.count - 2 : 1
            let frontBottom = frontPanel.edges[frontBottomIndex]
            let backBottom = backPanel.edges[backBottomIndex]
            addedStitchIDs.append([(frontName, frontTop.id), (backName, backTop.id)])
            if standingActive {
                let frontStandingIndex = side == "right" ? frontPanel.edges.count - 2 : 1
                let backStandingIndex = side == "right" ? 1 : backPanel.edges.count - 2
                addedStitchIDs.append([(frontName, frontPanel.edges[frontStandingIndex].id),
                                       (backName, backPanel.edges[backStandingIndex].id)])
            }
            addedStitchIDs.append([(frontName, frontBottom.id), (backName, backBottom.id)])
        }

        if let cuffType {
            let topRuffle = try number(design, path: ["sleeve", "cuff", "top_ruffle"])
            let skirtFraction = try number(design, path: ["sleeve", "cuff", "skirt_fraction"])
            let skirtFlare = try number(design, path: ["sleeve", "cuff", "skirt_flare"])
            let skirtRuffle = try number(design, path: ["sleeve", "cuff", "skirt_ruffle"])
            guard topRuffle > 0, (0...1).contains(skirtFraction),
                  skirtFlare >= 1, skirtRuffle > 0, cuffLength > 0 else {
                throw GarmentCodeProgramError.invalidMeasurements
            }
            for side in ["right", "left"] {
                let tag = side == "right" ? "r" : "l"
                let sleeveFrontName = "\(side)_sleeve_f"
                let sleeveBackName = "\(side)_sleeve_b"
                guard let sleeveFront = panels[sleeveFrontName], let sleeveBack = panels[sleeveBackName] else {
                    throw GarmentCodeGeometryError.invalidPanel(sleeveFrontName)
                }
                let frontOut = side == "right" ? sleeveFront.edges[0] : sleeveFront.edges.last!
                let backOut = side == "right" ? sleeveBack.edges.last! : sleeveBack.edges[0]
                let cuffHalfWidth = max((frontOut.length() + backOut.length()) / topRuffle, wrist) / 2
                let bandLength = cuffType == "CuffBandSkirt" ? cuffLength * (1 - skirtFraction) : cuffLength
                let skirtLength = cuffType == "CuffBandSkirt" ? cuffLength * skirtFraction : cuffLength
                let bandFront = "sl_\(side)_cuff_f", bandBack = "sl_\(side)_cuff_b"
                let skirtFront = "sl_\(side)_cuff_skirt_f", skirtBack = "sl_\(side)_cuff_skirt_b"
                let firstTop = side == "right" ? "e2" : "e1"
                let secondTop = side == "right" ? "e1" : "e2"
                let panelSeams = side == "right" ? [("e3", "e0"), ("e1", "e2")]
                                                  : [("e0", "e3"), ("e2", "e1")]
                func stitch(_ first: String, _ firstEdge: String,
                            _ second: String, _ secondEdge: String) {
                    addedStitchIDs.append([(first, "\(first)-\(firstEdge)"),
                                           (second, "\(second)-\(secondEdge)")])
                }
                if cuffType == "CuffBand" || cuffType == "CuffBandSkirt" {
                    panels[bandFront] = pantCuffBandPanel(name: bandFront, width: cuffHalfWidth,
                                                          depth: bandLength, tag: tag, front: true,
                                                          label: "arm")
                    panels[bandBack] = pantCuffBandPanel(name: bandBack, width: cuffHalfWidth,
                                                         depth: bandLength, tag: tag, front: false,
                                                         label: "arm")
                    for (frontEdge, backEdge) in panelSeams {
                        stitch(bandFront, frontEdge, bandBack, backEdge)
                    }
                    if cuffType == "CuffBand" {
                        addedStitchIDs += [[(bandFront, "\(bandFront)-\(firstTop)"),
                                            (sleeveFrontName, frontOut.id)],
                                           [(bandBack, "\(bandBack)-\(secondTop)"),
                                            (sleeveBackName, backOut.id)]]
                    }
                }
                if cuffType == "CuffSkirt" || cuffType == "CuffBandSkirt" {
                    let flare = (skirtFlare - 1) * cuffHalfWidth
                    panels[skirtFront] = pantCuffSkirtPanel(name: skirtFront, waistLength: cuffHalfWidth,
                                                             length: skirtLength, ruffles: skirtRuffle,
                                                             flare: flare, tag: tag, front: true,
                                                             label: "arm")
                    panels[skirtBack] = pantCuffSkirtPanel(name: skirtBack, waistLength: cuffHalfWidth,
                                                            length: skirtLength, ruffles: skirtRuffle,
                                                            flare: flare, tag: tag, front: false,
                                                            label: "arm")
                    for (frontEdge, backEdge) in panelSeams {
                        stitch(skirtFront, frontEdge, skirtBack, backEdge)
                    }
                    if cuffType == "CuffSkirt" {
                        addedStitchIDs += [[(skirtFront, "\(skirtFront)-\(firstTop)"),
                                            (sleeveFrontName, frontOut.id)],
                                           [(skirtBack, "\(skirtBack)-\(secondTop)"),
                                            (sleeveBackName, backOut.id)]]
                    } else {
                        stitch(bandFront, side == "right" ? "e0" : "e3",
                               skirtFront, firstTop)
                        stitch(bandBack, side == "right" ? "e3" : "e0",
                               skirtBack, secondTop)
                        addedStitchIDs += [[(bandFront, "\(bandFront)-\(firstTop)"),
                                            (sleeveFrontName, frontOut.id)],
                                           [(bandBack, "\(bandBack)-\(secondTop)"),
                                            (sleeveBackName, backOut.id)]]
                    }
                }
            }
        }

        let allStitchIDs = baseStitchIDs + addedStitchIDs
        let finalStitches = try allStitchIDs.map { ids in
            GarmentCodeStitch(sides: try ids.map { panelName, edgeID in
                guard let panel = panels[panelName],
                      let index = panel.edges.firstIndex(where: { $0.id == edgeID }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(panelName, edgeID)
                }
                return GarmentCodeStitchSide(panel: panelName, edge: index)
            })
        }
        return try GarmentCodePatternFile(geometry: panels, stitches: finalStitches)
    }

    private static func remapStitchIndices(_ stitches: inout [GarmentCodeStitch],
                                           panel: String,
                                           first: Int,
                                           second: Int,
                                           replacementCount: Int) {
        guard replacementCount > 0 else { return }
        let edgeDelta = replacementCount - 2
        stitches = stitches.map { stitch in
            GarmentCodeStitch(sides: stitch.sides.map { side in
                guard side.panel == panel else { return side }
                if side.edge == first { return .init(panel: panel, edge: first) }
                if side.edge == second { return .init(panel: panel, edge: first + replacementCount - 1) }
                if side.edge > second { return .init(panel: panel, edge: side.edge + edgeDelta) }
                return side
            }, rightWrong: stitch.rightWrong)
        }
    }

    private static func mirrorEdgeSequence(_ edges: [GarmentCodeGeometryEdge],
                                           prefix: String) -> [GarmentCodeGeometryEdge] {
        edges.reversed().enumerated().map { index, edge in
            var result = edge.reversed().reflected(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
            result.id = "\(prefix)-\(index)"
            return result
        }
    }

    private static func projectedArmholeEdges(base: GarmentCodeGeometryEdge,
                                               design: GarmentCodeDesignParameters,
                                               front: Bool) throws -> [GarmentCodeGeometryEdge] {
        guard let style = selectedOption(design, path: ["sleeve", "armhole_shape"]) else {
            throw GarmentCodeProgramError.missingDesignParameter("sleeve.armhole_shape")
        }
        if style == "ArmholeCurve" { return [base] }
        guard style == "ArmholeSquare" || style == "ArmholeAngle" else {
            throw GarmentCodeProgramError.unsupportedParameter("sleeve.armhole_shape=\(style)")
        }
        let side = front ? base.end : base.start
        let shoulder = front ? base.start : base.end
        let inclination = shoulder.x - side.x
        let depth = shoulder.y - side.y
        guard inclination > 0, depth > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let corner: GarmentCodePoint
        if style == "ArmholeSquare" {
            corner = .init(x: shoulder.x, y: side.y)
        } else {
            let fraction = try number(design, path: ["sleeve", "smoothing_coeff"])
            corner = .init(x: side.x + inclination * (1 - fraction),
                           y: side.y + depth * fraction)
        }
        let label = base.label
        let sideToShoulder = [
            GarmentCodeGeometryEdge(id: "\(base.id)-shape0", start: side, end: corner, label: label),
            GarmentCodeGeometryEdge(id: "\(base.id)-shape1", start: corner, end: shoulder, label: label)
        ]
        return front ? sideToShoulder.reversed().map { $0.reversed() } : sideToShoulder
    }

    private static func projectedNecklineEdges(base: GarmentCodeGeometryEdge,
                                                design: GarmentCodeDesignParameters,
                                                front: Bool) throws -> [GarmentCodeGeometryEdge] {
        let prefix = front ? "f" : "b"
        guard let style = selectedOption(design, path: ["collar", "\(prefix)_collar"]) else {
            throw GarmentCodeProgramError.missingDesignParameter("collar.\(prefix)_collar")
        }
        guard style != "CircleNeckHalf" else { return [base] }
        let outer = front ? base.end : base.start
        let inner = front ? base.start : base.end
        let depth = outer.y - inner.y
        let halfWidth = inner.x - outer.x
        guard depth > 0, halfWidth > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let flipped = design.value(at: ["collar", "\(prefix)_flip_curve"]) == .bool(true)
        let angle = try number(design, path: ["collar", "\(prefix)c_angle"])
        let bezierX = try number(design, path: ["collar", "\(prefix)_bezier_x"])
        let bezierY = try number(design, path: ["collar", "\(prefix)_bezier_y"])
        let label = base.label
        var outwardToInner: [GarmentCodeGeometryEdge]
        switch style {
        case "VNeckHalf":
            outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner, label: label)]
        case "SquareNeckHalf", "TrapezoidNeckHalf":
            let lowerX: Double
            if style == "SquareNeckHalf" { lowerX = 0 }
            else {
                let angleRadians = angle * .pi / 180
                if abs(sin(angleRadians)) < 0.0175 {
                    outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner, label: label)]
                    break
                }
                lowerX = -depth * cos(angleRadians) / sin(angleRadians)
                if lowerX > halfWidth {
                    outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner, label: label)]
                    break
                }
            }
            let corner = GarmentCodePoint(x: outer.x + lowerX, y: inner.y)
            outwardToInner = [
                .init(id: "\(base.id)-neck0", start: outer, end: corner, label: label),
                .init(id: "\(base.id)-neck1", start: corner, end: inner, label: label)
            ]
        case "CurvyNeckHalf":
            let sign = flipped ? -1.0 : 1.0
            outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner,
                                    curvature: .init(type: "cubic", params: [[0.4, sign * 0.3], [0.8, -sign * 0.3]]),
                                    label: label)]
        case "CircleArcNeckHalf":
            let arcAngle = angle * .pi / 180
            let radius = hypot(halfWidth, depth) / (2 * sin(abs(arcAngle) / 2))
            guard radius.isFinite, radius > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
            outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner,
                                    curvature: .init(circleRadius: radius, largeArc: abs(arcAngle) > .pi,
                                                     right: !flipped), label: label)]
        case "Bezier2NeckHalf":
            let sign = flipped ? 1.0 : -1.0
            outwardToInner = [.init(id: "\(base.id)-neck0", start: outer, end: inner,
                                    curvature: .init(type: "quadratic", params: [[bezierX, sign * bezierY]]),
                                    label: label)]
        default:
            throw GarmentCodeProgramError.unsupportedParameter("collar.\(prefix)_collar=\(style)")
        }
        return front ? outwardToInner.reversed().map { $0.reversed() } : outwardToInner
    }

    /// Swift port of `bands.StraightWB` and `bands.FittedWB`.
    /// The optional rise is the one supplied by an attached lower garment;
    /// standalone waistbands follow MetaGarment's default rise of 1.
    static func waistband(body: GarmentCodeBodyParameters,
                          design: GarmentCodeDesignParameters,
                          rise requestedRise: Double? = nil) throws -> GarmentCodePatternFile {
        guard let style = selectedOption(design, path: ["meta", "wb"]),
              style == "StraightWB" || style == "FittedWB" else {
            throw GarmentCodeProgramError.wrongProgram("meta.wb 必须选择 StraightWB 或 FittedWB")
        }
        guard let bodyWaist = body["waist"], let bodyHips = body["hips"],
              let waistBackWidth = body["waist_back_width"],
              let hipBackWidth = body["hip_back_width"],
              let hipsLine = body["hips_line"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let waistScale = try number(design, path: ["waistband", "waist"])
        let widthRatio = try number(design, path: ["waistband", "width"])
        guard waistScale > 0, widthRatio > 0 else { throw GarmentCodeProgramError.invalidMeasurements }

        let waist = waistScale * bodyWaist
        let hips = waistScale * bodyHips
        var rise = requestedRise ?? 1
        guard rise.isFinite else { throw GarmentCodeProgramError.invalidMeasurements }
        if rise + widthRatio > 1 { rise = 1 - widthRatio }
        let topLevel = rise + widthRatio
        let topWidth = interpolate(hips, waist, topLevel)
        let topBackFraction = interpolate(hipBackWidth / bodyHips,
                                          waistBackWidth / bodyWaist, topLevel)
        let bandDepth = widthRatio * hipsLine
        guard topWidth > 0, topBackFraction > 0, topBackFraction < 1,
              bandDepth > 0 else { throw GarmentCodeProgramError.invalidMeasurements }

        let front: GarmentCodePanelGeometry
        let back: GarmentCodePanelGeometry
        if style == "StraightWB" {
            let backWidth = topWidth * topBackFraction
            front = straightBandPanel(name: "wb_front", width: topWidth - backWidth,
                                      depth: bandDepth, reverseForPanelNormal: true)
            back = straightBandPanel(name: "wb_back", width: backWidth,
                                     depth: bandDepth, reverseForPanelNormal: false)
        } else {
            let bottomWidth = interpolate(hips, waist, rise)
            let bottomBackFraction = interpolate(hipBackWidth / bodyHips,
                                                  waistBackWidth / bodyWaist, rise)
            front = try fittedBandPanel(name: "wb_front", depth: bandDepth,
                                        topWidth: topWidth * (1 - topBackFraction),
                                        bottomWidth: bottomWidth * (1 - bottomBackFraction),
                                        reverseForPanelNormal: true)
            back = try fittedBandPanel(name: "wb_back", depth: bandDepth,
                                       topWidth: topWidth * topBackFraction,
                                       bottomWidth: bottomWidth * bottomBackFraction,
                                       reverseForPanelNormal: false)
        }

        let frontTopEdge = style == "StraightWB" ? 2 : 3
        let backTopEdge = style == "StraightWB" ? 1 : 0
        var labeledFront = front
        var labeledBack = back
        labeledFront.edges[frontTopEdge].label = "lower_interface"
        labeledBack.edges[backTopEdge].label = "lower_interface"

        let stitches: [GarmentCodeStitch]
        if style == "StraightWB" {
            stitches = [
                .init(sides: [.init(panel: "wb_front", edge: 3), .init(panel: "wb_back", edge: 0)]),
                .init(sides: [.init(panel: "wb_front", edge: 1), .init(panel: "wb_back", edge: 2)])
            ]
        } else {
            stitches = [
                .init(sides: [.init(panel: "wb_front", edge: 0), .init(panel: "wb_back", edge: 3)]),
                .init(sides: [.init(panel: "wb_front", edge: 2), .init(panel: "wb_back", edge: 1)])
            ]
        }
        return try GarmentCodePatternFile(
            geometry: ["wb_front": labeledFront, "wb_back": labeledBack], stitches: stitches
        )
    }

    /// Pattern-only port of GarmentCode `Pants` without optional cuffs. All
    /// standard rise, length, width and flare formulas are applied; the three
    /// official cuff shapes are assembled at each leg hem.
    static func pants(body: GarmentCodeBodyParameters,
                      design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "Pants" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 Pants")
        }
        let cuffType: String?
        if case let .string(value)? = design.value(at: ["pants", "cuff", "type"]) { cuffType = value }
        else { cuffType = nil }
        guard cuffType == nil || ["CuffBand", "CuffSkirt", "CuffBandSkirt"].contains(cuffType!) else {
            throw GarmentCodeProgramError.unsupportedParameter("pants.cuff.type")
        }
        guard let waist = body["waist"], let hips = body["hips"],
              let backWaist = body["waist_back_width"], let backHips = body["hip_back_width"],
              let hipsLine = body["hips_line"], let legLength = body["_leg_length"],
              let legCircumference = body["leg_circ"], let crotchDifference = body["crotch_hip_diff"],
              let hipInclination = body["_hip_inclination"], let bustPoints = body["bust_points"],
              let bumPoints = body["bum_points"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let rise = try number(design, path: ["pants", "rise"])
        let lengthRatio = try number(design, path: ["pants", "length"])
        let widthRatio = try number(design, path: ["pants", "width"])
        let flareRatio = try number(design, path: ["pants", "flare"])
        var cuffLengthRatio = cuffType == nil ? 0 : try number(design, path: ["pants", "cuff", "cuff_len"])
        guard (0.5...1).contains(rise), widthRatio > 0,
              lengthRatio > 0, flareRatio > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        if cuffType != nil {
            let minimumLengthRatio = design.design["pants"]?.children["length"]?.range?
                .compactMap(\.numberValue).min() ?? 0.2
            if lengthRatio - cuffLengthRatio < minimumLengthRatio {
                cuffLengthRatio = lengthRatio - minimumLengthRatio
            }
            guard cuffLengthRatio > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        }
        let adjustedWaist = interpolate(hips, waist, rise)
        let adjustedBackWaist = interpolate(backHips, backWaist, rise)
        let hipDepth = rise * hipsLine
        let length = (lengthRatio - cuffLengthRatio) * legLength
        let cuffLength = cuffLengthRatio * legLength
        let minimumExtension = legCircumference - hips / 2 + 5
        let frontHip = (hips - backHips) / 2
        let totalExtension = minimumExtension * widthRatio
        let frontExtension = frontHip / 4
        let front = try pantPanel(name: "pant_f_r", body: body, waist: (adjustedWaist - adjustedBackWaist) / 2,
                                  hips: frontHip, hipDepth: hipDepth, length: length,
                                  crotchExtension: frontExtension, hiplineExtension: 1,
                                  dartPosition: bustPoints / 2, matchTop: (waist - backWaist) / 2,
                                  legCircumference: legCircumference, flareRatio: flareRatio,
                                  crotchDifference: crotchDifference, hipInclination: hipInclination,
                                  doubleDart: false)
        let back = try pantPanel(name: "pant_b_r", body: body, waist: adjustedBackWaist / 2,
                                 hips: backHips / 2, hipDepth: hipDepth, length: length,
                                 crotchExtension: totalExtension - frontExtension,
                                 hiplineExtension: 1.1, dartPosition: bumPoints / 2,
                                 matchTop: backWaist / 2, legCircumference: legCircumference,
                                 flareRatio: flareRatio, crotchDifference: crotchDifference,
                                 hipInclination: hipInclination, doubleDart: true)
        var panels = [front.panel, back.panel]
        panels += [try mirrorPantPanel(front.panel, name: "pant_f_l"),
                   try mirrorPantPanel(back.panel, name: "pant_b_l")]
        let byID = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
        func edge(_ panel: String, _ id: String) throws -> Int {
            guard let index = byID[panel]?.edges.firstIndex(where: { $0.id == id }) else {
                throw GarmentCodeGeometryError.invalidPanel(panel)
            }
            return index
        }
        var stitches: [GarmentCodeStitch] = []
        for panelName in ["pant_f_r", "pant_f_l", "pant_b_r", "pant_b_l"] {
            let isFront = panelName.hasPrefix("pant_f")
            let sourceName = isFront ? "pant_f_r" : "pant_b_r"
            let dartIDs = (isFront ? front.dartEdgeIDs : back.dartEdgeIDs).map { pair in
                pair.map { $0.replacingOccurrences(of: sourceName, with: panelName) }
            }
            for pair in dartIDs {
                stitches.append(.init(sides: [.init(panel: panelName, edge: try edge(panelName, pair[0])),
                                              .init(panel: panelName, edge: try edge(panelName, pair[1]))]))
            }
        }
        for side in ["r", "l"] {
            let f = "pant_f_\(side)", b = "pant_b_\(side)"
            for seam in ["inside", "outside-lower", "outside-upper"] {
                stitches.append(.init(sides: [.init(panel: f, edge: try edge(f, "\(f)-\(seam)")),
                                              .init(panel: b, edge: try edge(b, "\(b)-\(seam)"))]))
            }
        }
        for (frontID, backID) in [("pant_f_r", "pant_f_l"), ("pant_b_r", "pant_b_l")] {
            for seam in ["crotch-upper", "crotch-lower"] {
                stitches.append(.init(sides: [.init(panel: frontID, edge: try edge(frontID, "\(frontID)-\(seam)")),
                                              .init(panel: backID, edge: try edge(backID, "\(backID)-\(seam)"))]))
            }
        }
        var cuffStitchIDs: [[(panel: String, edge: String)]] = []
        if let cuffType {
            let topRuffle = try number(design, path: ["pants", "cuff", "top_ruffle"])
            let skirtFraction = try number(design, path: ["pants", "cuff", "skirt_fraction"])
            let skirtFlare = try number(design, path: ["pants", "cuff", "skirt_flare"])
            let skirtRuffle = try number(design, path: ["pants", "cuff", "skirt_ruffle"])
            guard topRuffle > 0, (0...1).contains(skirtFraction),
                  skirtFlare >= 1, skirtRuffle > 0 else {
                throw GarmentCodeProgramError.invalidMeasurements
            }
            for tag in ["r", "l"] {
                let pantFront = "pant_f_\(tag)", pantBack = "pant_b_\(tag)"
                guard let frontHem = lowestEdge(in: panels.first(where: { $0.id == pantFront })),
                      let backHem = lowestEdge(in: panels.first(where: { $0.id == pantBack })) else {
                    throw GarmentCodeGeometryError.invalidPanel(pantFront)
                }
                let halfWidth = (frontHem.length() + backHem.length()) / topRuffle / 2
                let cuffTag = "pant_\(tag)"
                let bandLength = cuffType == "CuffBandSkirt" ? cuffLength * (1 - skirtFraction) : cuffLength
                let skirtLength = cuffType == "CuffBandSkirt" ? cuffLength * skirtFraction : cuffLength

                if cuffType == "CuffBand" || cuffType == "CuffBandSkirt" {
                    let frontName = "\(cuffTag)_cuff_f", backName = "\(cuffTag)_cuff_b"
                    panels.append(pantCuffBandPanel(name: frontName, width: halfWidth,
                                                    depth: bandLength, tag: tag, front: true))
                    panels.append(pantCuffBandPanel(name: backName, width: halfWidth,
                                                    depth: bandLength, tag: tag, front: false))
                    let cuffSides = tag == "r"
                        ? [("e3", "e0"), ("e1", "e2")]
                        : [("e0", "e3"), ("e2", "e1")]
                    cuffStitchIDs += cuffSides.map { a, b in
                        [(frontName, "\(frontName)-\(a)"), (backName, "\(backName)-\(b)")]
                    }
                    if cuffType == "CuffBand" {
                        let frontTopEdge = tag == "r" ? "e2" : "e1"
                        let backTopEdge = tag == "r" ? "e1" : "e2"
                        cuffStitchIDs += [[(pantFront, frontHem.id), (frontName, "\(frontName)-\(frontTopEdge)")],
                                          [(pantBack, backHem.id), (backName, "\(backName)-\(backTopEdge)")]]
                    }
                }
                if cuffType == "CuffSkirt" || cuffType == "CuffBandSkirt" {
                    let frontName = "\(cuffTag)_cuff_skirt_f", backName = "\(cuffTag)_cuff_skirt_b"
                    let flare = (skirtFlare - 1) * halfWidth
                    panels.append(pantCuffSkirtPanel(name: frontName, waistLength: halfWidth,
                                                     length: skirtLength, ruffles: skirtRuffle,
                                                     flare: flare, tag: tag, front: true))
                    panels.append(pantCuffSkirtPanel(name: backName, waistLength: halfWidth,
                                                     length: skirtLength, ruffles: skirtRuffle,
                                                     flare: flare, tag: tag, front: false))
                    let cuffSides = tag == "r"
                        ? [("e3", "e0"), ("e1", "e2")]
                        : [("e0", "e3"), ("e2", "e1")]
                    cuffStitchIDs += cuffSides.map { a, b in
                        [(frontName, "\(frontName)-\(a)"), (backName, "\(backName)-\(b)")]
                    }
                    if cuffType == "CuffSkirt" {
                        let frontTopEdge = tag == "r" ? "e2" : "e1"
                        let backTopEdge = tag == "r" ? "e1" : "e2"
                        cuffStitchIDs += [[(pantFront, frontHem.id), (frontName, "\(frontName)-\(frontTopEdge)")],
                                          [(pantBack, backHem.id), (backName, "\(backName)-\(backTopEdge)")]]
                    } else {
                        let bandFrontSkirtEdge = tag == "r" ? "e0" : "e3"
                        let skirtFrontBandEdge = tag == "r" ? "e2" : "e1"
                        let bandBackSkirtEdge = tag == "r" ? "e3" : "e0"
                        let skirtBackBandEdge = tag == "r" ? "e1" : "e2"
                        let pantFrontBandEdge = tag == "r" ? "e2" : "e1"
                        let pantBackBandEdge = tag == "r" ? "e1" : "e2"
                        cuffStitchIDs += [[("\(cuffTag)_cuff_f", "\(cuffTag)_cuff_f-\(bandFrontSkirtEdge)"),
                                           (frontName, "\(frontName)-\(skirtFrontBandEdge)")],
                                          [("\(cuffTag)_cuff_b", "\(cuffTag)_cuff_b-\(bandBackSkirtEdge)"),
                                           (backName, "\(backName)-\(skirtBackBandEdge)")],
                                          [(pantFront, frontHem.id),
                                           ("\(cuffTag)_cuff_f", "\(cuffTag)_cuff_f-\(pantFrontBandEdge)")],
                                          [(pantBack, backHem.id),
                                           ("\(cuffTag)_cuff_b", "\(cuffTag)_cuff_b-\(pantBackBandEdge)")]]
                    }
                }
            }
        }
        for pair in cuffStitchIDs {
            guard pair.count == 2,
                  let firstIndex = panels.first(where: { $0.id == pair[0].panel })?.edges.firstIndex(where: { $0.id == pair[0].edge }),
                  let secondIndex = panels.first(where: { $0.id == pair[1].panel })?.edges.firstIndex(where: { $0.id == pair[1].edge }) else {
                throw GarmentCodeGeometryError.invalidPanel("pants cuff stitch")
            }
            stitches.append(.init(sides: [.init(panel: pair[0].panel, edge: firstIndex),
                                          .init(panel: pair[1].panel, edge: secondIndex)]))
        }
        return try GarmentCodePatternFile(geometry: Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) }),
                                          stitches: stitches)
    }

    /// Fitted pencil skirt with its stock front/back seams and side slits.
    static func pencilSkirt(body: GarmentCodeBodyParameters,
                            design: GarmentCodeDesignParameters,
                            requestedTotalLength: Double? = nil) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "PencilSkirt" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 PencilSkirt")
        }
        let sideCut = design.value(at: ["pencil-skirt", "style_side_cut"])
        let sunCut = sideCut == .string("Sun")
        let logoCut = sideCut == .string("SIGGRAPH_logo")
        guard sideCut == nil || sideCut == .null || sunCut || logoCut else {
            throw GarmentCodeProgramError.unsupportedParameter("pencil-skirt slits/style_side_cut")
        }
        let frontSlit = try number(design, path: ["pencil-skirt", "front_slit"])
        let backSlit = try number(design, path: ["pencil-skirt", "back_slit"])
        let leftSlit = try number(design, path: ["pencil-skirt", "left_slit"])
        let rightSlit = try number(design, path: ["pencil-skirt", "right_slit"])
        guard (0...0.9).contains(frontSlit), (0...0.9).contains(backSlit),
              (0...0.9).contains(leftSlit), (0...0.9).contains(rightSlit) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        guard let bodyWaist = body["waist"], let bodyHips = body["hips"],
              let waistBack = body["waist_back_width"], let hipBack = body["hip_back_width"],
              let hipLine = body["hips_line"], let legLength = body["_leg_length"],
              let hipInclination = body["_hip_inclination"], let bustPoints = body["bust_points"],
              let bumPoints = body["bum_points"] else { throw GarmentCodeProgramError.missingBodyParameter }
        let rise = try number(design, path: ["pencil-skirt", "rise"])
        let lengthRatio = try number(design, path: ["pencil-skirt", "length"])
        let flare = try number(design, path: ["pencil-skirt", "flare"])
        let lowAngle = try number(design, path: ["pencil-skirt", "low_angle"])
        guard (0.5...1).contains(rise), flare > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let waist = interpolate(bodyHips, bodyWaist, rise)
        let backWaist = interpolate(hipBack, waistBack, rise)
        let hipDepth = rise * hipLine
        let length = requestedTotalLength.map { $0 - hipDepth } ?? lengthRatio * legLength
        guard length > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        var front = try fittedSkirtPanel(name: "skirt_front", waist: (waist - backWaist) / 2,
                                         hips: (bodyHips - hipBack) / 2, hipDepth: hipDepth,
                                         totalHipCircumference: bodyHips,
                                         length: length,
                                         hiplineExtension: 1, dartPosition: bustPoints / 2,
                                         dartFraction: 0.8, matchTop: waist - backWaist,
                                         lowAngle: lowAngle, flare: flare, hipInclination: hipInclination,
                                         doubleDart: false, back: false)
        var back = try fittedSkirtPanel(name: "skirt_back", waist: backWaist / 2,
                                        hips: hipBack / 2, hipDepth: hipDepth,
                                        totalHipCircumference: bodyHips,
                                        length: length, hiplineExtension: 1.05,
                                        dartPosition: bumPoints / 2, dartFraction: 0.85,
                                        matchTop: waistBack, lowAngle: lowAngle,
                                        flare: flare, hipInclination: hipInclination,
                                        doubleDart: true, back: true)
        // The official panel applies the hem and side slits before projecting
        // a decorative cut into the remaining sewable part of the side edge.
        if frontSlit > 0 { try insertHemSlit(panel: &front.panel, depth: frontSlit * length) }
        if backSlit > 0 { try insertHemSlit(panel: &back.panel, depth: backSlit * length) }
        var frontSlitSeams: [String: String] = [:]
        var backSlitSeams: [String: String] = [:]
        if leftSlit > 0 {
            frontSlitSeams["left-lower"] = try splitSideSlit(panel: &front.panel,
                edgeID: "skirt_front-left-lower", ratio: leftSlit)
            backSlitSeams["left-lower"] = try splitSideSlit(panel: &back.panel,
                edgeID: "skirt_back-left-lower", ratio: leftSlit)
        }
        if rightSlit > 0 {
            frontSlitSeams["right-lower"] = try splitSideSlit(panel: &front.panel,
                edgeID: "skirt_front-right-lower", ratio: rightSlit)
            backSlitSeams["right-lower"] = try splitSideSlit(panel: &back.panel,
                edgeID: "skirt_back-right-lower", ratio: rightSlit)
        }
        let frontLeftSewable = frontSlitSeams["left-lower"] ?? "skirt_front-left-lower"
        let backLeftSewable = backSlitSeams["left-lower"] ?? "skirt_back-left-lower"
        var frontSideCutEdges: [String] = []
        var backSideCutEdges: [String] = []
        if sunCut {
            let depth = 0.7 * (bodyHips / 4 - bustPoints / 2)
            guard depth > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
            let points = sunCutPoints(width: depth * 1.5, depth: depth, rays: 6,
                                      innerRayDepth: depth * 0.2)
            var stagedFront = front.panel
            if let edges = try? insertSideCut(panel: &stagedFront,
                                             edgeID: frontLeftSewable, shape: points) {
                front.panel = stagedFront
                frontSideCutEdges = edges
            } else {
                frontSideCutEdges = [frontLeftSewable]
            }
            var stagedBack = back.panel
            if let edges = try? insertSideCut(panel: &stagedBack,
                                             edgeID: backLeftSewable, shape: points) {
                back.panel = stagedBack
                backSideCutEdges = edges
            } else {
                backSideCutEdges = [backLeftSewable]
            }
        } else if logoCut {
            let depth = 0.7 * (bodyHips / 4 - bustPoints / 2)
            let shape = try GarmentCodeSiggraphShape.load(width: depth * 1.5)
            var stagedFront = front.panel
            if let edges = try? insertBezierSideCuts(panel: &stagedFront,
                                                    edgeID: frontLeftSewable,
                                                    shapes: shape.left, reverseBase: true) {
                front.panel = stagedFront
                frontSideCutEdges = edges
            } else {
                frontSideCutEdges = [frontLeftSewable]
            }
            var stagedBack = back.panel
            if let edges = try? insertBezierSideCuts(panel: &stagedBack,
                                                    edgeID: backLeftSewable,
                                                    shapes: shape.right) {
                back.panel = stagedBack
                backSideCutEdges = edges
            } else {
                backSideCutEdges = [backLeftSewable]
            }
        }
        var logoLeftStitches: [GarmentCodeStitch] = []
        if logoCut {
            var panelMap = [front.panel.id: front.panel, back.panel.id: back.panel]
            var frontInterface = GarmentCodeInterface(edges: [
                .init(panel: front.panel.id, edge: "skirt_front-left-upper")
            ] + frontSideCutEdges.reversed().map {
                .init(panel: front.panel.id, edge: $0)
            })
            var backInterface = GarmentCodeInterface(edges: [
                .init(panel: back.panel.id, edge: "skirt_back-left-upper",
                      reversed: true, ruffle: 1.05)
            ] + backSideCutEdges.map {
                .init(panel: back.panel.id, edge: $0)
            })
            logoLeftStitches = try GarmentCodeStitchingRule.assemble(
                &frontInterface, &backInterface, panels: &panelMap,
                upstreamSequential: true)
            front.panel = panelMap[front.panel.id]!
            back.panel = panelMap[back.panel.id]!
        }
        let panels = [front.panel, back.panel]
        let indexByID = Dictionary(uniqueKeysWithValues: panels.map { panel in
            (panel.id, Dictionary(uniqueKeysWithValues: panel.edges.enumerated().map { ($0.element.id, $0.offset) }))
        })
        func edgeIndex(_ panel: String, _ edgeID: String) throws -> Int {
            guard let index = indexByID[panel]?[edgeID] else { throw GarmentCodeGeometryError.invalidPanel(panel) }
            return index
        }
        var stitches: [GarmentCodeStitch] = []
        stitches += logoLeftStitches
        for pair in front.dartEdgeIDs {
            stitches.append(.init(sides: [.init(panel: "skirt_front", edge: try edgeIndex("skirt_front", pair[0])),
                                          .init(panel: "skirt_front", edge: try edgeIndex("skirt_front", pair[1]))]))
        }
        for pair in back.dartEdgeIDs {
            stitches.append(.init(sides: [.init(panel: "skirt_back", edge: try edgeIndex("skirt_back", pair[0])),
                                          .init(panel: "skirt_back", edge: try edgeIndex("skirt_back", pair[1]))]))
        }
        for seam in ["right-lower", "right-upper", "left-upper", "left-lower"] {
            if logoCut && seam.hasPrefix("left-") { continue }
            if sunCut && seam == "left-lower" {
                let frontIDs = frontSideCutEdges.sorted {
                    (indexByID["skirt_front"]?[$0] ?? 0) > (indexByID["skirt_front"]?[$1] ?? 0)
                }
                let backIDs = backSideCutEdges.sorted {
                    (indexByID["skirt_back"]?[$0] ?? 0) < (indexByID["skirt_back"]?[$1] ?? 0)
                }
                guard frontIDs.count == backIDs.count else { throw GarmentCodeGeometryError.invalidPanel("Sun side cut") }
                for (frontID, backID) in zip(frontIDs, backIDs) {
                    stitches.append(.init(sides: [.init(panel: "skirt_front", edge: try edgeIndex("skirt_front", frontID)),
                                                  .init(panel: "skirt_back", edge: try edgeIndex("skirt_back", backID))]))
                }
                continue
            }
            let frontID = frontSlitSeams[seam] ?? "skirt_front-\(seam)"
            let backID = backSlitSeams[seam] ?? "skirt_back-\(seam)"
            stitches.append(.init(sides: [.init(panel: "skirt_front", edge: try edgeIndex("skirt_front", frontID)),
                                          .init(panel: "skirt_back", edge: try edgeIndex("skirt_back", backID))]))
        }
        return try GarmentCodePatternFile(geometry: Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) }),
                                          stitches: stitches)
    }

    /// PyGarment's left/right skirt slits retain the lower side segment as an
    /// open slit and keep only the upper edge in the side-seam interface.
    private static func splitSideSlit(panel: inout GarmentCodePanelGeometry,
                                      edgeID: String, ratio: Double) throws -> String {
        guard let edge = panel.edges.first(where: { $0.id == edgeID }) else {
            throw GarmentCodeGeometryError.invalidPanel(panel.id)
        }
        let fromHem = edge.start.y <= edge.end.y
        let parameter = fromHem ? ratio : 1 - ratio
        guard let pieces = panel.splitEdge(id: edgeID, atFractions: [parameter]), pieces.count == 2,
              let first = panel.edges.first(where: { $0.id == pieces[0] }),
              let second = panel.edges.first(where: { $0.id == pieces[1] }) else {
            throw GarmentCodeGeometryError.invalidPanel(edgeID)
        }
        let firstMeanY = (first.start.y + first.end.y) / 2
        let secondMeanY = (second.start.y + second.end.y) / 2
        return firstMeanY > secondMeanY ? first.id : second.id
    }

    /// Port of `cut_into_edge(dart_shape(2, depth=...), bottom)` for the
    /// straight hem used by the fitted pencil-skirt block.
    private static func insertHemSlit(panel: inout GarmentCodePanelGeometry,
                                      depth: Double) throws {
        guard depth > 0,
              let index = panel.edges.indices.min(by: {
                  (panel.edges[$0].start.y + panel.edges[$0].end.y) <
                  (panel.edges[$1].start.y + panel.edges[$1].end.y)
              }) else { throw GarmentCodeGeometryError.invalidPanel(panel.id) }
        let base = panel.edges[index]
        let delta = base.end - base.start
        let length = delta.length
        guard base.curvature == nil, length > 2 + 1e-7,
              abs(delta.y) < 1e-7 else { throw GarmentCodeProgramError.invalidMeasurements }
        let direction = delta.normalized
        // Pattern loop normalization in PyGarment makes both front and back
        // hem cuts face toward increasing local Y in the serialized panels.
        let rightNormal = GarmentCodePoint(x: 0, y: 1)
        let firstFraction = (length / 2 - 1) / length
        let secondFraction = (length / 2 + 1) / length
        let before = base.split(at: firstFraction).0
        let remainder = base.split(at: firstFraction).1
        let (opening, after) = remainder.split(at: (secondFraction - firstFraction) / (1 - firstFraction))
        let center = base.start + direction * (length / 2)
        let apex = center + rightNormal * depth
        let mouthStart = center - direction
        let mouthEnd = center + direction
        let replacements = [before,
            GarmentCodeGeometryEdge(id: "\(base.id)-slit-left", start: mouthStart, end: apex),
            GarmentCodeGeometryEdge(id: "\(base.id)-slit-right", start: apex, end: mouthEnd),
            after]
        _ = opening // opening is the removed original hem segment
        panel.edges.replaceSubrange(index...index, with: replacements)
    }

    /// Port of `shapes.Sun`, including the same circle-arc sampling convention
    /// used by svgpathtools' normalized Bezier parameter.
    private static func sunCutPoints(width: Double, depth: Double,
                                     rays: Int, innerRayDepth: Double) -> [GarmentCodePoint] {
        func arcSamples(start: GarmentCodePoint, end: GarmentCodePoint,
                        through point: GarmentCodePoint, count: Int,
                        offset: Double) -> [GarmentCodePoint] {
            let determinant = 2 * (start.x * (end.y - point.y) + end.x * (point.y - start.y) +
                                   point.x * (start.y - end.y))
            guard abs(determinant) > 1e-12 else { return [] }
            let startNorm = start.x * start.x + start.y * start.y
            let endNorm = end.x * end.x + end.y * end.y
            let pointNorm = point.x * point.x + point.y * point.y
            let center = GarmentCodePoint(
                x: (startNorm * (end.y - point.y) + endNorm * (point.y - start.y) + pointNorm * (start.y - end.y)) / determinant,
                y: (startNorm * (point.x - end.x) + endNorm * (start.x - point.x) + pointNorm * (end.x - start.x)) / determinant)
            let radius = start.distance(to: center)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            var endAngle = atan2(end.y - center.y, end.x - center.x)
            let middleDistance = point.distance(to: (start + end) * 0.5)
            let largeArc = middleDistance > radius
            let right = (point - start).x * (end - start).y - (point - start).y * (end - start).x > 0
            if right {
                while endAngle < startAngle { endAngle += 2 * .pi }
                while endAngle - startAngle > 2 * .pi { endAngle -= 2 * .pi }
            } else {
                while endAngle > startAngle { endAngle -= 2 * .pi }
                while endAngle - startAngle < -2 * .pi { endAngle += 2 * .pi }
            }
            var delta = endAngle - startAngle
            if (abs(delta) > .pi) != largeArc { delta += right ? -2 * .pi : 2 * .pi }
            return (0..<count).map { index in
                let t = offset + Double(index) / Double(rays)
                let angle = startAngle + delta * t
                return .init(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
        let outer = arcSamples(start: .zero, end: .init(x: width, y: 0),
                               through: .init(x: width / 2, y: depth), count: rays,
                               offset: 0.5 / Double(rays))
        let inner = arcSamples(start: .init(x: innerRayDepth, y: 0),
                               end: .init(x: width - innerRayDepth, y: 0),
                               through: .init(x: width / 2, y: depth - innerRayDepth),
                               count: rays + 1, offset: 0)
        var vertices = outer
        for (index, point) in inner.enumerated() { vertices.insert(point, at: min(index * 2, vertices.count)) }
        return vertices
    }

    /// Port of the straight-shape `cut_into_edge_single` path used by the Sun
    /// cutout. A bounded coordinate search solves the same width/symmetry fit
    /// objective that upstream minimizes over the curved side edge.
    private static func insertSideCut(panel: inout GarmentCodePanelGeometry,
                                      edgeID: String, shape: [GarmentCodePoint]) throws -> [String] {
        guard shape.count >= 3, let index = panel.edges.firstIndex(where: { $0.id == edgeID }) else {
            throw GarmentCodeGeometryError.invalidPanel(edgeID)
        }
        let edge = panel.edges[index]
        let shapeWidth = shape[0].distance(to: shape[shape.count - 1])
        let edgeLength = edge.length()
        guard shapeWidth > 0, edgeLength > shapeWidth else { throw GarmentCodeProgramError.invalidMeasurements }
        var low = 0.0, high = 1.0
        for _ in 0..<48 {
            let middle = (low + high) / 2
            if edge.split(at: middle).0.length() < edgeLength / 2 {
                low = middle
            } else { high = middle }
        }
        let centerT = (low + high) / 2
        let center = edge.point(at: centerT)
        func objective(_ x: Double, _ y: Double) -> Double {
            let leftT = max(0, centerT - y), rightT = min(1, centerT + x)
            let left = edge.point(at: leftT), right = edge.point(at: rightT)
            return pow(left.distance(to: right) - shapeWidth, 2) +
                pow(left.distance(to: center) - right.distance(to: center), 2)
        }
        var x = 0.1, y = 0.1, step = 0.1
        var error = objective(x, y)
        for _ in 0..<1000 where step > 1e-10 {
            var bestX = x, bestY = y, best = error
            for dx in [-step, 0, step] { for dy in [-step, 0, step] where dx != 0 || dy != 0 {
                let candidateX = min(1 - centerT, max(0, x + dx))
                let candidateY = min(centerT, max(0, y + dy))
                let candidate = objective(candidateX, candidateY)
                if candidate < best { best = candidate; bestX = candidateX; bestY = candidateY }
            }}
            if best < error { x = bestX; y = bestY; error = best }
            else { step *= 0.5 }
        }
        guard error < 1e-4 else { throw GarmentCodeProgramError.invalidMeasurements }
        let lowerT = centerT - y, upperT = centerT + x
        let keepBefore = lowerT > 0.01
        let keepAfter = upperT < 0.99
        let insertionStart = keepBefore ? edge.point(at: lowerT) : edge.start
        let insertionEnd = keepAfter ? edge.point(at: upperT) : edge.end
        let vector = insertionEnd - insertionStart
        let angle = atan2(shape[shape.count - 1].y - shape[0].y,
                          shape[shape.count - 1].x - shape[0].x)
        let insertionAngle = atan2(vector.y, vector.x)
        let rotation = insertionAngle - angle
        let cosine = cos(rotation), sine = sin(rotation)
        var transformed = shape.map { point in
            GarmentCodePoint(x: point.x * cosine - point.y * sine,
                             y: point.x * sine + point.y * cosine)
        }
        let translation = insertionStart - transformed[0]
        transformed = transformed.map { $0 + translation }
        let average = transformed.reduce(GarmentCodePoint.zero) { sum, point in
            .init(x: sum.x + point.x, y: sum.y + point.y)
        } * (1 / Double(transformed.count))
        let cross = vector.x * (average.y - insertionStart.y) - vector.y * (average.x - insertionStart.x)
        let shouldReflect = panel.id == "skirt_back" ? cross >= 0 : cross < 0
        if shouldReflect {
            transformed = transformed.map { $0.reflected(acrossLineFrom: insertionStart, to: insertionEnd) }
        }
        if panel.id == "skirt_front" && !keepBefore && !keepAfter {
            // The stock side edge is stored bottom-to-top in our normalized
            // contour, opposite to PyGarment's top-to-bottom projection. When
            // the cut nearly fills that edge, PyGarment anchors its first
            // shape vertex at the upper end and snaps only the final vertex
            // to the lower end. Preserve that interior placement here.
            let gap = edgeLength - shapeWidth
            let alongEdge = (edge.end - edge.start) * (gap / edgeLength)
            transformed = transformed.map { $0 + alongEdge }
        }
        if !keepBefore { transformed[0] = edge.start }
        if !keepAfter { transformed[transformed.count - 1] = edge.end }
        let before = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: 0, upper: lowerT)
        let after = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: upperT, upper: 1)
        var replacements: [GarmentCodeGeometryEdge] = []
        if keepBefore {
            replacements.append(.init(id: "\(edgeID)-cut-before", start: edge.start, end: insertionStart,
                                      curvature: GarmentCodeGeometryEdge.curvature(for: before)))
        }
        for (i, pair) in zip(transformed, transformed.dropFirst()).enumerated() {
            replacements.append(.init(id: "\(edgeID)-cut-\(i)", start: pair.0, end: pair.1))
        }
        if keepAfter {
            replacements.append(.init(id: "\(edgeID)-cut-after", start: insertionEnd, end: edge.end,
                                      curvature: GarmentCodeGeometryEdge.curvature(for: after)))
        }
        panel.edges.replaceSubrange(index...index, with: replacements)
        return replacements.map(\.id)
    }

    /// SVG logo cutout: PyGarment projects the four upward-facing curve
    /// sequences from top to bottom onto the remaining lower side edge.
    private static func insertBezierSideCuts(panel: inout GarmentCodePanelGeometry,
                                             edgeID: String,
                                             shapes: [[GarmentCodeGeometryEdge]],
                                             reverseBase: Bool = false) throws -> [String] {
        guard let base = panel.edges.first(where: { $0.id == edgeID }), shapes.count == 4 else {
            throw GarmentCodeGeometryError.invalidPanel(edgeID)
        }
        let midY = shapes.flatMap { sequence in [sequence[0].start.y, sequence[sequence.count - 1].end.y] }
        let medianY = ((midY.min() ?? 0) + (midY.max() ?? 0)) / 2
        let placements = shapes.map { sequence in
            (base.length() / 2 + (sequence[0].start.y + sequence[sequence.count - 1].end.y) / 2 - medianY,
             sequence)
        }.sorted { $0.0 > $1.0 }
        var projectedID = edgeID
        var allIDs = [edgeID]
        for (offset, sequence) in placements {
            guard let index = panel.edges.firstIndex(where: { $0.id == projectedID }) else {
                throw GarmentCodeGeometryError.invalidPanel(projectedID)
            }
            let edge = reverseBase ? panel.edges[index].reversed() : panel.edges[index]
            let length = edge.length()
            let width = sequence[0].start.distance(to: sequence[sequence.count - 1].end)
            guard length > width, offset >= width / 2 - 0.01,
                  offset <= length - width / 2 + 0.01 else {
                throw GarmentCodeProgramError.invalidMeasurements
            }
            var low = 0.0, high = 1.0
            for _ in 0..<48 {
                let middle = (low + high) / 2
                if edge.split(at: middle).0.length() < offset { low = middle }
                else { high = middle }
            }
            let centerT = (low + high) / 2
            let center = edge.point(at: centerT)
            func objective(_ x: Double, _ y: Double) -> Double {
                let left = edge.point(at: max(0, centerT - y))
                let right = edge.point(at: min(1, centerT + x))
                return pow(left.distance(to: right) - width, 2) +
                    pow(left.distance(to: center) - right.distance(to: center), 2)
            }
            var x = 0.1, y = 0.1, step = 0.1
            var error = objective(x, y)
            for _ in 0..<1000 where step > 1e-10 {
                var bestX = x, bestY = y, best = error
                for dx in [-step, 0, step] { for dy in [-step, 0, step] where dx != 0 || dy != 0 {
                    let nextX = min(1 - centerT, max(0, x + dx))
                    let nextY = min(centerT, max(0, y + dy))
                    let candidate = objective(nextX, nextY)
                    if candidate < best { best = candidate; bestX = nextX; bestY = nextY }
                }}
                if best < error { x = bestX; y = bestY; error = best }
                else { step *= 0.5 }
            }
            guard error < 0.01 else { throw GarmentCodeProgramError.invalidMeasurements }
            let lowerT = centerT - y, upperT = centerT + x
            let insertionStart = edge.point(at: lowerT)
            let insertionEnd = edge.point(at: upperT)
            let sourceStart = sequence[0].start
            let sourceEnd = sequence[sequence.count - 1].end
            let from = sourceEnd - sourceStart
            let into = insertionEnd - insertionStart
            let angle = atan2(into.y, into.x) - atan2(from.y, from.x)
            var transformed = sequence.map { $0.translated(by: .zero - sourceStart)
                .rotated(by: angle, around: .zero).translated(by: insertionStart) }
            let vertices = transformed.map(\.start) + [transformed[transformed.count - 1].end]
            let average = vertices.reduce(GarmentCodePoint.zero) { sum, point in
                .init(x: sum.x + point.x, y: sum.y + point.y)
            } * (1 / Double(vertices.count))
            let cross = into.x * (average.y - insertionStart.y) -
                into.y * (average.x - insertionStart.x)
            if cross >= 0 {
                transformed = transformed.map {
                    $0.reflected(acrossLineFrom: insertionStart, to: insertionEnd)
                }
            }
            let before = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: 0, upper: lowerT)
            let after = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: upperT, upper: 1)
            let prefix = "\(edgeID)-logo-\(allIDs.count)"
            let beforeEdge = GarmentCodeGeometryEdge(id: "\(prefix)-before", start: edge.start,
                end: insertionStart, curvature: GarmentCodeGeometryEdge.curvature(for: before))
            let afterEdge = GarmentCodeGeometryEdge(id: "\(prefix)-after", start: insertionEnd,
                end: edge.end, curvature: GarmentCodeGeometryEdge.curvature(for: after))
            let inserted = transformed.enumerated().map { number, curve in
                var copy = curve
                copy.id = "\(prefix)-curve-\(number)"
                return copy
            }
            let logicalReplacements = [beforeEdge] + inserted + [afterEdge]
            let replacements = reverseBase
                ? logicalReplacements.reversed().map { $0.reversed() }
                : logicalReplacements
            panel.edges.replaceSubrange(index...index, with: replacements)
            guard let position = allIDs.firstIndex(of: projectedID) else {
                throw GarmentCodeGeometryError.invalidPanel(projectedID)
            }
            allIDs.replaceSubrange(position...position, with: replacements.map(\.id))
            // In the upstream direction the next lower-offset cut always
            // projects onto the portion before the previous cut. Reversing a
            // normalized front panel swaps which replacement segment that is.
            projectedID = beforeEdge.id
        }
        return allIDs
    }

    /// GarmentCode SkirtLevels supports its official base and tier catalog
    /// options. Each tier's front/back waist is derived from the previous
    /// front/back hem interface lengths and the level ruffle factor.
    static func skirtLevels(body: GarmentCodeBodyParameters,
                            design: GarmentCodeDesignParameters,
                            requestedRise: Double? = nil) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "SkirtLevels" else {
            throw GarmentCodeProgramError.wrongProgram("SkirtLevels")
        }
        guard case let .string(baseStyle)? = design.value(at: ["levels-skirt", "base"]),
              ["PencilSkirt", "Skirt2", "SkirtCircle", "AsymmSkirtCircle"].contains(baseStyle),
              case let .string(levelStyle)? = design.value(at: ["levels-skirt", "level"]),
              ["Skirt2", "SkirtCircle", "AsymmSkirtCircle"].contains(levelStyle) else {
            throw GarmentCodeProgramError.unsupportedParameter("levels-skirt.base/level")
        }
        guard let legLength = body["_leg_length"], let hipsLine = body["hips_line"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let countValue = try number(design, path: ["levels-skirt", "num_levels"])
        let ruffle = try number(design, path: ["levels-skirt", "level_ruffle"])
        let totalRatio = try number(design, path: ["levels-skirt", "length"])
        let baseFraction = try number(design, path: ["levels-skirt", "base_length_frac"])
        let designRise = try number(design, path: ["levels-skirt", "rise"])
        let rise = requestedRise ?? designRise
        guard countValue.rounded() == countValue, (1...5).contains(Int(countValue)),
              ruffle >= 1, totalRatio > 0, (0...1).contains(rise),
              (0...1).contains(designRise), (0...1).contains(baseFraction) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let count = Int(countValue)
        let totalLength = totalRatio * legLength
        let baseLength = totalLength * baseFraction + hipsLine * designRise
        let tierLength = (totalLength - totalLength * baseFraction) / Double(count)

        var baseDesign = design
        guard baseDesign.setValue(.string(baseStyle), at: ["meta", "bottom"]) else {
            throw GarmentCodeProgramError.missingDesignParameter("levels-skirt.base")
        }
        let base: GarmentCodePatternFile
        switch baseStyle {
        case "PencilSkirt":
            for slit in ["front_slit", "back_slit", "left_slit", "right_slit"] {
                _ = baseDesign.setValue(.number(0), at: ["pencil-skirt", slit])
            }
            guard baseDesign.setValue(.number(rise), at: ["pencil-skirt", "rise"]) else {
                throw GarmentCodeProgramError.missingDesignParameter("pencil-skirt.rise")
            }
            base = try pencilSkirt(body: body, design: baseDesign,
                                   requestedTotalLength: baseLength)
        case "Skirt2":
            _ = baseDesign.setValue(.number(rise), at: ["skirt", "rise"])
            _ = baseDesign.setValue(.number(0), at: ["skirt", "bottom_cut"])
            base = try twoPanelSkirt(body: body, design: baseDesign, lengthOverride: baseLength)
        case "SkirtCircle":
            _ = baseDesign.setValue(.number(rise), at: ["flare-skirt", "rise"])
            base = try circleSkirt(body: body, design: baseDesign,
                                   requestedLength: baseLength, includeCut: false)
        default:
            _ = baseDesign.setValue(.number(rise), at: ["flare-skirt", "rise"])
            base = try asymmetricCircleSkirt(body: body, design: baseDesign,
                                             requestedLength: baseLength, includeCut: false)
        }
        var panels = try base.geometryPanels()
        var stitchRecords = try stitchEdgeRecords(base, in: panels)
        var previousFront = "skirt_front"
        var previousBack = "skirt_back"
        var levelDesign = design
        guard levelDesign.setValue(.string(levelStyle), at: ["meta", "bottom"]) else {
            throw GarmentCodeProgramError.missingDesignParameter("levels-skirt.level")
        }
        _ = levelDesign.setValue(.number(0), at: ["skirt", "bottom_cut"])
        _ = levelDesign.setValue(.bool(false), at: ["flare-skirt", "cut", "add"])
        for slit in ["front_slit", "back_slit", "left_slit", "right_slit"] {
            _ = levelDesign.setValue(.number(0), at: ["pencil-skirt", slit])
        }
        var levelBody = body

        for levelIndex in 0..<count {
            guard let frontHem = lowestEdge(in: panels[previousFront]),
                  let backHem = lowestEdge(in: panels[previousBack]) else {
                throw GarmentCodeGeometryError.invalidPanel(previousFront)
            }
            levelBody.set(ruffle * (frontHem.length() + backHem.length()), for: "waist")
            levelBody.set(ruffle * backHem.length(), for: "waist_back_width")

            let tag = "_\(levelIndex)"
            let tier: GarmentCodePatternFile
            switch levelStyle {
            case "Skirt2":
                tier = try twoPanelSkirt(body: levelBody, design: levelDesign,
                                         lengthOverride: tierLength, tag: tag,
                                         topRuffles: false)
            case "SkirtCircle":
                tier = try renamedPanels(circleSkirt(body: levelBody, design: levelDesign,
                                                     requestedLength: tierLength, includeCut: false),
                                         suffix: tag)
            default:
                tier = try renamedPanels(asymmetricCircleSkirt(body: levelBody, design: levelDesign,
                                                               requestedLength: tierLength, includeCut: false),
                                         suffix: tag)
            }
            var tierPanels = try tier.geometryPanels()
            stitchRecords += try stitchEdgeRecords(tier, in: tierPanels)
            let tierFront = "skirt_front\(tag)", tierBack = "skirt_back\(tag)"
            guard let frontTop = tierPanels[tierFront]?.edges.first(where: { $0.label == "lower_interface" }),
                  let backTop = tierPanels[tierBack]?.edges.first(where: { $0.label == "lower_interface" }) else {
                throw GarmentCodeGeometryError.invalidPanel(tierFront)
            }
            stitchRecords.append([(previousFront, frontHem.id), (tierFront, frontTop.id)])
            stitchRecords.append([(previousBack, backHem.id), (tierBack, backTop.id)])
            for panelName in [tierFront, tierBack] {
                tierPanels[panelName]?.edges.indices.forEach { index in
                    if tierPanels[panelName]?.edges[index].label == "lower_interface" {
                        tierPanels[panelName]?.edges[index].label = nil
                    }
                }
            }
            panels.merge(tierPanels) { _, new in new }
            previousFront = tierFront
            previousBack = tierBack
        }

        let stitches = try resolveStitchEdgeRecords(stitchRecords, in: panels)
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    /// GarmentCode GodetSkirt supports the official PencilSkirt and Skirt2
    /// bases. Each hem edge is cut at equal intervals and paired with a
    /// triangular insert. Both public upstream bases expose straight hems to
    /// this component (Skirt2's optional bottom cut is suppressed upstream).
    static func godetSkirt(body: GarmentCodeBodyParameters,
                           design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "GodetSkirt" else {
            throw GarmentCodeProgramError.wrongProgram("GodetSkirt")
        }
        guard case let .string(baseStyle)? = design.value(at: ["godet-skirt", "base"]),
              ["PencilSkirt", "Skirt2"].contains(baseStyle) else {
            throw GarmentCodeProgramError.unsupportedParameter("godet-skirt.base")
        }
        var baseDesign = design
        guard baseDesign.setValue(.string(baseStyle), at: ["meta", "bottom"]) else {
            throw GarmentCodeProgramError.missingDesignParameter("meta.bottom")
        }
        if baseStyle == "Skirt2" {
            _ = baseDesign.setValue(.number(0), at: ["skirt", "bottom_cut"])
        }
        let base = baseStyle == "PencilSkirt"
            ? try pencilSkirt(body: body, design: baseDesign)
            : try twoPanelSkirt(body: body, design: baseDesign)
        let basePanels = try base.geometryPanels()
        var panels = basePanels
        var oldStitchIDs: [[(panel: String, edge: String)]] = []
        for stitch in base.pattern.stitches {
            oldStitchIDs.append(try stitch.sides.map { side in
                guard let panel = basePanels[side.panel], panel.edges.indices.contains(side.edge) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(side.panel, "\(side.edge)")
                }
                return (side.panel, panel.edges[side.edge].id)
            })
        }

        let insertWidth = try number(design, path: ["godet-skirt", "insert_w"])
        let insertDepth = try number(design, path: ["godet-skirt", "insert_depth"])
        let requestedCount = try number(design, path: ["godet-skirt", "num_inserts"])
        let spacing = try number(design, path: ["godet-skirt", "cuts_distance"])
        guard insertWidth > 0, insertDepth > 0, requestedCount >= 2,
              requestedCount.rounded() == requestedCount, spacing >= 0,
              Int(requestedCount).isMultiple(of: 2) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let perPanel = Int(requestedCount) / 2
        let sideLength = hypot(insertWidth / 2, insertDepth)
        var insertStitchIDs: [[(panel: String, edge: String)]] = []

        for name in ["skirt_front", "skirt_back"] {
            guard var panel = panels[name], !panel.edges.isEmpty,
                  let hemIndex = panel.edges.indices.min(by: {
                      averageY(panel.edges[$0]) < averageY(panel.edges[$1])
                  }) else { throw GarmentCodeGeometryError.invalidPanel(name) }
            let hem = panel.edges[hemIndex]
            guard hem.curvature == nil else {
                throw GarmentCodeProgramError.unsupportedParameter("GodetSkirt curved hem cuts")
            }
            let length = hem.length()
            var cutWidth = (length - spacing * Double(perPanel)) / Double(perPanel)
            var effectiveSpacing = spacing
            if cutWidth < 1 {
                cutWidth = 1
                effectiveSpacing = (length - cutWidth * Double(perPanel)) / Double(perPanel)
                guard effectiveSpacing >= 0 else {
                    throw GarmentCodeProgramError.invalidMeasurements
                }
            }
            var cutDepth: Double
            if sideLength > cutWidth / 2 {
                cutDepth = sqrt(sideLength * sideLength - pow(cutWidth / 2, 2))
            } else {
                cutDepth = 1
                cutWidth = 2 * sqrt(max(sideLength * sideLength - 1, 0))
            }
            guard cutDepth > 0, cutWidth > 0 else { throw GarmentCodeProgramError.invalidMeasurements }

            let direction = (hem.end - hem.start).normalized
            let inward = panel.signedArea >= 0 ? direction.leftNormal : direction.leftNormal * -1
            var replacement: [GarmentCodeGeometryEdge] = []
            var cursor = 0.0
            for index in 0..<perPanel {
                let startDistance = effectiveSpacing / 2 + Double(index) * (cutWidth + effectiveSpacing)
                let endDistance = startDistance + cutWidth
                guard startDistance >= cursor - 1e-7, endDistance <= length + 1e-7 else {
                    throw GarmentCodeProgramError.invalidMeasurements
                }
                let start = hem.start + direction * startDistance
                let end = hem.start + direction * endDistance
                let apex = (start + end) * 0.5 + inward * cutDepth
                if start.distance(to: hem.start + direction * cursor) > 1e-7 {
                    replacement.append(.init(id: "\(name)-godet-hem-\(index)-lead",
                                             start: hem.start + direction * cursor, end: start))
                }
                let leftID = "\(name)-godet-\(index)-left"
                let rightID = "\(name)-godet-\(index)-right"
                replacement.append(contentsOf: [.init(id: leftID, start: start, end: apex),
                                                .init(id: rightID, start: apex, end: end)])
                let insertIndex = name == "skirt_back" ? perPanel - 1 - index : index
                let insertName = "ins_\(name)_\(insertIndex)"
                let triangleEdges: [GarmentCodeGeometryEdge]
                if name == "skirt_front" {
                    triangleEdges = [
                        .init(id: "\(insertName)-bottom", start: .zero, end: .init(x: insertWidth, y: 0)),
                        .init(id: "\(insertName)-right", start: .init(x: insertWidth, y: 0), end: .init(x: insertWidth / 2, y: insertDepth)),
                        .init(id: "\(insertName)-left", start: .init(x: insertWidth / 2, y: insertDepth), end: .zero)
                    ]
                } else {
                    triangleEdges = [
                        .init(id: "\(insertName)-left", start: .zero, end: .init(x: insertWidth / 2, y: insertDepth)),
                        .init(id: "\(insertName)-right", start: .init(x: insertWidth / 2, y: insertDepth), end: .init(x: insertWidth, y: 0)),
                        .init(id: "\(insertName)-bottom", start: .init(x: insertWidth, y: 0), end: .zero)
                    ]
                }
                let triangle = GarmentCodePanelGeometry(id: insertName, label: "leg", edges: triangleEdges)
                panels[insertName] = triangle
                if name == "skirt_front" {
                    insertStitchIDs.append([(insertName, "\(insertName)-left"), (name, leftID)])
                    insertStitchIDs.append([(insertName, "\(insertName)-right"), (name, rightID)])
                } else {
                    insertStitchIDs.append([(insertName, "\(insertName)-left"), (name, rightID)])
                    insertStitchIDs.append([(insertName, "\(insertName)-right"), (name, leftID)])
                }
                cursor = endDistance
            }
            if length - cursor > 1e-7 {
                replacement.append(.init(id: "\(name)-godet-hem-end",
                                         start: hem.start + direction * cursor, end: hem.end))
            }
            panel.edges.replaceSubrange(hemIndex...hemIndex, with: replacement)
            panels[name] = panel
        }

        let stitchesByIDs = oldStitchIDs + insertStitchIDs
        let stitches = try stitchesByIDs.map { pair -> GarmentCodeStitch in
            let sides = try pair.map { item -> GarmentCodeStitchSide in
                guard let panel = panels[item.panel],
                      let index = panel.edges.firstIndex(where: { $0.id == item.edge }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(item.panel, item.edge)
                }
                return .init(panel: item.panel, edge: index)
            }
            return .init(sides: sides)
        }
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    private static func averageY(_ edge: GarmentCodeGeometryEdge) -> Double {
        (edge.start.y + edge.end.y) / 2
    }

    private static func fittedSkirtPanel(name: String, waist: Double, hips: Double,
                                         hipDepth: Double, totalHipCircumference: Double, length: Double,
                                         hiplineExtension: Double, dartPosition: Double,
                                         dartFraction: Double, matchTop: Double,
                                         lowAngle: Double, flare: Double,
                                         hipInclination: Double, doubleDart: Bool,
                                         back: Bool) throws -> (panel: GarmentCodePanelGeometry, dartEdgeIDs: [[String]]) {
        let lowWidth = totalHipCircumference * (flare - 1) / 4 + hips
        let adjustedDepth = hipDepth * hiplineExtension
        let dartDepth = max(hipDepth * dartFraction - (hipDepth - adjustedDepth), 0)
        let widthDifference = hips - waist
        let hipShift = min(tan(hipInclination * .pi / 180) * adjustedDepth, widthDifference)
        let angleShift = tan(lowAngle * .pi / 180) * lowWidth
        let a = GarmentCodePoint(x: hips - lowWidth, y: angleShift)
        let b = GarmentCodePoint(x: 0, y: length)
        let rightBottom = abs(flare - 1) < 1e-9
            ? GarmentCodeGeometryEdge(id: "\(name)-right-lower", start: a, end: b)
            : GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-right-lower", start: a, end: b,
                                                             endTangent: .init(x: 0, y: 1), initialGuess: .init(x: 0.75, y: 0))
        let c = GarmentCodePoint(x: hipShift, y: length + adjustedDepth)
        let rightTop = GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-right-upper", start: b, end: c,
                                                                     startTangent: .init(x: 0, y: 1), initialGuess: .init(x: 0.5, y: 0))
        let topEnd = GarmentCodePoint(x: hips * 2 - hipShift, y: length + adjustedDepth)
        let top = GarmentCodeGeometryEdge(id: "\(name)-top", start: c, end: topEnd)
        let leftTopEnd = GarmentCodePoint(x: hips * 2, y: length)
        let leftTop = GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-left-upper", start: topEnd, end: leftTopEnd,
                                                                    endTangent: .init(x: 0, y: -1), initialGuess: .init(x: 0.5, y: 0))
        let anglePoint = GarmentCodePoint(x: hips + lowWidth, y: -angleShift)
        let leftBottom = abs(flare - 1) < 1e-9
            ? GarmentCodeGeometryEdge(id: "\(name)-left-lower", start: leftTopEnd, end: anglePoint)
            : GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-left-lower", start: leftTopEnd, end: anglePoint,
                                                             startTangent: .init(x: 0, y: -1), initialGuess: .init(x: 0.25, y: 0))
        var topSegments: [GarmentCodeGeometryEdge] = []
        var dartEdgeIDs: [[String]] = []
        let dartWidth = widthDifference - hipShift
        if widthDifference > hipShift {
            let offsets: [Double]
            let sideLengths: [Double]
            let dartWidths: [Double]
            if doubleDart {
                let dist = dartPosition * 0.5
                offsets = [-(dartPosition + dist / 2 + dartWidth / 2) - dartWidth / 4,
                           -(dartPosition - dist / 2) - dartWidth / 4,
                           dartPosition - dist / 2 + dartWidth / 4,
                           dartPosition + dist / 2 + dartWidth / 2 + dartWidth / 4]
                sideLengths = [dartDepth * 0.9, dartDepth, dartDepth, dartDepth * 0.9]
                dartWidths = Array(repeating: dartWidth / 2, count: 4)
            } else {
                offsets = [-dartPosition - dartWidth / 2, dartPosition + dartWidth / 2]
                sideLengths = [dartDepth, dartDepth]
                dartWidths = [dartWidth, dartWidth]
            }
            let centers = zip(offsets, dartWidths).enumerated().map { (i, pair) in
                (i, top.length() / 2 + pair.0, pair.1, sideLengths[i])
            }.sorted { $0.1 < $1.1 }
            var cursor = 0.0
            let direction = (top.end - top.start).normalized
            for (index, center, width, sideLength) in centers {
                let startDistance = center - width / 2, endDistance = center + width / 2
                guard startDistance >= cursor, endDistance <= top.length() else { throw GarmentCodeProgramError.invalidMeasurements }
                let s = top.start + direction * startDistance, e = top.start + direction * endDistance
                let depth = sqrt(max(0, sideLength * sideLength - pow(width / 2, 2)))
                let apex = (s + e) * 0.5 - direction.leftNormal * depth
                topSegments.append(.init(id: "\(name)-top-segment-\(index)", start: top.start + direction * cursor, end: s))
                let leftID = "\(name)-dart\(index)-left", rightID = "\(name)-dart\(index)-right"
                topSegments.append(contentsOf: [.init(id: leftID, start: s, end: apex),
                                                .init(id: rightID, start: apex, end: e)])
                dartEdgeIDs.append([leftID, rightID])
                cursor = endDistance
            }
            topSegments.append(.init(id: "\(name)-top-segment-end", start: top.start + direction * cursor, end: top.end))
        } else {
            topSegments = [top]
        }
        var panel = GarmentCodePanelGeometry(id: name, label: "leg",
                                             edges: [rightBottom, rightTop] + topSegments + [leftTop, leftBottom,
                                                .init(id: "\(name)-closure", start: anglePoint, end: a)])
        let desiredNegative = back
        if (panel.signedArea < 0) != desiredNegative { panel.reverse() }
        // FittedSkirtPanel sets a top-center pivot before BasicPattern's
        // final first-vertex pivot. Both operations truncate toward zero;
        // omitting the first one changes the serialized fractional origin.
        panel.translate(by: .init(x: -Double(Int(hips)),
                                  y: -Double(Int(max(length + adjustedDepth, abs(angleShift))))))
        panel.edges.indices.forEach { if panel.edges[$0].id.hasPrefix("\(name)-top") { panel.edges[$0].label = "lower_interface" } }
        return (panel, dartEdgeIDs)
    }

    private static func pantPanel(name: String, body: GarmentCodeBodyParameters,
                                  waist: Double, hips: Double, hipDepth: Double, length: Double,
                                  crotchExtension: Double, hiplineExtension: Double,
                                  dartPosition: Double, matchTop: Double,
                                  legCircumference: Double, flareRatio: Double,
                                  crotchDifference: Double, hipInclination: Double,
                                  doubleDart: Bool) throws -> (panel: GarmentCodePanelGeometry, dartEdgeIDs: [[String]]) {
        let flare = legCircumference * (flareRatio - 1) / 4
        let adjustedDepth = hipDepth * hiplineExtension
        let dartDepth = adjustedDepth * 0.8
        let widthDifference = hips - waist
        let hipShift = min(tan(hipInclination * .pi / 180) * adjustedDepth, widthDifference)
        let a = GarmentCodePoint(x: -flare, y: 0)
        let b = GarmentCodePoint(x: 0, y: length)
        let rightBottom = abs(flare) < 1e-9
            ? GarmentCodeGeometryEdge(id: "\(name)-outside-lower", start: a, end: b)
            : GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-outside-lower", start: a, end: b,
                                                             endTangent: .init(x: 0, y: 1),
                                                             initialGuess: .init(x: 0.75, y: 0))
        let c = GarmentCodePoint(x: hipShift, y: length + adjustedDepth)
        let rightTop = GarmentCodeGeometryEdge.quadraticFromTangents(id: "\(name)-outside-upper",
                                                                     start: b, end: c,
                                                                     startTangent: .init(x: 0, y: 1),
                                                                     initialGuess: .init(x: 0.5, y: 0))
        let topEnd = GarmentCodePoint(x: widthDifference + waist, y: length + adjustedDepth)
        let crotchTopEnd = GarmentCodePoint(x: hips, y: length + 0.45 * adjustedDepth)
        let crotchBottomEnd = GarmentCodePoint(x: hips + crotchExtension, y: length - crotchDifference)
        let crotchBottom = GarmentCodeGeometryEdge.quadraticFromTangents(
            id: "\(name)-crotch-lower", start: crotchTopEnd, end: crotchBottomEnd,
            startTangent: .init(x: 0, y: -1), endTangent: .init(x: 1, y: 0),
            initialGuess: .init(x: 0.5, y: -0.5))
        let insideEnd = GarmentCodePoint(x: crotchBottomEnd.x - 2 + flare,
                                         y: min(0, length - crotchDifference * 1.5))
        let inside = GarmentCodeGeometryEdge.quadraticFromTangents(
            id: "\(name)-inside", start: crotchBottomEnd, end: insideEnd,
            endTangent: .init(x: flare, y: insideEnd.y - crotchBottomEnd.y),
            initialGuess: .init(x: 0.3, y: 0))
        let top = GarmentCodeGeometryEdge(id: "\(name)-top", start: c, end: topEnd)
        var topSegments: [GarmentCodeGeometryEdge] = []
        var dartEdgeIDs: [[String]] = []
        let dartWidth = widthDifference - hipShift
        if widthDifference > hipShift {
            let dist = dartPosition * 0.5
            let offsets = doubleDart
                ? [-(dartPosition + dist / 2 + dartWidth / 2 + dartWidth / 4),
                   -(dartPosition - dist / 2) - dartWidth / 4]
                : [-dartPosition - dartWidth / 2]
            let widths = Array(repeating: doubleDart ? dartWidth / 2 : dartWidth, count: offsets.count)
            let placements = zip(offsets, widths).enumerated().map { index, pair in
                (index, top.length() + pair.0, pair.1)
            }.sorted { $0.1 < $1.1 }
            var cursor = 0.0
            for (index, centerDistance, dartW) in placements {
                let startDistance = centerDistance - dartW / 2
                let endDistance = centerDistance + dartW / 2
                guard startDistance >= cursor, endDistance <= top.length() else {
                    throw GarmentCodeProgramError.invalidMeasurements
                }
                let direction = (top.end - top.start).normalized
                let s = top.start + direction * startDistance
                let e = top.start + direction * endDistance
                let requestedSideLength = doubleDart && index == 0 ? dartDepth * 0.9 : dartDepth
                let perpendicularDepth = sqrt(max(0, requestedSideLength * requestedSideLength - pow(dartW / 2, 2)))
                let apex = (s + e) * 0.5 - direction.leftNormal * perpendicularDepth
                topSegments.append(.init(id: "\(name)-top-segment-\(index)", start: top.start + direction * cursor, end: s))
                let leftID = "\(name)-dart\(index)-left", rightID = "\(name)-dart\(index)-right"
                topSegments.append(contentsOf: [.init(id: leftID, start: s, end: apex),
                                                .init(id: rightID, start: apex, end: e)])
                dartEdgeIDs.append([leftID, rightID])
                cursor = endDistance
            }
            topSegments.append(.init(id: "\(name)-top-segment-end", start: top.start + (top.end - top.start).normalized * cursor, end: top.end))
        } else {
            topSegments = [top]
        }
        let baseEdges = [rightBottom, rightTop] + topSegments + [
            .init(id: "\(name)-crotch-upper", start: topEnd, end: crotchTopEnd),
            crotchBottom, inside,
            .init(id: "\(name)-closure", start: insideEnd, end: a)
        ]
        var panel = GarmentCodePanelGeometry(id: name, label: "leg", edges: baseEdges)
        let desiredNegativeNormal = doubleDart // Back-half panels face the opposite side of the body.
        if (panel.signedArea < 0) != desiredNegativeNormal { panel.reverse() }
        panel.edges.indices.forEach { i in
            if panel.edges[i].id.hasPrefix("\(name)-top") { panel.edges[i].label = "lower_interface" }
        }
        return (panel, dartEdgeIDs)
    }

    private static func mirrorPantPanel(_ panel: GarmentCodePanelGeometry,
                                        name: String) throws -> GarmentCodePanelGeometry {
        guard panel.edges.first != nil else { throw GarmentCodeGeometryError.invalidPanel(panel.id) }
        var mirrored = panel
        mirrored.id = name
        mirrored.edges = panel.edges.map { edge in
            var copy = edge.reflected(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
            copy.id = edge.id.replacingOccurrences(of: panel.id, with: name)
            return copy
        }
        mirrored.reverse()
        return mirrored
    }

    /// Swift port of the uncut two-panel `skirt_paneled.Skirt2` program.
    static func twoPanelSkirt(body: GarmentCodeBodyParameters,
                              design: GarmentCodeDesignParameters,
                              lengthOverride: Double? = nil,
                              tag: String = "",
                              topRuffles: Bool = true) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "Skirt2" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 Skirt2")
        }
        let bottomCut = try number(design, path: ["skirt", "bottom_cut"])
        guard let bodyWaist = body["waist"], let bodyHips = body["hips"],
              let waistBack = body["waist_back_width"],
              let hipLine = body["hips_line"], let legLength = body["_leg_length"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let rise = try number(design, path: ["skirt", "rise"])
        let lengthRatio = try number(design, path: ["skirt", "length"])
        let ruffles = try number(design, path: ["skirt", "ruffle"])
        let flare = try number(design, path: ["skirt", "flare"])
        guard rise.isFinite, (0...1).contains(rise), ruffles > 0,
              flare.isFinite else { throw GarmentCodeProgramError.invalidMeasurements }

        let waist = interpolate(bodyHips, bodyWaist, rise)
        let backWaist = interpolate(body["hip_back_width"] ?? waistBack, waistBack, rise)
        let length = max(lengthOverride ?? (rise * hipLine + lengthRatio * legLength), 5)
        let panelRuffles = topRuffles ? ruffles : 1
        guard (0...0.9).contains(bottomCut), lengthRatio.isFinite else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let slitFraction = bottomCut * lengthRatio / length
        let frontName = "skirt_front\(tag)"
        let backName = "skirt_back\(tag)"
        var front = paneledSkirtPanel(name: frontName, waistLength: waist - backWaist,
                                      length: length, ruffles: panelRuffles,
                                      flare: flare, cutFraction: slitFraction,
                                      reverseForPanelNormal: true)
        var back = paneledSkirtPanel(name: backName, waistLength: backWaist,
                                     length: length, ruffles: panelRuffles,
                                     flare: flare, cutFraction: slitFraction,
                                     reverseForPanelNormal: false)
        let topEdgeIndex = slitFraction > 0 ? 2 : 1
        front.edges[front.edges.count - 1 - topEdgeIndex].label = "lower_interface"
        back.edges[topEdgeIndex].label = "lower_interface"
        let stitches = [
            GarmentCodeStitch(sides: [.init(panel: frontName, edge: front.edges.count - 1 - (slitFraction > 0 ? 1 : 0)),
                                      .init(panel: backName, edge: slitFraction > 0 ? 1 : 0)]),
            GarmentCodeStitch(sides: [.init(panel: frontName, edge: front.edges.count - 1 - (slitFraction > 0 ? 3 : 2)),
                                      .init(panel: backName, edge: slitFraction > 0 ? 3 : 2)])
        ]
        return try GarmentCodePatternFile(
            geometry: [frontName: front, backName: back], stitches: stitches
        )
    }

    /// Swift port of the default panel-curve-free `SkirtManyPanels` program.
    /// The official panel distribution changes only 3D placement; each 2D
    /// panel remains the same local outline and adjacent side seams are stitched.
    static func manyPanelSkirt(body: GarmentCodeBodyParameters,
                               design: GarmentCodeDesignParameters) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "SkirtManyPanels" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 SkirtManyPanels")
        }
        guard let bodyWaist = body["waist"], let bodyHips = body["hips"],
              let hipsLine = body["hips_line"], let legLength = body["_leg_length"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let rise = try number(design, path: ["flare-skirt", "rise"])
        let lengthRatio = try number(design, path: ["flare-skirt", "length"])
        let suns = try number(design, path: ["flare-skirt", "suns"])
        let countValue = try number(design, path: ["flare-skirt", "skirt-many-panels", "n_panels"])
        let panelCurve = try number(design, path: ["flare-skirt", "skirt-many-panels", "panel_curve"])
        guard countValue.rounded() == countValue,
              (4...15).contains(Int(countValue)), (0...1).contains(rise),
              bodyWaist > 0, bodyHips > 0, hipsLine > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        guard [-0.35, -0.25, -0.15, 0, 0.15, 0.25, 0.35, 0.45].contains(panelCurve) else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let count = Int(countValue)
        let waist = interpolate(bodyHips, bodyWaist, rise)
        let hipLine = rise * hipsLine
        let length = max(hipLine + lengthRatio * legLength, 5)
        let topWidth = waist / Double(count)
        let flareCoefficient = 1 + suns * length * 2 * .pi / waist
        let bottomWidth = topWidth * flareCoefficient
        guard topWidth > 0, bottomWidth >= topWidth, length > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let flare = (bottomWidth - topWidth) / 2
        let points = [
            GarmentCodePoint.zero,
            .init(x: flare, y: length),
            .init(x: flare + topWidth, y: length),
            .init(x: bottomWidth, y: 0)
        ]
        var panels: [String: GarmentCodePanelGeometry] = [:]
        for index in 0..<count {
            var edges: [GarmentCodeGeometryEdge] = [
                .init(id: "skirt_panel_\(index)-e0", start: points[0], end: points[1]),
                .init(id: "skirt_panel_\(index)-e1", start: points[1], end: points[2]),
                .init(id: "skirt_panel_\(index)-e2", start: points[2], end: points[3])
            ]
            if abs(panelCurve) < 1e-12 {
                edges.append(.init(id: "skirt_panel_\(index)-e3", start: points[3], end: points[0]))
            } else {
                let control = GarmentCodePoint(x: 0.5, y: panelCurve)
                let passPoint = points[3] + (points[0] - points[3]) * control.x +
                    (points[0] - points[3]).leftNormal * control.y
                let arc = try circleThrough(start: points[3], end: points[0], point: passPoint)
                edges.append(.init(id: "skirt_panel_\(index)-e3", start: points[3], end: points[0],
                                   curvature: .init(circleRadius: arc.radius,
                                                    largeArc: arc.largeArc, right: arc.right)))
            }
            var panel = GarmentCodePanelGeometry(id: "skirt_panel_\(index)", label: "leg", edges: edges)
            // The upstream distribution normalizes every panel to a positive
            // facing, bottom-edge-first 2D edge loop before serialization.
            panel.reverse()
            panel.edges[2].label = "lower_interface"
            panels[panel.id] = panel
        }
        var stitches: [GarmentCodeStitch] = []
        for index in 0..<count {
            let next = (index + 1) % count
            stitches.append(.init(sides: [
                .init(panel: "skirt_panel_\(index)", edge: 1),
                .init(panel: "skirt_panel_\(next)", edge: 3)
            ]))
        }
        return try GarmentCodePatternFile(geometry: panels, stitches: stitches)
    }

    /// Swift port of `circle_skirt.SkirtCircle` with its standard two-panel
    /// `CircleArcPanel` construction. `MetaGarment`'s 3D placements are omitted;
    /// local panel geometry, labels, and side-stitch topology are retained.
    static func circleSkirt(body: GarmentCodeBodyParameters,
                            design: GarmentCodeDesignParameters,
                            requestedLength: Double? = nil,
                            includeCut: Bool = true) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "SkirtCircle" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 SkirtCircle")
        }
        let sunFraction = try number(design, path: ["flare-skirt", "suns"])
        guard sunFraction > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let (waist, computedLength) = try circleSkirtMeasurements(body: body, design: design)
        let skirtLength = max(requestedLength ?? computedLength, 5)
        let angle = (sunFraction / 2) * 2 * Double.pi
        guard angle < 2 * .pi else { throw GarmentCodeProgramError.invalidMeasurements }
        let topRadius = (waist / 2) / angle
        guard topRadius.isFinite, topRadius > 0 else { throw GarmentCodeProgramError.invalidMeasurements }

        var front = circleArcPanel(name: "skirt_front", topRadius: topRadius,
                                   length: skirtLength, angle: angle,
                                   reverseForPanelNormal: true)
        var back = circleArcPanel(name: "skirt_back", topRadius: topRadius,
                                  length: skirtLength, angle: angle,
                                  reverseForPanelNormal: false)
        if includeCut {
            try applyCircleSkirtCutIfRequested(front: &front, back: &back,
                                               design: design, skirtLength: skirtLength)
        }
        var frontPanel = front
        var backPanel = back
        // MetaGarment propagates the lower-interface label to the skirt top
        // when no waistband is selected. CircleArcPanel's top edge is 3 after
        // the front's normal correction, and 0 on the back.
        frontPanel.edges[frontPanel.edges.firstIndex(where: { $0.id == "skirt_front-top" })!].label = "lower_interface"
        backPanel.edges[backPanel.edges.firstIndex(where: { $0.id == "skirt_back-top" })!].label = "lower_interface"

        let stitches = try edgePairStitches(
            front: frontPanel, back: backPanel,
            edgePairs: [("skirt_front-left", "skirt_back-left"),
                        ("skirt_front-right", "skirt_back-right")]
        )
        return try GarmentCodePatternFile(
            geometry: ["skirt_front": frontPanel, "skirt_back": backPanel],
            stitches: stitches
        )
    }

    /// Swift port of `circle_skirt.AsymmSkirtCircle` with its two `AsymHalfCirclePanel`s.
    static func asymmetricCircleSkirt(body: GarmentCodeBodyParameters,
                                      design: GarmentCodeDesignParameters,
                                      requestedLength: Double? = nil,
                                      includeCut: Bool = true) throws -> GarmentCodePatternFile {
        guard selectedOption(design, path: ["meta", "bottom"]) == "AsymmSkirtCircle" else {
            throw GarmentCodeProgramError.wrongProgram("meta.bottom 必须选择 AsymmSkirtCircle")
        }
        let frontRatio = try number(design, path: ["flare-skirt", "asymm", "front_length"])
        guard (0...1).contains(frontRatio) else { throw GarmentCodeProgramError.invalidMeasurements }
        let (waist, computedLength) = try circleSkirtMeasurements(body: body, design: design)
        let length = max(requestedLength ?? computedLength, 5)
        let topRadius = waist / (2 * Double.pi)
        let frontLength = frontRatio * length
        let totalLength = 2 * topRadius + length + frontLength
        let halfDifference = totalLength / 2 - frontLength - topRadius
        let sideLength = sqrt(max(0, pow(totalLength / 2, 2) - pow(halfDifference, 2))) - topRadius
        guard topRadius.isFinite, topRadius > 0, sideLength > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }

        var front = asymmetricHalfCirclePanel(name: "skirt_front", topRadius: topRadius,
                                              frontLength: frontLength, sideLength: sideLength,
                                              reverseForPanelNormal: true)
        var back = asymmetricHalfCirclePanel(name: "skirt_back", topRadius: topRadius,
                                             frontLength: length, sideLength: sideLength,
                                             reverseForPanelNormal: false)
        if includeCut {
            try applyCircleSkirtCutIfRequested(front: &front, back: &back,
                                               design: design, skirtLength: length)
        }
        front.edges[front.edges.firstIndex(where: { $0.id == "skirt_front-top" })!].label = "lower_interface"
        back.edges[back.edges.firstIndex(where: { $0.id == "skirt_back-top" })!].label = "lower_interface"
        let stitches = try edgePairStitches(
            front: front, back: back,
            edgePairs: [("skirt_front-left", "skirt_back-left"),
                        ("skirt_front-right", "skirt_back-right")]
        )
        return try GarmentCodePatternFile(
            geometry: ["skirt_front": front, "skirt_back": back], stitches: stitches
        )
    }

    private static func circleArcPanel(name: String, topRadius: Double,
                                       length: Double, angle: Double,
                                       reverseForPanelNormal: Bool) -> GarmentCodePanelGeometry {
        let halfArc = angle / 2
        let topChord = 2 * topRadius * sin(halfArc)
        let bottomChord = 2 * (topRadius + length) * sin(halfArc)
        let vertical = length * cos(halfArc)
        let vertices = [
            GarmentCodePoint(x: -topChord / 2, y: 0),
            GarmentCodePoint(x: topChord / 2, y: 0),
            GarmentCodePoint(x: bottomChord / 2, y: -vertical),
            GarmentCodePoint(x: -bottomChord / 2, y: -vertical)
        ]
        var panel = GarmentCodePanelGeometry(id: name, label: "leg", edges: [
            .init(id: "\(name)-top", start: vertices[0], end: vertices[1],
                  curvature: .init(circleRadius: topRadius,
                                   largeArc: halfArc > .pi / 2, right: true)),
            .init(id: "\(name)-right", start: vertices[1], end: vertices[2]),
            .init(id: "\(name)-hem", start: vertices[2], end: vertices[3],
                  curvature: .init(circleRadius: topRadius + length,
                                   largeArc: halfArc > .pi / 2, right: false)),
            .init(id: "\(name)-left", start: vertices[3], end: vertices[0])
        ])
        if reverseForPanelNormal { panel.reverse() }
        return panel
    }

    private static func asymmetricHalfCirclePanel(name: String, topRadius: Double,
                                                  frontLength: Double, sideLength: Double,
                                                  reverseForPanelNormal: Bool) -> GarmentCodePanelGeometry {
        let outerRadius = topRadius + sideLength
        let bottomDepth = topRadius + frontLength
        let vertices = [
            GarmentCodePoint(x: -topRadius, y: 0),
            GarmentCodePoint(x: topRadius, y: 0),
            GarmentCodePoint(x: outerRadius, y: 0),
            GarmentCodePoint(x: -outerRadius, y: 0)
        ]
        // CircleEdgeFactory.from_three_points for a symmetric chord and an
        // explicit lower control point. The circumcenter lies on the y-axis.
        let centerY = (outerRadius * outerRadius - bottomDepth * bottomDepth) / (2 * bottomDepth)
        let bottomRadius = abs(bottomDepth + centerY)
        let largeArc = bottomDepth > bottomRadius
        var panel = GarmentCodePanelGeometry(id: name, label: "leg", edges: [
            .init(id: "\(name)-top", start: vertices[0], end: vertices[1],
                  curvature: .init(circleRadius: topRadius, largeArc: false, right: true)),
            .init(id: "\(name)-right", start: vertices[1], end: vertices[2]),
            .init(id: "\(name)-hem", start: vertices[2], end: vertices[3],
                  curvature: .init(circleRadius: bottomRadius, largeArc: largeArc, right: false)),
            .init(id: "\(name)-left", start: vertices[3], end: vertices[0])
        ])
        if reverseForPanelNormal { panel.reverse() }
        return panel
    }

    private static func straightBandPanel(name: String, width: Double,
                                          depth: Double,
                                          reverseForPanelNormal: Bool) -> GarmentCodePanelGeometry {
        let points = [GarmentCodePoint.zero, .init(x: 0, y: depth),
                      .init(x: width, y: depth), .init(x: width, y: 0)]
        var panel = GarmentCodePanelGeometry(id: name, label: "body", edges: points.indices.map { index in
            .init(id: "\(name)-e\(index)", start: points[index], end: points[(index + 1) % points.count])
        })
        if reverseForPanelNormal { panel.reverse() }
        return panel
    }

    private static func pantCuffBandPanel(name: String, width: Double, depth: Double,
                                          tag: String, front: Bool,
                                          label: String = "leg") -> GarmentCodePanelGeometry {
        let points: [GarmentCodePoint]
        switch (tag, front) {
        case ("r", true):
            points = [.zero, .init(x: width, y: 0), .init(x: width, y: depth), .init(x: 0, y: depth)]
        case ("r", false):
            points = [.zero, .init(x: 0, y: depth), .init(x: width, y: depth), .init(x: width, y: 0)]
        case ("l", true):
            points = [.zero, .init(x: 0, y: depth), .init(x: -width, y: depth), .init(x: -width, y: 0)]
        default:
            points = [.zero, .init(x: -width, y: 0), .init(x: -width, y: depth), .init(x: 0, y: depth)]
        }
        return GarmentCodePanelGeometry(id: name, label: label, edges: points.indices.map { index in
            .init(id: "\(name)-e\(index)", start: points[index], end: points[(index + 1) % points.count])
        })
    }

    private static func pantCuffSkirtPanel(name: String, waistLength: Double,
                                           length: Double, ruffles: Double, flare: Double,
                                           tag: String, front: Bool,
                                           label: String = "leg") -> GarmentCodePanelGeometry {
        let topWidth = waistLength * ruffles
        let lowWidth = topWidth + 2 * flare
        let topShift = (lowWidth - topWidth) / 2
        let topLeft = GarmentCodePoint(x: topShift, y: length)
        let topRight = GarmentCodePoint(x: topShift + topWidth, y: length)
        let bottomRight = GarmentCodePoint(x: lowWidth, y: 0)
        let rightSide = tag == "r"
        let points: [GarmentCodePoint]
        switch (rightSide, front) {
        case (true, true): points = [.zero, bottomRight, topRight, topLeft]
        case (true, false): points = [.zero, topLeft, topRight, bottomRight]
        case (false, true): points = [.zero, topLeft, topRight, bottomRight].map { .init(x: -$0.x, y: $0.y) }
        case (false, false): points = [.zero, bottomRight, topRight, topLeft].map { .init(x: -$0.x, y: $0.y) }
        }
        return GarmentCodePanelGeometry(id: name, label: label, edges: points.indices.map { index in
            .init(id: "\(name)-e\(index)", start: points[index], end: points[(index + 1) % points.count])
        })
    }

    private static func lowestEdge(in panel: GarmentCodePanelGeometry?) -> GarmentCodeGeometryEdge? {
        guard let panel else { return nil }
        let edge = panel.edges.min { lhs, rhs in
            (lhs.start.y + lhs.end.y) < (rhs.start.y + rhs.end.y)
        }
        let yValues = panel.edges.map { ($0.start.y + $0.end.y) / 2 }
        if (yValues.max() ?? 0) - (yValues.min() ?? 0) < 1e-7,
           let curvedHem = panel.edges.first(where: {
               $0.curvature != nil && $0.label != "lower_interface"
           }) {
            return curvedHem
        }
        return edge
    }

    private static func renamedPanels(_ file: GarmentCodePatternFile,
                                      suffix: String) throws -> GarmentCodePatternFile {
        let source = try file.geometryPanels()
        var renamed: [String: GarmentCodePanelGeometry] = [:]
        let names = Dictionary(uniqueKeysWithValues: source.keys.map { ($0, $0 + suffix) })
        for (name, var panel) in source {
            let newName = names[name]!
            panel.id = newName
            panel.edges = panel.edges.map { edge in
                var edge = edge
                edge.id = edge.id.replacingOccurrences(of: name, with: newName)
                return edge
            }
            renamed[newName] = panel
        }
        let stitches = file.pattern.stitches.map { stitch in
            GarmentCodeStitch(sides: stitch.sides.map { side in
                GarmentCodeStitchSide(panel: names[side.panel] ?? side.panel, edge: side.edge)
            }, rightWrong: stitch.rightWrong)
        }
        return try GarmentCodePatternFile(geometry: renamed, stitches: stitches)
    }

    private static func stitchEdgeRecords(_ file: GarmentCodePatternFile,
                                          in panels: [String: GarmentCodePanelGeometry]) throws
        -> [[(panel: String, edge: String)]] {
        try file.pattern.stitches.map { stitch in
            try stitch.sides.map { side in
                guard let panel = panels[side.panel], panel.edges.indices.contains(side.edge) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(side.panel, "\(side.edge)")
                }
                return (side.panel, panel.edges[side.edge].id)
            }
        }
    }

    private static func resolveStitchEdgeRecords(
        _ records: [[(panel: String, edge: String)]],
        in panels: [String: GarmentCodePanelGeometry]
    ) throws -> [GarmentCodeStitch] {
        try records.map { record in
            let sides = try record.map { reference -> GarmentCodeStitchSide in
                guard let panel = panels[reference.panel],
                      let index = panel.edges.firstIndex(where: { $0.id == reference.edge }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
                }
                return .init(panel: reference.panel, edge: index)
            }
            return .init(sides: sides)
        }
    }

    private static func paneledSkirtPanel(name: String, waistLength: Double,
                                          length: Double, ruffles: Double,
                                          flare: Double,
                                          cutFraction: Double = 0,
                                          reverseForPanelNormal: Bool) -> GarmentCodePanelGeometry {
        let topWidth = waistLength * ruffles
        let lowWidth = topWidth + 2 * flare
        let topShift = (lowWidth - topWidth) / 2
        let topLeft = GarmentCodePoint(x: topShift, y: length)
        let topRight = GarmentCodePoint(x: topShift + topWidth, y: length)
        let bottomRight = GarmentCodePoint(x: lowWidth, y: 0)
        var edges: [GarmentCodeGeometryEdge]
        if cutFraction > 0 {
            let rightCut = GarmentCodePoint(x: topShift * cutFraction, y: length * cutFraction)
            let leftCut = GarmentCodePoint(x: bottomRight.x + (topRight.x - bottomRight.x) * cutFraction,
                                           y: bottomRight.y + (topRight.y - bottomRight.y) * cutFraction)
            edges = [
                .init(id: "\(name)-right-lower", start: .zero, end: rightCut),
                .init(id: "\(name)-right-upper", start: rightCut, end: topLeft),
                .init(id: "\(name)-top", start: topLeft, end: topRight),
                .init(id: "\(name)-left-upper", start: topRight, end: leftCut),
                .init(id: "\(name)-left-lower", start: leftCut, end: bottomRight),
                .init(id: "\(name)-hem", start: bottomRight, end: .zero)
            ]
        } else {
            let points = [GarmentCodePoint.zero, topLeft, topRight, bottomRight]
            edges = points.indices.map { index in
                .init(id: "\(name)-e\(index)", start: points[index], end: points[(index + 1) % points.count])
            }
        }
        var panel = GarmentCodePanelGeometry(id: name, label: "leg", edges: edges)
        if reverseForPanelNormal { panel.reverse() }
        return panel
    }

    private static func applyCircleSkirtCutIfRequested(front: inout GarmentCodePanelGeometry,
                                                       back: inout GarmentCodePanelGeometry,
                                                       design: GarmentCodeDesignParameters,
                                                       skirtLength: Double) throws {
        guard case .bool(true)? = design.value(at: ["flare-skirt", "cut", "add"]) else { return }
        let widthRatio = try number(design, path: ["flare-skirt", "cut", "width"])
        let depthRatio = try number(design, path: ["flare-skirt", "cut", "depth"])
        let placement = try number(design, path: ["flare-skirt", "cut", "place"])
        guard (0.05...0.4).contains(widthRatio), (0.05...0.95).contains(depthRatio),
              (-1...1).contains(placement), skirtLength > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let width = widthRatio * skirtLength
        let depth = depthRatio * skirtLength
        let targetFront = placement > 0
        let panel = targetFront ? front : back
        guard let hemIndex = panel.edges.firstIndex(where: { $0.id == "\(panel.id)-hem" }) else {
            throw GarmentCodeGeometryError.invalidPanel(panel.id)
        }
        let hem = panel.edges[hemIndex]
        let arcLength = hem.length()
        let offset = min(arcLength - width / 2, max(width / 2, abs(placement * arcLength)))
        let centerT = offset / arcLength
        let maxHalfT = min(centerT, 1 - centerT)
        guard maxHalfT > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let maxChord = hem.point(at: centerT - maxHalfT).distance(to: hem.point(at: centerT + maxHalfT))
        guard maxChord >= width else { throw GarmentCodeProgramError.invalidMeasurements }
        var low = 0.0, high = maxHalfT
        for _ in 0..<72 {
            let half = (low + high) / 2
            let chord = hem.point(at: centerT - half).distance(to: hem.point(at: centerT + half))
            if chord < width { low = half } else { high = half }
        }
        let halfT = (low + high) / 2
        let startT = centerT - halfT
        let endT = centerT + halfT
        let before = hem.split(at: startT, idPrefix: "\(hem.id)-cut-before")
        let endLocal = (endT - startT) / (1 - startT)
        let after = before.1.split(at: endLocal, idPrefix: "\(hem.id)-cut-after")
        let start = before.1.start
        let end = after.0.end
        let chord = end - start
        let normal = chord.normalized.leftNormal * (hem.start.x > hem.end.x ? -1 : 1)
        let apex = (start + end) * 0.5 + normal * depth
        let cutEdges = [
            GarmentCodeGeometryEdge(id: "\(hem.id)-cut-a", start: start, end: apex),
            GarmentCodeGeometryEdge(id: "\(hem.id)-cut-b", start: apex, end: end)
        ]
        var updated = panel
        updated.edges.replaceSubrange(hemIndex...hemIndex, with: [before.0] + cutEdges + [after.1])
        if targetFront { front = updated } else { back = updated }
    }

    private static func edgePairStitches(front: GarmentCodePanelGeometry,
                                        back: GarmentCodePanelGeometry,
                                        edgePairs: [(String, String)]) throws -> [GarmentCodeStitch] {
        try edgePairs.map { frontID, backID in
            guard let frontIndex = front.edges.firstIndex(where: { $0.id == frontID }),
                  let backIndex = back.edges.firstIndex(where: { $0.id == backID }) else {
                throw GarmentCodeGeometryError.invalidPanel(front.id)
            }
            return .init(sides: [.init(panel: front.id, edge: frontIndex),
                                 .init(panel: back.id, edge: backIndex)])
        }
    }

    private static func circleThrough(start: GarmentCodePoint, end: GarmentCodePoint,
                                      point: GarmentCodePoint) throws -> (radius: Double, largeArc: Bool, right: Bool) {
        let determinant = 2 * (start.x * (point.y - end.y) + point.x * (end.y - start.y) +
                               end.x * (start.y - point.y))
        guard abs(determinant) > 1e-12 else { throw GarmentCodeProgramError.invalidMeasurements }
        let s = start.x * start.x + start.y * start.y
        let p = point.x * point.x + point.y * point.y
        let e = end.x * end.x + end.y * end.y
        let center = GarmentCodePoint(
            x: (s * (point.y - end.y) + p * (end.y - start.y) + e * (start.y - point.y)) / determinant,
            y: (s * (end.x - point.x) + p * (start.x - end.x) + e * (point.x - start.x)) / determinant
        )
        let radius = center.distance(to: start)
        let midpoint = (start + end) * 0.5
        let middleDistance = point.distance(to: midpoint)
        let first = point - start
        let second = end - start
        let cross = first.x * second.y - first.y * second.x
        guard radius.isFinite, radius > 0, cross.isFinite, abs(cross) > 1e-12 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        return (radius, middleDistance > radius, cross > 0)
    }

    private static func fittedBandPanel(name: String, depth: Double,
                                        topWidth: Double, bottomWidth: Double,
                                        reverseForPanelNormal: Bool) throws -> GarmentCodePanelGeometry {
        let difference = bottomWidth - topWidth
        guard depth > 0, difference > 0 else { throw GarmentCodeProgramError.invalidMeasurements }
        let angle = difference / depth
        guard angle > 0, angle < 2 * .pi else { throw GarmentCodeProgramError.invalidMeasurements }
        let topRadius = topWidth / angle
        let halfArc = angle / 2
        let topChord = 2 * topRadius * sin(halfArc)
        let bottomChord = 2 * (topRadius + depth) * sin(halfArc)
        let vertical = depth * cos(halfArc)
        let points = [
            GarmentCodePoint(x: -topChord / 2, y: 0),
            GarmentCodePoint(x: topChord / 2, y: 0),
            GarmentCodePoint(x: bottomChord / 2, y: -vertical),
            GarmentCodePoint(x: -bottomChord / 2, y: -vertical)
        ]
        var panel = GarmentCodePanelGeometry(id: name, label: "body", edges: [
            .init(id: "\(name)-top", start: points[0], end: points[1],
                  curvature: .init(circleRadius: topRadius,
                                   largeArc: halfArc > .pi / 2, right: true)),
            .init(id: "\(name)-right", start: points[1], end: points[2]),
            .init(id: "\(name)-bottom", start: points[2], end: points[3],
                  curvature: .init(circleRadius: topRadius + depth,
                                   largeArc: halfArc > .pi / 2, right: false)),
            .init(id: "\(name)-left", start: points[3], end: points[0])
        ])
        if reverseForPanelNormal { panel.reverse() }
        return panel
    }

    private static func circleSkirtMeasurements(body: GarmentCodeBodyParameters,
                                                design: GarmentCodeDesignParameters) throws -> (waist: Double, length: Double) {
        guard let bodyWaist = body["waist"], let bodyHips = body["hips"],
              let hipsLine = body["hips_line"], let legLength = body["_leg_length"] else {
            throw GarmentCodeProgramError.missingBodyParameter
        }
        let rise = try number(design, path: ["flare-skirt", "rise"])
        let lengthRatio = try number(design, path: ["flare-skirt", "length"])
        guard rise.isFinite, (0...1).contains(rise),
              bodyWaist > 0, bodyHips > 0, hipsLine > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        // BaseBottoms.eval_rise() and SkirtCircle.__init__().
        return (interpolate(bodyHips, bodyWaist, rise), max(rise * hipsLine + lengthRatio * legLength, 5))
    }

    private static func selectedOption(_ design: GarmentCodeDesignParameters,
                                       path: [String]) -> String? {
        guard case let .string(value)? = design.value(at: path) else { return nil }
        return value
    }

    private static func number(_ design: GarmentCodeDesignParameters,
                               path: [String]) throws -> Double {
        guard let value = design.value(at: path)?.numberValue, value.isFinite else {
            throw GarmentCodeProgramError.missingDesignParameter(path.joined(separator: "."))
        }
        return value
    }

    private static func interpolate(_ lower: Double, _ upper: Double, _ fraction: Double) -> Double {
        lower + (upper - lower) * fraction
    }
}

enum GarmentCodeProgramError: LocalizedError {
    case wrongProgram(String)
    case unsupportedParameter(String)
    case missingBodyParameter
    case missingDesignParameter(String)
    case invalidMeasurements
    case curveFitDidNotConverge

    var errorDescription: String? {
        switch self {
        case let .wrongProgram(message): message
        case let .unsupportedParameter(name): "尚未移植官方参数组合：\(name)"
        case .missingBodyParameter: "缺少生成此款式所需的人体尺寸"
        case let .missingDesignParameter(name): "缺少设计参数：\(name)"
        case .invalidMeasurements: "尺寸组合超出此款式的可生成范围"
        case .curveFitDidNotConverge: "曲线求解未收敛，未生成纸样；请调整参数后重试"
        }
    }
}
