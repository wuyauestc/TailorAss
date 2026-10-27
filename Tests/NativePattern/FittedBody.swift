import Foundation
import Synchronization
import Darwin

@main @MainActor struct FittedBodyRegression {
    typealias FB = GarmentCodeFittedBody
    typealias M = GarmentCodeBodySurfaceMeasurements
    enum Failure: Error { case failed(String) }
    static func require(_ value: Bool, _ reason: String) throws { if !value { throw Failure.failed(reason) } }
    static func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return try e.encode(value) }
    static func reject(_ label: String, _ work: () throws -> Void) throws { do { try work() } catch { return }; throw Failure.failed("Expected rejection: " + label) }
    static func rejectAsync(_ label: String, _ work: @escaping @Sendable () throws -> Void) async throws {
        do { try await Task.detached { try work() }.value } catch { return }; throw Failure.failed("Expected rejection: " + label)
    }
    nonisolated struct Export: Encodable {
        let bindings: FB.Bindings, positions: [M.V], triangleIndices: [UInt32]
        let restMeasurements: M.Report, restGeometry: GarmentCodeBodySurfaceValidator.Report, finalGeometry: GarmentCodeBodySurfaceValidator.Report
        let fitting: FB.FittingSummary?
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2]), resource = root.appendingPathComponent("resources")
        let catalog = try GarmentCodeParameterCatalog.load(from: resource.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        nonisolated struct Female: Decodable { nonisolated struct Parameters: Decodable { let body: [String: Double] }; let parameters: Parameters }
        let female = try JSONDecoder().decode(Female.self, from: Data(contentsOf: root.appendingPathComponent("female-standing-mesher-source.json")))
        let captured = try FB.resources(resourceDirectory: resource)
        let contract = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeBodySurfaceMeasurements.json")), template = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBody.json")), rig = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeStandardBodyRig/rig.json")), aux = try Data(contentsOf: resource.appendingPathComponent("GarmentCodeBodyFitAuxiliaryWeights.json"))
        var rows: [[String: Any]] = []
        for (name, raw) in [("default", catalog.body), ("female", female.parameters.body)] {
            let body = GarmentCodeBodyParameters(values: raw), values = body.values
            let source = try GarmentCodeStandardBody.load(body: body, resourceDirectory: resource), original = source.positions
            let pose = FB.PosePolicy.matchPatternReference(alphaDegrees: values["arm_pose_angle"]!)
            let request = try FB.captureFit(source: source, bodyValues: values, pose: pose, resourceDirectory: resource)
            let prepared = try await Task.detached { try FB.fitAndPrepare(request) }.value
            let surface = prepared.surface
            try require(prepared.fittingSummary?.status == .draftSurfaceGoalsReached && surface.matchesPatternReference && !surface.compatibleWithLegacyInverseSDF && !surface.anatomicalFitCertified, "Actual opt-in fit then complete preparation")
            try require(surface.bodyValues == values && source.positions == original && surface.bindings.bodyValues.count == 33 && surface.bindings.controls.count == 4, "Same complete source values and original source unchanged")
            try require(prepared.finalGeometryReport.completedAllPairs && prepared.restGeometryReport.completedAllPairs && surface.geometrySHA256 == prepared.exactQueries.geometrySHA256 && surface.geometrySHA256 == prepared.poseData.geometrySHA256, "Full actual geometry and Q bindings")
            try surface.verify(positions: surface.mesh.positions, triangleIndices: surface.mesh.triangleIndices, bodyValues: values)
            let recipe = FB.recipe(source: source, bodyValues: values, controls: surface.controls, pose: pose, resources: captured)
            try surface.verify(recipe: recipe)
            let on = prepared.exactQueries.query(surface.mesh.positions[0]), inside = prepared.exactQueries.query(.zero), outside = prepared.exactQueries.query(.init(x: 3, y: 3, z: 3))
            try require(on.classification == .onSurface && on.signedDistanceMeters == 0 && inside.classification == .inside && inside.signedDistanceMeters! < 0 && outside.classification == .outside && outside.signedDistanceMeters! > 0, "Actual final mesh on/inside/outside Q queries")
            let export = Export(bindings: surface.bindings, positions: surface.mesh.positions, triangleIndices: surface.mesh.triangleIndices,
                                restMeasurements: prepared.restMeasurements, restGeometry: prepared.restGeometryReport, finalGeometry: prepared.finalGeometryReport, fitting: prepared.fittingSummary)
            try encode(export).write(to: out.appendingPathComponent(name + "-prepared.json"))
            try encode(prepared.poseData).write(to: out.appendingPathComponent(name + "-pose.json"))
            try encode([on, inside, outside]).write(to: out.appendingPathComponent(name + "-queries.json"))
            var wrong = surface.mesh.positions; wrong[0].x += 1e-6
            try reject("actual surface replacement") { try surface.verify(positions: wrong, triangleIndices: surface.mesh.triangleIndices, bodyValues: values) }
            var indices = surface.mesh.triangleIndices; indices.swapAt(0, 1)
            try reject("source face replacement") { try surface.verify(positions: surface.mesh.positions, triangleIndices: indices, bodyValues: values) }
            var other = body; other.set(values["underbust"]! + 1, for: "underbust")
            try reject("unused source parameter replacement") { try surface.verify(positions: surface.mesh.positions, triangleIndices: surface.mesh.triangleIndices, bodyValues: other.values) }
            var changedControls = surface.controls; changedControls[0] = changedControls[0].nextUp
            let changed = FB.recipe(source: source, bodyValues: values, controls: changedControls, pose: pose, resources: captured)
            try reject("controls request replacement") { try surface.verify(recipe: changed) }
            let wrongPose = FB.PosePolicy.matchPatternReference(alphaDegrees: values["arm_pose_angle"]!.nextUp)
            let changedPose = FB.recipe(source: source, bodyValues: values, controls: surface.controls, pose: wrongPose, resources: captured)
            try reject("pose metadata replacement") { try surface.verify(recipe: changedPose) }
            try await rejectAsync("wrong actual requested pattern pose") { _ = try FB.prepare(changedPose) }
            let noFit = FB.recipe(source: source, bodyValues: values, controls: [0, 0, 0, 0], pose: pose, resources: captured)
            try await rejectAsync("unmet six actual goals") { _ = try FB.prepare(noFit) }
            var limited = FB.Limits(); limited.maximumEstimatedWorkingBytes = 1
            let memoryLimit = limited
            try await rejectAsync("factory memory reservation") { _ = try FB.prepare(recipe, limits: memoryLimit) }
            limited = .init(); limited.surfaceValidation.maximumCandidatePairs = 1
            let geometryLimit = limited
            try await rejectAsync("complete geometry budget") { _ = try FB.prepare(recipe, limits: geometryLimit) }
            limited = .init(); limited.queries.maximumBVHNodes = 1
            let queryLimit = limited
            try await rejectAsync("actual Q index budget") { _ = try FB.prepare(recipe, limits: queryLimit) }
            var fitOptions = GarmentCodeBodySurfaceFitter.Options(); fitOptions.maximumEvaluations = 1
            let fitLimit = fitOptions
            var failedWithRealResiduals = false
            do { _ = try await Task.detached { try FB.fitAndPrepare(request, options: fitLimit) }.value }
            catch let FB.PreparationError.fittingRejected(status, residuals, evaluations) { failedWithRealResiduals = status == .evaluationBudget && residuals.count == 6 && evaluations == 1 }
            try require(failedWithRealResiduals, "Bounded optimizer failure retains real residuals without receipt")
            do { _ = try await Task.detached { try FB.prepare(recipe, isCancelled: { true }) }.value; throw Failure.failed("Immediate cancellation returned receipt") } catch is CancellationError {}
            let calls = Mutex(0)
            do { _ = try await Task.detached { try FB.prepare(recipe, isCancelled: { calls.withLock { $0 += 1; return $0 >= 2000 } }) }.value; throw Failure.failed("Mid replay cancellation returned receipt") } catch is CancellationError {}
            let finalCalls = Mutex(0)
            let counted = try await Task.detached { try FB.prepare(recipe, isCancelled: { finalCalls.withLock { $0 += 1; return false } }) }.value
            let threshold = finalCalls.withLock { $0 }, publicationCalls = Mutex(0)
            do { _ = try await Task.detached { try FB.prepare(recipe, isCancelled: { publicationCalls.withLock { $0 += 1; return $0 >= threshold } }) }.value; throw Failure.failed("Publication cancellation returned receipt") } catch is CancellationError {}
            try require(counted.surface.geometrySHA256 == surface.geometrySHA256, "Fixed-control replay matches actual optimization pipeline")
            let rounding = Mutex(0)
            let roundingRejected = await Task.detached { () -> Bool in
                let old = fegetround(); defer { fesetround(old) }
                do { _ = try FB.prepare(recipe, isCancelled: { rounding.withLock { $0 += 1; if $0 == 2000 { fesetround(FE_UPWARD) }; return false } }); return false }
                catch FB.PreparationError.unsupportedRounding { return true } catch { return false }
            }.value
            try require(roundingRejected, "Callback rounding change cannot publish receipt")
            rows.append(["profile": name, "sourceGeometrySHA256": surface.bindings.sourceGeometrySHA256, "fittedRestGeometrySHA256": surface.bindings.fittedRestGeometrySHA256,
                "finalGeometrySHA256": surface.geometrySHA256, "fitRecipeSHA256": surface.fitRecipeSHA256, "poseRecipeSHA256": surface.poseRecipeSHA256,
                "maximumGoalResidualMeters": surface.bindings.maximumRestGoalResidualMeters, "restCandidates": prepared.restGeometryReport.candidateTrianglePairs,
                "finalCandidates": prepared.finalGeometryReport.candidateTrianglePairs, "fittingEvaluations": prepared.fittingSummary!.evaluations])
        }
        // A zero-control surface that really meets its chosen project targets
        // may coincide with the old mesh; the new type still has no SDF power.
        var zeroBody = GarmentCodeBodyParameters(values: catalog.body)
        let base = try GarmentCodeStandardBody.load(body: zeroBody, resourceDirectory: resource)
        let measurer = try M.Prepared(contractData: contract, templateData: template, rigData: rig)
        let initial = try measurer.measure(positions: base.positions, triangleIndices: base.triangleIndices, bodyValues: zeroBody.values)
        for (key, id) in [("bust", "chestSurfaceReference"), ("shoulder_w", "shoulderLateralSurfaceWidth"), ("arm_length", "outerArmSurfaceRoute.L"), ("wrist", "wristSurfaceLoop.L")] {
            zeroBody.set(initial.measurements.first { $0.definition.id == id }!.observedMeters * 100, for: key)
        }
        let zeroSource = try GarmentCodeStandardBody.load(body: zeroBody, resourceDirectory: resource)
        let zero = FB.recipe(source: zeroSource, bodyValues: zeroBody.values, controls: [0, 0, 0, 0], pose: .fittedReference, resources: captured)
        let identity = try await Task.detached { try FB.prepare(zero) }.value
        try require(identity.surface.mesh.positions == zeroSource.positions && !identity.surface.matchesPatternReference && !identity.surface.compatibleWithLegacyInverseSDF, "Identity coincidence has no legacy or pattern-reference privileges")
        try identity.surface.verify(positions: identity.surface.mesh.positions, triangleIndices: identity.surface.mesh.triangleIndices, bodyValues: zeroBody.values, requirePatternReference: false)
        try reject("reference role cannot claim pattern pose") { try identity.surface.verify(positions: identity.surface.mesh.positions, triangleIndices: identity.surface.mesh.triangleIndices, bodyValues: zeroBody.values) }
        try reject("main-thread heavy preparation") { _ = try FB.prepare(zero) }
        var limits = FB.Limits(); limits.maximumCapturedResourceBytes = 1
        try reject("bounded file capture") { _ = try FB.resources(resourceDirectory: resource, limits: limits) }
        let altered = try FB.Resources(templateData: template + Data([32]), rigData: rig, contractData: contract, auxiliaryWeightsData: aux)
        let bad = FB.recipe(source: base, bodyValues: GarmentCodeBodyParameters(values: catalog.body).values, controls: [0, 0, 0, 0], pose: .fittedReference, resources: altered)
        try await rejectAsync("resource-byte replacement") { _ = try FB.prepare(bad) }
        let summary: [String: Any] = ["passed": true, "profiles": rows, "identitySurfaceGeometrySHA256": identity.surface.geometrySHA256,
            "controls": ["resources", "controls", "pose", "parameters", "actual-mesh", "faces", "goals", "memory", "complete-surface-budget", "Q-index-budget", "optimizer-budget-real-residuals", "immediate-mid-publication-cancel", "callback-RNE", "identity-no-SDF-or-pattern-privilege", "main-thread-rejection"],
            "newPrivateReceiptIssuedAfterFullReplayAndValidation": true, "legacyBodyOrSDFModified": false, "clothSimulationRun": false]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("swift-summary.json"))
        print(rows)
    }
}
