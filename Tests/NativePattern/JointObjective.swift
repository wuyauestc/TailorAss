import Foundation
import CryptoKit

typealias J=GarmentCodeJointObjective
typealias V=J.V
nonisolated final class ObjectiveCancel:@unchecked Sendable {
    private let lock=NSLock();private var count=0;private let limit:Int
    init(_ limit:Int){self.limit=limit}
    func check()->Bool {lock.lock();defer{lock.unlock()};count+=1;return count>=limit}
}
@main @MainActor struct JointObjectiveRegression {
    enum Failure:Error {case failed(String)}
    struct Source:Decodable {
        let positions:[V],referencePositions:[V],referenceTriangles:[UInt32]
        let panelGroups:[J.H.PanelGroup],sourceSHA256:String
    }
    static func require(_ ok:Bool,_ s:String)throws {if !ok {throw Failure.failed(s)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
    static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    static func dot(_ a:[V],_ b:[V])->Double {zip(a,b).reduce(0){$0+dot($1.0,$1.1)}}
    static func plus(_ a:[V],_ b:[V],_ t:Double)->[V] {zip(a,b).map{$0+$1*t}}
    static func difference(_ a:[V],_ b:[V])->[V] {zip(a,b).map{$0-$1}}
    static func norm(_ a:[V])->Double {sqrt(dot(a,a))}
    static func direction(_ n:Int)->[V] {(0..<n).map{i in let x=Double(i);return v(sin(x*1.3+0.2),cos(x*0.7),sin(x*0.3+0.8))}}
    static func materials()throws->(J.M.Material,J.M.StrainBarrier,J.H.Material) {
        (try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
         try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
         try .init(bendingStiffnessNewtonMeter:2e-4))
    }
    static func rejected(_ f:()throws->Void)throws {
        do {try f()} catch is J.ObjectiveError {return};throw Failure.failed("Invalid joint input was accepted")
    }
    static func fd(_ frame:J.Frame,_ x:[V],_ p:[V],_ epsilon:Double)throws->[String:Double] {
        let current=try frame.evaluate(positions:x),ep=try frame.evaluate(positions:plus(x,p,epsilon)),em=try frame.evaluate(positions:plus(x,p,-epsilon))
        let eg=(ep.energyJoules-em.energyJoules)/(2*epsilon),g=dot(current.gradientNewton,p)
        let hv=try frame.hessianProduct(positions:x,direction:p),gh=difference(ep.gradientNewton,em.gradientNewton).map{$0/(2*epsilon)}
        let e=abs(eg-g)/max(1e-12,abs(eg),abs(g)),h=norm(difference(hv,gh))/max(1e-12,norm(hv),norm(gh))
        try require(e<1e-5 && h<1e-5,"Joint energy/force/Hv FD: \(e) \(h)")
        return ["energyGradientRelativeError":e,"hessianProductRelativeError":h,"energyJoules":current.energyJoules,"bendingJoules":current.bendingJoules,"barrierJoules":current.strainBarrierJoules]
    }
    static func main()throws {
        let args=CommandLine.arguments,fixture=URL(fileURLWithPath:args[1]),output=URL(fileURLWithPath:args[2])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let (material,barrier,bend)=try materials(),reference=[v(0,0,0),v(0.1,0,0),v(0.1,0.1,0),v(0,0.1,0)]
        let ref=reference+reference,tri:[UInt32]=[0,1,2,0,2,3,4,5,6,4,6,7]
        let groups=[J.H.PanelGroup(panelID:"first",vertexIDs:[0,1,2,3],triangleIDs:[0,1]),J.H.PanelGroup(panelID:"second",vertexIDs:[4,5,6,7],triangleIDs:[2,3])]
        let a=try GarmentCodeSewing.Attachment(vertexIDs:[1,2],weights:[0.25,0.75]),b=try GarmentCodeSewing.Attachment(vertexIDs:[4,7],weights:[0.4,0.6])
        let stitches=[try GarmentCodeSewing.Constraint(a:a,b:b,initialGapMeters:0.12)]
        func make(_ compliance:Double=0.02,_ mass:[Double]=Array(repeating:0.001,count:8),_ constraints:[GarmentCodeSewing.Constraint]?=nil)throws->J.Prepared {
            try .init(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,massesKg:mass,stitches:constraints ?? stitches,
                      material:material,strainBarrier:barrier,bendingMaterial:bend,sewingComplianceMetersPerNewton:compliance)
        }
        let prepared=try make(),x=ref.enumerated().map{i,p in p*1.04+v(i>=4 ? 0.2:0,0,i%4==3 ? 0.001:0)}
        let predictor=x.enumerated().map{i,p in p+v(0.0001*Double(i),0.0002,0)},frame=try prepared.frame(predictor:predictor,timeStepSeconds:1/240,sewingRamp:0.6),p=direction(x.count)
        var results:[String:Any]=["scope":"Joint inertia+NH+principal barrier+hinge+real scalar sewing energy and derivatives. No body/self forces or physical time step, no garment acceptance."]
        results["syntheticCoupledFD"]=try fd(frame,x,p,1e-7)
        let cache=try frame.linearize(positions:x)
        let uncached=try frame.hessianProduct(positions:x,direction:p)
        let cached=try frame.hessianProduct(positions:x,direction:p,linearization:cache)
        try require(zip(uncached,cached).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern},"Cached full objective Hv must preserve original bits")
        try rejected{_ = try frame.hessianProduct(positions:plus(x,p,1e-6),direction:p,linearization:cache)}
        let otherSource=try make().frame(predictor:predictor,timeStepSeconds:1/240,sewingRamp:0.6)
        try rejected{_ = try otherSource.hessianProduct(positions:x,direction:p,linearization:cache)}
        let ev=try frame.evaluate(positions:x),components=ev.inertiaJoules+ev.membraneJoules+ev.strainBarrierJoules+ev.bendingJoules+ev.sewingJoules
        try require(abs(ev.energyJoules-components)<1e-12 && ev.strainBarrierJoules>0 && ev.bendingJoules>0,"All energies active and summed")
        // Removing inertia leaves internal forces and torque balanced, including
        // barycentric sewing. Translation Hessian action is exactly mass/h².
        let noInertia=try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.6),internalE=try noInertia.evaluate(positions:x)
        let force=internalE.gradientNewton.reduce(V.zero,+),torque=zip(x,internalE.gradientNewton).reduce(V.zero){$0+$1.0.cross($1.1)}
        let translation=Array(repeating:v(0.7,-0.2,0.3),count:x.count),translationH=try frame.hessianProduct(positions:x,direction:translation)
        let expected=translation.map{$0*(0.001*240*240)}
        try require(force.length<1e-10 && torque.length<1e-10 && norm(difference(translationH,expected))<1e-9,"Coupled rigid identities")
        let opposite=direction(x.count).reversed().map{$0},hp=try frame.hessianProduct(positions:x,direction:p),hq=try frame.hessianProduct(positions:x,direction:opposite)
        let symmetry=abs(dot(p,hq)-dot(opposite,hp));try require(symmetry<1e-8,"Exact coupled Hessian symmetry")
        results["invariants"]=["netInternalForceNewton":force.length,"netInternalTorqueNewtonMeter":torque.length,"bilinearSymmetryAbsoluteError":symmetry]
        let compressedStitch=try GarmentCodeSewing.Constraint(a:zAttachment(0),b:zAttachment(4),initialGapMeters:0.5)
        let compressed=try make(0.02,Array(repeating:0.001,count:8),[compressedStitch]).frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0)
        let unsewn=try make(0.02,Array(repeating:0.001,count:8),[]).frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0)
        var tangent=Array(repeating:V.zero,count:8);tangent[0]=v(0,1,0)
        let compressedH=try compressed.hessianProduct(positions:x,direction:tangent),unsewnH=try unsewn.hessianProduct(positions:x,direction:tangent)
        let sewingCurvature=dot(tangent,difference(compressedH,unsewnH))
        try require(sewingCurvature < -1,"Actual negative sewing curvature must not be PSD clamped")
        results["compressedSeamTangentCurvatureNewtonPerMeter"]=sewingCurvature
        let y=plus(x,p,1e-6),delta=try frame.nonelasticEnergyDelta(from:x,to:y),ey=try frame.evaluate(positions:y)
        let direct=ey.inertiaJoules+ey.sewingJoules-ev.inertiaJoules-ev.sewingJoules
        try require(abs(delta.energyJoules-direct)<1e-12,"Stable nonelastic delta")
        let completeDelta=try frame.energyDelta(from:x,to:y)
        try require(abs(completeDelta.energyJoules-(ey.energyJoules-ev.energyJoules))<1e-12,"Complete active-barrier and bending energy increment")
        results["stableFullDeltaJoules"]=completeDelta.energyJoules
        // Explicit loading strategy: zero target at every stage, coefficient
        // continuation only. Verify the whole derivatives, not scaled visuals.
        let schedule=J.SewingSchedule.quadraticStiffness(initialNewtonPerMeter:1)
        var continuation:[[String:Double]]=[]
        for ramp in [0.0,0.25,0.5,0.75,1] {
            let f=try prepared.frame(predictor:predictor,timeStepSeconds:1/240,sewingRamp:ramp,sewingSchedule:schedule)
            let expected=ramp==0 ? 1:(ramp==1 ? 50:pow(50,ramp))
            try require(abs(f.sewingStiffnessNewtonPerMeter-expected)<1e-12,"Explicit stiffness coefficient")
            try require(f.sewingTargetMeters(prepared.sewingRows[0])==0,"Quadratic target is always zero")
            var item=try fd(f,x,p,1e-7);item["ramp"]=ramp;item["stiffnessNewtonPerMeter"]=f.sewingStiffnessNewtonPerMeter
            let e0=try f.evaluate(positions:x),e1=try f.evaluate(positions:y),d=try f.nonelasticEnergyDelta(from:x,to:y)
            try require(abs(d.energyJoules-(e1.inertiaJoules+e1.sewingJoules-e0.inertiaJoules-e0.sewingJoules))<1e-12,
                        "Quadratic stored-coordinate energy increment")
            continuation.append(item)
        }
        let endOld=try prepared.frame(predictor:predictor,timeStepSeconds:1/240,sewingRamp:1)
        let endNew=try prepared.frame(predictor:predictor,timeStepSeconds:1/240,sewingRamp:1,sewingSchedule:schedule)
        let eo=try endOld.evaluate(positions:x),en=try endNew.evaluate(positions:x)
        let ho=try endOld.hessianProduct(positions:x,direction:p),hn=try endNew.hessianProduct(positions:x,direction:p)
        func sameBits(_ a:[V],_ b:[V])->Bool {zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}}
        try require(eo.energyJoules.bitPattern==en.energyJoules.bitPattern && sameBits(eo.gradientNewton,en.gradientNewton) && sameBits(ho,hn),
                    "Homotopy endpoint must recover exactly the original final Phi/g/raw Hv")
        for initial in [0.0,-1,Double.nan,51] {
            try rejected{_ = try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.5,
                         sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:initial))}
        }
        results["quadraticSewingContinuationFD"]=continuation
        results["continuationEndpointOriginalObjectiveBitwiseIdentical"]=true
        // A closed final seam has a smooth squared-vector energy even when its
        // exact gap is zero. A nonzero target at that position is nonsmooth.
        let zA=try GarmentCodeSewing.Attachment(vertexID:0),zB=try GarmentCodeSewing.Attachment(vertexID:4)
        let nonzero=try GarmentCodeSewing.Constraint(a:zA,b:zB,initialGapMeters:0.1),zero=try GarmentCodeSewing.Constraint(a:zA,b:zB,initialGapMeters:0)
        let closed=try make(0.02,Array(repeating:0.001,count:8),[nonzero]).frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:1)
        let smooth=try closed.evaluate(positions:ref);try require(smooth.sewingJoules==0 && smooth.inertiaJoules==0,"Closed seam has zero sewing and inertia energy")
        _ = try closed.hessianProduct(positions:ref,direction:p)
        _ = try closed.nonelasticEnergyDelta(from:ref,to:ref)
        _ = try make(0.02,Array(repeating:0.001,count:8),[zero]).frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0.2).evaluate(positions:ref)
        try rejected{_ = try make(0.02,Array(repeating:0.001,count:8),[nonzero]).frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0.2).evaluate(positions:ref)}
        try rejected{_ = try make(0)};try rejected{_ = try make(-1)};try rejected{_ = try make(.nan)}
        try rejected{_ = try make(0.02,Array(repeating:0,count:8))};try rejected{_ = try make(0.02,[0.1])}
        try rejected{_ = try prepared.frame(predictor:x,timeStepSeconds:0,sewingRamp:0.1)}
        try rejected{_ = try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:1.01)}
        try rejected{_ = try frame.evaluate(positions:Array(x.dropLast()))}
        try rejected{_ = try frame.hessianProduct(positions:x,direction:Array(p.dropLast()))}
        let cancel=ObjectiveCancel(8)
        do {_ = try frame.hessianProduct(positions:x,direction:p,isCancelled:{cancel.check()});throw Failure.failed("Cancel not propagated")}catch is CancellationError{}
        // Real source paper: all 69 rows retained with original barycentric
        // attachments, 2000 independent IDs and 4948 source-only bending hinges.
        let decoder=JSONDecoder(),source=try decoder.decode(Source.self,from:Data(contentsOf:fixture.appendingPathComponent("native-source-topology.json")))
        let plan=try decoder.decode(GarmentCodeSewing.Plan.self,from:Data(contentsOf:fixture.appendingPathComponent("native-full-plan.json")))
        try require(plan.sourceSHA256==source.sourceSHA256 && source.sourceSHA256=="28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35","Complete fixture source binding")
        let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:source.referencePositions.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:source.referenceTriangles,arealDensity:0.18)
        var real:[[String:Any]]=[]
        for compliance in [0.02,1e-8] {
            let actual=try J.Prepared(referencePositions:source.referencePositions,referenceTriangles:source.referenceTriangles,panelGroups:source.panelGroups,massesKg:masses.massesKg,stitches:plan.constraints,material:material,strainBarrier:barrier,bendingMaterial:bend,sewingComplianceMetersPerNewton:compliance)
            try require(actual.sewingRows.count==69 && actual.bending.hinges.count==4948,"Whole source and seam preservation")
            // Small source-relative distortion activates the barrier and adds
            // nonzero hinge angles without using the old failed physics frame.
            let positions=source.positions.enumerated().map{i,p in p*1.04+v(0,0,0.00005*sin(Double(i)))}
            let actualFrame=try actual.frame(predictor:positions,timeStepSeconds:1/240,sewingRamp:0.01)
            var value:[String:Any]=try fd(actualFrame,positions,direction(positions.count),1e-8)
            let trial=plus(positions,direction(positions.count),1e-7)
            let stable=try actualFrame.energyDelta(from:positions,to:trial)
            let e0=try actualFrame.evaluate(positions:positions),e1=try actualFrame.evaluate(positions:trial)
            let direct=e1.energyJoules-e0.energyJoules
            let error=abs(stable.energyJoules-direct)/max(1e-10,abs(direct))
            try require(error<1e-5,"Complete-source stable objective increment")
            value["fullDeltaRelativeDifferenceToOrdinaryResolvableDifference"]=error
            value["sewingComplianceMetersPerNewton"]=compliance;real.append(value)
        }
        results["actualCompleteSourceFD"]=real;results["sourceSHA256"]=source.sourceSHA256
        results["passed"]=true;results["physicalStepAccepted"]=false
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("joint-objective-summary.json"))
        print("Joint objective energy/gradient/exact Hv and complete-source checks passed; no physical step claimed.")
    }
    static func zAttachment(_ id:Int)throws->GarmentCodeSewing.Attachment {try .init(vertexID:id)}
}
