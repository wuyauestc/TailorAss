import Foundation
import NativeClothCollision

typealias N=GarmentCodeJointNewton
typealias J=GarmentCodeJointObjective
typealias T=GarmentCodeJointBodyObjective
typealias V=J.V
nonisolated struct QuadraticFrame:N.FrameOperator {
    struct Evaluation:N.EvaluationValue {let energyJoules:Double,gradientNewton:[V],positions:[V]}
    struct Delta:N.DeltaValue {let energyJoules:Double}
    let cloth:J.Frame,target:[V]
    func evaluate(positions:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation {
        if isCancelled(){throw CancellationError()}
        let g=zip(positions,target).map{V(x:2*($0.x-$1.x),y:3*($0.y-$1.y),z:5*($0.z-$1.z))}
        let e=zip(positions,target).reduce(0){s,p in let d=p.0-p.1;return s+d.x*d.x+1.5*d.y*d.y+2.5*d.z*d.z}
        return .init(energyJoules:e,gradientNewton:g,positions:positions)
    }
    func hessianProduct(at:Evaluation,direction:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V] {
        if isCancelled(){throw CancellationError()};return direction.map{V(x:2*$0.x,y:3*$0.y,z:5*$0.z)}
    }
    func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta {
        if isCancelled(){throw CancellationError()}
        var value=0.0
        for i in target.indices {let p=b.positions[i]-a.positions[i],d=a.positions[i]-target[i];value+=2*d.x*p.x+p.x*p.x+3*d.y*p.y+1.5*p.y*p.y+5*d.z*p.z+2.5*p.z*p.z}
        return .init(energyJoules:value)
    }
}
/// Its exact minimizer is closer than one coordinate ULP to the translated
/// initial triangle. A no-op cannot be counted as a real accepted line.
nonisolated struct UnrepresentableQuadraticFrame:N.FrameOperator {
    typealias Evaluation=QuadraticFrame.Evaluation
    typealias Delta=QuadraticFrame.Delta
    let cloth:J.Frame,origin:[V]
    func evaluate(positions:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation {
        if isCancelled(){throw CancellationError()}
        let shift=zip(positions,origin).map{$0-$1},g0=V(x:1e-4,y:-2e-4,z:3e-4)
        return .init(energyJoules:shift.reduce(0){$0+g0.x*$1.x+g0.y*$1.y+g0.z*$1.z+0.5e20*$1.lengthSquared},
            gradientNewton:shift.map{$0*1e20+g0},positions:positions)
    }
    func hessianProduct(at:Evaluation,direction:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V] {
        if isCancelled(){throw CancellationError()};return direction.map{$0*1e20}
    }
    func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta {
        if isCancelled(){throw CancellationError()}
        let value=zip(a.positions,b.positions).enumerated().reduce(0.0){sum,item in
            let i=item.offset,delta=item.element.1-item.element.0
            return sum+a.gradientNewton[i].x*delta.x+a.gradientNewton[i].y*delta.y+a.gradientNewton[i].z*delta.z+0.5e20*delta.lengthSquared
        }
        return .init(energyJoules:value)
    }
}
@main @MainActor struct JointNewtonRegression {
    enum Failure:Error {case failed(String)}
    struct Source:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[J.H.PanelGroup],sourceSHA256:String}
    struct State:Codable {let positions:[V]}
    struct Masses:Decodable {let massesKg:[Double]}
    struct Body:Decodable {let bodyPositions:[[Double]],bodyTriangles:[UInt32],clothTriangles:[UInt32]}
    static func require(_ ok:Bool,_ message:String)throws {if !ok{throw Failure.failed(message)}}
    static func v(_ a:Double,_ b:Double,_ c:Double)->V {.init(x:a,y:b,z:c)}
    static func object<T:Encodable>(_ x:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(x))}
    static func core(_ ref:[V],_ tri:[UInt32],_ groups:[J.H.PanelGroup],_ mass:[Double],_ rows:[GarmentCodeSewing.Constraint])throws->J.Prepared {
        try .init(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,massesKg:mass,stitches:rows,
            material:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bendingMaterial:try .init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]),decoder=JSONDecoder()
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try JointCoordinateControls.run(out:out)
        try JointCoordinateCompetitionControls.run(out:out)
        try JointCoordinateCompetitionBoundaryChecks.run(output:out)
        let ref=[v(0,0,0),v(0.2,0,0),v(0,0.1,0)],groups=[J.H.PanelGroup(panelID:"paper",vertexIDs:[0,1,2],triangleIDs:[0])]
        let objective=try core(ref,[0,1,2],groups,[0.001,0.002,0.003],[]),plan=try N.P.Plan(prepared:objective)
        let frame=QuadraticFrame(cloth:try objective.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0),target:ref.map{$0+v(0.001,-0.002,0.003)})
        let solved=try N.solve(frame:frame,initialPositions:ref,preconditioner:plan.makeWorkspace(),pathGuard:{_,_ in true})
        try require(solved.report.converged,"Analytic quadratic KKT")
        let error=zip(solved.positions,frame.target).map{($0-$1).length}.max() ?? 0
        try require(error<1e-12 && solved.report.history.allSatisfy{$0.linear.converged && $0.energyDeltaEstimateJoules<0},"Independent analytic solution and actual descent")
        try require(solved.report.history.allSatisfy{$0.directionKind == .conjugateGradient && $0.precedingCG==nil},
                    "Normal CG trajectory cannot silently become a P fallback")
        var historical=try object(solved.report) as! [String:Any]
        historical.removeValue(forKey:"coordinateSearches")
        historical["history"]=(historical["history"] as! [[String:Any]]).map{row -> [String:Any] in
            var old=row;old.removeValue(forKey:"directionKind");old.removeValue(forKey:"precedingCG");old.removeValue(forKey:"precedingP");return old
        }
        let decodedHistorical=try decoder.decode(N.Report.self,from:JSONSerialization.data(withJSONObject:historical))
        try require(decodedHistorical.converged && decodedHistorical.coordinateSearches==nil && decodedHistorical.history.allSatisfy{$0.directionKind==nil && $0.precedingCG==nil && $0.precedingP==nil},
                    "Historical reports without the optional direction fields must remain decodable")
        try require(solved.report.trajectoryMode == .physicalLinearStep && solved.acceptedTrajectory.isEmpty,
                    "Physical default must retain its whole-step contract")
        let polyline=try N.solve(frame:frame,initialPositions:ref,preconditioner:plan.makeWorkspace(),
            trajectoryMode:.configurationPolyline,pathGuard:{_,_ in true})
        try require(polyline.report.converged && !polyline.acceptedTrajectory.isEmpty &&
            polyline.acceptedTrajectory.count==polyline.report.history.count,"Every accepted configuration update must be recorded")
        var chain=ref
        let motion=try GarmentCodeMembranePath.Prepared(membrane:objective.membrane)
        for segment in polyline.acceptedTrajectory {
            try require(segment.previous==chain,"Recorded configuration chain cannot jump")
            let independentlyChecked=try motion.certify(from:segment.previous,to:segment.accepted,barrier:objective.strainBarrier)
            try require(independentlyChecked.status == .clear && independentlyChecked.completedAllTriangles &&
                segment.sourceMotion.status == .clear,"The recorded segment itself must retain the source metric domain")
            chain=segment.accepted
        }
        try require(chain==polyline.positions && zip(chain,frame.target).allSatisfy{($0-$1).length<1e-12},
                    "Configuration chain must reach the same real objective solution")
        // A rotation near the upper stretch boundary has a safe entire linear
        // path: singular values lie in [scale*cos(angle/2), scale]. A generic
        // Frobenius perturbation bound is only sufficient and is much smaller.
        // The independent quadratic solution must remain reachable in one
        // full Newton update, with the actual source interval certified.
        let scale=1.069,angle=0.02,nearLimit=ref.map{$0*scale}
        let rotated=nearLimit.map{v(cos(angle)*$0.x-sin(angle)*$0.y,sin(angle)*$0.x+cos(angle)*$0.y,$0.z)}
        let direction=zip(rotated,nearLimit).map{$0-$1}
        let conservative=try objective.membrane.principalBarrierStepLimit(positions:nearLimit,direction:direction,barrier:objective.strainBarrier)
        try require(conservative<0.05 && scale*cos(angle/2)>objective.strainBarrier.lowerLimit && scale<objective.strainBarrier.upperLimit,
                    "Independent safe near-boundary rotation premise")
        let rotatedFrame=QuadraticFrame(cloth:try objective.frame(predictor:nearLimit,timeStepSeconds:1/240,sewingRamp:0),target:rotated)
        var one=N.Limits();one.maximumNewtonIterations=1
        let rotatedResult=try N.solve(frame:rotatedFrame,initialPositions:nearLimit,preconditioner:plan.makeWorkspace(),limits:one,pathGuard:{_,_ in true})
        try require(rotatedResult.report.converged && zip(rotatedResult.positions,rotated).allSatisfy{($0-$1).length<1e-11},
                    "Safe near-boundary analytic Newton step must not be clipped by the sufficient Weyl bound")
        try require((solved.report.history+polyline.report.history+rotatedResult.report.history).allSatisfy{
            $0.sourcePath.status == .clear && $0.sourcePath.completedAllTriangles &&
            $0.localSourcePath?.status == .clear && $0.localSourcePath?.completedAllTriangles == true
        },"Both actual and local numerical source paths require complete certificates")
        // Soft loading must not demand an arbitrary extra ten orders of
        // reduction after absolute force AND current-P correction are tiny.
        let weak=QuadraticFrame(cloth:frame.cloth,target:ref.map{$0+v(1e-10,-1e-10,1e-10)})
        let weakSolved=try N.solve(frame:weak,initialPositions:ref,preconditioner:plan.makeWorkspace(),pathGuard:{_,_ in true})
        try require(weakSolved.report.converged && weakSolved.report.history.isEmpty &&
            weakSolved.report.finalGradientRelativeToInitial==1 && weakSolved.report.finalGradientInfinityNewton<1e-6 &&
            weakSolved.report.finalPreconditionedGradientInfinityMeters!<1e-7,
            "Low-force criterion must be scale-aware and explicitly reported")
        // Force alone is insufficient for a light/free mode. Its numerical
        // P correction must also be small; otherwise perform a real solve.
        let light=try core(ref,[0,1,2],groups,Array(repeating:1e-8,count:3),[])
        let lightFrame=QuadraticFrame(cloth:try light.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0),
                                      target:ref.map{$0+v(1e-7,-1e-7,1e-7)})
        let lightSolved=try N.solve(frame:lightFrame,initialPositions:ref,preconditioner:N.P.Plan(prepared:light).makeWorkspace(),pathGuard:{_,_ in true})
        try require(lightSolved.report.initialGradientInfinityNewton<1e-6 && lightSolved.report.converged &&
            !lightSolved.report.history.isEmpty && lightSolved.report.finalPreconditionedGradientInfinityMeters!<1e-7,
            "Small mass must not pass only because its initial force is small")
        let blocked=try N.solve(frame:frame,initialPositions:ref,preconditioner:plan.makeWorkspace(),pathGuard:{_,_ in false})
        try require(!blocked.report.converged && blocked.positions==ref && blocked.report.history.isEmpty,"Failed path cannot partially publish a state")
        let translated=ref.map{$0+v(1,1,1)}
        let unrepresentable=UnrepresentableQuadraticFrame(cloth:frame.cloth,origin:translated)
        var roundedPathCalls=0
        let rounded=try N.solve(frame:unrepresentable,initialPositions:translated,preconditioner:plan.makeWorkspace(),pathGuard:{_,_ in roundedPathCalls+=1;return true})
        try require(rounded.report.status == .lineSearchFailed && rounded.positions==translated && rounded.report.history.isEmpty && roundedPathCalls==0,
                    "Unrepresentable minimizer cannot accept a zero-rounded step or a positive-energy P fallback")
        do {_ = try N.solve(frame:frame,initialPositions:ref,preconditioner:plan.makeWorkspace(),pathGuard:{_,_ in true},isCancelled:{true});throw Failure.failed("Cancellation ignored")}catch is CancellationError{}
        let fixtures=root.appendingPathComponent("AppFixtures"),s=fixtures.appendingPathComponent("3d-hinge"),f=fixtures.appendingPathComponent("3d-joint-body-r237")
        let source=try decoder.decode(Source.self,from:Data(contentsOf:s.appendingPathComponent("native-source-topology.json")))
        let stitches=try decoder.decode(GarmentCodeSewing.Plan.self,from:Data(contentsOf:s.appendingPathComponent("native-full-plan.json")))
        let mass=try decoder.decode(Masses.self,from:Data(contentsOf:f.appendingPathComponent("masses-kg.json")))
        let start=try decoder.decode(State.self,from:Data(contentsOf:f.appendingPathComponent("accepted-r236.json")))
        let body=try decoder.decode(Body.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativeClothCollisionTests/Fixtures/IPCBodyContact/actual-case.json")))
        let cloth=try core(source.referencePositions,source.referenceTriangles,source.panelGroups,mass.massesKg,stitches.constraints)
        let prepared=try T.Prepared(cloth:cloth,referencePositions:source.referencePositions,clothTriangleIndices:body.clothTriangles,
            bodyPositions:body.bodyPositions.map{v($0[0],$0[1],$0[2])},bodyTriangleIndices:body.bodyTriangles,
            parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002))
        let actualFrame=try prepared.frame(predictor:start.positions,timeStepSeconds:1/240,sewingRamp:237/480)
        let workspace=try N.P.Plan(prepared:cloth).makeWorkspace(),stamp=Date()
        let result=try N.solve(frame:actualFrame,initialPositions:start.positions,preconditioner:workspace,pathGuard:{a,b in
            let q=try prepared.bodyMotion(from:a,to:b);return q.permitsWholeCandidate && q.statistics.completedAllFeatures
        })
        let seconds=Date().timeIntervalSince(stamp)
        try JSONEncoder().encode(result.report).write(to:out.appendingPathComponent("actual-r237-newton-report.json"))
        try JSONEncoder().encode(State(positions:result.positions)).write(to:out.appendingPathComponent("actual-r237-mathematical-state.json"))
        if let blocked=result.lastRejectedCandidate {try JSONEncoder().encode(State(positions:blocked)).write(to:out.appendingPathComponent("actual-r237-rejected-candidate.json"))}
        let quality=try cloth.membrane.inspect(positions:result.positions)
        var edgeStrain=0.0
        for t in cloth.membrane.triangles {for (a,b) in [(t.a,t.b),(t.b,t.c),(t.c,t.a)] {
            edgeStrain=max(edgeStrain,abs((result.positions[b]-result.positions[a]).length/(source.referencePositions[b]-source.referencePositions[a]).length-1))
        }}
        let topology=try GarmentCodeClothContact.Topology(vertexCount:result.positions.count,triangleIndices:body.clothTriangles)
        let selfQuality=try GarmentCodeClothContact.inspect(positions:result.positions,topology:topology,thickness:0.005)
        let checksPassed=result.report.converged && result.evaluation.body.statistics.stencils>0 && edgeStrain<0.08 && selfQuality.intersectingTrianglePairs==0
        let summary:[String:Any]=["passed":checksPassed,"analyticMaximumPositionErrorMeters":error,"analyticReport":try object(solved.report),
            "weakLoadStoppingReport":try object(weakSolved.report),"smallMassStoppingReport":try object(lightSolved.report),
            "configurationPolylineReport":try object(polyline.report),"configurationSegments":polyline.acceptedTrajectory.count,
            "historicalDirectionFieldsOptionalDecode":true,"unrepresentableMinimizerReport":try object(rounded.report),"unrepresentablePathCalls":roundedPathCalls,
            "safeNearLimitRotationReport":try object(rotatedResult.report),"conservativeWeylProposal":conservative,
            "actualR237":["report":try object(result.report),"sourceSHA256":source.sourceSHA256,"seconds":seconds,
                "bodyEnergyJoules":result.evaluation.body.energyJoules,"bodyStencils":result.evaluation.body.statistics.stencils,
                "sourceQuality":try object(quality),"maximumSourceEdgeStrain":edgeStrain,"selfIntersections":selfQuality.intersectingTrianglePairs],
            "physicalStepAccepted":false,"scope":"Production Newton + original physical P + true cloth/body Phi, one mathematical subproblem. Self force/bending/gravity/full garment not accepted."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-newton-summary.json"))
        try require(result.report.converged,"First real body-coupled r237 subproblem did not converge: \(result.report.status)")
        try require(result.evaluation.body.statistics.stencils>0 && edgeStrain<0.08 && selfQuality.intersectingTrianglePairs==0,"Real active contact/source/self endpoint controls")
        print("Joint Newton: analytic and real first body-coupled KKT subproblems passed; full garment not claimed.")
    }
}
