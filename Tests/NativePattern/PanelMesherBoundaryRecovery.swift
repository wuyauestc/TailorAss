import Foundation
import CryptoKit

/// Exact former failure input, checked with the independent original mesh
/// boundary/area/manifold oracle. Elapsed time stays outside mesh JSON.
@main @MainActor struct PanelMesherBoundaryRecoveryRegression {
    typealias M=GarmentCodePanelMesher
    enum Failure:Error{case check(String)}
    static func require(_ condition:Bool,_ message:String)throws{if !condition{throw Failure.check(message)}}
    static func encoded<T:Encodable>(_ x:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];return try e.encode(x)}
    final class Polls:@unchecked Sendable {
        private let lock=NSLock();private var count=0
        let limit:Int
        init(_ limit:Int=Int.max){self.limit=limit}
        func cancel()->Bool{lock.lock();defer{lock.unlock()};count += 1;return count>=limit}
        func value()->Int{lock.lock();defer{lock.unlock()};return count}
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source=root.appendingPathComponent("Tests/NativePattern/Fixtures/female-standing-mesher-source.json"),bytes=try Data(contentsOf:source)
        let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        try require(hash=="b7d81ac6fe6517b92515c40c5cda9077d6b4786c4ca540a6bdcbdb5f90d96dae","former failure source was edited")
        let doc=try GarmentCodePatternFile.validatedImport(from:bytes),panels=try doc.geometryPanels()
        var rows:[[String:Any]]=[]
        for id in ["left_sleeve_f","right_sleeve_f"] {for target in [0.04,0.035,0.03] {
            let panel=panels[id]!,start=ProcessInfo.processInfo.systemUptime
            let mesh=try M.prepare(panel:panel,targetEdgeMeters:target,flatnessMeters:0.00005,maximumVertices:6000,maximumTriangles:16000)
            let elapsed=ProcessInfo.processInfo.systemUptime-start
            let independent=try PanelMesherRegression.check(mesh,panel:panel,target:target,flatness:0.00005)
            guard let recovery=mesh.boundaryRecovery else{throw Failure.check("former failure no longer exercises the explicit recovery")}
            try require(recovery.attempts==2 && recovery.originalRefinementRounds==79 && recovery.originalRoundChecks==80 && recovery.recoveryRefinementRounds<80 && recovery.recoveryRoundChecks==recovery.recoveryRefinementRounds+1,"actual extra attempts/rounds not disclosed")
            try require(mesh.quality.minimumAngleDegrees>10 && mesh.flatPositions.count<=6000 && mesh.triangleIndices.count/3<=16000,"standing mesh regressed in quality or exceeds its original V/T budget")
            try require(abs(recovery.maximumBoundarySpacingMeters-target/4)<1e-14,"recovery spacing does not follow the caller target")
            rows.append(independent.merging(["targetMeters":target,"attempts":recovery.attempts,"originalRefinementRounds":recovery.originalRefinementRounds,"recoveryRefinementRounds":recovery.recoveryRefinementRounds,"totalRoundChecks":recovery.originalRoundChecks+recovery.recoveryRoundChecks,"elapsedSeconds":elapsed]){_,b in b})
            print("PASS",id,target,"attempts",recovery.attempts,"rounds",recovery.originalRefinementRounds,recovery.recoveryRefinementRounds,"seconds",elapsed)
        }}
        let panel=panels["left_sleeve_f"]!,target=0.04
        let combined=Polls(),recovered=try M.prepare(panel:panel,targetEdgeMeters:target,maximumVertices:6000,maximumTriangles:16000,isCancelled:{combined.cancel()})
        let explicit=Polls(),spacing=Dictionary(uniqueKeysWithValues:panel.edges.indices.map{($0,target/4)})
        let dense=try M.prepare(panel:panel,targetEdgeMeters:target,maximumVertices:6000,maximumTriangles:16000,maximumBoundarySpacingMeters:spacing,isCancelled:{explicit.cancel()})
        try require(dense.boundaryRecovery==nil,"explicit dense input unexpectedly needed a third attempt")
        let full=combined.value(),second=explicit.value(),between=full-second
        try require(full>second+1 && second>2,"cancellation probes did not cover both real attempts")
        // The second call is the exact same source/spacing as the recovery.
        // Removing its poll count identifies the explicit between-attempt check.
        for (tag,limit) in [("before sampling",1),("between attempts",between),("during recovery",full-1)] {
            let probe=Polls(limit);var cancelled=false
            do{_=try M.prepare(panel:panel,targetEdgeMeters:target,maximumVertices:6000,maximumTriangles:16000,isCancelled:{probe.cancel()})}catch is CancellationError{cancelled=true}
            try require(cancelled && probe.value()==limit,"cancellation was ignored \(tag)")
            print("PASS cancellation",tag,"poll",limit)
        }
        var unchanged=recovered;unchanged.boundaryRecovery=nil
        try require(try encoded(unchanged)==encoded(dense),"fallback changed source geometry or numerical algorithm beyond its explicit boundary spacing")
        let json=try JSONSerialization.jsonObject(with:encoded(dense)) as! [String:Any]
        try require(json["boundaryRecovery"]==nil,"nil recovery field changed old mesh JSON")
        let decoded=try JSONDecoder().decode(M.Mesh.self,from:encoded(dense))
        try require(decoded.boundaryRecovery==nil,"old mesh JSON missing optional diagnostics cannot decode")
        // At 30 mm the original failed pass stays below 260 V, while the
        // exact denser rebuild needs 305. It must fail with both reasons.
        var rejectedBudget=false,budgetReason=""
        do{_=try M.prepare(panel:panel,targetEdgeMeters:0.03,maximumVertices:260,maximumTriangles:16000)}
        catch M.MesherError.budgetExceeded(let reason){budgetReason=reason;rejectedBudget=reason.contains("内部网格细化未能收敛") && reason.contains("同源边界加密后仍失败") && reason.contains("所需顶点或三角面超过上限")}
        try require(rejectedBudget,"fallback hid original/recovery failure or exceeded V budget")
        let finer=try M.prepare(panel:panel,targetEdgeMeters:0.04,maximumVertices:6000,maximumTriangles:16000,maximumBoundarySpacingMeters:[0:0.005])
        _=try PanelMesherRegression.check(finer,panel:panel,target:0.04,flatness:0.00005)
        let b=finer.boundaries[0]
        try require(zip(b.arcFractions,b.arcFractions.dropFirst()).allSatisfy{($1-$0)*b.sourceLengthMeters<=0.005*(1+1e-10)},"recovery loosened an already finer boundary override")
        try require(try Data(contentsOf:source)==bytes,"meshing rewrote original source")
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_BOUNDARY_RECOVERY_OUTPUT"] ?? "/private/tmp/TailorAssBoundaryRecovery")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let report:[String:Any]=["passed":true,"sourceSHA256":hash,"rows":rows,"formerFailureCases":rows.count,"cancellationPolls":["combined":full,"explicitDense":second,"betweenAttempts":between,"duringRecovery":full-1],"twoStageBudgetFailure":budgetReason,"existingTighterOverridePreserved":true,"oldNilDiagnosticsJSONUnchanged":true,"scope":"Exact original source, independent full boundary/area/manifold/max-edge checks, two bounded attempts with unchanged flatness/target/V/T. Extra total rounds and wall time explicitly reported. Not physical garment acceptance."]
        try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:out.appendingPathComponent("boundary-recovery-proof.json"))
        print("PASS exact-source bounded boundary recovery, cancellation, original budgets and compatibility")
    }
}
