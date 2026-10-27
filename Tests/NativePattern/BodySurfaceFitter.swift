import Foundation
import Synchronization
import Darwin

@main @MainActor struct BodySurfaceFitterRegression {
    typealias F = GarmentCodeBodySurfaceFitter
    enum Failure: Error { case failed(String) }
    static func require(_ value: Bool, _ reason: String) throws { if !value { throw Failure.failed(reason) } }
    static func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return try e.encode(value) }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2]), resource = root.appendingPathComponent("resources")
        let contract = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeBodySurfaceMeasurements.json")), template = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBody.json")), rig = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBodyRig/rig.json"))
        let auxiliary = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeBodyFitAuxiliaryWeights.json"))
        let prepared = try F.Prepared(contractData: contract, templateData: template, rigData: rig, auxiliaryWeightsData: auxiliary)
        let catalog = try GarmentCodeParameterCatalog.load(from: resource.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        nonisolated struct Female: Decodable { nonisolated struct Parameters: Decodable { let body: [String: Double] }; let parameters: Parameters }
        let female = try JSONDecoder().decode(Female.self, from: Data(contentsOf: root.appendingPathComponent("female-standing-mesher-source.json")))
        var rows: [[String: Any]] = []
        for (name, raw) in [("default", catalog.body), ("female", female.parameters.body)] {
            let body = GarmentCodeBodyParameters(values: raw), source = try GarmentCodeStandardBody.load(body: body, resourceDirectory: resource), original = source.positions
            let result = prepared.fit(source: source, bodyValues: body.values)
            let oldRounding = fegetround()
            fesetround(FE_UPWARD)
            let unsupportedRounding = prepared.fit(source: source, bodyValues: body.values)
            fesetround(oldRounding)
            try require(unsupportedRounding.status == .invalidInput && unsupportedRounding.diagnosticMeasurement == nil, "Unsupported rounding cannot produce a draft acceptance")
            let roundingCalls = Mutex(0)
            let changedRounding = prepared.fit(source: source, bodyValues: body.values, isCancelled: {
                roundingCalls.withLock { $0 += 1; if $0 == 5000 { fesetround(FE_UPWARD) }; return false }
            })
            fesetround(oldRounding)
            try require(changedRounding.status == .invalidInput && changedRounding.diagnosticMeasurement == nil && changedRounding.residuals.count == 6, "Callback rounding changes fail closed with last measured residuals")
            try require(result.status == .draftSurfaceGoalsReached && result.residuals.count == 6 && result.residuals.allSatisfy { abs($0.observedMinusRequestedMeters) <= 1e-5 }, "Actual four-type fixed surface goals: " + name)
            try require(!result.bodyCapabilityIssued && result.requiresCompleteIntersectionAudit && !result.compatibleWithLegacyInverseSDF && !result.all26BodyFieldsIndependentlyFitted, "Draft cannot become a fitted collision body")
            try require(result.diagnosticMeasurement != nil && result.diagnosticMeasurement!.bodyValues == body.values && source.positions == original, "Actual source untouched and full values retained")
            try require(zip(result.iterations, result.iterations.dropFirst()).allSatisfy { $1.costSquareMeters < $0.costSquareMeters }, "Every committed iteration reduces actual surface cost")
            try encode(result).write(to: out.appendingPathComponent(name + "-attempt.json"))
            try encode(source.positions).write(to: out.appendingPathComponent(name + "-original-positions.json"))
            var options = F.Options(); options.maximumIterations = 0
            let zero = prepared.fit(source: source, bodyValues: body.values, options: options)
            try require(zero.status == .iterationBudget && zero.residuals.count == 6 && zero.diagnosticPositions == original, "Zero iteration budget retains real initial residuals")
            options = .init(); options.maximumEvaluations = 1
            let limited = prepared.fit(source: source, bodyValues: body.values, options: options)
            try require(limited.status == .evaluationBudget && limited.evaluations == 1 && limited.residuals.count == 6 && limited.diagnosticPositions == original, "Evaluation budget cannot publish a fabricated fit")
            options = .init(); options.maximumWorkingBytes = 1
            let memory = prepared.fit(source: source, bodyValues: body.values, options: options)
            try require(memory.status == .memoryBudget && memory.evaluations == 0 && memory.residuals.count == 6, "Memory reservation fail returns measured residuals")
            options = .init(); options.absoluteGoalToleranceMeters = .nan
            let invalid = prepared.fit(source: source, bodyValues: body.values, options: options)
            try require(invalid.status == .invalidOptions && invalid.residuals.count == 6, "Invalid options do not produce acceptance")
            let immediate = prepared.fit(source: source, bodyValues: body.values, isCancelled: { true })
            try require(immediate.status == .cancelled && immediate.evaluations == 0 && immediate.diagnosticPositions.isEmpty, "Immediate cancellation")
            let calls = Mutex(0)
            let cancelled = prepared.fit(source: source, bodyValues: body.values, isCancelled: { calls.withLock { $0 += 1; return $0 >= 5000 } })
            try require(cancelled.status == .cancelled && cancelled.residuals.count == 6 && cancelled.diagnosticMeasurement == nil, "Mid-fit cancellation returns last real residuals without complete report")
            var mismatched = body; mismatched.set(body["height"]! + 1, for: "height")
            let wrong = prepared.fit(source: source, bodyValues: mismatched.values)
            try require(wrong.status == .invalidInput && wrong.evaluations == 0 && wrong.residuals.count == 6, "Exact original source replay rejects mismatched canonical parameters")
            var missing = body.values; missing.removeValue(forKey: "arm_length")
            try require(prepared.fit(source: source, bodyValues: missing).status == .invalidInput, "Missing goals rejected")
            var impossible = body; impossible.set(1000, for: "wrist")
            options = .init(); options.maximumIterations = 4; options.maximumEvaluations = 64
            let bounded = prepared.fit(source: source, bodyValues: impossible.values, options: options)
            try require(bounded.status != .draftSurfaceGoalsReached && bounded.evaluations <= 64 && bounded.residuals.count == 6 && bounded.residuals.contains { abs($0.observedMinusRequestedMeters) > 1 }, "Unreachable bounded goal retains actual failure")
            try encode(bounded).write(to: out.appendingPathComponent(name + "-bounded-failure.json"))
            if name == "default" {
                let laterCalls = Mutex(0)
                let laterCancel = prepared.fit(source: source, bodyValues: body.values, isCancelled: { laterCalls.withLock { $0 += 1; return $0 >= 12000 } })
                try require(laterCancel.status == .cancelled && laterCancel.iterations.count >= 2 && laterCancel.diagnosticPositions != original && laterCancel.residuals.count == 6, "Cancellation after a committed draft retains its real improved residuals")
                let fullCalls = Mutex(0)
                let counted = prepared.fit(source: source, bodyValues: body.values, isCancelled: { fullCalls.withLock { $0 += 1; return false } })
                try require(counted.status == .draftSurfaceGoalsReached, "Counted actual fit completed")
                let publicationThreshold = fullCalls.withLock { $0 }
                let publicationCalls = Mutex(0)
                let publicationCancel = prepared.fit(source: source, bodyValues: body.values, isCancelled: { publicationCalls.withLock { $0 += 1; return $0 >= publicationThreshold } })
                try require(publicationCancel.status == .cancelled && publicationCancel.diagnosticMeasurement == nil && publicationCancel.residuals.count == 6, "Cancellation at final publication cannot return a converged status")
                try encode(laterCancel).write(to: out.appendingPathComponent("default-cancel-after-accepted.json"))
                try encode(publicationCancel).write(to: out.appendingPathComponent("default-cancel-publication.json"))
                let values = body.values
                let a = Task.detached { prepared.fit(source: source, bodyValues: values) }, b = Task.detached { prepared.fit(source: source, bodyValues: values) }
                let pair = await (a.value, b.value)
                try require(try encode(pair.0) == encode(pair.1), "Concurrent deterministic immutable fitter")
            }
            rows.append(["profile": name, "status": result.status.rawValue, "iterations": result.iterations.count - 1,
                "evaluations": result.evaluations, "maximumResidualMeters": result.residuals.map { abs($0.observedMinusRequestedMeters) }.max()!,
                "geometrySHA256": result.diagnosticMeasurement!.geometrySHA256, "cancelledAfterEvaluations": cancelled.evaluations,
                "boundedFailure": bounded.status.rawValue, "boundedFailureEvaluations": bounded.evaluations])
        }
        for (label, data, rd) in [("contract", contract + Data([32]), rig), ("rig", contract, rig + Data([32]))] {
            var rejected = false; do { _ = try F.Prepared(contractData: data, templateData: template, rigData: rd, auxiliaryWeightsData: auxiliary) } catch { rejected = true }
            try require(rejected, label + " byte binding")
        }
        do { _ = try F.Prepared(contractData: contract, templateData: template, rigData: rig, auxiliaryWeightsData: auxiliary, isCancelled: { true }); throw Failure.failed("Preparation cancellation") } catch is CancellationError {}
        let summary: [String: Any] = ["passed": true, "profiles": rows, "productionIntegrated": false, "bodyCapabilityIssued": false,
            "completeIntersectionAuditRequired": true, "controls": ["source-identity-and-parameters", "source-byte-binding", "zero-iteration", "evaluation-budget", "memory-budget", "nonfinite-option", "immediate-and-mid-cancel", "missing-goal", "unreachable-goal", "immutable-concurrent-determinism"]]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("swift-summary.json"))
        print(rows)
    }
}
