import Foundation
import NativeClothCollision

typealias M=GarmentCodeMembrane
typealias J=GarmentCodeJointObjective
typealias P=GarmentCodeJointPreconditioner
typealias V=M.V
nonisolated final class BarrierCancellation:@unchecked Sendable {
    let lock=NSLock();var count=0
    func stop()->Bool {lock.lock();defer{lock.unlock()};count+=1;return count>=3}
}
@main @MainActor struct PrincipalBarrierPreconditionerRegression {
    enum Failure:Error {case failed(String)}
    static func v(_ x:Double,_ y:Double,_ z:Double=0)->V {.init(x:x,y:y,z:z)}
    static func require(_ b:Bool,_ s:String)throws {if !b{throw Failure.failed(s)}}
    static func rejected(_ s:String,_ f:()throws->Void)throws {do{try f()}catch{return};throw Failure.failed("Accepted "+s)}
    static func flat(_ x:[V])->[Double] {x.flatMap{[$0.x,$0.y,$0.z]}}
    static func vectors(_ x:[Double])->[V] {stride(from:0,to:x.count,by:3).map{v(x[$0],x[$0+1],x[$0+2])}}
    static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    static func rotate(_ x:V)->V {
        let a=v(0.3,0.7,-0.2),n=a/a.length,c=cos(0.63),s=sin(0.63)
        return x*c+n.cross(x)*s+n*(dot(n,x)*(1-c))
    }
    static func raw(_ m:M.Prepared,_ x:[V],_ b:M.StrainBarrier)throws->[Double] {
        var h=Array(repeating:0.0,count:81)
        for k in 0..<9 {var p=Array(repeating:0.0,count:9);p[k]=1
            let q=flat(try m.principalBarrierHessianProduct(positions:x,direction:vectors(p),barrier:b))
            for i in 0..<9 {h[i*9+k]=q[i]}
        };return h
    }
    static func block(_ m:M.Prepared,_ x:[V],_ b:M.StrainBarrier)throws->[Double] {
        let r=try m.principalBarrierPreconditioner(positions:x,barrier:b)
        try require(r.blocks.count<=1,"Single source triangle")
        return r.blocks.first?.hessian ?? Array(repeating:0,count:81)
    }
    static func matrixRotate(_ h:[Double])->[Double] {
        var result=Array(repeating:0.0,count:81)
        let axes=[rotate(v(1,0,0)),rotate(v(0,1,0)),rotate(v(0,0,1))].map{[$0.x,$0.y,$0.z]}
        for i in 0..<9 {for j in 0..<9 {for a in 0..<3 {for b in 0..<3 {
            result[i*9+j]+=axes[a][i%3]*h[(3*(i/3)+a)*9+3*(j/3)+b]*axes[b][j%3]
        }}}};return result
    }
    static func maxError(_ a:[Double],_ b:[Double])->Double {zip(a,b).map{abs($0-$1)}.max() ?? 0}
    static func scale(_ x:[Double])->Double {max(1,x.map(abs).max() ?? 0)}
    static func main()throws {
        let out=URL(fileURLWithPath:CommandLine.arguments[1]),barrier=try M.StrainBarrier(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)
        let ref=[v(0,0),v(0.041,0.007),v(-0.009,0.052)],unit=[v(0,0),v(1,0),v(0,1)]
        let m=try M.Prepared(referencePositions:ref,triangleIndices:[0,1,2]),um=try M.Prepared(referencePositions:unit,triangleIndices:[0,1,2])
        let cases:[(String,Double,Double,Bool)]=[("inactive",1,1,false),("lower_activation",0.97,0.97,false),("upper_activation",1.03,1.03,false),
            ("uniform_stretch",1.05,1.05,false),("uniform_compression",0.95,0.95,false),("mixed",0.95,1.05,false),
            ("near_repeated_stretch",1.05,1.05+2e-14,true),("near_repeated_compression",0.95,0.95+2e-14,true),
            ("one_ulp_stretch",1.05,1.05.nextUp,true),("one_ulp_compression",0.95,0.95.nextUp,true),
            ("near_upper_limit",0.97812,1.0699462705470582,false),("near_lower_limit",0.9301,1.01,false)]
        var rows:[[String:Any]]=[],maximumCovariance=0.0,maximumScaling=0.0,maximumRenumbering=0.0
        for (name,sl,sh,near) in cases {
            let angle=0.37,c=cos(angle),s=sin(angle),fu=v(sl*c,sh*s),fv=v(-sl*s,sh*c)
            let ux=[V.zero,fu,fv],x=ref.map{fu*$0.x+fv*$0.y}
            let h=try block(m,x,barrier),uh=try block(um,ux,barrier),rawH=try raw(um,ux,barrier)
            let before=try m.principalBarrier(positions:x,barrier:barrier),beforeHv=try m.principalBarrierHessianProduct(positions:x,direction:ref,barrier:barrier)
            let rotated=try block(m,x.map(rotate),barrier),covariance=maxError(rotated,matrixRotate(h))/scale(h)
            let scaledM=try M.Prepared(referencePositions:ref.map{$0*10},triangleIndices:[0,1,2]),scaled=try block(scaledM,x.map{$0*10},barrier)
            let scaling=maxError(h,scaled)/scale(h)
            let permutation=[1,2,0],pm=try M.Prepared(referencePositions:permutation.map{ref[$0]},triangleIndices:[0,1,2]),ph=try block(pm,permutation.map{x[$0]},barrier)
            var restored=Array(repeating:0.0,count:81)
            for i in 0..<9 {for j in 0..<9 {restored[(3*permutation[i/3]+i%3)*9+3*permutation[j/3]+j%3]=ph[i*9+j]}}
            let renumber=maxError(h,restored)/scale(h)
            maximumCovariance=max(maximumCovariance,covariance);maximumScaling=max(maximumScaling,scaling);maximumRenumbering=max(maximumRenumbering,renumber)
            try require(covariance<2e-10 && scaling<2e-10 && renumber<2e-10,"Covariance/SI/renumbering "+name)
            let after=try m.principalBarrier(positions:x,barrier:barrier),afterHv=try m.principalBarrierHessianProduct(positions:x,direction:ref,barrier:barrier)
            try require(before.energyJoules.bitPattern==after.energyJoules.bitPattern && flat(before.gradientNewton).map(\.bitPattern)==flat(after.gradientNewton).map(\.bitPattern) &&
                flat(beforeHv).map(\.bitPattern)==flat(afterHv).map(\.bitPattern),"True barrier E/g/rawHv changed")
            let f=try um.deformation(positions:ux,triangleID:0),t=m.triangles[0]
            let raw6=(3..<9).flatMap{i in (3..<9).map{j in rawH[i*9+j]/0.5}},psd6=(3..<9).flatMap{i in (3..<9).map{j in uh[i*9+j]/0.5}}
            rows.append(["name":name,"nearRepeated":near,"F":[[fu.x,fv.x],[fu.y,fv.y],[fu.z,fv.z]],"rawDensity6":raw6,"PSDDensity6":psd6,
                "localPSD9":h,"du":[t.du.x,t.du.y,t.du.z],"dv":[t.dv.x,t.dv.y,t.dv.z],"sourceArea":t.referenceAreaSquareMeters,
                "singularValues":[f.minimumPrincipalStretch,f.maximumPrincipalStretch],"covarianceRelativeError":covariance,"SIScalingRelativeError":scaling,"renumberingRelativeError":renumber])
        }
        let square=[v(0,0),v(0.1,0),v(0.1,0.1),v(0,0.1)],tri:[UInt32]=[0,1,2,0,2,3],sm=try M.Prepared(referencePositions:square,triangleIndices:tri),sx=square.map{$0*1.05}
        let valid=try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier)
        try require(valid.blocks.count==2 && valid.chargedStagedBytes>0,"All active source triangles")
        var one=M.BarrierPreconditionerLimits();one.maximumBlocks=1
        try rejected("block budget"){_ = try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier,limits:one)}
        one = .init();one.maximumStagedBytes=valid.chargedStagedBytes-1
        try rejected("staged byte budget"){_ = try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier,limits:one)}
        one = .init();one.maximumStagedBytes=0
        try rejected("invalid budget"){_ = try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier,limits:one)}
        try rejected("cancel at start"){_ = try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier,isCancelled:{true})}
        let cancellation=BarrierCancellation()
        do {_ = try sm.principalBarrierPreconditioner(positions:sx,barrier:barrier,isCancelled:{cancellation.stop()});throw Failure.failed("Late cancellation ignored")}catch is CancellationError{}
        try require(cancellation.count>=3,"Late callback reached after staging")
        // Use strictly outside states: multiplying a decimal boundary by the
        // source coordinates can round the resulting singular value inward.
        for s in [0.9299,1.0701] {try rejected("outside strict barrier domain"){_ = try sm.principalBarrierPreconditioner(positions:square.map{$0*s},barrier:barrier)}}
        try rejected("wrong coordinate count"){_ = try sm.principalBarrierPreconditioner(positions:Array(sx.dropLast()),barrier:barrier)}
        var nan=sx;nan[0].x = .nan
        try rejected("nonfinite coordinates"){_ = try sm.principalBarrierPreconditioner(positions:nan,barrier:barrier)}
        let groups=[J.H.PanelGroup(panelID:"source",vertexIDs:[0,1,2,3],triangleIDs:[0,1])]
        func core(_ b:M.StrainBarrier)throws->J.Prepared {try .init(referencePositions:square,referenceTriangles:tri,panelGroups:groups,massesKg:Array(repeating:0.001,count:4),stitches:[],
            material:.init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),strainBarrier:b,bendingMaterial:.init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)}
        let actual=try core(barrier),wide=try core(.init(lowerLimit:0.8,lowerActivation:0.9,upperActivation:1.1,upperLimit:1.2,stiffnessNewtonPerMeter:11))
        let pp=try P.Plan(prepared:actual),wp=try P.Plan(prepared:wide),pw=try pp.makeWorkspace(),ww=try wp.makeWorkspace()
        try require(pp.columnStarts==wp.columnStarts && pp.rowIndices==wp.rowIndices,"Barrier proxy must not extend source graph")
        let frame=try actual.frame(predictor:sx,timeStepSeconds:1/240,sewingRamp:1),wf=try wide.frame(predictor:sx,timeStepSeconds:1/240,sewingRamp:1)
        let e=try frame.evaluate(positions:sx),dir=square.map{v(sin($0.x+0.3),cos($0.y+0.7),0.4)},hv=try frame.hessianProduct(positions:sx,direction:dir)
        let report=try pw.update(frame:frame,positions:sx);_ = try ww.update(frame:wf,positions:sx)
        var expected=Array(repeating:0.0,count:pp.rowIndices.count)
        for block in valid.blocks {for x in pp.sourceScatter[block.triangleID] {expected[x.offset]+=block.hessian[9*x.a+x.b]}}
        let actualDelta=zip(pw.lowerValues,ww.lowerValues).map{$0-$1},scatterError=maxError(actualDelta,expected)/scale(expected)
        try require(scatterError<1e-12 && report.principalBarrierTriangles==2,"Complete barrier source scatter")
        let e2=try frame.evaluate(positions:sx),hv2=try frame.hessianProduct(positions:sx,direction:dir)
        try require(e.energyJoules.bitPattern==e2.energyJoules.bitPattern && flat(e.gradientNewton).map(\.bitPattern)==flat(e2.gradientNewton).map(\.bitPattern) && flat(hv).map(\.bitPattern)==flat(hv2).map(\.bitPattern),"Full true objective E/g/rawHv changed")
        try rejected("foreign barrier parameters"){_ = try pw.update(frame:wf,positions:sx)}
        try rejected("foreign failure leaves no factor"){_ = try pw.product(dir)}
        var limited=P.Limits();limited.principalBarrier.maximumStagedBytes=1
        let lw=try P.Plan(prepared:actual,limits:limited).makeWorkspace()
        _ = try lw.update(frame:actual.frame(predictor:square,timeStepSeconds:1/240,sewingRamp:1),positions:square)
        try rejected("P active staging budget"){_ = try lw.update(frame:frame,positions:sx)}
        try require(lw.latest==nil,"Budget failure cannot retain factor report")
        try rejected("budget failure leaves no factor"){_ = try lw.product(dir)}
        let result:[String:Any]=["passed":true,"scope":"Pure source principal-barrier PSD numerical preconditioner; true operators unchanged; no garment acceptance", "cases":rows,
            "maximumCovarianceRelativeError":maximumCovariance,"maximumSIScalingRelativeError":maximumScaling,"maximumRenumberingRelativeError":maximumRenumbering,
            "sourceScatterRelativeError":scatterError,"existingGraphUnchanged":true,"trueFullObjectiveBitwiseUnchanged":true,"lateCancellationReached":true,
            "invalidDomainCoordinateBudgetAndStaleFactorControlsPassed":true]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("principal-barrier-preconditioner.json"))
        print("Principal barrier PSD matrices and true-operator boundary controls exported for independent eigenvalue oracle.")
    }
}
