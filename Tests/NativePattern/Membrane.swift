import Foundation
import CryptoKit

@main @MainActor
struct MembraneRegression {
    typealias M=GarmentCodeMembrane
    typealias V=M.V
    enum Failure:Error {case check(String)}
    static func v(_ x:Double,_ y:Double=0,_ z:Double=0)->V {.init(x:x,y:y,z:z)}
    static func require(_ value:@autoclosure()throws->Bool,_ reason:String)throws {if try !value(){throw Failure.check(reason)}}
    static func near(_ a:Double,_ b:Double,_ tolerance:Double=1e-10)->Bool {abs(a-b)<=tolerance*max(1,abs(a),abs(b))}
    static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    static func sum(_ a:[V])->V {a.reduce(V.zero,+)}
    static func component(_ x:V,_ a:Int)->Double {a==0 ? x.x:(a==1 ? x.y:x.z)}
    static func changed(_ x:V,_ a:Int,_ delta:Double)->V {v(x.x+(a==0 ? delta:0),x.y+(a==1 ? delta:0),x.z+(a==2 ? delta:0))}
    static func invalid(_ body:()throws->Void)throws {
        do {try body()} catch is M.MembraneError {return};throw Failure.check("Invalid membrane input was accepted")
    }
    static func cancelled(_ body:()throws->Void)throws {
        do {try body()} catch is CancellationError {return};throw Failure.check("Cancellation did not propagate")
    }
    struct Capture:Decodable {
        let referencePositions:[V],positions:[V],frame60Positions:[V],referenceTriangles:[UInt32],simulationTriangleIndices:[UInt32]
        let sourceSHA256:String
    }
    struct Oracle:Decodable {
        struct Probe:Decodable {let vertex:Int,axis:Int,gradientNewton:Double}
        let minimumPrincipalStretch:Double,maximumPrincipalStretch:Double,minimumAreaRatio:Double
        let referenceAreaSquareMeters:Double,actualAreaSquareMeters:Double,energyJoules:Double
        let shearStiffnessNewtonPerMeter:Double,areaStiffnessNewtonPerMeter:Double
        let frame60MaximumEdgeStrain:Double,frame60MaximumPrincipalStretch:Double
        let gradientProbes:[Probe]
    }
    static func derivativeCheck(_ m:M.Prepared,_ x:[V],_ material:M.Material)throws->Double {
        let e=try m.neoHookean(positions:x,material:material)
        let d=x.indices.map{v(sin(Double($0)*1.7+0.1),cos(Double($0)*0.6),sin(Double($0)*0.3+0.7))}
        let z=x.indices.map{v(cos(Double($0)*1.3),sin(Double($0)*0.4+0.2),cos(Double($0)*0.7))}
        let h=1e-6
        let hv=try m.neoHookeanHessianProduct(positions:x,direction:d,material:material)
        let hz=try m.neoHookeanHessianProduct(positions:x,direction:z,material:material)
        let plus=try m.neoHookean(positions:zip(x,d).map{$0+$1*h},material:material)
        let minus=try m.neoHookean(positions:zip(x,d).map{$0-$1*h},material:material)
        var error=0.0
        for i in x.indices {
            let fd=(plus.gradientNewton[i]-minus.gradientNewton[i])/(2*h)
            error=max(error,(fd-hv[i]).length/max(1,hv[i].length))
            for a in 0..<3 {
                var p=x,n=x;p[i]=changed(x[i],a,h);n[i]=changed(x[i],a,-h)
                let ep=try m.neoHookean(positions:p,material:material).energyJoules
                let en=try m.neoHookean(positions:n,material:material).energyJoules
                try require(near((ep-en)/(2*h),component(e.gradientNewton[i],a),2e-7),"Energy gradient central-difference mismatch")
            }
        }
        try require(error<2e-6,"Exact Hessian product does not match differentiated gradient: \(error)")
        let a=zip(z,hv).reduce(0.0){$0+dot($1.0,$1.1)},b=zip(d,hz).reduce(0.0){$0+dot($1.0,$1.1)}
        try require(near(a,b,1e-10),"Membrane Hessian is not symmetric")
        try require(sum(e.gradientNewton).length<1e-9,"Internal membrane force changed total momentum")
        try require(zip(x,e.gradientNewton).map{$0.cross($1)}.reduce(V.zero,+).length<1e-9,"Internal membrane force changed total torque")
        let translation=try m.neoHookeanHessianProduct(positions:x,direction:Array(repeating:v(1,2,-0.5),count:x.count),material:material)
        try require(translation.allSatisfy{$0.length<1e-12},"Rigid translation is not a Hessian null mode")
        return error
    }
    static func barrierDerivativeCheck(_ m:M.Prepared,_ x:[V],_ barrier:M.StrainBarrier)throws->Double {
        let e=try m.principalBarrier(positions:x,barrier:barrier)
        let d=x.indices.map{v(sin(Double($0)*0.3+0.1),cos(Double($0)*0.7+0.2),sin(Double($0)*0.8+0.3))}
        let hv=try m.principalBarrierHessianProduct(positions:x,direction:d,barrier:barrier)
        let h=1e-7
        let plus=try m.principalBarrier(positions:zip(x,d).map{$0+$1*h},barrier:barrier)
        let minus=try m.principalBarrier(positions:zip(x,d).map{$0-$1*h},barrier:barrier)
        var error=0.0
        for i in x.indices {
            let fd=(plus.gradientNewton[i]-minus.gradientNewton[i])/(2*h)
            error=max(error,(fd-hv[i]).length/max(1,hv[i].length))
            for a in 0..<3 {
                var p=x,n=x;p[i]=changed(x[i],a,h);n[i]=changed(x[i],a,-h)
                let ep=try m.principalBarrier(positions:p,barrier:barrier).energyJoules
                let en=try m.principalBarrier(positions:n,barrier:barrier).energyJoules
                try require(near((ep-en)/(2*h),component(e.gradientNewton[i],a),2e-7),"Principal barrier gradient does not match finite differences")
            }
        }
        try require(error<2e-5,"Principal barrier Hessian finite-difference mismatch: \(error); state \(x)")
        try require(sum(e.gradientNewton).length<1e-10 && zip(x,e.gradientNewton).map{$0.cross($1)}.reduce(V.zero,+).length<1e-10,"Barrier lost rigid momentum invariance")
        return error
    }
    static func main()throws {
        let ref=[v(0),v(1),v(0,1)],tris:[UInt32]=[0,1,2]
        let material=try M.Material(shearStiffnessNewtonPerMeter:17,areaStiffnessNewtonPerMeter:9)
        let m=try M.Prepared(referencePositions:ref,triangleIndices:tris)
        let atRest=try m.inspect(positions:ref),zero=try m.neoHookean(positions:ref,material:material)
        try require(atRest.minimumPrincipalStretch==1 && atRest.maximumPrincipalStretch==1 && atRest.referenceAreaSquareMeters==0.5 &&
                    zero.energyJoules==0 && zero.gradientNewton.allSatisfy{$0 == .zero},"Original metric is not stress free")
        // Large SO(3) rotation + translation, independent of world facing.
        func rotate(_ x:V)->V {v(x.z,-x.x,-x.y)}
        let rigid=ref.map{rotate($0)+v(1.7,-0.4,0.8)}
        let er=try m.neoHookean(positions:rigid,material:material),qr=try m.inspect(positions:rigid)
        try require(abs(er.energyJoules)<1e-12 && qr.maximumAbsolutePrincipalStrain<1e-12 && er.gradientNewton.allSatisfy{$0.length<1e-11},"Rigid motion acquired membrane energy")
        let stiff=try M.Material(shearStiffnessNewtonPerMeter:1e12,areaStiffnessNewtonPerMeter:1e12)
        let nearRigid=[v(0),v(-0.8451679802466643,-0.5345007812583384),v(0.3602260452304105,-0.5695997644061068,-0.7387782513895262)]
        let stiffRigid=try m.neoHookean(positions:nearRigid,material:stiff)
        try require(stiffRigid.energyJoules>=0 && stiffRigid.energyJoules<1e-16,"Near-rigid energy lost its nonnegative quadratic scale at high stiffness")
        let scale=1.2,stretched=ref.map{$0*scale},l=log(scale)
        let expected=0.5*(17*(scale*scale-1-2*l)+2*9*l*l)
        try require(near(try m.neoHookean(positions:stretched,material:material).energyJoules,expected),"Uniform dilation analytic energy incorrect")
        let shear=0.3,sheared=ref.map{v($0.x+shear*$0.y,$0.y,$0.z)}
        try require(near(try m.neoHookean(positions:sheared,material:material).energyJoules,0.5*0.5*17*shear*shear),"Simple-shear analytic energy incorrect")
        var maxHessianError=0.0
        for x in [stretched,sheared,[v(0.1,0.2,0.3),v(1.15,0.3,0.2),v(-0.1,1.1,0.5)]] {
            maxHessianError=max(maxHessianError,try derivativeCheck(m,x,material))
            let e=try m.neoHookean(positions:x,material:material),xr=x.map{rotate($0)+v(-0.4,0.7,1.2)}
            let rotated=try m.neoHookean(positions:xr,material:material)
            try require(near(e.energyJoules,rotated.energyJoules) && zip(e.gradientNewton,rotated.gradientNewton).allSatisfy{(rotate($0)-$1).length<1e-9},"Energy/gradient does not transform objectively")
        }
        let barrier=try M.StrainBarrier(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)
        let quiet=try m.principalBarrier(positions:ref,barrier:barrier)
        try require(quiet.energyJoules==0 && quiet.gradientNewton.allSatisfy{$0 == .zero},"Barrier added an artificial rest stress")
        var maxBarrierHessianError=0.0
        for x in [ref.map{$0*1.05},ref.map{$0*0.95},[v(0),v(1.05),v(0,0.95)],ref.map{v($0.x+0.1*$0.y,$0.y)}] {
            maxBarrierHessianError=max(maxBarrierHessianError,try barrierDerivativeCheck(m,x,barrier))
        }
        let repeatedRotated=ref.map {p->V in
            let x=p.x*1.05,y=p.y*1.05
            return v(0.6*x-0.64*y,0.8*x+0.48*y,0.6*y)+v(0.1,-0.3,0.7)
        }
        maxBarrierHessianError=max(maxBarrierHessianError,try barrierDerivativeCheck(m,repeatedRotated,barrier))
        for dilation in [0.93,1.07,0.8,1.2] {try invalid{_=try m.principalBarrier(positions:ref.map{$0*dilation},barrier:barrier)}}
        let towardCollapse=ref.map{$0*(-2)},safe=try m.principalBarrierStepLimit(positions:ref,direction:towardCollapse,barrier:barrier)
        try require(safe>0 && safe<0.04,"Weyl step limit permitted a path through a collapsed triangle")
        for i in 0...32 {
            let f=Double(i)/32*safe
            _=try m.principalBarrier(positions:zip(ref,towardCollapse).map{$0+$1*f},barrier:barrier)
        }
        try require(try m.principalBarrierStepLimit(positions:ref,direction:Array(repeating:v(1,2,3),count:3),barrier:barrier)==1,"A rigid translation was unnecessarily limited")
        try invalid{_=try m.principalBarrierStepLimit(positions:ref.map{$0*1.08},direction:ref,barrier:barrier)}
        try cancelled{_=try m.principalBarrier(positions:ref,barrier:barrier,isCancelled:{true})}
        try cancelled{_=try m.principalBarrierHessianProduct(positions:ref,direction:ref,barrier:barrier,isCancelled:{true})}
        try cancelled{_=try m.principalBarrierStepLimit(positions:ref,direction:ref,barrier:barrier,isCancelled:{true})}
        let thin=[v(0),v(1),v(0.5,0.01)],thinMoved=[v(0),v(1),v(0.5,0.02)]
        let thinMetric=try M.Prepared(referencePositions:thin,triangleIndices:tris).inspect(positions:thinMoved)
        let edgeMax=[(0,1),(1,2),(2,0)].map{abs((thinMoved[$0.0]-thinMoved[$0.1]).length/(thin[$0.0]-thin[$0.1]).length-1)}.max()!
        try require(edgeMax<0.001 && near(thinMetric.maximumPrincipalStretch,2),"Thin triangle failed to expose edge-only strain blind spot")
        let doubled=try M.Prepared(referencePositions:ref.map{$0*2},triangleIndices:tris)
        let es=try m.neoHookean(positions:sheared,material:material),ed=try doubled.neoHookean(positions:sheared.map{$0*2},material:material)
        try require(near(ed.energyJoules,es.energyJoules*4) && zip(es.gradientNewton,ed.gradientNewton).allSatisfy{($0*2-$1).length<1e-10},"SI area/force scaling was renormalized")
        let refinedRef=ref+[(ref[0]+ref[1]+ref[2])/3],refinedX=sheared+[(sheared[0]+sheared[1]+sheared[2])/3]
        let refined=try M.Prepared(referencePositions:refinedRef,triangleIndices:[0,1,3,1,2,3,2,0,3])
        let refinedE=try refined.neoHookean(positions:refinedX,material:material)
        try require(near(refinedE.energyJoules,es.energyJoules),"Affine source refinement changed physical energy")
        for i in 0..<3 {try require((refinedE.gradientNewton[i]+refinedE.gradientNewton[3]/3-es.gradientNewton[i]).length<1e-10,"Refinement changed affine virtual work")}
        let collapsed=[v(0),v(1),v(0.5)]
        try require(try m.inspect(positions:collapsed).degenerateTriangles==1,"Collapse was hidden by metric clamping")
        try invalid{_=try m.neoHookean(positions:collapsed,material:material)}
        try invalid{_=try m.neoHookeanHessianProduct(positions:collapsed,direction:ref,material:material)}
        try invalid{_=try M.Material(shearStiffnessNewtonPerMeter:0,areaStiffnessNewtonPerMeter:1)}
        try invalid{_=try M.Material(shearStiffnessNewtonPerMeter:1,areaStiffnessNewtonPerMeter:-1)}
        try invalid{_=try M.Prepared(referencePositions:ref,triangleIndices:[0,2,1])}
        try invalid{_=try M.Prepared(referencePositions:ref,triangleIndices:[0,1,3])}
        try invalid{_=try M.Prepared(referencePositions:ref+[v(1,1)],triangleIndices:tris)}
        try invalid{_=try m.inspect(positions:[v(.nan),v(1),v(0,1)])}
        try invalid{_=try m.neoHookeanHessianProduct(positions:ref,direction:[],material:material)}
        try cancelled{_=try M.Prepared(referencePositions:ref,triangleIndices:tris,isCancelled:{true})}
        try cancelled{_=try m.inspect(positions:ref,isCancelled:{true})}
        try cancelled{_=try m.neoHookean(positions:ref,material:material,isCancelled:{true})}
        try cancelled{_=try m.neoHookeanHessianProduct(positions:ref,direction:ref,material:material,isCancelled:{true})}
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir=root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-membrane")
        let capture=try JSONDecoder().decode(Capture.self,from:Data(contentsOf:dir.appendingPathComponent("native-rigid-469.json")))
        let oracle=try JSONDecoder().decode(Oracle.self,from:Data(contentsOf:dir.appendingPathComponent("numpy-svd-oracle.json")))
        let source=try JSONDecoder().decode(GarmentCodePatternFile.self,from:Data(contentsOf:dir.appendingPathComponent("complete-source.json")))
        let sourceEncoder=JSONEncoder();sourceEncoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let sourceHash=SHA256.hash(data:try sourceEncoder.encode(source)).map{String(format:"%02x",$0)}.joined()
        try require(sourceHash==capture.sourceSHA256,"Captured original full paper lost its canonical source identity")

        let actual=try M.Prepared(referencePositions:capture.referencePositions,triangleIndices:capture.referenceTriangles)
        try invalid{_=try M.Prepared(referencePositions:capture.referencePositions,triangleIndices:capture.simulationTriangleIndices)}
        let frame60=try actual.inspect(positions:capture.frame60Positions)
        try require(oracle.frame60MaximumEdgeStrain<0.051 && near(frame60.maximumPrincipalStretch,oracle.frame60MaximumPrincipalStretch) && frame60.maximumPrincipalStretch>1.18,"Real early frame failed to preserve the edge/principal-strain counterexample")
        try invalid{_=try actual.principalBarrier(positions:capture.frame60Positions,barrier:barrier)}
        let quality=try actual.inspect(positions:capture.positions)
        let realMaterial=try M.Material(shearStiffnessNewtonPerMeter:oracle.shearStiffnessNewtonPerMeter,areaStiffnessNewtonPerMeter:oracle.areaStiffnessNewtonPerMeter)
        let evaluation=try actual.neoHookean(positions:capture.positions,material:realMaterial)
        try require(near(quality.minimumPrincipalStretch,oracle.minimumPrincipalStretch) && near(quality.maximumPrincipalStretch,oracle.maximumPrincipalStretch) &&
                    near(quality.minimumAreaRatio,oracle.minimumAreaRatio) && near(quality.referenceAreaSquareMeters,oracle.referenceAreaSquareMeters) &&
                    near(quality.actualAreaSquareMeters,oracle.actualAreaSquareMeters) && near(evaluation.energyJoules,oracle.energyJoules),"Captured garment differs from independent LAPACK SVD oracle")
        try invalid{_=try actual.principalBarrier(positions:capture.positions,barrier:barrier)}
        var probeError=0.0
        for probe in oracle.gradientProbes {
            let actual=component(evaluation.gradientNewton[probe.vertex],probe.axis)
            probeError=max(probeError,abs(actual-probe.gradientNewton)/max(1,abs(probe.gradientNewton)))
        }
        try require(probeError<2e-6,"Actual captured membrane gradient failed independent SVD energy differences: \(probeError)")
        let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_MEMBRANE_OUTPUT"] ?? "/private/tmp/TailorAssMembrane")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let qualityData=try JSONEncoder().encode(quality),qualityJSON=try JSONSerialization.jsonObject(with:qualityData)
        let result:[String:Any]=["passed":true,"scope":"Source membrane metric, energy and derivatives only; no contact, sewn-garment solve or App routing claimed", "actualRejectedSourceSHA256":capture.sourceSHA256,
            "actualFrame60MaximumEdgeStrain":oracle.frame60MaximumEdgeStrain,"actualFrame60MaximumPrincipalStretch":frame60.maximumPrincipalStretch,"thinTriangleMaximumEdgeStrain":edgeMax,"thinTriangleMaximumPrincipalStretch":thinMetric.maximumPrincipalStretch,
            "maximumAnalyticHessianRelativeError":maxHessianError,"maximumPrincipalBarrierHessianRelativeError":maxBarrierHessianError,"principalFeasiblePathStepFraction":safe,"maximumIndependentSVDGradientRelativeError":probeError,
            "realEnergyJoules":evaluation.energyJoules,"actualRejectedFrameMembraneQuality":qualityJSON]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("membrane-summary.json"))
        print("PASS membrane: source metric, rigid/affine/SI/refinement invariance, thin-triangle blind spot, exact gradient/Hessian, collapse/input/cancel rejection, real rejected 469-frame independent SVD oracle")
        print("Hessian relative error \(maxHessianError); real SVD energy-gradient error \(probeError)")
    }
}
