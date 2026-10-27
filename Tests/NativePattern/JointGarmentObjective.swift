import Foundation
import NativeClothCollision

typealias G=GarmentCodeJointGarmentObjective
typealias J=GarmentCodeJointObjective
typealias V=J.V
@main @MainActor struct JointGarmentRegression {
    enum Failure:Error {case failed(String)}
    struct Case:Decodable {
        let name:String,rest:[[Double]],current:[[Double]],triangles:[UInt32]
        let kappa:Double,dmin:Double,h:Double
    }
    struct Cases:Decodable {let cases:[Case]}
    struct Golden:Decodable {
        let energy:Double,gradient:[Double],hessian:[[Double]]
        let stencilCount:Int,negativeStencilCount:Int
    }
    struct ActualGolden:Decodable {let `case`:Golden}
    static func require(_ b:Bool,_ s:String)throws{if !b{throw Failure.failed(s)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V{.init(x:x,y:y,z:z)}
    static func plus(_ x:[V],_ p:[V],_ t:Double)->[V]{zip(x,p).map{$0+$1*t}}
    static func sub(_ x:[V],_ y:[V])->[V]{zip(x,y).map{$0-$1}}
    static func dot(_ x:[V],_ y:[V])->Double{zip(x,y).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}}
    static func norm(_ x:[V])->Double{sqrt(dot(x,x))}
    static func object<T:Encodable>(_ x:T)throws->Any{try JSONSerialization.jsonObject(with:JSONEncoder().encode(x))}
    static func materials()throws->(J.M.Material,J.M.StrainBarrier,J.H.Material) {
        (try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
         try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
         try .init(bendingStiffnessNewtonMeter:2e-4))
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let decoder=JSONDecoder(),fixture=root.appendingPathComponent("Tests/NativeClothCollisionTests/Fixtures/IPCClothContact")
        let cases=try decoder.decode(Cases.self,from:Data(contentsOf:fixture.appendingPathComponent("generic-fd-cases.json")))
        guard let c=cases.cases.first(where:{$0.name=="self_plane_body_refine_2_generic"}) else {throw Failure.failed("Missing exact full-moving fixture")}
        let ref=c.rest.map{v($0[0],$0[1],0)},n=ref.count
        let groups=[J.H.PanelGroup(panelID:"front",vertexIDs:Array(0..<4),triangleIDs:[0,1]),
                    J.H.PanelGroup(panelID:"other",vertexIDs:Array(4..<13),triangleIDs:Array(2..<10))]
        let (m,b,h)=try materials(),mass=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:ref.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:c.triangles,arealDensity:0.18)
        var x=c.current.map{v($0[0]*1.04,$0[1]*1.04,$0[2]*1.04)};x[3].z+=2e-5
        let row=try GarmentCodeSewing.Constraint(a:.init(vertexID:0),b:.init(vertexID:4),initialGapMeters:(x[0]-x[4]).length)
        let core=try J.Prepared(referencePositions:ref,referenceTriangles:c.triangles,panelGroups:groups,massesKg:mass.massesKg,
            stitches:[row],material:m,strainBarrier:b,bendingMaterial:h,sewingComplianceMetersPerNewton:0.02)
        // A separate closed body sits below both moving cloth panels. Its
        // asymmetric centre keeps the combined FD away from exact feature ties.
        let cx=0.00131,cy=0.00073,lo = -0.05,top = -0.0008,r=0.03
        let body=[v(cx-r,cy-r,lo),v(cx+r,cy-r,lo),v(cx+r,cy+r,lo),v(cx-r,cy+r,lo),
                  v(cx-r,cy-r,top),v(cx+r,cy-r,top),v(cx+r,cy+r,top),v(cx-r,cy+r,top)]
        let bodyTriangles:[UInt32]=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7]
        let bodyObjective=try G.T.Prepared(cloth:core,referencePositions:ref,clothTriangleIndices:c.triangles,
            bodyPositions:body,bodyTriangleIndices:bodyTriangles,
            parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002))
        let full=try G.Prepared(body:bodyObjective,parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        let frame=try full.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.3),e=try frame.evaluate(positions:x)
        try require(e.selfContact.statistics.stencils>0 && e.body.body.statistics.stencils>0,"Self AND body forces active in the same objective")
        try require(e.body.cloth.strainBarrierJoules>0 && e.body.cloth.bendingJoules>0 && e.body.cloth.sewingJoules>0,"Source barrier, bending and real sewing active together")
        var rows:[[String:Double]]=[]
        for seed in [0.3,1.7,4.1] {
            let p=(0..<n).map{i in let a=Double(i)+seed;return v(sin(a*1.3),cos(a*0.7),sin(a*0.4+0.6))},step=1e-10
            let a=try frame.evaluate(positions:plus(x,p,step)),b=try frame.evaluate(positions:plus(x,p,-step))
            let fd=(a.energyJoules-b.energyJoules)/(2*step),g=dot(e.gradientNewton,p),gerror=abs(fd-g)/max(1e-8,abs(fd),abs(g))
            let hv=try frame.hessianProduct(at:e,direction:p),fdh=sub(a.gradientNewton,b.gradientNewton).map{$0/(2*step)}
            let coreHv=try frame.cloth.hessianProduct(positions:x,direction:p)
            let bodyHv=try e.body.body.hessianProduct(direction:p.map{SIMD3($0.x,$0.y,$0.z)})
            let selfHv=try e.selfContact.hessianProduct(direction:p.map{SIMD3($0.x,$0.y,$0.z)})
            let baseline=zip(zip(coreHv,bodyHv),selfHv).map{($0.0+v($0.1.x,$0.1.y,$0.1.z))+v($1.x,$1.y,$1.z)}
            try require(zip(hv,baseline).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern},"Cached combined raw Hv must match uncached source/body/self bits")
            let herror=norm(sub(hv,fdh))/max(1e-8,norm(hv),norm(fdh))
            try require(gerror<1e-5 && herror<2e-4,"Combined source/body/self E/g/Hv FD: \(gerror), \(herror)")
            let delta=try frame.energyDelta(from:b,to:a),ordinary=a.energyJoules-b.energyJoules
            let derror=abs(delta.energyJoules-ordinary)/max(1e-12,abs(ordinary))
            try require(derror<1e-5,"Resolvable combined energy increment")
            rows.append(["gradientRelativeError":gerror,"exactHvRelativeError":herror,"deltaRelativeDifference":derror])
        }
        let psd=try frame.selfPreconditioner(at:e)
        try require(psd.energyJoules==e.selfContact.energyJoules && psd.gradientNewtons==e.selfContact.gradientNewtons,"Self P must not change actual force")
        let other=try full.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.3)
        do {_ = try other.hessianProduct(at:e,direction:x);throw Failure.failed("Foreign frame accepted")}catch G.ObjectiveError.foreignEvaluation{}
        do {_ = try frame.evaluate(positions:x,isCancelled:{true});throw Failure.failed("Cancel ignored")}catch is CancellationError{}
        // Formal full-source factory: an actual sleeved shirt, not a trimmed
        // synthetic patch, retains all panels, masses and original stitch rows.
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let bodyParameters=GarmentCodeBodyParameters(values:catalog.body)
        var design=GarmentCodeDesignParameters(catalog:catalog)
        _ = design.setValue(.string("Shirt"),at:["meta","upper"])
        _ = design.setValue(.null,at:["meta","wb"]);_ = design.setValue(.null,at:["meta","bottom"])
        _ = design.setValue(.bool(false),at:["sleeve","sleeveless"])
        let source=try GarmentCodeNativeGenerator.generate(body:bodyParameters,design:design)
        var settings=GarmentCodeCircleDrape.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.solverIterations=32
        settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let original=try GarmentCodeNativeAssembly.prepare(document:source,body:bodyParameters,design:design,settings:settings,initialization:.rigidBodyAndClothPositiveClearance)
        let joint=try GarmentCodeJointInput.prepare(source:original,material:m,strainBarrier:b,bendingMaterial:h,sewingComplianceMetersPerNewton:1e-8)
        let prepared=try G.Prepared(input:joint,bodyParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        let actualFrame=try prepared.frame(predictor:original.cloth.positions,timeStepSeconds:1/240,sewingRamp:0)
        let actual=try actualFrame.evaluate(positions:original.cloth.positions)
        let official=try decoder.decode(Case.self,from:Data(contentsOf:fixture.appendingPathComponent("shirt-case.json")))
        let sameRest=official.rest==original.cloth.referencePositions.map{[$0.x,$0.y,$0.z]}
        let sameCurrent=official.current==original.cloth.positions.map{[$0.x,$0.y,$0.z]}
        try require(sameRest && sameCurrent && official.triangles==original.cloth.triangleIndices,"Exact original full-builder shirt control source")
        // The historical v1.6.1 unordered EE key aliases opposite edge orders
        // with different fixed distance functions. Compare with the separately
        // retained constructor-corrected full builder, including its real
        // signed leaves; the original oracle remains a historical artifact.
        let correctedPath="Tests/NativeClothCollisionTests/Fixtures/IPCOrientationIdentity/shirt-golden.json"
        let golden=try decoder.decode(ActualGolden.self,from:Data(contentsOf:root.appendingPathComponent(correctedPath))).case
        try require(actual.selfContact.statistics.stencils==golden.stencilCount &&
            actual.selfContact.statistics.negativeStencils==golden.negativeStencilCount,"All corrected signed actual shirt self terms retained")
        try require(abs(actual.selfContact.energyJoules-golden.energy)<1e-15,"Actual full-source corrected official self energy")
        let actualGradient=actual.selfContact.gradientNewtons.flatMap{[$0.x,$0.y,$0.z]}
        try require(actualGradient.count==golden.gradient.count && zip(actualGradient,golden.gradient).allSatisfy{abs($0-$1)<=1e-10},
                    "Actual full-source corrected official gradient")
        let direction=actual.selfContact.gradientNewtons.indices.map{i in
            SIMD3<Double>(sin(Double(i)+0.3),cos(Double(i)+0.7),0.4)
        },flatDirection=direction.flatMap{[$0.x,$0.y,$0.z]}
        var expectedProduct=Array(repeating:0.0,count:flatDirection.count)
        for row in golden.hessian {
            try require(row.count==3 && row.allSatisfy(\.isFinite),"Corrected oracle finite sparse Hessian entry")
            try require(row[0]>=0 && row[0]<Double(flatDirection.count) && row[0].rounded(.towardZero)==row[0] &&
                row[1]>=0 && row[1]<Double(flatDirection.count) && row[1].rounded(.towardZero)==row[1],"Corrected oracle Hessian indices")
            expectedProduct[Int(row[0])]+=row[2]*flatDirection[Int(row[1])]
        }
        let actualProduct=try actual.selfContact.hessianProduct(direction:direction).flatMap{[$0.x,$0.y,$0.z]}
        let productError=zip(actualProduct,expectedProduct).map{abs($0-$1)}.max() ?? 0
        try require(productError<=1e-6,"Actual full-source corrected official raw Hessian product")
        try require(prepared.body.cloth.massesKg.count==1732 && actual.gradientNewton.count==1732,"Complete original DOFs")
        let summary:[String:Any]=["passed":true,"simultaneousControls":rows,
            "syntheticBodyEnergyJoules":e.body.body.energyJoules,"syntheticSelfEnergyJoules":e.selfContact.energyJoules,
            "syntheticBendingJoules":e.body.cloth.bendingJoules,"syntheticBarrierJoules":e.body.cloth.strainBarrierJoules,
            "actualShirt":["sourceSHA256":joint.sourceSHA256,"panels":original.panelBindings.count,"vertices":1732,
                "sewingRows":joint.objective.sewingRows.count,"selfStencils":actual.selfContact.statistics.stencils,
                "negativeSelfStencils":actual.selfContact.statistics.negativeStencils,
                "selfEnergyJoules":actual.selfContact.energyJoules,"exactOfficialInputMatched":true,
                "reference":correctedPath,"referenceRawHvMaximumError":productError],
            "physicalStepAccepted":false,"scope":"Combined source/body/all-moving self E/G/raw Hv and formal full-source bridge; no whole garment dynamics acceptance."]
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-garment-objective-summary.json"))
        print("Joint garment objective: simultaneous active body/self/source derivatives and complete actual-shirt bridge passed.")
    }
}
