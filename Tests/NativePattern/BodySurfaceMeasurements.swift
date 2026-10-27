import Foundation
import Synchronization

@main @MainActor struct BodySurfaceMeasurementsRegression {
    typealias M = GarmentCodeBodySurfaceMeasurements
    typealias V = M.V
    enum Failure: Error { case failed(String) }
    static func require(_ condition: Bool, _ text: String) throws { if !condition { throw Failure.failed(text) } }
    static func reject(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch { return }; throw Failure.failed("Expected rejection: " + name)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let resource = root.appendingPathComponent("resources")
        let contract = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeBodySurfaceMeasurements.json"))
        let template = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBody.json"))
        let rig = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBodyRig/rig.json"))
        let prepared = try M.Prepared(contractData: contract, templateData: template, rigData: rig)
        let catalog = try GarmentCodeParameterCatalog.load(from: resource.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        nonisolated struct Female: Decodable { nonisolated struct Parameters: Decodable { let body: [String: Double] }; let parameters: Parameters }
        let female = try JSONDecoder().decode(Female.self, from: Data(contentsOf: root.appendingPathComponent("female-standing-mesher-source.json")))
        var profiles: [[String: Any]] = []
        for (name, raw) in [("default", catalog.body), ("female", female.parameters.body)] {
            let body = GarmentCodeBodyParameters(values: raw)
            let mesh = try GarmentCodeStandardBody.load(body: body, resourceDirectory: resource)
            let originalPositions = mesh.positions, originalTriangles = mesh.triangleIndices
            let report = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: body.values)
            try require(report.measurements.count == 7 && report.bodyValues.count == 33 && !report.bodyFittingApplied && !report.defaultBodyBehaviorChanged, "Full source and seven project references")
            try require(mesh.positions == originalPositions && mesh.triangleIndices == originalTriangles, "Read-only source geometry")
            try encode(report).write(to: out.appendingPathComponent(name + "-surface-measurements.json"))
            var targetOnly = body; targetOnly.set(body["bust"]! + 1, for: "bust")
            let changed = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: targetOnly.values)
            try require(changed.geometrySHA256 == report.geometrySHA256 && changed.parameterSHA256 != report.parameterSHA256, "Parameter-only change binds all values without deforming source")
            try require(zip(report.measurements, changed.measurements).allSatisfy { $0.observedMeters.bitPattern == $1.observedMeters.bitPattern }, "Targets do not invent surface fitting")
            // A geometric covariance control, not a certified/posed BodyMesh.
            let scaled = mesh.positions.map { $0 * 1.25 + V(x: 0.12, y: -0.07, z: 0.03) }
            let scaling = try prepared.measure(positions: scaled, triangleIndices: mesh.triangleIndices, bodyValues: body.values)
            try require(scaling.geometrySHA256 != report.geometrySHA256 && zip(report.measurements, scaling.measurements).allSatisfy { abs($1.observedMeters - $0.observedMeters * 1.25) < 2e-12 }, "Actual surface metric under SI scaling and translation")
            try encode(scaling).write(to: out.appendingPathComponent(name + "-scaled-control.json"))
            var wrongTopology = mesh.triangleIndices; wrongTopology.swapAt(0, 1)
            try reject("foreign topology") { _ = try prepared.measure(positions: mesh.positions, triangleIndices: wrongTopology, bodyValues: body.values) }
            var invalid = mesh.positions; invalid[0].x = .nan
            try reject("nonfinite actual surface") { _ = try prepared.measure(positions: invalid, triangleIndices: mesh.triangleIndices, bodyValues: body.values) }
            var collapsed = mesh.positions; collapsed[Int(mesh.triangleIndices[0])] = collapsed[Int(mesh.triangleIndices[1])]
            try reject("degenerate actual face") { _ = try prepared.measure(positions: collapsed, triangleIndices: mesh.triangleIndices, bodyValues: body.values) }
            var missing = body.values; missing.removeValue(forKey: "arm_length")
            try reject("missing target") { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: missing) }
            var unknown = body.values; unknown["unknown"] = 1
            try reject("unknown parameter") { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: unknown) }
            var stale = body.values; stale["_base_sleeve_balance"]! += 1
            try reject("stale derived") { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: stale) }
            for key in ["bust", "shoulder_w", "arm_length", "wrist"] {
                var nonpositive = body; nonpositive.set(0, for: key)
                try reject("nonpositive " + key) { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: nonpositive.values) }
            }
            do { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: body.values, isCancelled: { true }); throw Failure.failed("Immediate cancellation") } catch is CancellationError {}
            let counter = Mutex(0)
            do { _ = try prepared.measure(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: body.values, isCancelled: { counter.withLock { $0 += 1; return $0 >= 5 } }); throw Failure.failed("Mid-surface cancellation") } catch is CancellationError {}
            let p = mesh.positions, t = mesh.triangleIndices, values = body.values
            let a = Task.detached { try prepared.measure(positions: p, triangleIndices: t, bodyValues: values) }
            let b = Task.detached { try prepared.measure(positions: p, triangleIndices: t, bodyValues: values) }
            let pair = try await (a.value, b.value)
            try require(try encode(pair.0) == encode(pair.1), "Concurrent immutable determinism")
            profiles.append(["name": name, "geometrySHA256": report.geometrySHA256, "measurements": report.measurements.map {
                ["id": $0.definition.id, "observedCentimeters": $0.observedMeters * 100, "requestedCentimeters": $0.requestedMeters * 100, "residualCentimeters": $0.observedMinusRequestedMeters * 100]
            }])
        }
        for (name, badContract, badTemplate, badRig) in [
            ("contract byte binding", contract + Data([32]), template, rig),
            ("template byte binding", contract, template + Data([32]), rig),
            ("rig byte binding", contract, template, rig + Data([32]))] {
            try reject(name) { _ = try M.Prepared(contractData: badContract, templateData: badTemplate, rigData: badRig) }
        }
        var limits = M.Limits(); limits.maximumSamples = 2
        try reject("sample budget") { _ = try M.Prepared(contractData: contract, templateData: template, rigData: rig, limits: limits) }
        limits = .init(); limits.maximumResourceBytes = 1
        try reject("resource bytes") { _ = try M.Prepared(contractData: contract, templateData: template, rigData: rig, limits: limits) }
        do { _ = try M.Prepared(contractData: contract, templateData: template, rigData: rig, isCancelled: { true }); throw Failure.failed("Preparation cancellation") } catch is CancellationError {}
        let preparationCounter = Mutex(0)
        do { _ = try M.Prepared(contractData: contract, templateData: template, rigData: rig, isCancelled: { preparationCounter.withLock { $0 += 1; return $0 >= 6 } }); throw Failure.failed("Preparation mid cancellation") } catch is CancellationError {}
        let summary: [String: Any] = ["passed": true, "profiles": profiles,
            "controls": ["source-byte-binding-3", "samples-budget", "bytes-budget", "prepare-cancel-immediate-and-mid", "foreign-topology", "nonfinite-surface", "degenerate-face", "missing-and-unknown-parameters", "stale-derived", "nonpositive-targets-4", "read-only-geometry", "target-only-no-fit", "SI-scale-and-translate", "measurement-cancel-immediate-and-mid", "concurrent-determinism"],
            "bodyFittingApplied": false, "clothSimulationRun": false]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("swift-summary.json"))
        print("PASS: two actual production body loads, seven project surface references, controls")
    }
}
