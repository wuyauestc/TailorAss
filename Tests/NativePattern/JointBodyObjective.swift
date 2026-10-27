import Foundation
import NativeClothCollision

typealias T=GarmentCodeJointBodyObjective
typealias J=GarmentCodeJointObjective
typealias V=J.V
@main @MainActor struct JointBodyRegression {
    enum Failure:Error {case failed(String)}
    struct Case:Decodable {
        let name:String,clothRest:[[Double]],clothCurrent:[[Double]],bodyPositions:[[Double]]
        let clothTriangles:[UInt32],bodyTriangles:[UInt32],kappa:Double,dmin:Double,h:Double
        var reference:[V] {clothRest.map{V(x:$0[0],y:$0[1],z:0)}}
        var current:[V] {clothCurrent.map{V(x:$0[0],y:$0[1],z:$0[2])}}
        var body:[V] {bodyPositions.map{V(x:$0[0],y:$0[1],z:$0[2])}}
    }
    struct Cases:Decodable {let cases:[Case]}
    struct Source:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[J.H.PanelGroup],sourceSHA256:String}
    struct State:Decodable {let positions:[V]}
    struct Masses:Decodable {let massesKg:[Double]}
    static func require(_ ok:Bool,_ message:String)throws {if !ok{throw Failure.failed(message)}}
    static func vector(_ a:Double,_ b:Double,_ c:Double)->V {.init(x:a,y:b,z:c)}
    static func plus(_ x:[V],_ p:[V],_ h:Double)->[V] {zip(x,p).map{$0+$1*h}}
    static func dot(_ a:[V],_ b:[V])->Double {zip(a,b).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}}
    static func norm(_ x:[V])->Double {sqrt(dot(x,x))}
    static func subtract(_ a:[V],_ b:[V])->[V] {zip(a,b).map{$0-$1}}
    static func direction(_ n:Int)->[V] {(0..<n).map{i in let x=Double(i);return vector(sin(x+0.3),cos(0.7*x+0.2),sin(1.3*x+0.4))}}
    static func core(reference:[V],triangles:[UInt32],groups:[J.H.PanelGroup],masses:[Double],stitches:[GarmentCodeSewing.Constraint],compliance:Double,kb:Double)throws->J.Prepared {
        try .init(referencePositions:reference,referenceTriangles:triangles,panelGroups:groups,massesKg:masses,stitches:stitches,
            material:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bendingMaterial:try .init(bendingStiffnessNewtonMeter:kb),sewingComplianceMetersPerNewton:compliance)
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let fixtures=root.appendingPathComponent("Tests/NativeClothCollisionTests/Fixtures/IPCBodyContact"),decoder=JSONDecoder()
        let cases=try decoder.decode(Cases.self,from:Data(contentsOf:fixtures.appendingPathComponent("generic-fd-cases.json"))).cases
        var rows:[[String:Any]]=[]
        for c in cases {
            let ref=c.reference,n=ref.count
            let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:ref.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:c.clothTriangles,arealDensity:0.18)
            let group=J.H.PanelGroup(panelID:"paper",vertexIDs:Array(0..<n),triangleIDs:Array(0..<(c.clothTriangles.count/3)))
            let stitch=try GarmentCodeSewing.Constraint(a:.init(vertexID:0),b:.init(vertexID:1),initialGapMeters:(ref[0]-ref[1]).length)
            let objective=try core(reference:ref,triangles:c.clothTriangles,groups:[group],masses:masses.massesKg,stitches:[stitch],compliance:0.02,kb:2e-4)
            let prepared=try T.Prepared(cloth:objective,referencePositions:ref,clothTriangleIndices:c.clothTriangles,
                bodyPositions:c.body,bodyTriangleIndices:c.bodyTriangles,
                parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h))
            let x=c.current.map{$0*1.04},frame=try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.02)
            let e=try frame.evaluate(positions:x),p=direction(n),h=1e-10
            let a=try frame.evaluate(positions:plus(x,p,h)),b=try frame.evaluate(positions:plus(x,p,-h))
            let fd=(a.energyJoules-b.energyJoules)/(2*h),exact=dot(e.gradientNewton,p)
            let gradientError=abs(fd-exact)/max(1e-9,abs(fd),abs(exact))
            let hd=try frame.hessianProduct(at:e,direction:p),fdh=subtract(a.gradientNewton,b.gradientNewton).map{$0/(2*h)}
            let hessianError=norm(subtract(hd,fdh))/max(1e-9,norm(hd),norm(fdh))
            try require(gradientError<1e-5 && hessianError<2e-4,"Coupled body gradient/Hv FD \(c.name): \(gradientError), \(hessianError)")
            let increment=try frame.energyDelta(from:b,to:a)
            let deltaError=abs(increment.energyJoules-(a.energyJoules-b.energyJoules))/max(1e-15,abs(a.energyJoules-b.energyJoules))
            try require(deltaError<2e-5,"Resolvable joint body energy increment")
            try require(e.body.statistics.stencils>0 && e.cloth.strainBarrierJoules>0,"Actual body force and active source barrier")
            let psd=try frame.bodyPreconditioner(at:e)
            try require(psd.energyJoules==e.body.energyJoules && psd.clothGradientNewtons==e.body.clothGradientNewtons,"PSD cannot alter physical force")
            let pd=try psd.hessianProduct(direction:p.map{SIMD3($0.x,$0.y,$0.z)})
            let quadratic=zip(p,pd).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}
            try require(quadratic>=(-1e-9),"Whole-local body PSD quadratic")
            let other=try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.02)
            do {_ = try other.hessianProduct(at:e,direction:p);throw Failure.failed("Stale frame Hessian accepted")}catch T.ObjectiveError.foreignEvaluation{}
            do {_ = try frame.evaluate(positions:x,isCancelled:{true});throw Failure.failed("Cancellation ignored")}catch is CancellationError{}
            do {_ = try frame.hessianProduct(at:e,direction:p,isCancelled:{true});throw Failure.failed("Hv cancellation ignored")}catch is CancellationError{}
            rows.append(["case":c.name,"bodyEnergyJoules":e.body.energyJoules,"stencils":e.body.statistics.stencils,
                "negativeStencils":e.body.statistics.negativeStencils,"combinedEnergyGradientFDRelativeError":gradientError,
                "combinedExactHvFDRelativeError":hessianError,"bodyPreconditionerQuadratic":quadratic,
                "resolvableEnergyDeltaRelativeDifference":deltaError])
        }
        // The first actual body activation belongs to valid source geometry;
        // it is a blocked trial, never re-labelled as an accepted frame.
        let f=root.appendingPathComponent("AppFixtures/3d-joint-body-r237"),s=root.appendingPathComponent("AppFixtures/3d-hinge")
        let source=try decoder.decode(Source.self,from:Data(contentsOf:s.appendingPathComponent("native-source-topology.json")))
        let plan=try decoder.decode(GarmentCodeSewing.Plan.self,from:Data(contentsOf:s.appendingPathComponent("native-full-plan.json")))
        let accepted=try decoder.decode(State.self,from:Data(contentsOf:f.appendingPathComponent("accepted-r236.json")))
        let trial=try decoder.decode(State.self,from:Data(contentsOf:f.appendingPathComponent("blocked-r237-trial.json")))
        let mass=try decoder.decode(Masses.self,from:Data(contentsOf:f.appendingPathComponent("masses-kg.json")))
        let actual=try decoder.decode(Case.self,from:Data(contentsOf:fixtures.appendingPathComponent("actual-case.json")))
        let expected=try JSONSerialization.jsonObject(with:Data(contentsOf:f.appendingPathComponent("expected.json"))) as! [String:Any]
        try require(source.sourceSHA256==plan.sourceSHA256 && source.sourceSHA256==expected["sourceSHA256"] as? String,"Whole source binding")
        let objective=try core(reference:source.referencePositions,triangles:source.referenceTriangles,groups:source.panelGroups,
            masses:mass.massesKg,stitches:plan.constraints,compliance:1e-8,kb:0)
        let prepared=try T.Prepared(cloth:objective,referencePositions:source.referencePositions,clothTriangleIndices:actual.clothTriangles,
            bodyPositions:actual.body,bodyTriangleIndices:actual.bodyTriangles,
            parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002))
        let frame=try prepared.frame(predictor:accepted.positions,timeStepSeconds:1/240,sewingRamp:237/480)
        let previous=try frame.evaluate(positions:accepted.positions),blocked=try frame.evaluate(positions:trial.positions)
        let bodyExpected=expected["body"] as! [String:Any]
        try require(previous.body.statistics.stencils==0 && previous.body.energyJoules==0,"Last accepted236 has no active body force")
        try require(blocked.body.statistics.stencils==1 && blocked.body.statistics.clothVertexBodyFaceStencils==1 && blocked.body.statistics.completeBVHFacePairs==54,"Complete real first activation")
        let energyError=abs(blocked.body.energyJoules-(bodyExpected["energyJoules"] as! Double))
        try require(energyError<1e-20,"Actual first activation matches frozen official body consumer")
        let force=subtract(blocked.gradientNewton,blocked.cloth.gradientNewton),forceMax=force.map{$0.length}.max() ?? 0
        try require(forceMax>1e-4 && norm(force)>0,"Body force must enter the actual joint gradient")
        let path=try prepared.bodyMotion(from:accepted.positions,to:trial.positions)
        try require(path.permitsWholeCandidate && path.statistics.completedAllFeatures && path.minimumSeparation==0.0005,"Whole body path uses the same barrier minimum")
        let p=direction(trial.positions.count),raw=try frame.hessianProduct(at:blocked,direction:p)
        try require(raw.count==2000 && raw.allSatisfy(\.isFinite),"Complete actual-source coupled Hv")
        let summary:[String:Any]=["passed":true,"syntheticActiveControls":rows,"firstRealBodyActivation":[
            "sourceSHA256":source.sourceSHA256,"lastAcceptedFrame":236,"blockedTrialFrame":237,"trialStillNotAccepted":true,
            "bodyEnergyJoules":blocked.body.energyJoules,"bodyEnergyDifferenceToFrozenConsumer":energyError,"jointBodyGradientMaxNormNewton":forceMax,
            "completeBVHFacePairs":54,"stencils":1,"sameMinimumWholeBodyPathClear":true],
            "physicalStepAccepted":false,"scope":"True joint cloth + complete signed body potential E/G/raw Hv, source-valid first body activation and same-floor body CCD. No self force or garment acceptance."]
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-body-objective-summary.json"))
        print("Joint body objective: complete physical force/Hv and real first activation passed; no physical step claimed.")
    }
}
