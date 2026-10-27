import Foundation
import NativeClothCollision
import Synchronization

/// Consistent coupled quadratic. Injected unresolved deltas model unavailable
/// comparison evidence, not a fabricated lower energy or physical acceptance.
nonisolated struct CoordinateCompetitionBoundaryFrame:GarmentCodeJointNewton.FrameOperator {
    typealias N=GarmentCodeJointNewton
    typealias V=N.V
    struct Evaluation:N.EvaluationValue {let energyJoules:Double,gradientNewton:[V],positions:[V]}
    struct Delta:N.DeltaValue {let energyJoules:Double}
    let cloth:GarmentCodeJointObjective.Frame,origin:[V],zTarget:Double
    let unresolvedCoordinates:Bool
    let k=1e12
    var linear:Double {0.57*k*Double.ulpOfOne}
    func evaluate(positions p:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation {
        if isCancelled(){throw CancellationError()}
        let u=p[0].x-origin[0].x,v=p[0].y-origin[0].y,w=p[0].z-origin[0].z
        var g=Array(repeating:V.zero,count:p.count)
        g[0] = .init(x:k*(u+0.9*v)-linear,y:k*(0.9*u+v)-linear,z:k*(w-zTarget))
        return .init(energyJoules:0.5*k*(u*u+1.8*u*v+v*v+w*w)-linear*(u+v)-k*zTarget*w,gradientNewton:g,positions:p)
    }
    func hessianProduct(at:Evaluation,direction p:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V] {
        if isCancelled(){throw CancellationError()};var h=Array(repeating:V.zero,count:p.count)
        h[0] = .init(x:k*(p[0].x+0.9*p[0].y),y:k*(0.9*p[0].x+p[0].y),z:k*p[0].z);return h
    }
    func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta {
        if isCancelled(){throw CancellationError()}
        let dx=b.positions[0].x-a.positions[0].x,dy=b.positions[0].y-a.positions[0].y,dz=b.positions[0].z-a.positions[0].z
        if unresolvedCoordinates && (dx != 0 || dy != 0) {throw GarmentCodeElasticEnergyDelta.DeltaError.precisionUnresolved}
        return .init(energyJoules:a.gradientNewton[0].x*dx+a.gradientNewton[0].y*dy+a.gradientNewton[0].z*dz+0.5*k*(dx*dx+1.8*dx*dy+dy*dy+dz*dz))
    }
}
@MainActor enum JointCoordinateCompetitionBoundaryChecks {
    enum Failure:Error {case failed(String)}
    static func run(output:URL)throws {
        typealias N=GarmentCodeJointNewton
        typealias J=GarmentCodeJointObjective
        typealias V=N.V
        func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
        func need(_ b:Bool,_ s:String)throws {if !b{throw Failure.failed(s)}}
        let reference=[v(0,0,0),v(0.2,0,0),v(0,0.1,0)],origin=reference.map{$0+v(1,1,0)}
        let p=try J.Prepared(referencePositions:reference,referenceTriangles:[0,1,2],panelGroups:[.init(panelID:"test",vertexIDs:[0,1,2],triangleIDs:[0])],
            massesKg:[100,100,100],stitches:[],material:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bendingMaterial:try .init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)
        let plan=try N.P.Plan(prepared:p);var rows:[[String:Any]]=[]
        for mode in ["comparisonDeltaUnresolved","normalHasLowerEnergy"] {
            let f=CoordinateCompetitionBoundaryFrame(cloth:try p.frame(predictor:origin,timeStepSeconds:1e-5,sewingRamp:0),origin:origin,
                zTarget:Double(sign:.plus,exponent:mode=="comparisonDeltaUnresolved" ? -58:-53,significand:1),unresolvedCoordinates:mode=="comparisonDeltaUnresolved")
            var limits=N.Limits();limits.maximumNewtonIterations=1
            var paths=0
            let result=try N.solve(frame:f,initialPositions:origin,preconditioner:plan.makeWorkspace(),limits:limits,trajectoryMode:.configurationPolyline,pathGuard:{_,_ in paths+=1;return true})
            guard let searches=result.report.coordinateSearches,searches.count==1,let search=searches.first,let h=result.report.history.first else {
                throw Failure.failed("One actual comparison must produce exactly one search summary")
            }
            try need(search.termination=="normalCandidateRetained" && search.preconditionerProducts==0 && search.preconditionerDiagonalQueries==2 && search.evaluatedCandidates==2 &&
                h.directionKind == .conjugateGradient && result.report.history.count==1 && result.acceptedTrajectory.count==1 && paths==1,
                "Unknown/worse extra candidates must not replace or duplicate the certified normal segment")
            try need(h.energyDeltaEstimateJoules<0 && h.armijoIncrementJoules<0 && h.energyDeltaEstimateJoules<=h.armijoIncrementJoules,
                "Retained normal candidate must keep its original strict Armijo proof")
            try need(result.positions[0].x==origin[0].x && result.positions[0].y==origin[0].y && result.positions[0].z != origin[0].z,
                "No rejected/unknown coordinate leaked into the committed normal position")
            try need(search.unresolvedCandidateEvaluations==(mode=="comparisonDeltaUnresolved" ? 2:0),"Truthful bounded unresolved count")
            let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(result.report))
            rows.append(["mode":mode,"passed":true,"actualPathCalls":paths,"report":object,"noPhysicalCapabilityMinted":true])
        }
        try JSONSerialization.data(withJSONObject:["passed":true,"cases":rows,"scope":"Consistent analytic source metric frame, injected comparison evidence failure only; no garment acceptance"],
            options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("coordinate-competition-boundary-summary.json"))
    }
}
