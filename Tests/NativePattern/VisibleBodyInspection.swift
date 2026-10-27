import Foundation
import Darwin

nonisolated private final class InspectorCancellation: @unchecked Sendable {
    // Test-only deterministic callback count, always protected by the lock.
    private let lock=NSLock();private var calls=0;private let limit:Int
    init(_ limit:Int = Int.max){self.limit=limit}
    func check()->Bool {lock.lock();defer{lock.unlock()};calls+=1;return calls>=limit}
    var count:Int {lock.lock();defer{lock.unlock()};return calls}
}

@main struct VisibleBodyInspectionRegression {
    typealias T = GarmentCodeVisibleBodyInspection
    typealias V = T.V
    enum Failure: Error { case check(String) }
    nonisolated static func require(_ b: Bool, _ s: String) throws { if !b { throw Failure.check(s) } }
    nonisolated static func object<A: Encodable>(_ a: A) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) }
    nonisolated static func points(_ a: Any) -> [V] {
        (a as! [[String: Any]]).map { .init(x: ($0["x"] as! NSNumber).doubleValue, y: ($0["y"] as! NSNumber).doubleValue, z: ($0["z"] as! NSNumber).doubleValue) }
    }
    nonisolated static func json(_ path: URL) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any] }
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let cube = [V(x:-0.5,y:-0.5,z:-0.5),V(x:0.5,y:-0.5,z:-0.5),V(x:0.5,y:0.5,z:-0.5),V(x:-0.5,y:0.5,z:-0.5),
            V(x:-0.5,y:-0.5,z:0.5),V(x:0.5,y:-0.5,z:0.5),V(x:0.5,y:0.5,z:0.5),V(x:-0.5,y:0.5,z:0.5)]
        let ids: [UInt32] = [0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
        let body = try T.Q.Prepared(positions: cube, triangleIndices: ids), sha = String(repeating: "a", count: 64)
        let p = try T.Prepared(sourceSHA256: sha, vertexCount: 3, triangleIndices: [0,1,2], body: body)
        let outside = [V(x:0.7,y:-0.1,z:-0.1), V(x:0.7,y:0.1,z:-0.1), V(x:0.7,y:0,z:0.1)]
        let r = try p.inspect(positions: outside)
        try require(r.meetsFinalBodyGate && r.completedAllSamples && r.expectedSamples == 7 && r.outsideSamples == 7,
            "All vertices, source-edge midpoints and face center must be independently checked")
        try require(r.vertexSamples == 3 && r.edgeMidpointSamples == 3 && r.triangleCentroidSamples == 1 &&
            r.surface.intersectingTrianglePairs == 0 && r.maximumPenetrationMeters == 0 && abs(r.minimumKnownUnsignedDistanceMeters!-0.2)<1e-14,
            "Outside analytic plane distances/counts")
        let interior = outside.map { V(x: 0.49, y: $0.y, z: $0.z) }, inside = try p.inspect(positions: interior)
        try require(inside.surface.intersectingTrianglePairs == 0 && inside.insideSamples == 7 && !inside.meetsFinalBodyGate &&
            abs(inside.maximumPenetrationMeters!-0.01)<1e-14, "Whole enclosed cloth must fail despite zero triangle crossings")
        let onSurface = try p.inspect(positions: outside.map { V(x:0.5,y:$0.y,z:$0.z) })
        try require(onSurface.onSurfaceSamples == 7 && !onSurface.meetsFinalBodyGate, "Surface tolerance cannot count as strictly outside")
        let crossed = try p.inspect(positions: [V(x:-0.7,y:0,z:0), V(x:0.7,y:0,z:0), V(x:0,y:0.7,z:0)])
        try require(crossed.outsideSamples >= 3 && crossed.insideSamples > 0 && crossed.surface.intersectingTrianglePairs > 0 && !crossed.meetsFinalBodyGate,
            "Outside vertices do not prove the cloth triangle is outside")
        let octahedron=[V(x:1,y:0,z:0),V(x:-1,y:0,z:0),V(x:0,y:1,z:0),V(x:0,y:-1,z:0),V(x:0,y:0,z:1),V(x:0,y:0,z:-1)]
        let octahedronIDs:[UInt32]=[0,2,4,4,2,1,1,2,5,5,2,0,4,3,0,1,3,4,5,3,1,0,3,5]
        let octahedronQuery=try T.Q.Prepared(positions:octahedron,triangleIndices:octahedronIDs)
        let edgeAligned=try T.Prepared(sourceSHA256:sha,vertexCount:3,triangleIndices:[0,1,2],body:octahedronQuery)
            .inspect(positions:[V(x:-2,y:0,z:-2),V(x:10,y:0,z:-2),V(x:-2,y:0,z:4)])
        try require(edgeAligned.allSamplesStrictlyOutside && edgeAligned.surface.intersectingTrianglePairs==0 &&
            edgeAligned.surfaceSeparation.status == .contactOrIndeterminate && !edgeAligned.meetsFinalBodyGate && edgeAligned.maximumPenetrationMeters==nil,
            "Edge-aligned penetration cannot pass merely because every finite sample is outside")
        let coplanar=try p.inspect(positions:[V(x:-2,y:0.5,z:-2),V(x:10,y:0.5,z:-2),V(x:-2,y:0.5,z:4)])
        try require(coplanar.allSamplesStrictlyOutside && coplanar.surface.intersectingTrianglePairs==0 &&
            coplanar.surfaceSeparation.status == .contactOrIndeterminate && !coplanar.meetsFinalBodyGate,
            "Coplanar overlap not seen by seven sample points must fail closed")
        let coplanarMiss=try p.inspect(positions:[V(x:0.7,y:0.5,z:0),V(x:0.8,y:0.5,z:0.1),V(x:0.8,y:0.5,z:-0.1)])
        try require(coplanarMiss.meetsFinalBodyGate && coplanarMiss.surfaceSeparation.status == .clear,
            "Coplanar but disjoint triangles need in-plane separation axes")
        var separationLimit=T.Limits();separationLimit.maximumSurfaceCandidatePairs=8
        let separationBudget=try T.Prepared(sourceSHA256:sha,vertexCount:3,triangleIndices:[0,1,2],body:octahedronQuery,limits:separationLimit)
            .inspect(positions:[V(x:-2,y:0,z:-2),V(x:10,y:0,z:-2),V(x:-2,y:0,z:4)])
        try require(separationBudget.completedAllSamples && separationBudget.surface.candidateTrianglePairs==8 &&
            separationBudget.surfaceSeparation.status == .budgetExceeded && separationBudget.stopReason == .surfaceSeparationBudget &&
            separationBudget.maximumPenetrationMeters==nil && !separationBudget.meetsFinalBodyGate,
            "Legacy and independent surface phases must share the unchanged pair budget")
        var sampleLimit = T.Limits(); sampleLimit.maximumSamples = 3
        let limited = try T.Prepared(sourceSHA256: sha, vertexCount: 3, triangleIndices: [0,1,2], body: body, limits: sampleLimit).inspect(positions: outside)
        try require(limited.stopReason == .sampleBudget && limited.examinedSamples == 3 && !limited.completedAllSamples &&
            limited.maximumPenetrationMeters == nil && !limited.meetsFinalBodyGate, "Partial samples cannot return final penetration or pass")
        var parityLimit = T.Limits(); parityLimit.query.maximumRayNodeVisits = 0
        let unresolved = try T.Prepared(sourceSHA256: sha, vertexCount: 3, triangleIndices: [0,1,2], body: body, limits: parityLimit).inspect(positions: outside)
        try require(unresolved.stopReason == .unresolvedQuery && unresolved.uncertainSamples == 1 &&
            unresolved.maximumPenetrationMeters == nil && !unresolved.meetsFinalBodyGate, "Unresolved parity must fail closed")
        var totalLimit = T.Limits(); totalLimit.maximumTotalNodeVisits = 1
        let exhausted = try T.Prepared(sourceSHA256: sha, vertexCount: 3, triangleIndices: [0,1,2], body: body, limits: totalLimit).inspect(positions: outside)
        try require(exhausted.totalNodeVisits <= 1 && !exhausted.meetsFinalBodyGate && exhausted.maximumPenetrationMeters == nil, "Whole-run work cap")
        do { _ = try p.inspect(positions: outside, isCancelled: { true }); throw Failure.check("Cancellation ignored") } catch is CancellationError {}
        let probe=InspectorCancellation()
        _=try p.inspect(positions:outside,isCancelled:{probe.check()})
        // After all point queries there are four callbacks in this one-face
        // miss: SAT face, SAT root, SAT completion, wrapper completion.
        // This threshold therefore cancels at the new SAT root traversal.
        let duringSAT=InspectorCancellation(probe.count-2),originalOutside=outside
        var cancelledInSAT=false
        do {_=try p.inspect(positions:outside,isCancelled:{duringSAT.check()})}
        catch is CancellationError {cancelledInSAT=true}
        try require(cancelledInSAT && outside==originalOutside && p.body.positions==cube,
            "Cancellation during final SAT must return no partial proof or mutate geometry")
        try require(try p.inspect(positions:outside).meetsFinalBodyGate,"Cancelled immutable inspector must remain reusable")
        let oldRounding=fegetround()
        try require(fesetround(FE_UPWARD)==0,"Rounding test unavailable")
        var roundingRejected=false
        do {_=try p.inspect(positions:outside)} catch T.InspectionError.invalid {roundingRejected=true} catch {}
        try require(fesetround(oldRounding)==0,"Restore rounding")
        try require(roundingRejected,"SAT cannot silently use unsupported rounding")
        do { _ = try p.inspect(positions: Array(outside.dropLast())); throw Failure.check("Wrong vertex count accepted") } catch T.InspectionError.invalid {}
        do {
            var weak = T.Limits(); weak.query.requiredAgreeingDirections = 1
            _ = try T.Prepared(sourceSHA256: sha, vertexCount: 3, triangleIndices: [0,1,2], body: body, limits: weak)
            throw Failure.check("Weakened parity accepted")
        } catch T.InspectionError.invalid {}
        let translated = try p.inspect(positions: outside.map { $0+V(x:0.01,y:0,z:0) })
        try require(r.clothStateSHA256 != translated.clothStateSHA256 && r.bodyGeometrySHA256 == translated.bodyGeometrySHA256 &&
            r.sourceSHA256 == sha && outside[0].x == 0.7, "Proof must bind current cloth/body/source and never project positions")
        var replays: [[String: Any]] = []
        let replayRoot = out.appendingPathComponent("replays")
        if FileManager.default.fileExists(atPath: replayRoot.path) {
            for dir in try FileManager.default.contentsOfDirectory(at: replayRoot, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                let input = try json(dir.appendingPathComponent("complete-initial-input.json")), state = try json(dir.appendingPathComponent("state.json"))
                let q = try T.Q.Prepared(positions: points(input["bodyPositions"]!), triangleIndices: (input["bodyTriangleIndices"] as! [NSNumber]).map(\.uint32Value))
                let x = points(state["positions"]!), initial = points(input["positions"]!)
                let t = try T.Prepared(sourceSHA256: input["sourceSHA256"] as! String, vertexCount: initial.count,
                    triangleIndices: (input["triangleIndices"] as! [NSNumber]).map(\.uint32Value), body: q)
                let initialProof = try t.inspect(positions: initial), candidateProof = try t.inspect(positions: x)
                try require(initialProof.meetsFinalBodyGate && candidateProof.meetsFinalBodyGate, "Actual complete source visible-body inspection: "+dir.lastPathComponent)
                replays.append(["name":dir.lastPathComponent,"initial":try object(initialProof),"candidate":try object(candidateProof),
                    "completeGarmentAccepted":false,"note":"Static body check only; no sewing, self-motion, gravity or convergence acceptance implied"])
            }
        }
        let summary: [String: Any] = ["passed":true,"analyticGroups":17,"cancelledDuringSAT":cancelledInSAT,"unsupportedRoundingRejected":roundingRejected,"outside":try object(r),"enclosed":try object(inside),
            "crossed":try object(crossed),"onSurface":try object(onSurface),"sampleBudget":try object(limited),"parityBudget":try object(unresolved),
            "edgeAligned":try object(edgeAligned),"coplanarOverlap":try object(coplanar),"coplanarMiss":try object(coplanarMiss),
            "surfaceSeparationBudget":try object(separationBudget),
            "replays":replays,"completeGarmentAccepted":false]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("visible-body-inspection-summary.json"), options: .atomic)
        print("PASS final visible-body inspection controls; replay cases", replays.count)
    }
}
