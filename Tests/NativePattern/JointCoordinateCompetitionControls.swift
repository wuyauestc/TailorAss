import Foundation
import NativeClothCollision

nonisolated struct CoordinateNormalCompetitor:N.FrameOperator {
    struct Evaluation:N.EvaluationValue {let energyJoules:Double,gradientNewton:[V],positions:[V]}
    struct Delta:N.DeltaValue {let energyJoules:Double}
    let cloth:J.Frame,origin:[V],k:Double
    var linear:Double {0.57*k*Double.ulpOfOne}
    var zTarget:Double {Double(sign:.plus,exponent:-58,significand:1)}
    func evaluate(positions x:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation {
        if isCancelled(){throw CancellationError()}
        let u=x[0].x-origin[0].x,v=x[0].y-origin[0].y,w=x[0].z-origin[0].z
        var g=Array(repeating:V.zero,count:x.count)
        g[0] = .init(x:k*(u+0.9*v)-linear,y:k*(0.9*u+v)-linear,z:k*(w-zTarget))
        return .init(energyJoules:0.5*k*(u*u+1.8*u*v+v*v+w*w)-linear*(u+v)-k*zTarget*w,gradientNewton:g,positions:x)
    }
    func hessianProduct(at:Evaluation,direction d:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V] {
        if isCancelled(){throw CancellationError()}
        var h=Array(repeating:V.zero,count:d.count)
        h[0] = .init(x:k*(d[0].x+0.9*d[0].y),y:k*(0.9*d[0].x+d[0].y),z:k*d[0].z)
        return h
    }
    func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta {
        if isCancelled(){throw CancellationError()}
        let dx=b.positions[0].x-a.positions[0].x,dy=b.positions[0].y-a.positions[0].y,dz=b.positions[0].z-a.positions[0].z
        return .init(energyJoules:a.gradientNewton[0].x*dx+a.gradientNewton[0].y*dy+a.gradientNewton[0].z*dz+0.5*k*(dx*dx+1.8*dx*dy+dy*dy+dz*dz))
    }
}
@MainActor enum JointCoordinateCompetitionControls {
    static func run(out:URL)throws {
        func need(_ b:Bool,_ m:String)throws {try JointCoordinateControls.need(b,m)}
        func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
        let ref=[v(0,0,0),v(0.2,0,0),v(0,0.1,0)],origin=ref.map{$0+v(1,1,0)}
        let p=try J.Prepared(referencePositions:ref,referenceTriangles:[0,1,2],panelGroups:[.init(panelID:"test",vertexIDs:[0,1,2],triangleIDs:[0])],massesKg:[100,100,100],stitches:[],material:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),bendingMaterial:try .init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)
        let frame=CoordinateNormalCompetitor(cloth:try p.frame(predictor:origin,timeStepSeconds:1e-5,sewingRamp:0),origin:origin,k:1e12)
        let plan=try N.P.Plan(prepared:p)
        var rows:[String:Any]=[:]
        for mode in ["preferCoordinate","retainNormalWhenCoordinateDenied","cancelAfterCoordinatePath"] {
            var limits=N.Limits();limits.maximumNewtonIterations=1
            var calls=0,coordinateCalls=0,normalCalls=0
            let flag=CoordinateCancellationFlag()
            do {
                let r=try N.solve(frame:frame,initialPositions:origin,preconditioner:plan.makeWorkspace(),limits:limits,trajectoryMode:.configurationPolyline,pathGuard:{a,b in
                    calls+=1
                    let coordinate=b[0].x != a[0].x || b[0].y != a[0].y
                    if coordinate {
                        coordinateCalls+=1
                        if mode=="retainNormalWhenCoordinateDenied" {return false}
                        if mode=="cancelAfterCoordinatePath" {flag.cancel()}
                    } else {normalCalls+=1}
                    return true
                },isCancelled:{flag.cancelled()})
                try need(mode != "cancelAfterCoordinatePath","Cancelled comparison returned Result")
                guard let search=r.report.coordinateSearches?.last,let h=r.report.history.first else {throw JointCoordinateControls.Failure.failed("Missing actual comparison")}
                try need(search.trigger=="certified_normal_step_and_current_P_within_32_max_coordinate_spacings" && search.normalCandidateEnergyDeltaJoules != nil,"Did not preserve certified normal candidate")
                try need(normalCalls>0 && coordinateCalls>0 && r.report.history.count==1 && r.acceptedTrajectory.count==1,"Wrong actual path/commit count")
                try need(h.energyDeltaEstimateJoules<0 && h.armijoIncrementJoules<0 && h.energyDeltaEstimateJoules<=h.armijoIncrementJoules,"Lost original strict Armijo")
                if mode=="preferCoordinate" {
                    try need(h.directionKind == .representableCoordinate && h.energyDeltaEstimateJoules<search.normalCandidateEnergyDeltaJoules!,"Did not choose a strictly better real energy increment")
                    let changed=zip(origin,r.positions).flatMap{a,b in [a.x != b.x,a.y != b.y,a.z != b.z]}.filter{$0}.count
                    try need(changed==1 && r.positions[0].z==origin[0].z,"Competition must choose one actual coordinate, not merge both steps")
                } else {
                    try need(h.directionKind != .representableCoordinate && search.termination=="normalCandidateRetained" && r.positions[0].x==origin[0].x && r.positions[0].y==origin[0].y && r.positions[0].z != origin[0].z,"Valid normal candidate lost or rejected coordinate leaked")
                }
                rows[mode]=["passed":true,"normalPathCalls":normalCalls,"coordinatePathCalls":coordinateCalls,"report":try JointCoordinateControls.object(r.report),"positions":r.positions.map{[$0.x,$0.y,$0.z]}]
            } catch is CancellationError {
                try need(mode=="cancelAfterCoordinatePath" && normalCalls>0 && coordinateCalls>0,"Unexpected cancellation")
                rows[mode]=["passed":true,"noResultReturned":true,"normalPathCalls":normalCalls,"coordinatePathCalls":coordinateCalls]
            }
        }
        try JSONSerialization.data(withJSONObject:["passed":true,"cases":rows,"origin":origin.map{[$0.x,$0.y,$0.z]},"k":frame.k,"linear":frame.linear,"zTarget":frame.zTarget,"fullGarmentAccepted":false],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("coordinate-competition-controls.json"))
        print("Coordinate normal-candidate competition controls PASS")
    }
}
