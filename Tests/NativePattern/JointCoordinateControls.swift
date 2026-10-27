import Foundation
import NativeClothCollision
import Synchronization

nonisolated struct CoordinateCoupledQuadratic:N.FrameOperator {
    struct Evaluation:N.EvaluationValue {let energyJoules:Double,gradientNewton:[V],positions:[V]}
    struct Delta:N.DeltaValue {let energyJoules:Double}
    let cloth:J.Frame,origin:[V],k:Double
    var linear:Double {0.57*k*Double.ulpOfOne}
    func evaluate(positions x:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation {
        if isCancelled(){throw CancellationError()}
        let u=x[0].x-origin[0].x,v=x[0].y-origin[0].y
        var g=Array(repeating:V.zero,count:x.count)
        g[0] = .init(x:k*(u+0.9*v)-linear,y:k*(0.9*u+v)-linear,z:0)
        return .init(energyJoules:0.5*k*(u*u+1.8*u*v+v*v)-linear*(u+v),gradientNewton:g,positions:x)
    }
    func hessianProduct(at:Evaluation,direction d:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V] {
        if isCancelled(){throw CancellationError()}
        var h=Array(repeating:V.zero,count:d.count)
        h[0] = .init(x:k*(d[0].x+0.9*d[0].y),y:k*(0.9*d[0].x+d[0].y),z:0)
        return h
    }
    func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta {
        if isCancelled(){throw CancellationError()}
        let dx=b.positions[0].x-a.positions[0].x,dy=b.positions[0].y-a.positions[0].y
        return .init(energyJoules:a.gradientNewton[0].x*dx+a.gradientNewton[0].y*dy+0.5*k*(dx*dx+1.8*dx*dy+dy*dy))
    }
}
nonisolated final class CoordinateCancellationFlag:Sendable {
    let flag=Mutex(false)
    func cancel(){flag.withLock{$0=true}}
    func cancelled()->Bool {flag.withLock{$0}}
}
@MainActor enum JointCoordinateControls {
    enum Failure:Error {case failed(String)}
    static func need(_ b:Bool,_ m:String)throws {if !b{throw Failure.failed(m)}}
    static func vec(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
    static func object<T:Encodable>(_ x:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(x))}
    static func run(out:URL)throws {
        let ref=[vec(0,0,0),vec(0.2,0,0),vec(0,0.1,0)],origin=ref.map{$0+vec(1,1,1)}
        let p=try J.Prepared(referencePositions:ref,referenceTriangles:[0,1,2],panelGroups:[.init(panelID:"test",vertexIDs:[0,1,2],triangleIDs:[0])],massesKg:[100,100,100],stitches:[],material:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),bendingMaterial:try .init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)
        let frame=CoordinateCoupledQuadratic(cloth:try p.frame(predictor:origin,timeStepSeconds:1e-5,sewingRamp:0),origin:origin,k:1e12)
        let plan=try N.P.Plan(prepared:p)
        var result:[String:Any]=[:]
        for mode in ["allow","deny","physicalOuterDeny","cancel"] {
            var limits=N.Limits();limits.maximumNewtonIterations=mode=="physicalOuterDeny" ? 2:1
            let flag=CoordinateCancellationFlag();var calls=0,localCalls=0,outerDenied=0,first:[V]?
            do {
                let r=try N.solve(frame:frame,initialPositions:origin,preconditioner:plan.makeWorkspace(),limits:limits,
                    trajectoryMode:mode=="physicalOuterDeny" ? .physicalLinearStep:.configurationPolyline,
                    pathGuard:{a,b in
                        calls+=1
                        if mode=="deny" {return false}
                        if mode=="cancel" {flag.cancel();return true}
                        if mode=="physicalOuterDeny" {
                            if first==nil {first=b;return true}
                            if a==origin {outerDenied+=1;return false}
                            localCalls+=1;return true
                        }
                        return true
                    },isCancelled:{flag.cancelled()})
                try need(mode != "cancel","Cancellation returned a Result")
                let searches=r.report.coordinateSearches ?? []
                try need(!searches.isEmpty,"The coordinate branch was not exercised: "+mode)
                try need(searches.allSatisfy{$0.preselectedCandidates<=64 && $0.evaluatedCandidates<=64 && $0.preconditionerProducts==0 &&
                    ($0.preconditionerDiagonalQueries ?? Int.max)<=64 && ($0.coupledHessianBasisProducts ?? Int.max)<=17 &&
                    ($0.coupledPreselectedCandidates ?? Int.max)<=8 && ($0.coupledChargedTemporaryBytes ?? Int.max)<=32*1_024*1_024},"Unbounded or misreported proposal work")
                if mode=="deny" {
                    try need(r.positions==origin && r.report.history.isEmpty && !r.report.converged && searches.allSatisfy{$0.acceptedDOF==nil},"Denied coordinate committed")
                } else {
                    try need(r.report.history.first?.directionKind == .representableCoordinate,"First actual move was not the coordinate proposal")
                    try need(r.report.history.allSatisfy{$0.energyDeltaEstimateJoules<0 && $0.armijoIncrementJoules<0 && $0.energyDeltaEstimateJoules<=$0.armijoIncrementJoules},"Accepted without strict descent/Armijo")
                    if mode=="physicalOuterDeny" {
                        try need(localCalls>0 && outerDenied>0 && r.positions==first && r.report.history.count==1 && !r.report.converged,"Whole physical chord bypassed")
                        try need(searches.count>=2 && searches.last?.acceptedDOF==nil,"Second coordinate branch did not exhaust under whole-path denial")
                    } else {try need(r.acceptedTrajectory.count==1,"Accepted configuration segment not recorded")}
                }
                result[mode]=["passed":true,"pathCalls":calls,"localAfterFirst":localCalls,"outerDenied":outerDenied,"report":try object(r.report),"positions":r.positions.map{[$0.x,$0.y,$0.z]}]
            } catch is CancellationError {
                try need(mode=="cancel" && calls>0,"Unexpected cancellation")
                result[mode]=["passed":true,"cancelled":true,"pathCalls":calls,"noResultReturned":true]
            }
        }
        let tinyWork = -Double.leastNonzeroMagnitude
        let underflowArmijo=1e-4*tinyWork,zeroDelta=0.0
        try need(tinyWork<0 && underflowArmijo==0 && zeroDelta<=underflowArmijo,
            "The actual IEEE boundary must defeat a non-strict scalar Armijo test")
        try need(!(zeroDelta<0 && underflowArmijo<0 && zeroDelta<=underflowArmijo),
            "Strict coordinate descent must reject an unresolved zero increment")
        let report:[String:Any]=["passed":true,"strictUnderflowArithmeticControl":true,"cases":result,"scope":"Independent consistent coupled-quadratic Frame. Real production N/P/source-path, injected path booleans only, no body/self geometry or garment accepted.","k":frame.k,"linear":frame.linear,"ulp":Double.ulpOfOne]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("coordinate-controls.json"))
        print("Independent coordinate guard controls PASS")
    }
}
