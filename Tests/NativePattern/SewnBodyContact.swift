import Foundation
import CryptoKit

nonisolated private final class SewnContactCounter:@unchecked Sendable {
    private let lock=NSLock()
    private var value=0
    func next()->Int {lock.lock();defer{lock.unlock()};value += 1;return value}
    var count:Int {lock.lock();defer{lock.unlock()};return value}
}

@main @MainActor
struct SewnBodyContactRegression {
    typealias C=GarmentCodeSewnBodyContact
    typealias S=GarmentCodeSewing
    typealias V=C.Vector3
    enum Failure:Error {case check(String)}
    static func require(_ v:@autoclosure()throws->Bool,_ message:String)throws {if try !v(){throw Failure.check(message)}}
    static func near(_ a:Double,_ b:Double,_ message:String,tolerance:Double=1e-11)throws {try require(abs(a-b)<=tolerance,"\(message): \(a) vs \(b)")}
    static func log(_ s:String){FileHandle.standardError.write(Data((s+"\n").utf8))}
    static func sha(_ d:Data)->String{SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    static func encode<T:Encodable>(_ v:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(v)}
    nonisolated static let plane:@Sendable(V)->V = {p in .init(x:p.x,y:max(0,p.y),z:p.z)}
    static func point(_ a:S.Attachment,_ p:[V])->V {zip(a.vertexIDs,a.weights).reduce(.zero){$0+p[$1.0]*$1.1}}

    nonisolated static func actorFreeAPI()throws {
        let a=try S.Attachment(vertexIDs:[0,1],weights:[0.5,0.5])
        let prepared=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:[1,1])
        var positions=[V(x:-0.1,y:-0.001,z:0),V(x:0.1,y:-0.001,z:0)]
        _=try prepared.project(positions:&positions,projectPoint:plane)
    }
    static func analytic()throws->[String:Any] {
        let mid=try S.Attachment(vertexIDs:[0,1],weights:[0.5,0.5]),radius=1.0025,angle=0.1
        var chord=[V(x:-radius*sin(angle),y:0,z:radius*cos(angle)),V(x:radius*sin(angle),y:0,z:radius*cos(angle))]
        let before=chord,prepared=try C.Prepared(vertexCount:2,attachments:[mid],normalizedInverseMass:[1,1])
        let sphere:@Sendable(V)->V={p in p.length<radius ? p*(radius/max(1e-20,p.length)) : p}
        let verticesOnly=chord.map(sphere)
        try require(verticesOnly==chord && point(mid,chord).length<radius-0.004,"Sphere fixture must have exterior source vertices and an interior chord midpoint")
        let stats=try prepared.project(positions:&chord,projectPoint:sphere)
        try near(point(mid,chord).length,radius,"Virtual chord point did not reach the analytic shell")
        try near((chord[0]-before[0]).z,radius*(1-cos(angle)),"Equal-mass chord correction")
        try require(stats.projectedAttachments==1 && stats.maximumFinalResidualMeters<1e-12 && stats.unresolvedFinalAttachments==0,"Analytic shell contact residual was not measured honestly")
        let repeated=try prepared.project(positions:&chord,projectPoint:sphere)
        try require(repeated.projectedAttachments==0,"Cached contact graph cannot be reused on an already exterior point")

        let weighted=try S.Attachment(vertexIDs:[0,1],weights:[0.25,0.75])
        let graph=try C.Prepared(vertexCount:2,attachments:[weighted],normalizedInverseMass:[1,3])
        var p=[V(x:-0.1,y:-0.004,z:0),V(x:0.1,y:-0.004,z:0)]
        let w0=p,den=1*0.25*0.25+3*0.75*0.75
        let weightedStats=try graph.project(positions:&p,projectPoint:plane)
        try near(p[0].y-w0[0].y,0.004*0.25/den,"First original inverse-mass coefficient")
        try near(p[1].y-w0[1].y,0.004*3*0.75/den,"Second original inverse-mass coefficient")
        try near(point(weighted,p).y,0,"Weighted affine point correction")
        try require(weightedStats.maximumFinalResidualMeters<1e-12,"Weighted plane correction left an unreported residual")
        p=[V(x:-0.1,y:0.001,z:0),V(x:0.1,y:0.002,z:0)]
        let exterior=p,exteriorStats=try graph.project(positions:&p,projectPoint:plane)
        try require(p==exterior && exteriorStats.projectedAttachments==0,"A plane with both endpoints outside acquired a false chord penetration")

        let mixed=try C.Prepared(vertexCount:2,attachments:[weighted],normalizedInverseMass:[1,0])
        p=w0;let pinned=p[1]
        let pinnedStats=try mixed.project(positions:&p,projectPoint:plane)
        try require(p[1]==pinned && pinnedStats.unresolvedPinnedAttachments==0,"Mixed fixed/free attachment moved a source pin")
        try near(p[0].y-w0[0].y,0.004/0.25,"One movable coefficient must carry the full virtual correction")
        try near(point(weighted,p).y,0,"Mixed-pin affine correction")
        let allFixed=try C.Prepared(vertexCount:2,attachments:[weighted],normalizedInverseMass:[0,0])
        p=w0;let immobile=try allFixed.project(positions:&p,projectPoint:plane)
        try require(p==w0 && immobile.unresolvedPinnedAttachments==1 && immobile.unresolvedFinalAttachments==1 && immobile.maximumFinalResidualMeters>0.0039,"An immobile penetration was falsely reported as solved")
        let conditioned=try C.Prepared(vertexCount:2,attachments:[weighted],normalizedInverseMass:[1e-30,0])
        p=w0;let tiny=try conditioned.project(positions:&p,projectPoint:plane)
        try require(p==w0 && tiny.unresolvedConditionedAttachments==1 && tiny.unresolvedPinnedAttachments==0 && tiny.unresolvedFinalAttachments==1,"A tiny nonzero effective mass was falsely labeled fixed or solved")

        p=[V(x:-0.1,y:-1,z:0),V(x:0.1,y:-1,z:0)]
        let cappedBefore=p,capped=try graph.project(positions:&p,projectPoint:plane)
        try near((p[1]-cappedBefore[1]).length,0.02,"Single 20mm cap")
        try near((p[1]-cappedBefore[1]).length/(p[0]-cappedBefore[0]).length,9,"Common cap scaling changed the original inverse-mass ratio")
        try require(capped.cappedAttachments==1 && capped.maximumSingleVertexCorrectionMeters<=0.02+1e-12 && capped.maximumFinalResidualMeters>0.98,"Capped projection hid its true residual")

        let duplicate=try S.Attachment(vertexIDs:[1,0,1],weights:[0.2,0.5,0.3]),vertex=try S.Attachment(vertexID:2)
        let unique=try C.Prepared(vertexCount:3,attachments:[mid,duplicate,mid,vertex,vertex],normalizedInverseMass:[1,1,1])
        try require(unique.providedAttachmentCount==5 && unique.uniqueVirtualAttachmentCount==1 && unique.skippedUniqueVertexAttachmentCount==1,"Canonical duplicate or one-vertex attachments were repeatedly processed")
        p=[V(x:-0.1,y:-0.001,z:0),V(x:0.1,y:-0.001,z:0),V(x:0,y:-0.01,z:0)]
        let skipped=p[2],uniqueStats=try unique.project(positions:&p,projectPoint:plane)
        try require(uniqueStats.examinedAttachments==1 && p[2]==skipped,"Virtual helper silently replaced the caller's separate source-vertex body contact")
        let a=try S.Attachment(vertexIDs:[0,1],weights:[0.5,0.5]),b=try S.Attachment(vertexIDs:[1,2],weights:[0.5,0.5])
        let shared=try C.Prepared(vertexCount:3,attachments:[a,b],normalizedInverseMass:[1,1,1])
        p=[V(x:-2,y:-0.001,z:0),V(x:0,y:-0.001,z:0),V(x:2,y:0.001,z:0)]
        let conflicting:@Sendable(V)->V={p in .init(x:p.x,y:p.x<0 ? max(0,p.y) : min(0,p.y),z:p.z)}
        let reopened=try shared.project(positions:&p,projectPoint:conflicting)
        try require(reopened.projectedAttachments==2 && reopened.unresolvedFinalAttachments==1,"A later shared-vertex update reopened an earlier contact without being measured")
        try near(reopened.maximumFinalResidualMeters,0.00025,"Post-pass residual must be recomputed")
        log("PASS analytic curved-shell chord, weighted affine correction, fixed points, exact common cap, canonical graph reuse and reopened-contact residual")
        return ["passed":true,"sphereInitialMidpointPenetrationMeters":radius-point(mid,before).length,
            "sphereFinalResidualMeters":stats.maximumFinalResidualMeters,"cappedTrueResidualMeters":capped.maximumFinalResidualMeters,
            "reopenedTrueResidualMeters":reopened.maximumFinalResidualMeters]
    }

    static func failures()throws->[String:Any] {
        let a=try S.Attachment(vertexIDs:[0,1],weights:[0.5,0.5])
        var cases=0
        func reject(_ action:()throws->Void)throws {var bad=false;do{try action()}catch C.ContactError.invalid{bad=true}catch C.ContactError.budgetExceeded{bad=true};try require(bad,"Invalid virtual body contact was accepted");cases += 1}
        try reject{_=try C.Prepared(vertexCount:0,attachments:[a],normalizedInverseMass:[])}
        try reject{_=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:[1])}
        for weights in [[-1.0,1.0],[Double.nan,1],[Double.infinity,1],[1e13,1]] {try reject{_=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:weights)}}
        let outside=try S.Attachment(vertexIDs:[0,5],weights:[0.5,0.5])
        try reject{_=try C.Prepared(vertexCount:2,attachments:[outside],normalizedInverseMass:[1,1])}
        try reject{_=try C.Prepared(vertexCount:2,attachments:[a,a],normalizedInverseMass:[1,1],maximumAttachments:1)}
        let graph=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:[1,1])
        let initial=[V(x:-0.1,y:-0.001,z:0),V(x:0.1,y:-0.001,z:0)]
        for cap in [0.0,-1.0,0.2,Double.nan] {
            var p=initial
            try reject{_=try graph.project(positions:&p,projectPoint:plane,maximumSingleVertexCorrectionMeters:cap)}
            try require(p==initial,"Invalid correction cap partially mutated source positions")
        }
        for tolerance in [-1.0,Double.nan,0.01] {var p=initial;try reject{_=try graph.project(positions:&p,projectPoint:plane,residualToleranceMeters:tolerance)};try require(p==initial,"Invalid residual tolerance partially mutated source positions")}
        var p=initial
        try reject{_=try graph.project(positions:&p,projectPoint:{_ in .init(x:.nan,y:0,z:0)})}
        try require(p==initial,"Invalid body projector modified source positions")
        p=initial;try reject{_=try graph.project(positions:&p,projectPoint:{_ in .init(x:20,y:0,z:0)})}
        try require(p==initial,"Out-of-domain projector modified source positions")
        let b=try S.Attachment(vertexIDs:[2,3],weights:[0.5,0.5]),two=try C.Prepared(vertexCount:4,attachments:[a,b],normalizedInverseMass:[1,1,1,1])
        let four=initial+initial;var q=four
        let invalidCounter=SewnContactCounter()
        try reject{_=try two.project(positions:&q,projectPoint:{v in invalidCounter.next()==2 ? .init(x:.nan,y:0,z:0) : plane(v)})}
        try require(q==four,"Mid-pass invalid projector leaked a partial update")
        var cancelled=false
        do{_=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:[1,1],isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Cancelled contact graph was returned")
        let buildCounter=SewnContactCounter();cancelled=false
        do{_=try C.Prepared(vertexCount:2,attachments:[a],normalizedInverseMass:[1,1],isCancelled:{buildCounter.next()>=2})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Mid-construction cancellation was ignored")
        p=initial;cancelled=false
        do{_=try graph.project(positions:&p,projectPoint:plane,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled && p==initial,"Pre-cancelled projection changed source positions")
        let counter=SewnContactCounter();q=four;cancelled=false
        do{_=try two.project(positions:&q,projectPoint:plane,isCancelled:{counter.next()>=3})}catch is CancellationError{cancelled=true}
        try require(cancelled && q==four,"Mid-pass cancellation leaked a partial correction")
        let empty=try C.Prepared(vertexCount:1,attachments:[try .init(vertexID:0)],normalizedInverseMass:[1]),calls=SewnContactCounter()
        var only=[V(x:0,y:-0.001,z:0)]
        let skip=try empty.project(positions:&only,projectPoint:{v in _=calls.next();return plane(v)})
        try require(calls.count==0 && skip.examinedAttachments==0 && only[0].y == -0.001,"Single-vertex contacts were not explicitly delegated to normal vertex contact")
        log("PASS \(cases) invalid/budget/projector cases, four transactional cancellation paths and vertex-only no-op")
        return ["passed":true,"invalidAndBudgetCases":cases,"cancellationCases":4,"transactionalFailureVerified":true]
    }

    static func realC62(root:URL)throws->[String:Any] {
        // Exact isolated four-node sample, source constraint c62, step600,
        // last limit pass39 SDF stage before self-contact. Original global IDs
        // [74,75,1101,1102] map bijectively to local [0,1,2,3]. No unknown
        // whole-garment coordinates are invented or claimed by this fixture.
        let originalIDs=[74,75,1101,1102]
        let initial:[V] = [
            .init(x:0.1399530500700402,y:-0.04654096210865396,z:-0.06355499014464387),
            .init(x:0.12085402933590603,y:-0.04731046829244709,z:-0.08136955649635584),
            .init(x:0.13185766646385344,y:-0.04917987443494005,z:-0.0738053109805106),
            .init(x:0.1353969872505853,y:-0.046077298266420846,z:-0.06823793208545229)]
        let weights=[1.3043733292087933,1.338322085634783,9.873320940692667,24.345439538917528]
        let a=try S.Attachment(vertexIDs:[0,1],weights:[0.7142857142857142,0.2857142857142858])
        let b=try S.Attachment(vertexIDs:[2,3],weights:[0.14285714285711748,0.8571428571428825])
        let constraint=try S.Constraint(a:a,b:b,initialGapMeters:0.0005922701108091902,
            initialDirection:.init(x:-0.6483697017806083,y:-0.37211556268890655,z:0.6641887817613631))
        let resources=root.appendingPathComponent("TrailorAss/Resources")
        let jsonBefore=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json")),fieldBefore=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodySDF.bin"))
        let bodyValues=["height":171.99,"waist":84.3338,"hips":103.478,"hips_line":23.4837,"_waist_level":108.77250000000001]
        let body=try GarmentCodeStandardBody.load(body:.init(values:bodyValues),resourceDirectory:resources),clearance=0.0025
        let projector:@Sendable(V)->V={body.project($0,thickness:clearance)}
        let vertexDistances=initial.map{body.signedDistance($0)!},beforeA=point(a,initial),beforeB=point(b,initial)
        try near(vertexDistances[0],0.002500565080298396,"Traced WB endpoint74 SDF",tolerance:2e-9)
        try near(vertexDistances[1],0.002500108728717698,"Traced WB endpoint75 SDF",tolerance:2e-9)
        try near(body.signedDistance(beforeA)!,0.0018991267834378314,"Traced WB virtual point SDF",tolerance:2e-9)
        try near(body.signedDistance(beforeB)!,0.002504451152196185,"Traced skirt virtual point SDF",tolerance:2e-9)
        try require(initial.map(projector)==initial,"The exact c62 sample should already pass the old source-vertex shell projection")
        let graph=try C.Prepared(vertexCount:4,constraints:[constraint],normalizedInverseMass:weights)
        var positions=initial
        let stats=try graph.project(positions:&positions,projectPoint:projector)
        let afterA=point(a,positions),afterB=point(b,positions),afterGap=(afterA-afterB).length
        try require(stats.projectedAttachments==1 && stats.maximumFinalResidualMeters<1e-8 && stats.unresolvedFinalAttachments==0,"True coarse virtual point shell contact remained unresolved")
        try require(body.signedDistance(afterA)!>=clearance-1e-7 && body.signedDistance(afterB)!>=clearance-1e-7,"Traced actual virtual points failed the unchanged 2.5mm shell")
        try require(afterGap<0.00005 && afterGap<(beforeA-beforeB).length/10,"Virtual point correction did not remove the actual c62 coarse/fine shell gap")
        let target=projector(beforeA),delta=target-beforeA,den=weights[0]*a.weights[0]*a.weights[0]+weights[1]*a.weights[1]*a.weights[1]
        for i in 0..<2 {try require((positions[i]-initial[i]-delta*(weights[i]*a.weights[i]/den)).length<1e-12,"Exact traced mass/coefficient displacement ratio changed")}
        try require(positions[2]==initial[2] && positions[3]==initial[3],"Already-exterior fine attachment moved unnecessarily")
        var sewingState=try S.State(constraintCount:1,vertexCount:4)
        for _ in 0..<20 {
            sewingState.resetForFrame()
            _=try S.project(positions:&positions,constraints:[constraint],normalizedInverseMass:weights,state:&sewingState,
                timeStep:1.0/240,physicalCompliance:1e-8,meanParticleMassKg:6.918741127860388e-05,rampFraction:1,
                maximumVertexCorrectionPerFrameMeters:0.5,maximumSingleVertexCorrectionMeters:0.02)
            positions=positions.map(projector)
            _=try graph.project(positions:&positions,projectPoint:projector)
        }
        let finalGap=(point(a,positions)-point(b,positions)).length
        try require(finalGap<0.0005 && body.signedDistance(point(a,positions))!>=clearance-1e-7 &&
            body.signedDistance(point(b,positions))!>=clearance-1e-7 && positions.allSatisfy{body.signedDistance($0)!>=clearance-1e-7},
            "Local c62 vertex/virtual/sewing loop reopened the original shell contradiction")
        try require(jsonBefore==Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json")) && fieldBefore==Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodySDF.bin")),"Virtual contact changed same-source body resource bytes")
        log("PASS actual isolated c62: coarse virtual SDF \(body.signedDistance(beforeA)!*1000)mm -> \(body.signedDistance(afterA)!*1000)mm; gap \((beforeA-beforeB).length*1000)mm -> \(afterGap*1000)mm; original inverse masses and body unchanged")
        return ["passed":true,"sourceSHA256":"28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35",
            "constraintIndex":62,"step":600,"phase":"last limit pass39 SDF, before self-contact","originalVertexIDs":originalIDs,
            "localVertexIDs":[0,1,2,3],"originalNormalizedInverseMass":weights,"vertexSignedDistancesBefore":vertexDistances,
            "coarseVirtualSignedDistanceBefore":body.signedDistance(beforeA)!,"fineVirtualSignedDistanceBefore":body.signedDistance(beforeB)!,
            "coarseVirtualSignedDistanceAfter":body.signedDistance(afterA)!,"fineVirtualSignedDistanceAfter":body.signedDistance(afterB)!,
            "actualGapBeforeMeters":(beforeA-beforeB).length,"actualGapAfterVirtualProjectionMeters":afterGap,
            "actualGapAfter20LocalCyclesMeters":finalGap,"bodyJSONSHA256":sha(jsonBefore),"bodyFieldSHA256":sha(fieldBefore),
            "scope":"Exact isolated four-node phase sample only. Vertex IDs are bijectively relabeled; no whole-garment state, source metric, self-contact or physical drape convergence is certified."]
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_BODY_CONTACT_OUTPUT"] ?? "/private/tmp/TailorAssSewnBodyContact")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try actorFreeAPI()
        let report:[String:Any]=["passed":true,"nonisolatedAPICallVerified":true,"analytic":try analytic(),"rejectionContracts":try failures(),"isolatedActualC62":try realC62(root:root)]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("sewn-body-contact-summary.json"))
        print("PASS prepared mass-weighted virtual sewing-point body contact, analytic/same-source cases, true residuals and transactional errors/cancellation")
    }
}
