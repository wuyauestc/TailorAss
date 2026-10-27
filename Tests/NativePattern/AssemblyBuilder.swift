import Foundation

@main @MainActor
struct AssemblyBuilderRegression {
    typealias K = GarmentCodeCircleDrape
    typealias B = GarmentCodeAssemblyBuilder
    typealias S = GarmentCodeSewing
    enum Failure: Error { case check(String) }
    struct FrozenGeometry: Decodable {
        let positions: [K.Vector3]
        let triangleIndices: [UInt32]
        let mannequinPositions: [K.Vector3]
    }
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure.check(message) }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try GarmentCodeParameterCatalog.load(from: root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body = GarmentCodeBodyParameters(values: catalog.body)
        var settings = K.Settings()
        settings.bodyMode = .standardMannequin
        settings.material = .medium
        settings.useSurfaceCollision = true
        settings.useBodySurfaceCollision = true
        settings.solverIterations = 32
        settings.bodyResourceDirectory = root.appendingPathComponent("TrailorAss/Resources")
        let staged=GarmentCodeSewnDrape.AssemblySchedule(staticFrames:240,gravityRampFrames:240)
        try require(staged.gravityFraction(step:0)==0 && staged.gravityFraction(step:239)==0 &&
            staged.gravityFraction(step:240)==1.0/240 && staged.gravityFraction(step:479)==1 &&
            GarmentCodeSewnDrape.AssemblySchedule.immediate.gravityFraction(step:0)==1,
            "Explicit static assembly and gravity ramp do not preserve their requested timing")
        for tag in ["skirt2-default","circle-0.75"] {
            let base=root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-body-surface/generated/"+tag)
            let previous=try JSONDecoder().decode(K.Output.self,from:Data(contentsOf:URL(fileURLWithPath:base.path+"-mesh.json")))
            let previousOBJ=try Data(contentsOf:URL(fileURLWithPath:base.path+".obj"))
            try require(previous.panelGroups == nil && Data(previous.objString.utf8)==previousOBJ,
                        "Legacy source-less \(tag) output changed its frozen OBJ bytes")
            print("PASS \(tag): previous output JSON decodes and OBJ remains byte-identical")
        }
        var cases: [[String: Any]] = []
        for style in ["StraightWB","FittedWB"] {
            var design = GarmentCodeDesignParameters(catalog: catalog)
            _ = design.setValue(.null, at: ["meta","upper"])
            _ = design.setValue(.null, at: ["meta","bottom"])
            _ = design.setValue(.string(style), at: ["meta","wb"])
            let source = try GarmentCodeNativeGenerator.generate(body: body, design: design)
            let bytes = try encode(source)
            let original = try GarmentCodeWaistbandAssembly.prepare(document: source, body: body, settings: settings)
            let old = original.cloth
            let panels = original.panelBindings.map { binding in
                B.Panel(mesh: binding.mesh, positions: binding.vertexIDs.map { old.positions[$0] },
                    fixedVertexIDs: Set(binding.vertexIDs.enumerated().compactMap { old.pinned[$0.element] ? $0.offset : nil }))
            }
            let hints = source.pattern.stitches.enumerated().map { index,stitch in
                S.StitchHint(stitchIndex: index, seamID: "waistband-side-\(index)",
                    a: .init(panelID: stitch.sides[0].panel, edgeIndex: stitch.sides[0].edge),
                    b: .init(panelID: stitch.sides[1].panel, edgeIndex: stitch.sides[1].edge),
                    aDirection: .forward, bDirection: .reverse, rightWrong: stitch.rightWrong, intent: .ordinary)
            }
            let metrics = B.Metrics(garmentStyle: old.garmentStyle, lengthLabel: old.patternLengthLabel,
                sourceWaistMeters: old.waistCircumferenceMeters, sourceHemMeters: old.hemCircumferenceMeters,
                sourceLengthMeters: old.radialLengthMeters, gatherRatio: old.waistGatherRatio,
                warnings: old.preparationWarnings)
            let rebuilt = try B.prepare(document: source, body: body, settings: old.settings,
                                         panels: panels, hints: hints, metrics: metrics)
            let actual = rebuilt.cloth
            try require(actual.positions == old.positions && actual.pinned == old.pinned,
                        "Shared builder changed original positions or support pins")
            try require(actual.referencePositions == old.referencePositions && actual.referenceTriangles == old.referenceTriangles,
                        "Shared builder changed source panel geometry")
            try require(actual.referenceToSimulation == old.referenceToSimulation && actual.triangleIndices == old.triangleIndices,
                        "Shared builder welded particles or changed original fabric normals")
            try require(actual.springs.count == old.springs.count && zip(actual.springs,old.springs).allSatisfy {
                $0.a == $1.a && $0.b == $1.b && $0.length == $1.length && $0.isShear == $1.isShear
            }, "Shared builder changed real source structural edges")
            try require(actual.bendingSprings.count == old.bendingSprings.count && zip(actual.bendingSprings,old.bendingSprings).allSatisfy {
                $0.a == $1.a && $0.b == $1.b && $0.length == $1.length
            }, "Shared builder changed source panel hinges")
            try require(actual.inverseMasses == old.inverseMasses && actual.meanParticleMassKg == old.meanParticleMassKg && actual.totalFabricMassKg == old.totalFabricMassKg,
                        "Shared builder changed source particle masses")
            try require(actual.mannequinPositions == old.mannequinPositions && actual.mannequinTriangleIndices == old.mannequinTriangleIndices,
                        "Shared builder changed the exact body surface")
            try require(try encode(rebuilt.plan) == encode(original.plan), "Shared builder changed actual sewing provenance or constraints")
            try require(rebuilt.sourceSHA256 == original.sourceSHA256 && rebuilt.panelBindings.count == panels.count,
                        "Shared builder lost verified source identity or panel bindings")
            try require(bytes == encode(source), "Shared builder modified source paper")
            let output = try GarmentCodeSewnDrape.simulate(input: rebuilt)
            try require(output.diagnostics.converged && output.diagnostics.maxEdgeStrain < 0.08 &&
                output.diagnostics.maxSeamGapMeters < 0.0005 && output.diagnostics.surfaceIntersectionCount == 0 &&
                output.diagnostics.bodySurfaceIntersectionCount == 0, "Shared-builder waistband did not pass the original physical quality gates")
            let referenceTag=style=="StraightWB" ? "straightwb-default" : "fittedwb-default"
            let frozen=try JSONDecoder().decode(FrozenGeometry.self,from:Data(contentsOf:root.appendingPathComponent(
                "Tests/NativePattern/Reports/2026-10-25-waistband-sewn/generated/"+referenceTag+"-mesh.json")))
            try require(output.positions==frozen.positions && output.triangleIndices==frozen.triangleIndices &&
                output.mannequinPositions==frozen.mannequinPositions,
                "The default immediate schedule changed the already verified waistband geometry")
            guard let groups = output.panelGroups else { throw Failure.check("Sewn output omitted source-panel membership") }
            try require(groups.count == rebuilt.panelBindings.count && zip(groups,rebuilt.panelBindings).allSatisfy {
                $0.panelID == $1.mesh.panelID && $0.vertexIDs == $1.vertexIDs && $0.triangleIDs == $1.triangleIDs
            }, "Output groups differ from the factory-verified source bindings")
            try require(Set(groups.flatMap(\.vertexIDs)) == Set(output.positions.indices) &&
                groups.reduce(0,{ $0+$1.vertexIDs.count }) == output.positions.count &&
                Set(groups.flatMap(\.triangleIDs)) == Set(0..<output.triangleIndices.count/3) &&
                groups.reduce(0,{ $0+$1.triangleIDs.count }) == output.triangleIndices.count/3,
                "Output panel membership omitted or repeated real particles/faces")
            var inCloth = false, currentGroup = "", exported: [String: [[Int]]] = [:], bodyFaces = 0
            for line in output.objString.split(separator: "\n") {
                let tokens = line.split(separator: " ").map(String.init)
                if tokens.first == "o" { inCloth = tokens[1] != "standard_mannequin" }
                if tokens.first == "g" { currentGroup = tokens[1] }
                if tokens.first == "f" {
                    if inCloth { exported[currentGroup, default: []].append(tokens.dropFirst().compactMap(Int.init)) }
                    else { try require(currentGroup == "mannequin", "Body faces inherited a source cloth group"); bodyFaces += 1 }
                }
            }
            for (index,group) in groups.enumerated() {
                let expected = group.triangleIDs.map { face in (0..<3).map { Int(output.triangleIndices[face*3+$0])+1 } }
                try require(exported["panel_\(index)_\(group.panelID)"] == expected, "OBJ omitted, reordered or changed a source panel face")
            }
            try require(bodyFaces == output.mannequinTriangleIndices.count/3 && exported.count == groups.count,
                        "OBJ omitted body faces or source groups")
            let decoded = try JSONDecoder().decode(K.Output.self, from: encode(output))
            try require(decoded.panelGroups?.count == groups.count && decoded.positions == output.positions,
                        "Source panel groups were lost on output JSON roundtrip")
            let legacy = K.Output(positions: output.positions, triangleIndices: output.triangleIndices,
                mannequinPositions: output.mannequinPositions, mannequinTriangleIndices: output.mannequinTriangleIndices,
                seamPaths: output.seamPaths, seamVertexPairs: output.seamVertexPairs, diagnostics: output.diagnostics)
            let legacyDecoded = try JSONDecoder().decode(K.Output.self, from: encode(legacy))
            try require(legacyDecoded.panelGroups == nil && !legacy.objString.contains("\ng "),
                        "Optional source groups changed legacy export behavior")
            let invalidGroups: [[K.PanelGroup]] = [[],[groups[0]],
                [.init(panelID: "bad",vertexIDs: Array(output.positions.indices),triangleIDs: [-1])],
                [.init(panelID: "bad",vertexIDs: Array(output.positions.indices),triangleIDs: [Int.max])],
                [groups[0],groups[0]]]
            for value in invalidGroups {
                var malformed = output
                malformed.panelGroups = value
                let allFaces = malformed.objString.split(separator: "\n").filter { $0.hasPrefix("f ") }.count
                try require(malformed.validatedPanelGroups == nil &&
                    allFaces == (output.triangleIndices.count+output.mannequinTriangleIndices.count)/3 &&
                    malformed.objString.contains("Invalid optional panel membership"),
                    "Malformed optional groups omitted faces, crashed or lost the export warning")
            }
            var rejected = 0
            let invalid: [[B.Panel]] = [Array(panels.dropLast()), [panels[0],panels[0]],
                [.init(mesh: panels[0].mesh, positions: Array(panels[0].positions.dropLast())),panels[1]],
                [.init(mesh: panels[0].mesh, positions: panels[0].positions, fixedVertexIDs: [-1]),panels[1]]]
            for value in invalid {
                do { _ = try B.prepare(document: source, body: body, settings: old.settings, panels: value, hints: hints, metrics: metrics) }
                catch { rejected += 1 }
            }
            do { _ = try B.prepare(document: source, body: body, settings: old.settings, panels: panels, hints: [], metrics: metrics) }
            catch { rejected += 1 }
            var cancelled = false
            do { _ = try B.prepare(document: source, body: body, settings: old.settings, panels: panels, hints: hints, metrics: metrics, isCancelled: { true }) }
            catch is CancellationError { cancelled = true }
            try require(rejected == invalid.count+1 && cancelled, "Missing/duplicate/invalid panels, missing source seams or cancellation were accepted")
            for badSchedule in [GarmentCodeSewnDrape.AssemblySchedule(staticFrames:-1,gravityRampFrames:0),
                .init(staticFrames:0,gravityRampFrames:-1),.init(staticFrames:Int.max,gravityRampFrames:0),
                .init(staticFrames:1200,gravityRampFrames:1200)] {
                var invalidScheduleRejected=false
                do{_=try GarmentCodeSewnDrape.simulate(input:rebuilt,schedule:badSchedule)}catch K.DrapeError.invalid{invalidScheduleRejected=true}
                try require(invalidScheduleRejected,"Invalid assembly schedule did not fail before simulation")
            }
            for badCoupling in [GarmentCodeSewnDrape.CouplingOptions(timeStepSeconds:0),
                .init(timeStepSeconds:.nan),.init(selfContactPaddingMeters:0)] {
                var invalidCouplingRejected=false
                do{_=try GarmentCodeSewnDrape.simulate(input:rebuilt,coupling:badCoupling)}catch K.DrapeError.invalid{invalidCouplingRejected=true}
                try require(invalidCouplingRejected,"Invalid coupling time step or contact padding entered simulation")
            }
            if style=="StraightWB" {
                let coupled=GarmentCodeSewnDrape.CouplingOptions(projectVirtualSewingPoints:true,
                    useSourcePathBounds:true,sourceAwareContactRibbons:true)
                let integrated=try GarmentCodeSewnDrape.simulate(input:rebuilt,coupling:coupled)
                try require(integrated.diagnostics.converged && integrated.diagnostics.maxEdgeStrain<0.08 &&
                    integrated.diagnostics.maxSeamGapMeters<0.0005 && integrated.diagnostics.surfaceIntersectionCount==0 &&
                    integrated.diagnostics.bodySurfaceIntersectionCount==0,
                    "Integrated source/body/contact helpers broke the existing straight waistband case")
                try require(integrated.positions.indices.allSatisfy{!actual.pinned[$0] || integrated.positions[$0]==actual.positions[$0]},
                    "Coupled helper integration moved an existing fixed source point")
                var withPointBlock=coupled;withPointBlock.simultaneousFinalSewing=true
                let simultaneous=try GarmentCodeSewnDrape.simulate(input:rebuilt,coupling:withPointBlock)
                try require(simultaneous.diagnostics.converged && simultaneous.diagnostics.maxEdgeStrain<0.08 &&
                    simultaneous.diagnostics.maxSeamGapMeters<0.0005 && simultaneous.diagnostics.surfaceIntersectionCount==0 &&
                    simultaneous.diagnostics.bodySurfaceIntersectionCount==0 &&
                    simultaneous.diagnostics.usesSimultaneousFinalSewing==true &&
                    simultaneous.diagnostics.sewingBlockLinearSystemsConverged==true,
                    "Simultaneous final point sewing failed the existing waistband's original physical gates")
                try require(simultaneous.positions.indices.allSatisfy{!actual.pinned[$0] || simultaneous.positions[$0]==actual.positions[$0]},
                    "Simultaneous final point sewing moved a source pin")
            }
            cases.append(["style":style,"identicalSourceAndInitialState":true,"identicalSewingPlan":true,
                          "identicalRestGraphAndMass":true,"invalidCasesRejected":rejected,"cancellationVerified":cancelled,
                          "physicalQualityPassed":true,"sourcePanelGroupsAndOBJVerified":true,
                          "simultaneousFinalSewingControlVerified":style=="StraightWB",
                          "maxSourceStrain":output.diagnostics.maxEdgeStrain,"maxActualSeamGapMeters":output.diagnostics.maxSeamGapMeters])
            print("PASS \(style): shared assembly exactly preserves all source/initial/rest/mass/body/sewing state; malformed inputs rejected")
        }
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GARMENTCODE_ASSEMBLY_BUILDER_OUTPUT"] ?? "/private/tmp/TailorAssAssemblyBuilder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result: [String: Any] = ["passed":true,"cases":cases,
            "scope":"Shared construction exactly matches both existing independent-waistband inputs and passes their original physics gates. Actual source-panel OBJ groups and optional JSON metadata verified. No new garment-family or App coverage is claimed."]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("assembly-builder-summary.json"))
    }
}
