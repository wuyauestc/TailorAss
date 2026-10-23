import Foundation

private struct BodyMetaGridFixture: Decodable {
    let body: [String: Double]
    let patterns: [String: GarmentCodePatternFile]
}

/// Geometry and topology comparisons against the pinned GarmentCode patterns.
/// Passing the sampled fixtures does not certify physical fit or production use.
@main
struct NativePatternSmoke {
    static func main() throws {
        if ProcessInfo.processInfo.environment["GARMENTCODE_NATIVE_ACCEPTANCE"] == "1" {
            precondition(["GARMENTCODE_METRICS_AUDIT", "GARMENTCODE_CONTOUR_AUDIT", "GARMENTCODE_SEAM_CHECK"]
                .allSatisfy { ProcessInfo.processInfo.environment[$0] != "1" },
                "Acceptance must not be combined with diagnostic modes that skip numeric gates")
        }
        let distanceLine = GarmentCodeGeometryEdge(id: "distance-line", start: .zero, end: .init(x: 10, y: 0))
        let nearLine = GarmentCodeGeometryEdge(id: "near-line", start: .init(x: 0, y: 0.2), end: .init(x: 10, y: 0.2))
        let farLine = GarmentCodeGeometryEdge(id: "far-line", start: .init(x: 0, y: 0.4), end: .init(x: 10, y: 0.4))
        precondition(curveWithin(nearLine, of: distanceLine, limit: 0.3))
        precondition(!curveWithin(farLine, of: distanceLine, limit: 0.3))
        let inflected = GarmentCodeGeometryEdge(id: "inflected", start: .zero, end: .init(x: 10, y: 0),
            curvature: .init(type: "cubic", params: [[0.3, 0.5], [0.7, -0.5]]))
        precondition(!curveWithin(inflected, of: distanceLine, limit: 1),
                     "Continuous distance must catch off-chord lobes despite a coincident midpoint")
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Keep official upstream oracles checked in and parseable for programs
        // whose Swift ports are still in progress. They are not counted as
        // implemented until a generated-vs-golden geometry comparison exists.
        for fixture in ["pants.json", "pants-varied.json", "godet-skirt.json",
                        "godet-skirt-varied.json", "pencil-skirt.json",
                        "skirt-levels.json", "skirt-levels-varied.json",
                        "shirt.json", "shirt-varied.json", "fitted-shirt.json",
                        "pencil-skirt-SIGGRAPH_logo.json"] {
            let url = repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(fixture)")
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf: url))
            precondition(!golden.pattern.panels.isEmpty, "Official oracle \(fixture) has no pattern panels")
        }
        let catalog = try GarmentCodeParameterCatalog.load(
            from: repositoryRoot.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")
        )
        let options = catalog.garmentOptions
        precondition(options.upper == ["FittedShirt", "Shirt"])
        precondition(options.waistband == ["StraightWB", "FittedWB"])
        precondition(options.bottom == ["SkirtCircle", "AsymmSkirtCircle", "GodetSkirt", "Pants", "Skirt2", "SkirtManyPanels", "PencilSkirt", "SkirtLevels"])
        precondition(catalog.node(at: ["shirt", "width"])?.range?.compactMap(\.numberValue) == [1.0, 1.3])
        precondition(catalog.node(at: ["shirt", "length"])?.value?.numberValue == 1.2)
        var upstreamDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(upstreamDesign.validationMessages().isEmpty, "Official catalog defaults must satisfy their ranges")
        precondition(upstreamDesign.setValue(.null, at: ["pencil-skirt", "style_side_cut"]))
        precondition(upstreamDesign.validationMessages().isEmpty,
                     "select_null must accept the official empty value even when omitted from range")
        precondition(upstreamDesign.setValue(.number(1.3), at: ["shirt", "width"]))
        precondition(upstreamDesign.value(at: ["shirt", "width"])?.numberValue == 1.3)
        precondition(upstreamDesign.setValue(.number(1.31), at: ["shirt", "width"]))
        precondition(!upstreamDesign.validationMessages().isEmpty, "Official numeric parameter bounds must be enforced")
        precondition(upstreamDesign.setValue(.number(4.5), at: ["flare-skirt", "skirt-many-panels", "n_panels"]))
        precondition(upstreamDesign.validationMessages().contains { $0.contains("必须是整数") },
                     "Official int parameters must reject fractional values")
        precondition(upstreamDesign.setValue(.number(4), at: ["flare-skirt", "skirt-many-panels", "n_panels"]))
        let upstreamBody = GarmentCodeBodyParameters(values: catalog.body)
        struct BodyEditOracle: Decodable {
            let key: String
            let value: Double
            let expected: [String: Double]
        }
        let bodyEdits = try JSONDecoder().decode([BodyEditOracle].self, from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/body-dependency-edits.json")))
        var dependencyBody = upstreamBody
        for edit in bodyEdits {
            dependencyBody.set(edit.value, for: edit.key)
            for (key, expected) in edit.expected {
                guard let actual = dependencyBody[key] else {
                    preconditionFailure("Body edit \(edit.key): missing \(key)")
                }
                precondition(abs(actual - expected) < 1e-10,
                             "Body edit \(edit.key): \(key) differs from upstream")
            }
        }
        let tangentFitSource = GarmentCodeGeometryEdge(
            id: "tangent-fit-oracle", start: .zero, end: .init(x: 1, y: 0),
            curvature: .init(type: "cubic", params: [[0.3, -0.2], [0.6, 0.2]]))
        let tangentFit = try GarmentCodeGeometryEdge.cubicMatchingTangents(
            tangentFitSource, targetStartTangent: .init(x: 1, y: 0),
            targetEndTangent: .init(x: 1, y: 0), targetLength: 2)
        let tangentControls = tangentFit.curvature?.params ?? []
        precondition(tangentControls.count == 2 &&
                     abs(tangentFit.end.x - 2) < 0.01 &&
                     abs(tangentFit.length() - 2) < 0.01 &&
                     abs(tangentControls[0][1]) < 0.01 &&
                     abs(tangentControls[1][1]) < 0.01,
                     "Cubic tangent fitter must preserve target length and the pinned SciPy tangent-fit objective")
        let sleeveOpeningPair = try GarmentCodeSleeveGeometry.evenOpenings(
            front: [.init(id: "front-opening", start: .zero, end: .init(x: 10, y: 0))],
            back: [.init(id: "back-opening", start: .zero, end: .init(x: 8, y: 0))])
        precondition(sleeveOpeningPair.front.allSatisfy { $0.length() > 0 } &&
                     sleeveOpeningPair.back.allSatisfy { $0.length() > 0 } &&
                     zip(sleeveOpeningPair.front, sleeveOpeningPair.front.dropFirst())
                        .allSatisfy { $0.end.distance(to: $1.start) < 1e-6 } &&
                     zip(sleeveOpeningPair.back, sleeveOpeningPair.back.dropFirst())
                        .allSatisfy { $0.end.distance(to: $1.start) < 1e-6 },
                     "Sleeve opening redistribution must preserve connected edge sequences")
        var cornerPanel = GarmentCodePanelGeometry(id: "corner-test", edges: [
            .init(id: "corner-bottom", start: .zero, end: .init(x: 10, y: 0)),
            .init(id: "corner-right", start: .init(x: 10, y: 0), end: .init(x: 10, y: 10)),
            .init(id: "corner-top", start: .init(x: 10, y: 10), end: .init(x: 0, y: 10)),
            .init(id: "corner-left", start: .init(x: 0, y: 10), end: .zero)
        ])
        let insertedCorner = try GarmentCodeCornerProjection.cut(
            panel: &cornerPanel,
            firstEdgeID: "corner-right", secondEdgeID: "corner-top",
            targetShape: [.init(id: "corner-projection", start: .zero,
                                end: .init(x: -5, y: 5))])
        precondition(insertedCorner.count == 1 && cornerPanel.isClosed &&
                     cornerPanel.edges.count == 5 &&
                     insertedCorner[0].start.distance(to: .init(x: 10, y: 10)) > 0.1,
                     "Corner projection must split its two boundary edges and preserve a closed panel")
        var shirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(shirtDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        let shirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt.json")))
        assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: shirtDesign),
                            shirtGolden, name: "Shirt", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: shirtDesign),
                            shirtGolden, name: "Shirt dispatcher", tolerance: 0.01)
        var sleevedShirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(sleevedShirtDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        precondition(sleevedShirtDesign.setValue(.bool(false), at: ["sleeve", "sleeveless"]))
        let sleevedShirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-sleeved.json")))
        assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: sleevedShirtDesign),
                            sleevedShirtGolden, name: "Shirt sleeved", tolerance: 0.035)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: sleevedShirtDesign),
                            sleevedShirtGolden, name: "Shirt sleeved dispatcher", tolerance: 0.035)
        precondition(shirtDesign.setValue(.number(1.2), at: ["shirt", "width"]))
        precondition(shirtDesign.setValue(.number(1.5), at: ["shirt", "length"]))
        precondition(shirtDesign.setValue(.number(1.15), at: ["shirt", "flare"]))
        let variedShirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-varied.json")))
        assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: shirtDesign),
                            variedShirtGolden, name: "Shirt varied", tolerance: 0.01)
        for neckline in ["VNeckHalf", "SquareNeckHalf", "TrapezoidNeckHalf",
                         "CurvyNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"] {
            var necklineDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(necklineDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
            precondition(necklineDesign.setValue(.string(neckline), at: ["collar", "f_collar"]))
            precondition(necklineDesign.setValue(.string(neckline), at: ["collar", "b_collar"]))
            let necklineGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-neckline-\(neckline).json")))
            assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: necklineDesign),
                                necklineGolden, name: "Shirt neckline \(neckline)", tolerance: 0.01)
        }
        var fittedShirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(fittedShirtDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        let fittedShirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt.json")))
        assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: fittedShirtDesign),
                            fittedShirtGolden, name: "FittedShirt", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: fittedShirtDesign),
                            fittedShirtGolden, name: "FittedShirt dispatcher", tolerance: 0.01)
        var sleevedFittedDesign = fittedShirtDesign
        precondition(sleevedFittedDesign.setValue(.bool(false), at: ["sleeve", "sleeveless"]))
        let sleevedFittedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-sleeved.json")))
        assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: sleevedFittedDesign),
                            sleevedFittedGolden, name: "FittedShirt sleeved", tolerance: 0.08)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: sleevedFittedDesign),
                            sleevedFittedGolden, name: "FittedShirt sleeved dispatcher", tolerance: 0.08)
        for (upper, filename) in [("Shirt", "shirt-sleeved-varied"),
                                  ("FittedShirt", "fitted-shirt-sleeved-varied")] {
            var variedSleeveDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(variedSleeveDesign.setValue(.string(upper), at: ["meta", "upper"]))
            precondition(variedSleeveDesign.setValue(.bool(false), at: ["sleeve", "sleeveless"]))
            if upper == "Shirt" {
                precondition(variedSleeveDesign.setValue(.number(0.75), at: ["sleeve", "length"]))
                precondition(variedSleeveDesign.setValue(.number(1.25), at: ["sleeve", "end_width"]))
                precondition(variedSleeveDesign.setValue(.number(40), at: ["sleeve", "sleeve_angle"]))
                precondition(variedSleeveDesign.setValue(.number(0.3), at: ["sleeve", "opening_dir_mix"]))
            } else {
                precondition(variedSleeveDesign.setValue(.number(0.6), at: ["sleeve", "length"]))
                precondition(variedSleeveDesign.setValue(.number(1.3), at: ["sleeve", "end_width"]))
            }
            let variedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename).json")))
            assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: variedSleeveDesign),
                                variedGolden, name: "\(upper) sleeved varied", tolerance: 0.08)
        }
        for cuff in ["CuffBand", "CuffSkirt", "CuffBandSkirt"] {
            var cuffDesign = sleevedShirtDesign
            precondition(cuffDesign.setValue(.string(cuff), at: ["sleeve", "cuff", "type"]))
            let cuffGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-sleeved-\(cuff).json")))
            assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: cuffDesign),
                                cuffGolden, name: "Shirt sleeved \(cuff)", tolerance: 0.06)
        }
        var ruffledSleeveDesign = sleevedShirtDesign
        precondition(ruffledSleeveDesign.setValue(.number(1.4), at: ["sleeve", "connect_ruffle"]))
        let ruffledSleeveGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-sleeved-connect-ruffle.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: ruffledSleeveDesign),
                            ruffledSleeveGolden, name: "Shirt sleeved connect ruffle", tolerance: 0.08)
        var standingSleeveDesign = sleevedShirtDesign
        precondition(standingSleeveDesign.setValue(.bool(true), at: ["sleeve", "standing_shoulder"]))
        precondition(standingSleeveDesign.setValue(.number(50), at: ["sleeve", "sleeve_angle"]))
        let standingSleeveGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-sleeved-standing.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: standingSleeveDesign),
                            standingSleeveGolden, name: "Shirt sleeved standing shoulder", tolerance: 0.15)
        for neckline in ["VNeckHalf", "SquareNeckHalf", "TrapezoidNeckHalf",
                         "CurvyNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"] {
            var necklineDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(necklineDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
            precondition(necklineDesign.setValue(.string(neckline), at: ["collar", "f_collar"]))
            precondition(necklineDesign.setValue(.string(neckline), at: ["collar", "b_collar"]))
            let necklineGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-neckline-\(neckline).json")))
            assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: necklineDesign),
                                necklineGolden, name: "FittedShirt neckline \(neckline)", tolerance: 0.01)
        }
        for (upper, prefix) in [("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")] {
            for armhole in ["ArmholeSquare", "ArmholeAngle"] {
                var armholeDesign = GarmentCodeDesignParameters(catalog: catalog)
                precondition(armholeDesign.setValue(.string(upper), at: ["meta", "upper"]))
                precondition(armholeDesign.setValue(.string(armhole), at: ["sleeve", "armhole_shape"]))
                let armholeGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(prefix)-armhole-\(armhole).json")))
                let generated = upper == "Shirt"
                    ? try GarmentCodePrograms.shirt(body: upstreamBody, design: armholeDesign)
                    : try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: armholeDesign)
                assertGeometryMatch(generated, armholeGolden, name: "\(upper) \(armhole)", tolerance: 0.01)
            }
        }
        var straplessDesign = GarmentCodeDesignParameters(catalog: catalog)
        var deepNeck = GarmentCodeDesignParameters(catalog: catalog)
        _ = deepNeck.setValue(.string("FittedShirt"), at: ["meta", "upper"])
        for prefix in ["f", "b"] {
            _ = deepNeck.setValue(.string("VNeckHalf"), at: ["collar", "\(prefix)_collar"])
            _ = deepNeck.setValue(.number(2), at: ["collar", "\(prefix)c_depth"])
        }
        let deepNeckGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-deep-neck.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: deepNeck),
                            deepNeckGolden, name: "FittedShirt deep neckline", tolerance: 0.01)
        for upper in ["Shirt", "FittedShirt"] {
            for style in ["CircleNeckHalf", "CurvyNeckHalf", "VNeckHalf", "SquareNeckHalf",
                          "TrapezoidNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"] {
                var variant = GarmentCodeDesignParameters(catalog: catalog)
                _ = variant.setValue(.string(upper), at: ["meta", "upper"])
                for prefix in ["f", "b"] {
                    _ = variant.setValue(.string(style), at: ["collar", "\(prefix)_collar"])
                    _ = variant.setValue(.bool(true), at: ["collar", "\(prefix)_flip_curve"])
                }
                for (key, value) in ["width": -0.2, "fc_depth": 0.6, "bc_depth": 0.3,
                                     "fc_angle": 75, "bc_angle": 110, "f_bezier_x": 0.6,
                                     "f_bezier_y": 0.3, "b_bezier_x": 0.4, "b_bezier_y": 0.7] {
                    _ = variant.setValue(.number(value), at: ["collar", key])
                }
                let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(upper)-neck-varied-\(style).json")))
                assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: variant),
                                    golden, name: "\(upper) varied neckline \(style)", tolerance: 0.01)
            }
        }
        precondition(straplessDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(straplessDesign.setValue(.bool(true), at: ["shirt", "strapless"]))
        let straplessGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-strapless.json")))
        assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: straplessDesign),
                            straplessGolden, name: "FittedShirt strapless", tolerance: 0.01)
        var asymmetricShirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(asymmetricShirtDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        precondition(asymmetricShirtDesign.setValue(.bool(true), at: ["left", "enable_asym"]))
        let asymmetricShirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-asymmetric.json")))
        assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: asymmetricShirtDesign),
                            asymmetricShirtGolden, name: "Shirt asymmetric", tolerance: 0.01)
        var asymmetricFittedDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(asymmetricFittedDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(asymmetricFittedDesign.setValue(.bool(true), at: ["left", "enable_asym"]))
        let asymmetricFittedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-asymmetric.json")))
        assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: asymmetricFittedDesign),
                            asymmetricFittedGolden, name: "FittedShirt asymmetric", tolerance: 0.01)
        var turtleShirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        for upper in ["Shirt", "FittedShirt"] {
            for tag in ["left-sleeve", "right-sleeve", "left-band-skirt", "right-band-skirt", "left-strapless"] {
                var variant = GarmentCodeDesignParameters(catalog: catalog)
                precondition(variant.setValue(.string(upper), at: ["meta", "upper"]))
                precondition(variant.setValue(.bool(true), at: ["left", "enable_asym"]))
                if tag == "left-sleeve" {
                    precondition(variant.setValue(.bool(false), at: ["left", "sleeve", "sleeveless"]))
                    precondition(variant.setValue(.string("CuffBand"), at: ["left", "sleeve", "cuff", "type"]))
                } else if tag == "right-sleeve" {
                    precondition(variant.setValue(.bool(false), at: ["sleeve", "sleeveless"]))
                    precondition(variant.setValue(.string("CuffSkirt"), at: ["sleeve", "cuff", "type"]))
                } else if tag.hasSuffix("band-skirt") {
                    let prefix = tag.hasPrefix("left") ? ["left", "sleeve"] : ["sleeve"]
                    precondition(variant.setValue(.bool(false), at: prefix + ["sleeveless"]))
                    precondition(variant.setValue(.string("CuffBandSkirt"), at: prefix + ["cuff", "type"]))
                } else {
                    precondition(variant.setValue(.bool(true), at: ["left", "shirt", "strapless"]))
                }
                let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(upper)-asym-\(tag).json")))
                assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: variant),
                                    golden, name: "\(upper) asymmetric \(tag)",
                                    tolerance: tag == "left-strapless" ? 0.01 : 0.15)
            }
        }
        precondition(turtleShirtDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        precondition(turtleShirtDesign.setValue(.string("Turtle"), at: ["collar", "component", "style"]))
        let turtleShirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-collar-Turtle.json")))
        assertGeometryMatch(try GarmentCodePrograms.shirt(body: upstreamBody, design: turtleShirtDesign),
                            turtleShirtGolden, name: "Shirt Turtle collar", tolerance: 0.01)
        var turtleFittedDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(turtleFittedDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(turtleFittedDesign.setValue(.string("Turtle"), at: ["collar", "component", "style"]))
        let turtleFittedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/fitted-shirt-collar-Turtle.json")))
        assertGeometryMatch(try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: turtleFittedDesign),
                            turtleFittedGolden, name: "FittedShirt Turtle collar", tolerance: 0.01)
        for (upper, prefix) in [("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")] {
            for variant in ["SimpleLapel", "SimpleLapel-standing", "SimpleLapel-VNeckHalf",
                            "SimpleLapel-back-VNeckHalf"] {
                var lapelDesign = GarmentCodeDesignParameters(catalog: catalog)
                precondition(lapelDesign.setValue(.string(upper), at: ["meta", "upper"]))
                precondition(lapelDesign.setValue(.string("SimpleLapel"), at: ["collar", "component", "style"]))
                if variant.hasSuffix("standing") {
                    precondition(lapelDesign.setValue(.bool(true), at: ["collar", "component", "lapel_standing"]))
                } else if variant.hasSuffix("VNeckHalf") {
                    let neckPath = variant.contains("back") ? "b_collar" : "f_collar"
                    precondition(lapelDesign.setValue(.string("VNeckHalf"), at: ["collar", neckPath]))
                }
                let lapelGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(prefix)-collar-\(variant).json")))
                let generated = upper == "Shirt"
                    ? try GarmentCodePrograms.shirt(body: upstreamBody, design: lapelDesign)
                    : try GarmentCodePrograms.fittedShirt(body: upstreamBody, design: lapelDesign)
                assertGeometryMatch(generated, lapelGolden, name: "\(upper) \(variant)", tolerance: 0.01)
            }
            var hoodDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(hoodDesign.setValue(.string(upper), at: ["meta", "upper"]))
            precondition(hoodDesign.setValue(.string("Hood2Panels"), at: ["collar", "component", "style"]))
            let hoodGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(prefix)-collar-Hood2Panels.json")))
            assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: hoodDesign),
                                hoodGolden, name: "\(upper) Hood2Panels", tolerance: 0.04)
            if upper == "Shirt" {
                precondition(hoodDesign.setValue(.number(1.25), at: ["collar", "component", "hood_length"]))
                precondition(hoodDesign.setValue(.number(1.3), at: ["collar", "component", "hood_depth"]))
                let variedHoodGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/shirt-collar-Hood2Panels-varied.json")))
                assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: hoodDesign),
                                    variedHoodGolden, name: "Shirt Hood2Panels varied", tolerance: 0.04)
            }
        }
        var shirtSkirtDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(shirtSkirtDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        precondition(shirtSkirtDesign.setValue(.string("Skirt2"), at: ["meta", "bottom"]))
        let shirtSkirtGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/Shirt-Skirt2.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: shirtSkirtDesign),
                            shirtSkirtGolden, name: "Shirt+Skirt2", tolerance: 0.01)
        var fittedPencilDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(fittedPencilDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(fittedPencilDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
        let fittedPencilGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/FittedShirt-PencilSkirt.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: fittedPencilDesign),
                            fittedPencilGolden, name: "FittedShirt+PencilSkirt", tolerance: 0.01)
        var shirtSkirtBeltDesign = shirtSkirtDesign
        precondition(shirtSkirtBeltDesign.setValue(.string("StraightWB"), at: ["meta", "wb"]))
        let shirtSkirtBeltGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/Shirt-Skirt2-StraightWB.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: shirtSkirtBeltDesign),
                            shirtSkirtBeltGolden, name: "Shirt+Skirt2+StraightWB", tolerance: 0.01)
        var shirtSkirtFittedBeltDesign = shirtSkirtDesign
        precondition(shirtSkirtFittedBeltDesign.setValue(.string("FittedWB"), at: ["meta", "wb"]))
        let shirtSkirtFittedBeltGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/Shirt-Skirt2-FittedWB.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: shirtSkirtFittedBeltDesign),
                            shirtSkirtFittedBeltGolden, name: "Shirt+Skirt2+FittedWB", tolerance: 0.01)
        var fittedPencilBeltDesign = fittedPencilDesign
        precondition(fittedPencilBeltDesign.setValue(.string("StraightWB"), at: ["meta", "wb"]))
        let fittedPencilBeltGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/FittedShirt-PencilSkirt-StraightWB.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: fittedPencilBeltDesign),
                            fittedPencilBeltGolden, name: "FittedShirt+PencilSkirt+StraightWB", tolerance: 0.01)
        for (bottom, belt) in [("SkirtCircle", ""), ("AsymmSkirtCircle", "FittedWB"),
                               ("GodetSkirt", ""), ("SkirtLevels", ""),
                               ("SkirtManyPanels", ""), ("SkirtManyPanels", "StraightWB"),
                               ("Pants", "")] {
            var combinationDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(combinationDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
            precondition(combinationDesign.setValue(.string(bottom), at: ["meta", "bottom"]))
            if !belt.isEmpty {
                precondition(combinationDesign.setValue(.string(belt), at: ["meta", "wb"]))
            }
            let filename = "Shirt-\(bottom)\(belt.isEmpty ? "" : "-\(belt)").json"
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
            assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: combinationDesign),
                                golden, name: filename, tolerance: 0.01)
        }
        var fittedPantsBeltDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(fittedPantsBeltDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(fittedPantsBeltDesign.setValue(.string("Pants"), at: ["meta", "bottom"]))
        precondition(fittedPantsBeltDesign.setValue(.string("FittedWB"), at: ["meta", "wb"]))
        let fittedPantsBeltGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/FittedShirt-Pants-FittedWB.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: fittedPantsBeltDesign),
                            fittedPantsBeltGolden, name: "FittedShirt+Pants+FittedWB", tolerance: 0.01)
        var fittedLevelsDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(fittedLevelsDesign.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
        precondition(fittedLevelsDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
        let fittedLevelsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/FittedShirt-SkirtLevels.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: fittedLevelsDesign),
                            fittedLevelsGolden, name: "FittedShirt+SkirtLevels", tolerance: 0.01)
        var pantsDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(pantsDesign.setValue(.string("Pants"), at: ["meta", "bottom"]))
        let generatedPants = try GarmentCodePrograms.pants(body: upstreamBody, design: pantsDesign)
        let pantsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pants.json")))
        assertGeometryMatch(generatedPants, pantsGolden, name: "Pants", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: pantsDesign),
                            pantsGolden, name: "Pants dispatcher", tolerance: 0.01)
        precondition(pantsDesign.setValue(.number(0.75), at: ["pants", "rise"]))
        precondition(pantsDesign.setValue(.number(0.55), at: ["pants", "length"]))
        precondition(pantsDesign.setValue(.number(1.2), at: ["pants", "width"]))
        precondition(pantsDesign.setValue(.number(1.1), at: ["pants", "flare"]))
        let variedPants = try GarmentCodePrograms.pants(body: upstreamBody, design: pantsDesign)
        let variedPantsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pants-varied.json")))
        assertGeometryMatch(variedPants, variedPantsGolden, name: "Pants varied", tolerance: 0.01)
        for cuffType in ["CuffBand", "CuffSkirt", "CuffBandSkirt"] {
            var cuffDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(cuffDesign.setValue(.string("Pants"), at: ["meta", "bottom"]))
            precondition(cuffDesign.setValue(.string(cuffType), at: ["pants", "cuff", "type"]))
            let cuffed = try GarmentCodePrograms.pants(body: upstreamBody, design: cuffDesign)
            let cuffGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pants-\(cuffType).json")))
            assertGeometryMatch(cuffed, cuffGolden, name: "Pants \(cuffType)", tolerance: 0.01)
            assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: cuffDesign),
                                cuffGolden, name: "Pants \(cuffType) dispatcher", tolerance: 0.01)
        }
        var pencilDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(pencilDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
        let pencil = try GarmentCodePrograms.pencilSkirt(body: upstreamBody, design: pencilDesign)
        let pencilGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt.json")))
        assertGeometryMatch(pencil, pencilGolden, name: "PencilSkirt", tolerance: 0.01)
        for (tag, flare, angle, rise) in [("narrow-low", 0.8, 20.0, 0.7),
                                          ("wide-low", 1.2, -15.0, 0.8),
                                          ("wide-high", 1.4, 20.0, 1.0)] {
            var variant = pencilDesign
            _ = variant.setValue(.number(flare), at: ["pencil-skirt", "flare"])
            _ = variant.setValue(.number(angle), at: ["pencil-skirt", "low_angle"])
            _ = variant.setValue(.number(rise), at: ["pencil-skirt", "rise"])
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-\(tag).json")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: variant)
            assertGeometryMatch(generated, golden, name: "PencilSkirt \(tag)", tolerance: 0.01)
        }
        for flare in [0.8, 1.2] {
            var flaredDesign = pencilDesign
            precondition(flaredDesign.setValue(.number(flare), at: ["pencil-skirt", "flare"]))
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-flare-\(flare).json")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: flaredDesign)
            assertGeometryMatch(generated, golden, name: "PencilSkirt flare \(flare)", tolerance: 0.01)
        }
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: pencilDesign),
                            pencilGolden, name: "PencilSkirt dispatcher", tolerance: 0.01)
        for slit in ["left_slit", "right_slit", "front_slit", "back_slit"] {
            var slitDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(slitDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
            precondition(slitDesign.setValue(.number(0.25), at: ["pencil-skirt", slit]))
            let slitPattern = try GarmentCodePrograms.pencilSkirt(body: upstreamBody, design: slitDesign)
            let slitGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-\(slit).json")))
            assertGeometryMatch(slitPattern, slitGolden, name: "PencilSkirt \(slit)", tolerance: 0.01)
        }
        var allSlitsDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(allSlitsDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
        for slit in ["left_slit", "right_slit", "front_slit", "back_slit"] {
            precondition(allSlitsDesign.setValue(.number(0.2), at: ["pencil-skirt", slit]))
        }
        let allSlits = try GarmentCodePrograms.pencilSkirt(body: upstreamBody, design: allSlitsDesign)
        let allSlitsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-all-slits.json")))
        assertGeometryMatch(allSlits, allSlitsGolden, name: "PencilSkirt all slits", tolerance: 0.01)
        var sunCutDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(sunCutDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
        precondition(sunCutDesign.setValue(.string("Sun"), at: ["pencil-skirt", "style_side_cut"]))
        let sunCut = try GarmentCodePrograms.pencilSkirt(body: upstreamBody, design: sunCutDesign)
        let sunCutGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-Sun.json")))
        assertGeometryMatch(sunCut, sunCutGolden, name: "PencilSkirt Sun side cut", tolerance: 0.01)
        for (tag, ratio, all) in [("left-slit", 0.1, false),
                                  ("deep-left-slit", 0.5, false),
                                  ("boundary-left-slit", 0.6, false),
                                  ("skip-left-slit", 0.8, false),
                                  ("all-slits", 0.1, true)] {
            var slitSunDesign = sunCutDesign
            for slit in (all ? ["left_slit", "right_slit", "front_slit", "back_slit"] : ["left_slit"]) {
                precondition(slitSunDesign.setValue(.number(ratio), at: ["pencil-skirt", slit]))
            }
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent(
                    "Tests/NativePattern/Fixtures/pencil-skirt-Sun-\(tag).json")))
            let generated = try GarmentCodePrograms.pencilSkirt(body: upstreamBody,
                                                                design: slitSunDesign)
            assertGeometryMatch(generated,
                                golden, name: "PencilSkirt Sun \(tag)", tolerance: 0.01)
        }
        var logoCutDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(logoCutDesign.setValue(.string("PencilSkirt"), at: ["meta", "bottom"]))
        precondition(logoCutDesign.setValue(.string("SIGGRAPH_logo"), at: ["pencil-skirt", "style_side_cut"]))
        let logoCutGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/pencil-skirt-SIGGRAPH_logo.json")))
        let logoCut = try GarmentCodePrograms.pencilSkirt(body: upstreamBody, design: logoCutDesign)
        assertGeometryMatch(logoCut,
                            logoCutGolden, name: "PencilSkirt SIGGRAPH logo side cut", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody,
                                                                     design: logoCutDesign),
                            logoCutGolden, name: "PencilSkirt SIGGRAPH logo dispatch", tolerance: 0.01)
        for (tag, hips, bustPoints) in [("wide", 109.0, 18.0),
                                       ("narrow", 96.0, 16.0)] {
            var sizedBody = upstreamBody
            sizedBody.set(hips, for: "hips")
            sizedBody.set(bustPoints, for: "bust_points")
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent(
                    "Tests/NativePattern/Fixtures/pencil-skirt-SIGGRAPH_logo-\(tag).json")))
            assertGeometryMatch(try GarmentCodePrograms.pencilSkirt(body: sizedBody,
                                                                     design: logoCutDesign),
                                golden, name: "PencilSkirt SIGGRAPH logo \(tag)", tolerance: 0.01)
        }
        for (tag, slits) in [("left-slit", ["left_slit"]),
                             ("all-slits", ["left_slit", "right_slit", "front_slit", "back_slit"])] {
            var slitLogoDesign = logoCutDesign
            for slit in slits {
                precondition(slitLogoDesign.setValue(.number(0.1), at: ["pencil-skirt", slit]))
            }
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent(
                    "Tests/NativePattern/Fixtures/pencil-skirt-SIGGRAPH_logo-\(tag).json")))
            assertGeometryMatch(try GarmentCodePrograms.pencilSkirt(body: upstreamBody,
                                                                     design: slitLogoDesign),
                                golden, name: "PencilSkirt SIGGRAPH logo \(tag)", tolerance: 0.01)
        }
        var deepSlitLogoDesign = logoCutDesign
        precondition(deepSlitLogoDesign.setValue(.number(0.5), at: ["pencil-skirt", "left_slit"]))
        let deepSlitGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent(
                "Tests/NativePattern/Fixtures/pencil-skirt-SIGGRAPH_logo-deep-left-slit.json")))
        assertGeometryMatch(try GarmentCodePrograms.pencilSkirt(body: upstreamBody,
                                                                 design: deepSlitLogoDesign),
                            deepSlitGolden, name: "PencilSkirt SIGGRAPH logo skipped by deep slit",
                            tolerance: 0.01)
        var skipSlitLogoDesign = logoCutDesign
        precondition(skipSlitLogoDesign.setValue(.number(0.8), at: ["pencil-skirt", "left_slit"]))
        let skipSlitGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent(
                "Tests/NativePattern/Fixtures/pencil-skirt-SIGGRAPH_logo-skip-left-slit.json")))
        assertGeometryMatch(try GarmentCodePrograms.pencilSkirt(body: upstreamBody,
                                                                 design: skipSlitLogoDesign),
                            skipSlitGolden, name: "PencilSkirt SIGGRAPH logo deep slit",
                            tolerance: 0.01)
        var godetDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(godetDesign.setValue(.string("GodetSkirt"), at: ["meta", "bottom"]))
        let godet = try GarmentCodePrograms.godetSkirt(body: upstreamBody, design: godetDesign)
        let godetGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/godet-skirt.json")))
        assertGeometryMatch(godet, godetGolden, name: "GodetSkirt", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: godetDesign),
                            godetGolden, name: "GodetSkirt dispatcher", tolerance: 0.01)
        precondition(godetDesign.setValue(.number(8), at: ["godet-skirt", "num_inserts"]))
        precondition(godetDesign.setValue(.number(20), at: ["godet-skirt", "insert_w"]))
        precondition(godetDesign.setValue(.number(25), at: ["godet-skirt", "insert_depth"]))
        let variedGodet = try GarmentCodePrograms.godetSkirt(body: upstreamBody, design: godetDesign)
        let variedGodetGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/godet-skirt-varied.json")))
        assertGeometryMatch(variedGodet, variedGodetGolden, name: "GodetSkirt varied", tolerance: 0.01)
        var godetSkirt2Design = GarmentCodeDesignParameters(catalog: catalog)
        precondition(godetSkirt2Design.setValue(.string("GodetSkirt"), at: ["meta", "bottom"]))
        precondition(godetSkirt2Design.setValue(.string("Skirt2"), at: ["godet-skirt", "base"]))
        let godetSkirt2 = try GarmentCodePrograms.godetSkirt(body: upstreamBody, design: godetSkirt2Design)
        let godetSkirt2Golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/godet-skirt-Skirt2.json")))
        assertGeometryMatch(godetSkirt2, godetSkirt2Golden, name: "GodetSkirt Skirt2 base", tolerance: 0.01)
        var levelsDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(levelsDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
        let levels = try GarmentCodePrograms.skirtLevels(body: upstreamBody, design: levelsDesign)
        let levelsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-levels.json")))
        assertGeometryMatch(levels, levelsGolden, name: "SkirtLevels", tolerance: 0.01)
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: levelsDesign),
                            levelsGolden, name: "SkirtLevels dispatcher", tolerance: 0.01)
        precondition(levelsDesign.setValue(.number(3), at: ["levels-skirt", "num_levels"]))
        precondition(levelsDesign.setValue(.number(1.3), at: ["levels-skirt", "level_ruffle"]))
        let variedLevels = try GarmentCodePrograms.skirtLevels(body: upstreamBody, design: levelsDesign)
        let variedLevelsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-levels-varied.json")))
        assertGeometryMatch(variedLevels, variedLevelsGolden, name: "SkirtLevels varied", tolerance: 0.01)
        var riseLevelsDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(riseLevelsDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
        precondition(riseLevelsDesign.setValue(.number(0.75), at: ["levels-skirt", "rise"]))
        let riseLevelsGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-levels-rise.json")))
        assertGeometryMatch(try GarmentCodePrograms.skirtLevels(body: upstreamBody, design: riseLevelsDesign),
                            riseLevelsGolden, name: "SkirtLevels rise", tolerance: 0.01)
        let levelsBaseStyles = ["Skirt2", "PencilSkirt", "SkirtCircle", "AsymmSkirtCircle"]
        let levelsTierStyles = ["Skirt2", "SkirtCircle", "AsymmSkirtCircle"]
        for baseStyle in levelsBaseStyles {
            for tierStyle in levelsTierStyles where !(baseStyle == "PencilSkirt" && tierStyle == "Skirt2") {
                var comboDesign = GarmentCodeDesignParameters(catalog: catalog)
                precondition(comboDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
                precondition(comboDesign.setValue(.string(baseStyle), at: ["levels-skirt", "base"]))
                precondition(comboDesign.setValue(.string(tierStyle), at: ["levels-skirt", "level"]))
                let combo = try GarmentCodePrograms.skirtLevels(body: upstreamBody, design: comboDesign)
                let filename = "skirt-levels-\(baseStyle)-\(tierStyle).json"
                let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
                assertGeometryMatch(combo, golden, name: "SkirtLevels \(baseStyle)+\(tierStyle)", tolerance: 0.01)
            }
        }
        for waistband in ["StraightWB", "FittedWB"] {
            var comboDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(comboDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
            precondition(comboDesign.setValue(.string(waistband), at: ["meta", "wb"]))
            let combo = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: comboDesign)
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/SkirtLevels-\(waistband).json")))
            assertGeometryMatch(combo, golden, name: "SkirtLevels+\(waistband)", tolerance: 0.01)
        }
        for baseStyle in ["Skirt2", "SkirtCircle", "AsymmSkirtCircle"] {
            for waistband in ["StraightWB", "FittedWB"] {
                var comboDesign = GarmentCodeDesignParameters(catalog: catalog)
                precondition(comboDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
                precondition(comboDesign.setValue(.string(baseStyle), at: ["levels-skirt", "base"]))
                precondition(comboDesign.setValue(.string(waistband), at: ["meta", "wb"]))
                let combo = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: comboDesign)
                let filename = "SkirtLevels-\(baseStyle)-\(waistband).json"
                let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                    repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
                assertGeometryMatch(combo, golden,
                                    name: "SkirtLevels \(baseStyle)+\(waistband)", tolerance: 0.01)
            }
        }
        for cutStyle in ["Sun", "SIGGRAPH_logo"] {
            var cutLevelsDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(cutLevelsDesign.setValue(.string("SkirtLevels"), at: ["meta", "bottom"]))
            precondition(cutLevelsDesign.setValue(.string("PencilSkirt"), at: ["levels-skirt", "base"]))
            precondition(cutLevelsDesign.setValue(.string(cutStyle), at: ["pencil-skirt", "style_side_cut"]))
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent(
                    "Tests/NativePattern/Fixtures/skirt-levels-PencilSkirt-\(cutStyle).json")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: cutLevelsDesign)
            assertGeometryMatch(generated, golden,
                                name: "SkirtLevels PencilSkirt \(cutStyle)", tolerance: 0.01)
        }
        for cutStyle in ["Sun", "SIGGRAPH_logo"] {
            var cutGodetDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(cutGodetDesign.setValue(.string("GodetSkirt"), at: ["meta", "bottom"]))
            precondition(cutGodetDesign.setValue(.string("PencilSkirt"), at: ["godet-skirt", "base"]))
            precondition(cutGodetDesign.setValue(.string(cutStyle), at: ["pencil-skirt", "style_side_cut"]))
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent(
                    "Tests/NativePattern/Fixtures/godet-skirt-PencilSkirt-\(cutStyle).json")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: cutGodetDesign)
            assertGeometryMatch(generated, golden,
                                name: "GodetSkirt PencilSkirt \(cutStyle)", tolerance: 0.01)
        }
        for (upper, bottom, waistband, tag) in [
            ("Shirt", "PencilSkirt", "StraightWB", "sun"),
            ("FittedShirt", "SkirtLevels", "FittedWB", "logo"),
            ("Shirt", "Pants", "None", "asymmetric"),
            ("FittedShirt", "Skirt2", "None", "strapless")
        ] {
            var combinedDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(combinedDesign.setValue(.string(upper), at: ["meta", "upper"]))
            precondition(combinedDesign.setValue(.string(bottom), at: ["meta", "bottom"]))
            if waistband != "None" {
                precondition(combinedDesign.setValue(.string(waistband), at: ["meta", "wb"]))
            }
            switch tag {
            case "sun":
                precondition(combinedDesign.setValue(.string("Sun"), at: ["pencil-skirt", "style_side_cut"]))
            case "logo":
                precondition(combinedDesign.setValue(.string("SIGGRAPH_logo"), at: ["pencil-skirt", "style_side_cut"]))
            case "asymmetric":
                precondition(combinedDesign.setValue(.bool(true), at: ["left", "enable_asym"]))
            case "strapless":
                precondition(combinedDesign.setValue(.bool(true), at: ["shirt", "strapless"]))
            default: break
            }
            let filename = "combo-\(upper)-\(bottom)-\(waistband)-\(tag).json"
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: combinedDesign)
            assertGeometryMatch(generated, golden, name: filename, tolerance: 0.01)
        }
        for (upper, waistband, tag) in [("Shirt", "StraightWB", "default"),
                                        ("FittedShirt", "FittedWB", "default"),
                                        ("Shirt", "FittedWB", "asymmetric"),
                                        ("FittedShirt", "StraightWB", "strapless")] {
            var upperBeltDesign = GarmentCodeDesignParameters(catalog: catalog)
            precondition(upperBeltDesign.setValue(.string(upper), at: ["meta", "upper"]))
            precondition(upperBeltDesign.setValue(.string(waistband), at: ["meta", "wb"]))
            if tag == "asymmetric" {
                precondition(upperBeltDesign.setValue(.bool(true), at: ["left", "enable_asym"]))
            } else if tag == "strapless" {
                precondition(upperBeltDesign.setValue(.bool(true), at: ["shirt", "strapless"]))
            }
            let suffix = tag == "default" ? "" : "-\(tag)"
            let filename = "combo-\(upper)-None-\(waistband)\(suffix).json"
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: upperBeltDesign)
            assertGeometryMatch(generated, golden, name: filename, tolerance: 0.01)
        }
        let metaGrid = try JSONDecoder().decode([String: GarmentCodePatternFile].self,
            from: Data(contentsOf: repositoryRoot.appendingPathComponent(
                "Tests/NativePattern/Fixtures/meta-grid-defaults.json")))
        precondition(metaGrid.count == 80, "Pinned default meta-component grid must cover all 80 selections")
        for key in metaGrid.keys.sorted() {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            precondition(parts.count == 3)
            var gridDesign = GarmentCodeDesignParameters(catalog: catalog)
            for (index, parameter) in ["upper", "wb", "bottom"].enumerated() where parts[index] != "None" {
                precondition(gridDesign.setValue(.string(parts[index]), at: ["meta", parameter]))
            }
            let generated = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: gridDesign)
            assertGeometryMatch(generated, metaGrid[key]!, name: "meta grid \(key)", tolerance: 0.15)
        }
        let femaleGrid = try JSONDecoder().decode(BodyMetaGridFixture.self,
            from: Data(contentsOf: repositoryRoot.appendingPathComponent(
                "Tests/NativePattern/Fixtures/meta-grid-female.json")))
        precondition(femaleGrid.patterns.count == 80)
        let femaleBody = GarmentCodeBodyParameters(values: femaleGrid.body)
        for key in femaleGrid.patterns.keys.sorted() {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            precondition(parts.count == 3)
            var gridDesign = GarmentCodeDesignParameters(catalog: catalog)
            for (index, parameter) in ["upper", "wb", "bottom"].enumerated() where parts[index] != "None" {
                precondition(gridDesign.setValue(.string(parts[index]), at: ["meta", parameter]))
            }
            let generated = try GarmentCodeNativeGenerator.generate(body: femaleBody, design: gridDesign)
            assertGeometryMatch(generated, femaleGrid.patterns[key]!,
                                name: "female meta grid \(key)", tolerance: 0.15)
        }
        let undartedBack = try JSONDecoder().decode(BodyMetaGridFixture.self,
            from: Data(contentsOf: repositoryRoot.appendingPathComponent(
                "Tests/NativePattern/Fixtures/fitted-shirt-undarted-back.json")))
        let undartedBody = GarmentCodeBodyParameters(values: undartedBack.body)
        for tag in undartedBack.patterns.keys.sorted() {
            var variant = GarmentCodeDesignParameters(catalog: catalog)
            precondition(variant.setValue(.string("FittedShirt"), at: ["meta", "upper"]))
            switch tag {
            case "strapless": _ = variant.setValue(.bool(true), at: ["shirt", "strapless"])
            case "skirt": _ = variant.setValue(.string("Skirt2"), at: ["meta", "bottom"])
            case "belt": _ = variant.setValue(.string("StraightWB"), at: ["meta", "wb"])
            case "sleeved": _ = variant.setValue(.bool(false), at: ["sleeve", "sleeveless"])
            default: break
            }
            let generated = try GarmentCodeNativeGenerator.generate(body: undartedBody, design: variant)
            assertGeometryMatch(generated, undartedBack.patterns[tag]!,
                                name: "undarted fitted back \(tag)", tolerance: tag == "sleeved" ? 0.15 : 0.01)
        }
        for bottom in ["PencilSkirt", "GodetSkirt"] {
            let baseStyles: [String?] = bottom == "GodetSkirt" ? ["PencilSkirt", "Skirt2"] : [nil]
            for baseStyle in baseStyles {
                for waistband in ["StraightWB", "FittedWB"] {
                    var comboDesign = GarmentCodeDesignParameters(catalog: catalog)
                    precondition(comboDesign.setValue(.string(bottom), at: ["meta", "bottom"]))
                    precondition(comboDesign.setValue(.string(waistband), at: ["meta", "wb"]))
                    if let baseStyle {
                        precondition(comboDesign.setValue(.string(baseStyle), at: ["godet-skirt", "base"]))
                    }
                    let combo = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: comboDesign)
                    let suffix = baseStyle.map { "-\($0)" } ?? ""
                    let filename = "\(bottom)\(suffix)-\(waistband).json"
                    let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                        repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
                    assertGeometryMatch(combo, golden,
                                        name: "\(bottom)\(suffix)+\(waistband)", tolerance: 0.01)
                }
            }
        }
        let tangentFitted = GarmentCodeGeometryEdge.quadraticFromTangents(
            id: "tangent-fit", start: .zero, end: .init(x: 10, y: 0),
            startTangent: .init(x: 1, y: 1), endTangent: .init(x: 1, y: -1),
            initialGuess: .init(x: 0.5, y: 0)
        )
        let control = GarmentCodePoint(x: 10 * tangentFitted.curvature!.params![0][0],
                                       y: 10 * tangentFitted.curvature!.params![0][1])
        let startDirection = control.normalized
        let endDirection = (GarmentCodePoint(x: 10, y: 0) - control).normalized
        precondition(startDirection.dot(GarmentCodePoint(x: 1, y: 1).normalized) > 0.999 &&
                     endDirection.dot(GarmentCodePoint(x: 1, y: -1).normalized) > 0.999,
                     "Quadratic tangent fitting must satisfy both requested endpoint directions")
        precondition(abs(upstreamBody["_waist_level"]! - (catalog.body["height"]! - catalog.body["head_l"]! - catalog.body["waist_line"]!)) < 1e-8)
        precondition(abs(upstreamBody["_bust_line"]! - ((2.0 / 3.0) * catalog.body["vert_bust_line"]! + (1.0 / 3.0) * catalog.body["bust_line"]!)) < 1e-8)
        var editedBody = upstreamBody
        editedBody.set(20, for: "armscye_depth")
        precondition(editedBody["_armscye_depth"] == 22.5)

        var circleDesign = GarmentCodeDesignParameters(catalog: catalog)
        precondition(circleDesign.setValue(.string("SkirtCircle"), at: ["meta", "bottom"]))
        let generatedCircle = try GarmentCodePrograms.circleSkirt(body: upstreamBody, design: circleDesign)
        let circleGoldenURL = repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-circle.json")
        let circleGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf: circleGoldenURL))
        precondition(Set(generatedCircle.pattern.panels.keys) == Set(circleGolden.pattern.panels.keys))
        for (name, expectedPanel) in circleGolden.pattern.panels {
            let actualPanel = generatedCircle.pattern.panels[name]!
            precondition(actualPanel.label == expectedPanel.label &&
                         actualPanel.vertices.count == expectedPanel.vertices.count &&
                         actualPanel.edges.count == expectedPanel.edges.count,
                         "CircleSkirt panel topology and labels must match the upstream golden")
            for vertexIndex in expectedPanel.vertices.indices {
                let actual = actualPanel.vertices[vertexIndex]
                let expected = expectedPanel.vertices[vertexIndex]
                precondition(abs(actual[0] - expected[0]) < 1e-8 &&
                             abs(actual[1] - expected[1]) < 1e-8,
                             "CircleSkirt \(name) vertex \(vertexIndex) differs from upstream")
            }
            for edgeIndex in expectedPanel.edges.indices {
                let actual = actualPanel.edges[edgeIndex]
                let expected = expectedPanel.edges[edgeIndex]
                precondition(actual.endpoints == expected.endpoints && actual.label == expected.label &&
                             actual.curvature?.type == expected.curvature?.type,
                             "CircleSkirt \(name) edge \(edgeIndex) topology/semantics differ")
                let actualParams = actual.curvature?.circle.map { [$0.radius, $0.largeArc ? 1.0 : 0.0, $0.right ? 1.0 : 0.0] }
                    ?? actual.curvature?.params?.flatMap { $0 }
                    ?? []
                let expectedParams = expected.curvature?.circle.map { [$0.radius, $0.largeArc ? 1.0 : 0.0, $0.right ? 1.0 : 0.0] }
                    ?? expected.curvature?.params?.flatMap { $0 }
                    ?? []
                precondition(actualParams.count == expectedParams.count &&
                             zip(actualParams, expectedParams).allSatisfy { abs($0 - $1) < 1e-8 },
                             "CircleSkirt \(name) edge \(edgeIndex) curvature differs")
            }
        }
        precondition(generatedCircle.pattern.stitches == circleGolden.pattern.stitches,
                     "CircleSkirt side stitches must match upstream panel-edge references")
        precondition(circleDesign.setValue(.bool(true), at: ["flare-skirt", "cut", "add"]))
        let cutCircle = try GarmentCodePrograms.circleSkirt(body: upstreamBody, design: circleDesign)
        let cutCircleGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-circle-cut.json")))
        assertGeometryMatch(cutCircle, cutCircleGolden, name: "SkirtCircle cut", tolerance: 2e-6)
        precondition(circleDesign.setValue(.bool(false), at: ["flare-skirt", "cut", "add"]))
        precondition(circleDesign.setValue(.string("AsymmSkirtCircle"), at: ["meta", "bottom"]))
        let generatedAsymmetricCircle = try GarmentCodePrograms.asymmetricCircleSkirt(body: upstreamBody,
                                                                                     design: circleDesign)
        let asymmetricGoldenURL = repositoryRoot.appendingPathComponent(
            "Tests/NativePattern/Fixtures/skirt-asymmetric-circle.json"
        )
        let asymmetricGolden = try GarmentCodePatternFile.validatedImport(
            from: Data(contentsOf: asymmetricGoldenURL)
        )
        precondition(generatedAsymmetricCircle.pattern.stitches == asymmetricGolden.pattern.stitches)
        for (name, expectedPanel) in asymmetricGolden.pattern.panels {
            let actualPanel = generatedAsymmetricCircle.pattern.panels[name]!
            precondition(actualPanel.label == expectedPanel.label && actualPanel.vertices.count == expectedPanel.vertices.count &&
                         actualPanel.edges.count == expectedPanel.edges.count)
            for vertexIndex in expectedPanel.vertices.indices {
                precondition(zip(actualPanel.vertices[vertexIndex], expectedPanel.vertices[vertexIndex])
                    .allSatisfy { abs($0 - $1) < 1e-8 },
                    "AsymmSkirtCircle \(name) vertex \(vertexIndex) differs from upstream")
            }
            for edgeIndex in expectedPanel.edges.indices {
                let actual = actualPanel.edges[edgeIndex], expected = expectedPanel.edges[edgeIndex]
                precondition(actual.endpoints == expected.endpoints && actual.label == expected.label &&
                             actual.curvature?.type == expected.curvature?.type)
                let actualParameters = actual.curvature?.circle.map {
                    [$0.radius, $0.largeArc ? 1.0 : 0.0, $0.right ? 1.0 : 0.0]
                } ?? []
                let expectedParameters = expected.curvature?.circle.map {
                    [$0.radius, $0.largeArc ? 1.0 : 0.0, $0.right ? 1.0 : 0.0]
                } ?? []
                precondition(actualParameters.count == expectedParameters.count &&
                             zip(actualParameters, expectedParameters).allSatisfy { abs($0 - $1) < 1e-8 },
                             "AsymmSkirtCircle \(name) edge \(edgeIndex) curvature differs")
            }
        }
        precondition(circleDesign.setValue(.bool(true), at: ["flare-skirt", "cut", "add"]))
        let cutAsymmetricCircle = try GarmentCodePrograms.asymmetricCircleSkirt(body: upstreamBody, design: circleDesign)
        let cutAsymmetricGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-asymmetric-circle-cut.json")))
        assertGeometryMatch(cutAsymmetricCircle, cutAsymmetricGolden, name: "AsymmSkirtCircle cut", tolerance: 2e-6)
        precondition(circleDesign.setValue(.bool(false), at: ["flare-skirt", "cut", "add"]))

        precondition(circleDesign.setValue(.string("Skirt2"), at: ["meta", "bottom"]))
        let generatedTwoPanel = try GarmentCodePrograms.twoPanelSkirt(body: upstreamBody,
                                                                      design: circleDesign)
        let twoPanelGoldenURL = repositoryRoot.appendingPathComponent(
            "Tests/NativePattern/Fixtures/skirt-two-panel.json"
        )
        let twoPanelGolden = try GarmentCodePatternFile.validatedImport(
            from: Data(contentsOf: twoPanelGoldenURL)
        )
        assertGeometryMatch(generatedTwoPanel, twoPanelGolden, name: "Skirt2")
        precondition(circleDesign.setValue(.number(0.5), at: ["skirt", "bottom_cut"]))
        let cutTwoPanel = try GarmentCodePrograms.twoPanelSkirt(body: upstreamBody, design: circleDesign)
        let cutTwoPanelGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-two-panel-cut.json")))
        assertGeometryMatch(cutTwoPanel, cutTwoPanelGolden, name: "Skirt2 bottom cut")
        precondition(circleDesign.setValue(.number(0), at: ["skirt", "bottom_cut"]))

        precondition(circleDesign.setValue(.string("SkirtManyPanels"), at: ["meta", "bottom"]))
        let generatedManyPanel = try GarmentCodePrograms.manyPanelSkirt(body: upstreamBody,
                                                                         design: circleDesign)
        let manyPanelGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-many-panels.json")))
        assertGeometryMatch(generatedManyPanel, manyPanelGolden, name: "SkirtManyPanels")
        precondition(circleDesign.setValue(.number(0.25), at: ["flare-skirt", "skirt-many-panels", "panel_curve"]))
        let curvedManyPanel = try GarmentCodePrograms.manyPanelSkirt(body: upstreamBody, design: circleDesign)
        let curvedManyPanelGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-many-panels-curved.json")))
        assertGeometryMatch(curvedManyPanel, curvedManyPanelGolden, name: "SkirtManyPanels curved")
        precondition(circleDesign.setValue(.number(0), at: ["flare-skirt", "skirt-many-panels", "panel_curve"]))

        precondition(circleDesign.setValue(.string("SkirtCircle"), at: ["meta", "bottom"]))
        let dispatchedCircle = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
        assertGeometryMatch(dispatchedCircle, circleGolden, name: "native generator dispatch")
        let exportedCircleData = try JSONEncoder().encode(dispatchedCircle)
        let restoredCircle = try GarmentCodePatternFile.validatedImport(from: exportedCircleData)
        precondition(restoredCircle.parameters?["design"]?.objectValue != nil &&
                     restoredCircle.parameters?["body"]?.objectValue != nil,
                     "Exported pattern JSON must include the exact edited design and body inputs")
        precondition(restoredCircle.properties?["units_in_meter"]?.numberValue == 100)
        let generatorMetadata = restoredCircle.properties?["tailorass_generator"]?.objectValue
        precondition(generatorMetadata?["upstream_commit"] ==
                     .string("d449629979028123a5c4dc9e732a2ec19b7fce31"))
        precondition(generatorMetadata?["port_version"] == .string("swift-pattern-only-2"))
        precondition(generatorMetadata?["tangent_solver"] == .string("native-simplex-v1"))
        precondition(generatorMetadata?["includes_3d_placement"] == .bool(false))
        precondition(circleDesign.setValue(.string("Shirt"), at: ["meta", "upper"]))
        let circleCombinationGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/Shirt-SkirtCircle.json")))
        assertGeometryMatch(try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign),
                            circleCombinationGolden, name: "Shirt+SkirtCircle dispatch", tolerance: 0.01)
        precondition(circleDesign.setValue(.null, at: ["meta", "upper"]))

        for (bottom, waistband, filename) in [
            ("SkirtCircle", "StraightWB", "SkirtCircle-StraightWB.json"),
            ("SkirtCircle", "FittedWB", "SkirtCircle-FittedWB.json"),
            ("AsymmSkirtCircle", "StraightWB", "AsymmSkirtCircle-StraightWB.json"),
            ("AsymmSkirtCircle", "FittedWB", "AsymmSkirtCircle-FittedWB.json"),
            ("Skirt2", "StraightWB", "Skirt2-StraightWB.json"),
            ("Skirt2", "FittedWB", "Skirt2-FittedWB.json"),
            ("SkirtManyPanels", "StraightWB", "SkirtManyPanels-StraightWB.json"),
            ("SkirtManyPanels", "FittedWB", "SkirtManyPanels-FittedWB.json")
        ] {
            precondition(circleDesign.setValue(.string(bottom), at: ["meta", "bottom"]))
            precondition(circleDesign.setValue(.string(waistband), at: ["meta", "wb"]))
            let combined = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
            let combinedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
            assertGeometryMatch(combined, combinedGolden, name: "\(bottom)+\(waistband)")
        }
        for (bottom, waistband, filename) in [
            ("SkirtCircle", "StraightWB", "SkirtCircle-StraightWB-cut.json"),
            ("AsymmSkirtCircle", "FittedWB", "AsymmSkirtCircle-FittedWB-cut.json")
        ] {
            precondition(circleDesign.setValue(.string(bottom), at: ["meta", "bottom"]))
            precondition(circleDesign.setValue(.string(waistband), at: ["meta", "wb"]))
            precondition(circleDesign.setValue(.bool(true), at: ["flare-skirt", "cut", "add"]))
            let combinedCut = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
            let combinedCutGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")))
            assertGeometryMatch(combinedCut, combinedCutGolden, name: "\(bottom)+\(waistband)+cut", tolerance: 2e-6)
            precondition(circleDesign.setValue(.bool(false), at: ["flare-skirt", "cut", "add"]))
        }
        precondition(circleDesign.setValue(.string("SkirtCircle"), at: ["meta", "bottom"]))
        precondition(circleDesign.setValue(.string("FittedWB"), at: ["meta", "wb"]))
        precondition(circleDesign.setValue(.bool(true), at: ["flare-skirt", "cut", "add"]))
        precondition(circleDesign.setValue(.number(0.5), at: ["flare-skirt", "cut", "place"]))
        let frontCutCombined = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
        let frontCutCombinedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/SkirtCircle-FittedWB-front-cut.json")))
        assertGeometryMatch(frontCutCombined, frontCutCombinedGolden,
                            name: "front-cut SkirtCircle+FittedWB", tolerance: 2e-6)
        precondition(circleDesign.setValue(.bool(false), at: ["flare-skirt", "cut", "add"]))
        precondition(circleDesign.setValue(.number(-0.5), at: ["flare-skirt", "cut", "place"]))
        precondition(circleDesign.setValue(.string("SkirtManyPanels"), at: ["meta", "bottom"]))
        precondition(circleDesign.setValue(.string("FittedWB"), at: ["meta", "wb"]))
        precondition(circleDesign.setValue(.number(0.25), at: ["flare-skirt", "skirt-many-panels", "panel_curve"]))
        let curvedCombined = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
        let curvedCombinedGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/SkirtManyPanels-FittedWB-curved.json")))
        assertGeometryMatch(curvedCombined, curvedCombinedGolden, name: "curved SkirtManyPanels+FittedWB")
        precondition(circleDesign.setValue(.number(0), at: ["flare-skirt", "skirt-many-panels", "panel_curve"]))
        precondition(circleDesign.setValue(.string("StraightWB"), at: ["meta", "wb"]))
        precondition(circleDesign.setValue(.number(6), at: ["flare-skirt", "skirt-many-panels", "n_panels"]))
        let sixPanelCombined = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
        let sixPanelGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/SkirtManyPanels-6-StraightWB.json")))
        assertGeometryMatch(sixPanelCombined, sixPanelGolden, name: "six-panel SkirtManyPanels+StraightWB")
        precondition(circleDesign.setValue(.number(4), at: ["flare-skirt", "skirt-many-panels", "n_panels"]))
        precondition(circleDesign.setValue(.string("Skirt2"), at: ["meta", "bottom"]))
        precondition(circleDesign.setValue(.string("StraightWB"), at: ["meta", "wb"]))
        precondition(circleDesign.setValue(.number(0.5), at: ["skirt", "bottom_cut"]))
        let combinedCutSkirt = try GarmentCodeNativeGenerator.generate(body: upstreamBody, design: circleDesign)
        let combinedCutGolden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/Skirt2-StraightWB-cut.json")))
        assertGeometryMatch(combinedCutSkirt, combinedCutGolden, name: "Skirt2 cut + StraightWB")
        precondition(circleDesign.setValue(.number(0), at: ["skirt", "bottom_cut"]))

        for (style, filename) in [("StraightWB", "waistband-straight.json"),
                                  ("FittedWB", "waistband-fitted.json")] {
            precondition(circleDesign.setValue(.null, at: ["meta", "bottom"]))
            precondition(circleDesign.setValue(.string(style), at: ["meta", "wb"]))
            let generatedWaistband = try GarmentCodePrograms.waistband(body: upstreamBody,
                                                                        design: circleDesign)
            let goldenURL = repositoryRoot.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename)")
            let golden = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf: goldenURL))
            assertGeometryMatch(generatedWaistband, golden, name: style)
        }

        let sampleURL = repositoryRoot.appendingPathComponent("TrailorAss/Resources/GarmentCodeTShirtSample.json")
        let official = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf: sampleURL))
        let normalizedPanels = try official.geometryPanels()
        var officialPanels: [GarmentCodePanelGeometry] = []
        for (name, geometry) in normalizedPanels.sorted(by: { $0.key < $1.key }) {
            precondition(geometry.isClosed, "\(name): edge loop must stay closed")
            precondition(abs(geometry.signedArea) > 1, "\(name): official outline must have measurable area")
            officialPanels.append(geometry)
        }
        let absoluteCurvePanel = GarmentCodePanel(
            vertices: [[0, 0], [10, 0], [10, 10], [0, 10]],
            edges: [
                .init(endpoints: [0, 1], label: nil, curvature: .init(type: "quadratic", params: [[5, 5]])),
                .init(endpoints: [1, 2], label: nil, curvature: nil),
                .init(endpoints: [2, 3], label: nil, curvature: nil),
                .init(endpoints: [3, 0], label: nil, curvature: nil)
            ], label: "absolute-curve"
        )
        let normalizedAbsolutePanel = try GarmentCodePanelGeometry(id: "absolute", panel: absoluteCurvePanel,
                                                                   curvatureCoordinates: "absolute", unitScale: 0.1)
        precondition(normalizedAbsolutePanel.edges[0].start == .zero &&
                     normalizedAbsolutePanel.edges[0].end == .init(x: 1, y: 0))
        precondition(normalizedAbsolutePanel.edges[0].curvature?.params?.first == [0.5, 0.5],
                     "Absolute Bezier controls must normalize to edge-relative coordinates after unit scaling")
        let absoluteDocument = GarmentCodePatternFile(
            pattern: GarmentCodePattern(panels: ["absolute": absoluteCurvePanel], stitches: []),
            properties: ["curvature_coords": .string("absolute"), "units_in_meter": .number(1000)]
        )
        let normalizedDocumentGeometry = try absoluteDocument.geometryPanels()["absolute"]!
        precondition(normalizedDocumentGeometry.edges[0].end == .init(x: 1, y: 0) &&
                     normalizedDocumentGeometry.edges[0].curvature?.params?.first == [0.5, 0.5],
                     "Pattern properties must control import normalization end to end")
        var exportParameters = GarmentCodeDesignParameters(catalog: catalog)
        precondition(exportParameters.setValue(.number(1.1), at: ["shirt", "width"]))
        let designParameterData = try JSONEncoder().encode(exportParameters.jsonValue)
        let designParameterObject = try JSONDecoder().decode(JSONValue.self, from: designParameterData)
        let encodedDesign = designParameterObject.objectValue!
        precondition(encodedDesign["shirt"] != nil)
        precondition(encodedDesign["meta"]?.objectValue?["upper"]?.objectValue?["v"] == .null,
                     "Explicit null selections in upstream parameters must remain explicit nulls")
        precondition(encodedDesign["shirt"]?.objectValue?["width"]?.objectValue?["v"] == .number(1.1))
        let exported = try GarmentCodePatternFile(
            geometry: Dictionary(uniqueKeysWithValues: officialPanels.map { ($0.id, $0) }),
            stitches: official.pattern.stitches
        )
        let exportedData = try JSONEncoder().encode(exported)
        let exportedRoundTrip = try GarmentCodePatternFile.validatedImport(from: exportedData)
        precondition(exportedRoundTrip.pattern.panels.count == official.pattern.panels.count)
        for (name, originalPanel) in official.pattern.panels {
            guard let rebuiltPanel = exportedRoundTrip.pattern.panels[name] else {
                preconditionFailure("Export lost upstream panel \(name)")
            }
            precondition(rebuiltPanel.vertices == originalPanel.vertices,
                         "Export must preserve every panel vertex coordinate")
            precondition(rebuiltPanel.edges == originalPanel.edges,
                         "Export must preserve every edge index, label and curvature")
        }
        precondition(exportedRoundTrip.pattern.stitches == official.pattern.stitches,
                     "Export must preserve official stitch pairing and right/wrong-side markers")
        let rightWrongData = Data("[[{\"panel\":\"a\",\"edge\":0},{\"panel\":\"b\",\"edge\":1},\"right_wrong\"]]".utf8)
        let rightWrongStitches = try JSONDecoder().decode([GarmentCodeStitch].self, from: rightWrongData)
        precondition(rightWrongStitches.first?.rightWrong == true)
        let encodedRightWrong = try JSONEncoder().encode(rightWrongStitches)
        precondition(String(decoding: encodedRightWrong, as: UTF8.self).contains("right_wrong"))
        let curvedEdge = officialPanels.flatMap(\.edges).first { $0.curvature?.type == "cubic" }!
        let splitBezier = curvedEdge.split(at: 0.37)
        precondition(abs(splitBezier.0.length() + splitBezier.1.length() - curvedEdge.length()) < 1e-3,
                     "Bezier split must preserve curve length")
        let oracleBezier = officialPanels.first { $0.id == "left_ftorso" }!.edges[2]
        let bezierMidpoint = oracleBezier.point(at: 0.5)
        precondition(abs(oracleBezier.length() - 22.963967911176596) < 1e-6 &&
                     abs(bezierMidpoint.x - 19.716169604223055) < 1e-6 &&
                     abs(bezierMidpoint.y - 33.85821746436201) < 1e-6,
                     "Bezier evaluation and length must match upstream svgpathtools")
        let reversedBezier = oracleBezier.reversed()
        for sample in 0...20 {
            let t = Double(sample) / 20
            precondition(reversedBezier.point(at: t).distance(to: oracleBezier.point(at: 1 - t)) < 1e-7,
                         "Reversing a Bezier edge must preserve its path in the opposite direction")
        }
        let reflectedBezier = oracleBezier.reflected(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
        for sample in 0...20 {
            let t = Double(sample) / 20
            let expected = oracleBezier.point(at: t).reflected(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
            precondition(reflectedBezier.point(at: t).distance(to: expected) < 1e-7,
                         "Reflecting an edge must reflect its curve features as well as endpoints")
        }
        var transformedPanel = normalizedPanels["left_ftorso"]!
        let sourcePanelVertices = transformedPanel.serializedVertices()
        transformedPanel.rotate(by: .pi / 2)
        transformedPanel.rotate(by: -.pi / 2)
        precondition(zip(transformedPanel.serializedVertices(), sourcePanelVertices).allSatisfy {
            hypot($0[0] - $1[0], $0[1] - $1[1]) < 1e-7
        }, "Panel rotation must preserve local curve geometry and be reversible")
        transformedPanel.reflect(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
        transformedPanel.reflect(acrossLineFrom: .zero, to: .init(x: 0, y: 1))
        precondition(zip(transformedPanel.serializedVertices(), sourcePanelVertices).allSatisfy {
            hypot($0[0] - $1[0], $0[1] - $1[1]) < 1e-7
        }, "Panel reflection must preserve loop geometry and be reversible")
        let circleEdge = officialPanels.flatMap(\.edges).first { $0.curvature?.type == "circle" }!
        let splitCircle = circleEdge.split(at: 0.37)
        precondition(abs(splitCircle.0.length() + splitCircle.1.length() - circleEdge.length()) < 1e-3,
                     "Circle-arc split must preserve curve length")
        let oracleCircle = officialPanels.first { $0.id == "left_ftorso" }!.edges[5]
        let oracleMidpoint = oracleCircle.point(at: 0.5)
        precondition(abs(oracleCircle.length() - 22.339396908026607) < 1e-6,
                     "Circle arc length must match upstream svgpathtools")
        precondition(abs(oracleMidpoint.x - 9.51214826089711) < 1e-6 &&
                     abs(oracleMidpoint.y - 39.30230350494968) < 1e-6,
                     "Circle arc parametrization must match upstream SVG arc semantics")
        let circleFlagOracles: [(Bool, Bool, Double, Double, Double)] = [
            (false, false, 4, 2, 9.272952180016125),
            (false, true, 4, -2, 9.272952180016125),
            (true, false, 4, 8, 22.142974355881808),
            (true, true, 4, -8, 22.142974355881808)
        ]
        for (largeArc, right, expectedX, expectedY, expectedLength) in circleFlagOracles {
            let edge = GarmentCodeGeometryEdge(id: "arc", start: .zero,
                                               end: .init(x: 8, y: 0),
                                               curvature: .init(circleRadius: 5,
                                                                largeArc: largeArc, right: right))
            let midpoint = edge.point(at: 0.5)
            precondition(abs(midpoint.x - expectedX) < 1e-6 &&
                         abs(midpoint.y - expectedY) < 1e-6 &&
                         abs(edge.length() - expectedLength) < 1e-6,
                         "Circle flags must match svgpathtools for all sweep/large-arc combinations")
            let (first, second) = edge.split(at: 0.37)
            let reversed = edge.reversed()
            for sample in 0...20 {
                let globalT = Double(sample) / 20
                let splitPoint = globalT <= 0.37
                    ? first.point(at: globalT / 0.37)
                    : second.point(at: (globalT - 0.37) / (1 - 0.37))
                precondition(splitPoint.distance(to: edge.point(at: globalT)) < 1e-6,
                             "Subdivided circular arcs must preserve the original path")
                precondition(reversed.point(at: globalT).distance(to: edge.point(at: 1 - globalT)) < 1e-6,
                             "Reversing a circular arc must preserve its path in the opposite direction")
            }
        }
        let undersizedArc = GarmentCodeGeometryEdge(
            id: "undersized-arc", start: .zero, end: .init(x: 8, y: 0),
            curvature: .init(circleRadius: 3, largeArc: false, right: false)
        )
        precondition(abs(undersizedArc.length() - 4 * .pi) < 1e-6 &&
                     abs(undersizedArc.point(at: 0.5).y - 4) < 1e-6,
                     "SVG arc semantics must scale radii up when endpoints cannot fit")

        var assemblyPanels = [
            "wide": GarmentCodePanelGeometry(id: "wide", edges: [
                .init(id: "wide-bottom", start: .init(x: 0, y: 0), end: .init(x: 10, y: 0)),
                .init(id: "wide-right", start: .init(x: 10, y: 0), end: .init(x: 10, y: 5)),
                .init(id: "wide-top", start: .init(x: 10, y: 5), end: .init(x: 0, y: 5)),
                .init(id: "wide-left", start: .init(x: 0, y: 5), end: .init(x: 0, y: 0))
            ]),
            "split": GarmentCodePanelGeometry(id: "split", edges: [
                .init(id: "split-bottom-left", start: .init(x: 0, y: 0), end: .init(x: 5, y: 0)),
                .init(id: "split-bottom-right", start: .init(x: 5, y: 0), end: .init(x: 10, y: 0)),
                .init(id: "split-right", start: .init(x: 10, y: 0), end: .init(x: 10, y: 5)),
                .init(id: "split-top", start: .init(x: 10, y: 5), end: .init(x: 0, y: 5)),
                .init(id: "split-left", start: .init(x: 0, y: 5), end: .init(x: 0, y: 0))
            ])
        ]
        var wideInterface = GarmentCodeInterface(edges: [
            .init(panel: "wide", edge: "wide-bottom")
        ])
        var splitInterface = GarmentCodeInterface(edges: [
            .init(panel: "split", edge: "split-bottom-left"),
            .init(panel: "split", edge: "split-bottom-right")
        ])
        let officialStitches = try GarmentCodeStitchingRule.assemble(
            &wideInterface, &splitInterface, panels: &assemblyPanels
        )
        precondition(officialStitches.count == 2 && wideInterface.edges.count == 2 && splitInterface.edges.count == 2,
                     "StitchingRule must subdivide a one-edge interface to match two segments")
        precondition(assemblyPanels["wide"]!.isClosed, "Stitch subdivision must preserve panel closure")
        var extendPanel = GarmentCodePanelGeometry(id: "extend", edges: [
            .init(id: "bottom", start: .zero, end: .init(x: 10, y: 0)),
            .init(id: "right", start: .init(x: 10, y: 0), end: .init(x: 10, y: 5)),
            .init(id: "top", start: .init(x: 10, y: 5), end: .init(x: 0, y: 5)),
            .init(id: "left", start: .init(x: 0, y: 5), end: .zero)
        ])
        precondition(extendPanel.extend(edgeIDs: ["bottom"], by: 2))
        precondition(extendPanel.isClosed && extendPanel.edges[0].end == .init(x: 20, y: 0) &&
                     extendPanel.edges[1].start == .init(x: 20, y: 0) &&
                     extendPanel.edges[1].end == .init(x: 10, y: 5),
                     "Edge extension must move shared vertices while keeping adjacent panel edges chained")

        if let filter = ProcessInfo.processInfo.environment["GARMENTCODE_CASE_FILTER"] {
            print("FILTERED RUN ONLY: compared matching cases: \(filter); not full acceptance")
        } else if ProcessInfo.processInfo.environment["GARMENTCODE_NATIVE_ACCEPTANCE"] == "1" {
            print("PASS: native geometry acceptance, exact topology/stitches, bounded fitted-curve shape and seam drift")
        } else if ProcessInfo.processInfo.environment["GARMENTCODE_SEAM_CHECK"] == "1" {
            print("PASS: topology and signed seam-residual change <0.05 cm; NOT full contour/garment acceptance")
        } else if ProcessInfo.processInfo.environment["GARMENTCODE_METRICS_AUDIT"] == "1" {
            print("AUDIT ONLY: numeric shape and seam metrics reported; topology checked; NOT garment acceptance")
        } else if ProcessInfo.processInfo.environment["GARMENTCODE_CONTOUR_AUDIT"] == "1" {
            print("AUDIT ONLY: contour failures were reported, not accepted as passing tests")
        } else {
            print("PASS: 80 default meta-component selections on each of two official body profiles (160 patterns), plus named non-default variants, match pinned GarmentCode panel topology, geometry and stitch references")
        }
        print("COVERAGE: pinned representative parameter combinations; arbitrary continuous combinations and physical fit are not certified")
    }

    private static func assertGeometryMatch(_ actual: GarmentCodePatternFile,
                                           _ expected: GarmentCodePatternFile,
                                           name: String,
                                           tolerance: Double = 1e-8,
                                           checkStitches: Bool = true) {
        if let filter = ProcessInfo.processInfo.environment["GARMENTCODE_CASE_FILTER"],
           !name.contains(filter) { return }
        let seamCheck = ProcessInfo.processInfo.environment["GARMENTCODE_SEAM_CHECK"] == "1"
        let metricsAudit = seamCheck || ProcessInfo.processInfo.environment["GARMENTCODE_METRICS_AUDIT"] == "1"
        let nativeAcceptance = ProcessInfo.processInfo.environment["GARMENTCODE_NATIVE_ACCEPTANCE"] == "1"
        // Arc conversion/inversion has sub-micrometer rounding noise even for
        // unchanged formulas. Keep historical strict diagnostics untouched.
        let tolerance = nativeAcceptance ? max(tolerance, 1e-6) : tolerance
        let hasFittedCurves = actual.pattern.panels.keys.contains { $0.contains("_sleeve_") || $0.contains("_hood") }
        var maximumContourError = 0.0
        var maximumEdgeLengthError = 0.0
        var maximumContourEdge = ""
        var maximumLengthEdge = ""
        precondition(Set(actual.pattern.panels.keys) == Set(expected.pattern.panels.keys),
                     "\(name): panel names differ from upstream")
        guard let actualGeometry = try? actual.geometryPanels(),
              let expectedGeometry = try? expected.geometryPanels() else {
            preconditionFailure("\(name): cannot restore centimeter geometry")
        }
        if let exportCase = ProcessInfo.processInfo.environment["GARMENTCODE_EXPORT_CASE"],
           (name.contains(exportCase) || (exportCase == "@fitted-curves" && actualGeometry.keys.contains {
               $0.contains("_sleeve_") || $0.contains("_hood")
           })),
           let exportDirectory = ProcessInfo.processInfo.environment["GARMENTCODE_EXPORT_DIR"] {
            // Sample in model coordinates, before any canvas layout or scaling.
            // This also avoids a second independent arc interpretation in plots.
            func contours(_ geometry: [String: GarmentCodePanelGeometry]) -> [String: [[[Double]]]] {
                geometry.mapValues { panel in panel.edges.map { edge in
                    (0...256).map { index in
                        let p = edge.point(at: Double(index) / 256)
                        return [p.x, p.y]
                    }
                } }
            }
            let record: [String: Any] = ["case": name, "units": "cm",
                "actual": contours(actualGeometry), "official": contours(expectedGeometry)]
            let directory = URL(fileURLWithPath: exportDirectory, isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = name.map { $0.isLetter || $0.isNumber ? $0 : "_" }
            try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(
                to: directory.appendingPathComponent(String(filename) + ".json"), options: .atomic)
        }
        func normalizedStitches(_ stitches: [GarmentCodeStitch]) -> [[String]] {
            stitches.map { stitch in
                stitch.sides.map { "\($0.panel)#\($0.edge)" }.sorted() +
                    (stitch.rightWrong ? ["right_wrong"] : [])
            }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        if checkStitches {
            let actualStitches = normalizedStitches(actual.pattern.stitches)
            let expectedStitches = normalizedStitches(expected.pattern.stitches)
            precondition(actualStitches == expectedStitches,
                         "\(name): stitch references differ from upstream; actualCount=\(actualStitches.count), expectedCount=\(expectedStitches.count), actualOnly=\(actualStitches.filter { !expectedStitches.contains($0) }), expectedOnly=\(expectedStitches.filter { !actualStitches.contains($0) })")
        }
        for panelName in expected.pattern.panels.keys.sorted() {
            let fittedPanel = nativeAcceptance && hasFittedCurves &&
                (panelName.contains("_sleeve_") || panelName.contains("_hood") || panelName.contains("_cuff_"))
            let shapeLimit = panelName.contains("_hood") ? 0.6 : 0.3
            guard let expectedPanel = expected.pattern.panels[panelName] else {
                preconditionFailure("\(name): missing expected panel \(panelName)")
            }
            guard let actualPanel = actual.pattern.panels[panelName] else {
                preconditionFailure("\(name): missing panel \(panelName)")
            }
            precondition(actualPanel.label == expectedPanel.label &&
                         actualPanel.vertices.count == expectedPanel.vertices.count &&
                         actualPanel.edges.count == expectedPanel.edges.count,
                         "\(name).\(panelName): panel metadata/topology differs actual vertices/edges=\(actualPanel.vertices.count)/\(actualPanel.edges.count) vertices=\(actualPanel.vertices), expected=\(expectedPanel.vertices.count)/\(expectedPanel.edges.count) vertices=\(expectedPanel.vertices)")
            for index in expectedPanel.vertices.indices {
                if !metricsAudit && !fittedPanel {
                precondition(zip(actualPanel.vertices[index], expectedPanel.vertices[index])
                    .allSatisfy { abs($0 - $1) < tolerance },
                    "\(name).\(panelName): vertex \(index) differs; actual=\(actualPanel.vertices[index]), expected=\(expectedPanel.vertices[index])")
                }
            }
            for index in expectedPanel.edges.indices {
                let actualEdge = actualPanel.edges[index]
                let expectedEdge = expectedPanel.edges[index]
                precondition(actualEdge.endpoints == expectedEdge.endpoints &&
                             actualEdge.label == expectedEdge.label &&
                             actualEdge.curvature?.type == expectedEdge.curvature?.type,
                             "\(name).\(panelName): edge \(index) semantics differ; actual=\(actualEdge), expected=\(expectedEdge)")
                func parameters(_ edge: GarmentCodeEdge) -> [Double] {
                    edge.curvature?.circle.map {
                        [$0.radius, $0.largeArc ? 1 : 0, $0.right ? 1 : 0]
                    } ?? edge.curvature?.params?.flatMap { $0 } ?? []
                }
                let actualValues = parameters(actualEdge)
                let expectedValues = parameters(expectedEdge)
                precondition(actualValues.count == expectedValues.count,
                             "\(name): curvature parameter count differs")
                if let actualArc = actualEdge.curvature?.circle, let expectedArc = expectedEdge.curvature?.circle {
                    precondition(actualArc.largeArc == expectedArc.largeArc && actualArc.right == expectedArc.right,
                                 "\(name): arc direction/major-arc semantics differ")
                }
                if !metricsAudit && !fittedPanel {
                precondition(actualValues.count == expectedValues.count &&
                             zip(actualValues, expectedValues).allSatisfy { abs($0 - $1) < tolerance },
                             "\(name).\(panelName): edge \(index) curvature differs; actual=\(actualValues), expected=\(expectedValues)")
                }
                // Relative Bezier controls are dimensionless, not centimeters.
                // Compare the reconstructed physical contour as well as JSON.
                let actualCurve = actualGeometry[panelName]!.edges[index]
                let expectedCurve = expectedGeometry[panelName]!.edges[index]
                let lengthError = abs(actualCurve.length() - expectedCurve.length())
                precondition(lengthError.isFinite, "\(name): non-finite edge length")
                if fittedPanel && !metricsAudit {
                    precondition(curveWithin(actualCurve, of: expectedCurve, limit: shapeLimit) &&
                                 curveWithin(expectedCurve, of: actualCurve, limit: shapeLimit),
                                 "\(name).\(panelName)#\(index): continuous contour distance exceeds \(shapeLimit) cm")
                    precondition(lengthError < 2 * shapeLimit,
                                 "\(name).\(panelName)#\(index): edge length drift exceeds shape allowance")
                }
                if lengthError > maximumEdgeLengthError {
                    maximumEdgeLengthError = lengthError
                    maximumLengthEdge = "\(panelName)#\(index)"
                }
                for sample in 0...32 {
                    let t = Double(sample) / 32
                    let a = actualCurve.point(at: t), e = expectedCurve.point(at: t)
                    let error = max(abs(a.x - e.x), abs(a.y - e.y))
                    precondition(error.isFinite, "\(name): non-finite reconstructed contour")
                    if error > maximumContourError {
                        maximumContourError = error
                        maximumContourEdge = "\(panelName)#\(index)"
                    }
                    if metricsAudit || fittedPanel { continue }
                    if ProcessInfo.processInfo.environment["GARMENTCODE_CONTOUR_AUDIT"] == "1" {
                        if error >= tolerance {
                            print("CONTOUR_MISMATCH \(name).\(panelName) edge=\(index) t=\(t) error_cm=\(error) limit_cm=\(tolerance)")
                        }
                    } else { precondition(error < tolerance,
                                 "\(name).\(panelName): edge \(index) physical contour error \(error) cm at t=\(t), limit=\(tolerance) cm")
                    }
                }
            }
        }
        if metricsAudit || nativeAcceptance {
            // Compare the change in signed seam mismatch, not whether the two
            // sides have equal lengths: official ruffles intentionally differ.
            var maximumSeamResidualChange = 0.0
            if checkStitches {
                for stitch in expected.pattern.stitches {
                    let a = stitch.sides[0], b = stitch.sides[1]
                    let actualResidual = actualGeometry[a.panel]!.edges[a.edge].length() -
                        actualGeometry[b.panel]!.edges[b.edge].length()
                    let expectedResidual = expectedGeometry[a.panel]!.edges[a.edge].length() -
                        expectedGeometry[b.panel]!.edges[b.edge].length()
                    maximumSeamResidualChange = max(maximumSeamResidualChange, abs(actualResidual - expectedResidual))
                }
            }
            let record: [String: Any] = ["case": name, "contour_max_axis_error_cm": maximumContourError,
                "edge_length_max_error_cm": maximumEdgeLengthError,
                "seam_residual_max_change_cm": maximumSeamResidualChange,
                "maximum_contour_edge": maximumContourEdge, "maximum_length_edge": maximumLengthEdge,
                "stitches_checked": checkStitches, "stitch_count": expected.pattern.stitches.count]
            if metricsAudit {
                let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                FileHandle.standardOutput.write(Data("GARMENT_METRICS ".utf8) + data + Data("\n".utf8))
            }
            if (seamCheck || nativeAcceptance) && checkStitches {
                precondition(maximumSeamResidualChange.isFinite && maximumSeamResidualChange < 0.05,
                             "\(name): seam mismatch drift exceeds 0.5 mm relative to official ruffle semantics")
            }
        }
    }

    /// Prove a directed continuous curve-to-curve distance bound. The target
    /// chord approximation has bounded interpolation error M/(8 n²); source
    /// intervals use their derivative bound to cover every point, not just t
    /// samples. Unresolved intervals fail conservatively.
    private static func curveWithin(_ source: GarmentCodeGeometryEdge,
                                    of target: GarmentCodeGeometryEdge, limit: Double) -> Bool {
        func bounds(_ edge: GarmentCodeGeometryEdge) -> (speed: Double, acceleration: Double) {
            if let arc = edge.curvature?.circle {
                let speed = edge.length()
                return (speed, speed * speed / max(arc.radius, edge.chordLength / 2))
            }
            let p = GarmentCodeGeometryEdge.subcurve(edge: edge, lower: 0, upper: 1)
            let degree = Double(p.count - 1)
            let speed = zip(p, p.dropFirst()).map { $0.distance(to: $1) * degree }.max() ?? 0
            var acceleration = 0.0
            if p.count >= 3 {
                for i in 0..<(p.count - 2) {
                    acceleration = max(acceleration, (p[i + 2] - p[i + 1] * 2 + p[i]).length * degree * (degree - 1))
                }
            }
            return (speed, acceleration)
        }
        let sourceSpeed = bounds(source).speed
        let targetAcceleration = bounds(target).acceleration
        guard sourceSpeed.isFinite, targetAcceleration.isFinite else { return false }
        let count = max(1, Int(min(4096, ceil(sqrt(targetAcceleration / (8 * 0.0001))))))
        let targetError = targetAcceleration / (8 * Double(count * count))
        guard targetError < limit else { return false }
        let points = (0...count).map { target.point(at: Double($0) / Double(count)) }
        let segments = zip(points, points.dropFirst()).map { ($0, $1 - $0) }
        func distance(_ point: GarmentCodePoint) -> Double {
            var best = Double.infinity
            for (start, vector) in segments {
                let squared = vector.dot(vector)
                let t = squared > 0 ? min(1, max(0, (point - start).dot(vector) / squared)) : 0
                best = min(best, point.distance(to: start + vector * t))
            }
            return best
        }
        func cover(_ lower: Double, _ upper: Double, depth: Int) -> Bool {
            let middle = (lower + upper) / 2
            let d = distance(source.point(at: middle))
            if d + sourceSpeed * (upper - lower) / 2 + targetError <= limit { return true }
            if d - targetError > limit || depth >= 22 { return false }
            return cover(lower, middle, depth: depth + 1) && cover(middle, upper, depth: depth + 1)
        }
        return cover(0, 1, depth: 0)
    }
}
