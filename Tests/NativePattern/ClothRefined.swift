import Foundation

/// Integration evidence for the anatomical body, surface contacts and numerical
/// materials. This does not compare against a matched external 3D simulation.
@main
struct ClothRefinedRegression {
    typealias Drape = GarmentCodeCircleDrape
    enum Failure: Error { case check(String) }
    struct Case {
        let tag: String
        let suns: Double
        let length: Double
        let material: GarmentCodeClothMaterial.Preset
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func near(_ a: Double, _ b: Double, _ message: String, tolerance: Double = 1e-10) throws {
        try require(abs(a-b) <= tolerance, "\(message): \(a) != \(b)")
    }
    static func log(_ text: String) { FileHandle.standardError.write(Data((text+"\n").utf8)) }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    static func save(_ output: Drape.Output, pattern: GarmentCodePatternFile,
                     tag: String, directory: URL) throws {
        try encode(output).write(to: directory.appendingPathComponent(tag+"-mesh.json"), options: .atomic)
        try encode(output.diagnostics).write(to: directory.appendingPathComponent(tag+"-diagnostics.json"), options: .atomic)
        try encode(pattern).write(to: directory.appendingPathComponent(tag+"-pattern.json"), options: .atomic)
        try output.objString.write(to: directory.appendingPathComponent(tag+".obj"), atomically: true, encoding: .utf8)
    }

    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try GarmentCodeParameterCatalog.load(from: root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body = GarmentCodeBodyParameters(values: catalog.body)
        let resources = root.appendingPathComponent("TrailorAss/Resources")
        let environment = ProcessInfo.processInfo.environment
        let outputDirectory = URL(fileURLWithPath: environment["GARMENTCODE_CLOTH_OUTPUT_DIR"] ?? "/private/tmp/TailorAssClothRefined")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let filter = environment["GARMENTCODE_CLOTH_REFINED_CASE_FILTER"]
        var failures: [String] = []
        var completed: [String: Drape.Output] = [:]
        var executed: [String] = []

        func design(suns: Double, length: Double) -> GarmentCodeDesignParameters {
            var value = GarmentCodeDesignParameters(catalog: catalog)
            _ = value.setValue(.null, at: ["meta","upper"])
            _ = value.setValue(.null, at: ["meta","wb"])
            _ = value.setValue(.string("SkirtCircle"), at: ["meta","bottom"])
            _ = value.setValue(.bool(false), at: ["flare-skirt","cut","add"])
            _ = value.setValue(.number(suns), at: ["flare-skirt","suns"])
            _ = value.setValue(.number(length), at: ["flare-skirt","length"])
            return value
        }

        if filter == nil || filter == "legacy-reference" {
            executed.append("legacy-reference")
            do {
                let document = try GarmentCodeNativeGenerator.generate(body: body, design: design(suns: 0.75, length: 0.2))
                let input = try Drape.prepare(document: document, body: body)
                let output = try Drape.simulate(input: input)
                try save(output, pattern: document, tag: "legacy-reference", directory: outputDirectory)
                let baselineURL = root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-3d/generated/circle-0.75-mesh.json")
                let baseline = try JSONDecoder().decode(Drape.Output.self, from: Data(contentsOf: baselineURL))
                try require(output.positions.count == baseline.positions.count, "Legacy vertex count changed")
                let maximumDelta = zip(output.positions, baseline.positions).map { ($0-$1).length }.max() ?? 0
                log("legacy-reference maximum_position_delta_m=\(maximumDelta)")
                try require(output.positions == baseline.positions, "Legacy reference positions changed; max delta \(maximumDelta)m")
                try require(output.triangleIndices == baseline.triangleIndices && output.seamPaths == baseline.seamPaths, "Legacy triangle/seam topology changed")
                try require(output.mannequinPositions == baseline.mannequinPositions && output.mannequinTriangleIndices == baseline.mannequinTriangleIndices, "Legacy reference body changed")
                try require(output.diagnostics.converged, "Legacy reference is no longer converged")
                try require(output.diagnostics.totalFabricMassKg == nil, "Legacy reference silently enabled weighted material")
            } catch { failures.append("legacy-reference: \(error)"); log("FAIL legacy-reference: \(error)") }
        }

        let cases: [Case] = [
            .init(tag: "circle-0.5", suns: 0.5, length: 0.2, material: .medium),
            .init(tag: "circle-0.75", suns: 0.75, length: 0.2, material: .medium),
            .init(tag: "circle-1.0", suns: 1, length: 0.2, material: .medium),
            .init(tag: "circle-0.75-length-0.35", suns: 0.75, length: 0.35, material: .medium),
            .init(tag: "circle-0.75-material-soft", suns: 0.75, length: 0.2, material: .soft),
            .init(tag: "circle-0.75-material-firm", suns: 0.75, length: 0.2, material: .firm)
        ]
        for item in cases where filter == nil || filter == item.tag {
            executed.append(item.tag)
            do {
                let document = try GarmentCodeNativeGenerator.generate(body: body, design: design(suns: item.suns, length: item.length))
                let before = try encode(document)
                try before.write(to: outputDirectory.appendingPathComponent(item.tag+"-pattern.json"), options: .atomic)
                var settings = Drape.Settings()
                settings.bodyMode = .standardMannequin
                settings.material = item.material
                settings.useSurfaceCollision = true
                settings.bodyResourceDirectory = resources
                // Match the App's refined profile, while the separate legacy
                // reference above deliberately retains its original 24 passes.
                settings.solverIterations = 32
                if let raw = environment["GARMENTCODE_CLOTH_REFINED_ITERATIONS"] {
                    guard let iterations = Int(raw), (4...32).contains(iterations) else {
                        throw Failure.check("Refined iteration override must be an integer from 4 to 32")
                    }
                    settings.solverIterations = iterations
                }
                let input = try Drape.prepare(document: document, body: body, settings: settings)
                try require(input.standardBody != nil, "Anatomical body silently fell back to cylinder")
                try require(input.surfaceTopology != nil, "Surface collision silently disabled")
                try require(input.inverseMasses.count == input.positions.count, "Area mass weights missing")
                try require(input.springs.contains(where: \.isShear), "Shear compliance has no tagged constraints")
                try require(input.inverseMasses.allSatisfy { $0.isFinite && $0 >= 0 }, "Invalid inverse masses")
                let output = try Drape.simulate(input: input)
                // Preserve every actual output before quality assertions so an
                // unsuccessful case is inspectable, never substituted by v1.
                try save(output, pattern: document, tag: item.tag, directory: outputDirectory)
                completed[item.tag] = output
                let d = output.diagnostics
                log("\(item.tag) seconds=\(d.computationSeconds) strain=\(d.maxEdgeStrain) speed=\(d.maxSpeedMetersPerSecond) bodyPenetration=\(d.maxBodyPenetrationMeters) intersections=\(d.surfaceIntersectionCount.map(String.init) ?? "missing") converged=\(d.converged)")
                if !d.converged || d.maxEdgeStrain >= 0.08 {
                    let worst = input.springs.sorted {
                        abs((output.positions[$0.a]-output.positions[$0.b]).length/$0.length-1) >
                        abs((output.positions[$1.a]-output.positions[$1.b]).length/$1.length-1)
                    }.prefix(5)
                    for spring in worst {
                        let actual = (output.positions[spring.a]-output.positions[spring.b]).length
                        let first = input.referenceToSimulation.firstIndex(of: spring.a) ?? 0
                        let second = input.referenceToSimulation.firstIndex(of: spring.b) ?? 0
                        let row = (first % ((input.panelColumns+1)*(input.radialSegments+1)))/(input.panelColumns+1)
                        log("  worst spring \(spring.a)-\(spring.b) signedStrain=\(actual/spring.length-1) refLength=\(spring.length) sourceRow=\(row) shear=\(spring.isShear) pinned=\(input.pinned[spring.a])-\(input.pinned[spring.b])")
                        log("    actualA=\(output.positions[spring.a]) actualB=\(output.positions[spring.b]) referenceA=\(input.referencePositions[first]) referenceB=\(input.referencePositions[second])")
                    }
                }
                try require(output.positions.count == input.positions.count && output.triangleIndices == input.triangleIndices, "Solver changed input mesh topology")
                try require(output.positions.allSatisfy(\.isFinite), "Non-finite cloth")
                try require(output.mannequinPositions.count > 100, "Missing anatomical mannequin mesh")
                try require(d.materialName == item.material.title && d.bodyModel != nil, "Body/material provenance missing")
                guard let totalMass = d.totalFabricMassKg else { throw Failure.check("Material mass diagnostic missing") }
                try near(totalMass, input.referenceAreaSquareMeters*item.material.parameters.arealDensityKgPerSquareMeter, "Areal density mass is independent of draped area")
                try near(d.waistCircumferenceMeters, (body["waist"] ?? 0)/100, "Waist rest metric changed")
                try require(d.maxSeamGapMeters == 0, "Welded seam gap")
                for pair in output.seamVertexPairs { try require(output.positions[pair.a] == output.positions[pair.b], "Seam points separated") }
                for index in input.pinned.indices where input.pinned[index] {
                    try require(output.positions[index] == input.positions[index], "Pinned waist support drifted")
                }
                let after = try encode(document)
                try require(after == before, "Draping mutated original pattern")
                try require(d.maxEdgeStrain < 0.08, "Reference edge strain exceeds original 8% gate")
                try require(d.maxSpeedMetersPerSecond < 0.025, "Motion exceeds original .025m/s gate")
                try require(d.maxBodyPenetrationMeters < 0.003, "Body contact exceeds original 3mm gate")
                try require(d.surfaceIntersectionCount == 0, "Final surface intersection inspection failed or missing")
                try require((d.closeSurfacePairCount ?? -1) >= 0, "Surface proximity diagnostic missing")
                try require(d.converged, "Original sustained convergence gate was not reached")
            } catch { failures.append("\(item.tag): \(error)"); log("FAIL \(item.tag): \(error)") }
        }
        try require(!executed.isEmpty, "Unknown refined case filter: \(filter ?? "nil")")

        // Compare actual final geometry at identical body, topology and design;
        // changing only a label or density diagnostic is not a material effect.
        if let medium = completed["circle-0.75"] {
            for name in ["soft", "firm"] {
                guard let variant = completed["circle-0.75-material-"+name] else { continue }
                do {
                    try require(variant.triangleIndices == medium.triangleIndices && variant.positions.count == medium.positions.count, "Material changed tessellation")
                    let rms = sqrt(zip(variant.positions, medium.positions).reduce(0) { $0+($1.0-$1.1).lengthSquared }/Double(medium.positions.count))
                    log("material-\(name) actual_final_position_rms_delta_m=\(rms)")
                    try require(rms > 1e-5, "\(name) material changed metadata but not final draped geometry")
                } catch { failures.append("material-\(name)-sensitivity: \(error)") }
            }
            if let longer = completed["circle-0.75-length-0.35"] {
                do {
                    try require(longer.diagnostics.radialLengthMeters > medium.diagnostics.radialLengthMeters+0.1, "Length did not change source geometry")
                    try require((longer.positions.map(\.y).min() ?? 0) < (medium.positions.map(\.y).min() ?? 0)-0.03, "Length did not change actual draped extent")
                } catch { failures.append("length-sensitivity: \(error)") }
            }
        }
        let summary: [String: Any] = ["executed": executed, "passed": failures.isEmpty, "failures": failures,
                                      "caseFilter": filter ?? "all",
                                      "standardSolverIterations": environment["GARMENTCODE_CLOTH_REFINED_ITERATIONS"] ?? "32",
                                      "legacySolverIterations": 24,
                                      "conditions": "Original sustained convergence, .025m/s motion, 8% strain, 3mm body contact; final discrete surface intersections zero. Not physical calibration."]
        let summaryData = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted,.sortedKeys])
        try summaryData.write(to: outputDirectory.appendingPathComponent("refined-summary.json"), options: .atomic)
        if !failures.isEmpty { throw Failure.check(failures.joined(separator: "\n")) }
        if filter == nil {
            print("PASS: refined cloth integration; preserved v1 reference, anatomical body, surface quality, SI mass/material effects, source immutability and sustained convergence (\(executed.count) cases)")
        } else {
            print("PASS: selected refined integration case(s): \(executed.joined(separator: ", ")); unselected cases were not tested")
        }
    }
}
