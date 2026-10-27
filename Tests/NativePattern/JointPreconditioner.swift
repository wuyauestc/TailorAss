import Foundation
import CryptoKit
import NativeClothCollision

typealias P=GarmentCodeJointPreconditioner
typealias J=GarmentCodeJointObjective
typealias V=J.V
nonisolated private final class HingePreconditionerCancellation: @unchecked Sendable {
    private let lock=NSLock();private var calls=0
    func cancelled()->Bool {lock.lock();defer{lock.unlock()};calls+=1;return calls>=5}
}
@main @MainActor struct JointPreconditionerRegression {
    enum Failure:Error {case failed(String)}
    struct Snapshot:Decodable {let positions:[V]}
    struct Source:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[J.H.PanelGroup],sourceSHA256:String}
    struct Mass:Decodable {let massesKg:[Double],pinned:[Bool],sourceSHA256:String}
    struct Oracle:Decodable {let direction:[V],hessianProduct:[V],sourceSHA256:String}
    struct Matrix:Decodable {let dimension:Int,columnStarts:[Int64],rowIndices:[Int32],values:[Double]}
    static func require(_ ok:Bool,_ s:String)throws {if !ok{throw Failure.failed(s)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
    static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    static func dot(_ a:[V],_ b:[V])->Double {zip(a,b).reduce(0){$0+dot($1.0,$1.1)}}
    static func norm(_ a:[V])->Double {sqrt(dot(a,a))}
    static func sub(_ a:[V],_ b:[V])->[V] {zip(a,b).map{$0-$1}}
    static func direction(_ n:Int,_ seed:Int=1)->[V] {(0..<n).map{i in v(sin(Double(i*7+seed)),cos(Double(i*11+seed)),sin(Double(i*13+seed)))}}
    static func rotate(_ a:V)->V {let c=cos(0.63),s=sin(0.63);return v(c*a.x-s*a.y,s*a.x+c*a.y,a.z)}
    static func rejected(_ body:()throws->Void)throws {do{try body()}catch{return};throw Failure.failed("Rejected preconditioner operation succeeded")}
    static func matrixHash(_ plan:P.Plan,_ values:[Double])->String {
        var data=Data("joint-P-csc-values-v1\0".utf8)
        func append<T:FixedWidthInteger>(_ x:T){var y=x.littleEndian;withUnsafeBytes(of:&y){data.append(contentsOf:$0)}}
        append(UInt64(plan.dimension));for x in plan.columnStarts {append(x)};for x in plan.rowIndices {append(x)}
        for x in values {append(x.bitPattern)}
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2]),decoder=JSONDecoder()
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let material=try J.M.Material(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170)
        let barrier=try J.M.StrainBarrier(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)
        let bending=try J.H.Material(bendingStiffnessNewtonMeter:0)
        let square=[v(0,0,0),v(0.1,0,0),v(0.1,0.1,0),v(0,0.1,0)],ref=square+square
        let triangles:[UInt32]=[0,1,2,0,2,3,4,5,6,4,6,7]
        let groups=[J.H.PanelGroup(panelID:"a",vertexIDs:[0,1,2,3],triangleIDs:[0,1]),J.H.PanelGroup(panelID:"b",vertexIDs:[4,5,6,7],triangleIDs:[2,3])]
        let a=try GarmentCodeSewing.Attachment(vertexIDs:[1,2],weights:[0.25,0.75]),b=try GarmentCodeSewing.Attachment(vertexIDs:[4,7],weights:[0.4,0.6])
        let stitches=[try GarmentCodeSewing.Constraint(a:a,b:b,initialGapMeters:0.12)]
        let mass=(0..<8).map{pow(2,Double($0))*1e-5}
        func make(_ constraints:[GarmentCodeSewing.Constraint]?=nil,_ compliance:Double=0.02,bendingMaterial:J.H.Material?=nil,panelGroups:[J.H.PanelGroup]?=nil)throws->J.Prepared {
            try .init(referencePositions:ref,referenceTriangles:triangles,panelGroups:panelGroups ?? groups,massesKg:mass,stitches:constraints ?? stitches,material:material,strainBarrier:barrier,bendingMaterial:bendingMaterial ?? bending,sewingComplianceMetersPerNewton:compliance)
        }
        let prepared=try make(),plan=try P.Plan(prepared:prepared),workspace=try plan.makeWorkspace()
        let x=ref.enumerated().map{i,p in let c=cos(0.7),s=sin(0.7);return v(c*p.x,p.y,-s*p.x)+v(i<4 ? 0:0.25,0,0.02)}
        let frame=try prepared.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.4),before=try frame.evaluate(positions:x),p=direction(8),q=direction(8,2)
        let update=try workspace.update(frame:frame,positions:x),pp=try workspace.product(p),hp=try frame.hessianProduct(positions:x,direction:p)
        var kb0Hashes=["synthetic":matrixHash(plan,workspace.lowerValues)]
        let relative=norm(sub(pp,hp))/norm(hp)
        try require(relative<1e-12,"Isometric current polar source plus positive scalar tangent must match true H: \(relative)")
        let pq=try workspace.product(q),sym=abs(dot(p,pq)-dot(q,pp))/max(1,abs(dot(p,pq)),abs(dot(q,pp)))
        try require(sym<1e-12 && dot(p,pp)>0,"P symmetry/positivity")
        let solved=try workspace.solve(rhs:p,generation:update.linear.generation),residual=norm(sub(try workspace.product(solved.vector),p))/norm(p)
        try require(residual<1e-8 && solved.linear.quadraticForm>0,"Pz true residual")
        let after=try frame.evaluate(positions:x)
        try require(before.energyJoules==after.energyJoules && before.gradientNewton==after.gradientNewton,"Preconditioner must not change Phi or gradient")
        let rotated=x.map(rotate),rotatedFrame=try prepared.frame(predictor:rotated,timeStepSeconds:1/240,sewingRamp:0.4)
        _=try workspace.update(frame:rotatedFrame,positions:rotated)
        let covariance=norm(sub(try workspace.product(p.map(rotate)),pp.map(rotate)))/norm(pp)
        try require(covariance<1e-12,"Polar source/frame rigid covariance: \(covariance)")
        // Actual H retains negative transverse sewing curvature. P clips only that block.
        let compressedRow=try GarmentCodeSewing.Constraint(a:.init(vertexID:0),b:.init(vertexID:4),initialGapMeters:0.5)
        let compressed=try make([compressedRow]),unsewn=try make([])
        let xf=ref.enumerated().map{i,p in p+v(i<4 ? 0:0.2,0,0)},cf=try compressed.frame(predictor:xf,timeStepSeconds:1/240,sewingRamp:0),uf=try unsewn.frame(predictor:xf,timeStepSeconds:1/240,sewingRamp:0)
        var tangent=Array(repeating:V.zero,count:8);tangent[0]=v(0,1,0)
        let negative=dot(tangent,sub(try cf.hessianProduct(positions:xf,direction:tangent),try uf.hessianProduct(positions:xf,direction:tangent)))
        let cw=try P.Plan(prepared:compressed).makeWorkspace(),cr=try cw.update(frame:cf,positions:xf)
        try require(negative < -1 && cr.negativeTransverseRowsClippedOnlyInPreconditioner==1 && dot(tangent,try cw.product(tangent))>0,"Only P may clip signed sewing curvature")
        // Smooth zero target is k*I even at exact coincidence; no epsilon normal.
        let zf=try compressed.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:1)
        _=try cw.update(frame:zf,positions:ref)
        let zeroTargetError=norm(sub(try cw.product(p),try zf.hessianProduct(positions:ref,direction:p)))/norm(try cw.product(p))
        try require(zeroTargetError<1e-12,"Closed coincident target must be smooth kI")
        let bad=try compressed.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0)
        try rejected{_=try cw.update(frame:bad,positions:ref)}
        try rejected{_=try cw.product(p)}
        try rejected{_=try P.Plan(prepared:prepared,isCancelled:{true})}
        _=try workspace.update(frame:frame,positions:x)
        try rejected{_=try workspace.update(frame:frame,positions:x,isCancelled:{true})}
        try rejected{_=try workspace.product(p)}
        var tiny=P.Limits();tiny.maximumSourceTriangles=1
        try rejected{_=try P.Plan(prepared:prepared,limits:tiny)}
        // Hinge GN belongs only to P. The exact folded H contains additional
        // theta*Dq curvature, which must remain in the true objective.
        let hingeMaterial=try J.H.Material(bendingStiffnessNewtonMeter:0.004)
        let hb=try make([],bendingMaterial:hingeMaterial),h0=try make([])
        let hbPlan=try P.Plan(prepared:hb),h0Plan=try P.Plan(prepared:h0)
        let hbWork=try hbPlan.makeWorkspace(),h0Work=try h0Plan.makeWorkspace()
        try require(hbPlan.hingeScatter.count==hb.bending.hinges.count && hbPlan.hingeScatter.allSatisfy{$0.count==78},"Every four-vertex hinge needs all 78 lower 12x12 entries")
        try require(h0Plan.hingeScatter.isEmpty && hbPlan.rowIndices.count>h0Plan.rowIndices.count,"kb0 must omit hinge pattern; enabled pattern needs opposite-vertex pairs")
        var folded=x;let normal=v(sin(0.7),0,cos(0.7));folded[3]=folded[3]+normal*0.015;folded[7]=folded[7]+normal*0.01
        let hbf=try hb.frame(predictor:folded,timeStepSeconds:1/240,sewingRamp:0.4),h0f=try h0.frame(predictor:folded,timeStepSeconds:1/240,sewingRamp:0.4)
        let trueBefore=try hbf.evaluate(positions:folded),trueHvBefore=try hbf.hessianProduct(positions:folded,direction:p)
        let hbu=try hbWork.update(frame:hbf,positions:folded);_=try h0Work.update(frame:h0f,positions:folded)
        let gn=try hb.bending.hessianProduct(positions:folded,direction:p,material:hingeMaterial,mode:.gaussNewtonPSD)
        let exact=try hb.bending.hessianProduct(positions:folded,direction:p,material:hingeMaterial,mode:.exact)
        let gnDifference=sub(try hbWork.product(p),try h0Work.product(p)),gnError=norm(sub(gnDifference,gn))/max(1,norm(gn))
        try require(gnError<1e-12,"Assembled added hinge blocks differ from independent H.gaussNewtonPSD: \(gnError)")
        try require(norm(sub(exact,gn))>1e-4,"Folded exact curvature must remain distinct from GN")
        let hbProduct=try hbWork.product(p),hbQ=try hbWork.product(q)
        let hbSymmetry=abs(dot(p,hbQ)-dot(q,hbProduct))/max(1,abs(dot(p,hbQ)),abs(dot(q,hbProduct)))
        try require(dot(p,gn)>=(-1e-12) && dot(p,hbProduct)>0 && hbSymmetry<1e-12,"Hinge GN PSD/full P SPD/symmetry")
        let hz=try hbWork.solve(rhs:p,generation:hbu.linear.generation)
        let hingeResidual=norm(sub(try hbWork.product(hz.vector),p))/norm(p)
        try require(hingeResidual<1e-8,"Full hinge pattern factor solve residual")
        let trueAfter=try hbf.evaluate(positions:folded),trueHvAfter=try hbf.hessianProduct(positions:folded,direction:p)
        try require(trueBefore.energyJoules==trueAfter.energyJoules && trueBefore.gradientNewton==trueAfter.gradientNewton && trueHvBefore==trueHvAfter,"P must leave exact hinge Phi/g/Hv unchanged")
        let hbRotated=folded.map(rotate),hbRotatedFrame=try hb.frame(predictor:hbRotated,timeStepSeconds:1/240,sewingRamp:0.4)
        _=try hbWork.update(frame:hbRotatedFrame,positions:hbRotated)
        let hingeCovariance=norm(sub(try hbWork.product(p.map(rotate)),hbProduct.map(rotate)))/norm(hbProduct)
        try require(hingeCovariance<1e-12,"Hinge GN rigid covariance")
        let renamed=groups.map{J.H.PanelGroup(panelID:$0.panelID+"-other",vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs)}
        let wrongSource=try make([],bendingMaterial:hingeMaterial,panelGroups:renamed)
        let wrongMaterial=try make([],bendingMaterial:.init(bendingStiffnessNewtonMeter:0.002))
        try require(!hbPlan.matches(wrongSource) && !hbPlan.matches(wrongMaterial),"Hinge source/material matching is mandatory")
        try rejected{_=try hbWork.update(frame:wrongMaterial.frame(predictor:folded,timeStepSeconds:1/240,sewingRamp:0.4),positions:folded)}
        try rejected{_=try hbWork.product(p)}
        _=try hbWork.update(frame:hbf,positions:folded)
        let cancelHinge=HingePreconditionerCancellation()
        try rejected{_=try hbWork.update(frame:hbf,positions:folded,isCancelled:{cancelHinge.cancelled()})}
        try rejected{_=try hbWork.product(p)}
        var hingeLimit=P.Limits();hingeLimit.maximumHinges=1
        try rejected{_=try P.Plan(prepared:hb,limits:hingeLimit)}
        hingeLimit=P.Limits();hingeLimit.maximumScatterBytes=h0Plan.scatterBytes
        _=try P.Plan(prepared:h0,limits:hingeLimit)
        try rejected{_=try P.Plan(prepared:hb,limits:hingeLimit)}
        hingeLimit=P.Limits();hingeLimit.linear.maximumLowerNonzeros=h0Plan.rowIndices.count
        _=try P.Plan(prepared:h0,limits:hingeLimit)
        try rejected{_=try P.Plan(prepared:hb,limits:hingeLimit)}
        var branchCut=x;branchCut[3]=branchCut[1]
        try rejected{_=try hbWork.update(frame:hbf,positions:branchCut)}
        try rejected{_=try hbWork.product(p)}
        var results:[String:Any]=["scope":"Production polar-source+physical-inertia+PSD-scalar-sewing matrix/linear regression only. No cloth time step or garment acceptance.","syntheticExactHRelativeError":relative,"symmetryRelativeError":sym,"PzRelativeResidual":residual,"rigidCovarianceRelativeError":covariance,"trueNegativeSewingCurvature":negative,"zeroTargetCoincidenceRelativeError":zeroTargetError]
        results["syntheticHingeGN"]=["hinges":hb.bending.hinges.count,"lowerEntriesPerHinge":78,"oldLowerNNZ":h0Plan.rowIndices.count,"newLowerNNZ":hbPlan.rowIndices.count,"independentGNProductRelativeError":gnError,"PzRelativeResidual":hingeResidual,"rigidCovarianceRelativeError":hingeCovariance,"symmetryRelativeError":hbSymmetry,"assemblySeconds":hbu.hingeAssemblySeconds,"trueEnergyGradientExactHvUnchanged":true]
        let fixture=root.appendingPathComponent("3d-joint-preconditioner"),source=try decoder.decode(Source.self,from:Data(contentsOf:root.appendingPathComponent("3d-hinge/native-source-topology.json")))
        let sewing=try decoder.decode(GarmentCodeSewing.Plan.self,from:Data(contentsOf:root.appendingPathComponent("3d-hinge/native-full-plan.json")))
        let physical=try decoder.decode(Mass.self,from:Data(contentsOf:fixture.appendingPathComponent("physical-masses.json")))
        try require(source.sourceSHA256==sewing.sourceSHA256 && source.sourceSHA256==physical.sourceSHA256 && !physical.pinned.contains(true),"Complete real source/mass/row binding")
        let real=try J.Prepared(referencePositions:source.referencePositions,referenceTriangles:source.referenceTriangles,panelGroups:source.panelGroups,massesKg:physical.massesKg,stitches:sewing.constraints,material:material,strainBarrier:barrier,bendingMaterial:bending,sewingComplianceMetersPerNewton:1e-8)
        let rp=try P.Plan(prepared:real),rw=try rp.makeWorkspace(),rigid=try decoder.decode(Snapshot.self,from:Data(contentsOf:fixture.appendingPathComponent("rigid-frame0.json"))).positions
        let initial=try real.frame(predictor:rigid,timeStepSeconds:1/240,sewingRamp:1/480)
        _=try rw.update(frame:initial,positions:rigid)
        kb0Hashes["realInitial"]=matrixHash(rp,rw.lowerValues)
        let oracle=try decoder.decode(Oracle.self,from:Data(contentsOf:fixture.appendingPathComponent("initial-vector-oracle.json"))),matrix=try decoder.decode(Matrix.self,from:Data(contentsOf:fixture.appendingPathComponent("initial-matrix-oracle.json")))
        try require(oracle.sourceSHA256==source.sourceSHA256 && matrix.dimension==rp.dimension,"Independent oracle source binding")
        let matrixVectorError=norm(sub(try rw.product(oracle.direction),oracle.hessianProduct))/norm(oracle.hessianProduct)
        try require(matrixVectorError<1e-11,"Independent complete initial Hessian-vector: \(matrixVectorError)")
        var values:[Int64:Double]=[:]
        for col in 0..<rp.dimension {for i in Int(rp.columnStarts[col])..<Int(rp.columnStarts[col+1]) {values[Int64(rp.rowIndices[i])*Int64(rp.dimension)+Int64(col)]=rw.lowerValues[i]}}
        var maximumEntryError=0.0
        for col in 0..<matrix.dimension {for i in Int(matrix.columnStarts[col])..<Int(matrix.columnStarts[col+1]) {
            let key=Int64(matrix.rowIndices[i])*Int64(matrix.dimension)+Int64(col),ref=matrix.values[i],actual=values.removeValue(forKey:key) ?? 0
            maximumEntryError=max(maximumEntryError,abs(actual-ref));try require(abs(actual-ref)<1e-7+1e-11*abs(ref),"Initial entry differs beyond arithmetic roundoff")
        }}
        try require(values.values.allSatisfy{abs($0)<1e-7},"Unexpected nonzero matrix coupling")
        let previous=try decoder.decode(Snapshot.self,from:Data(contentsOf:fixture.appendingPathComponent("r16-predictor.json"))).positions,current=try decoder.decode(Snapshot.self,from:Data(contentsOf:fixture.appendingPathComponent("r16-current.json"))).positions
        let r16=try real.frame(predictor:previous,timeStepSeconds:1/240,sewingRamp:16/480),r16before=try r16.evaluate(positions:current)
        let ur=try rw.update(frame:r16,positions:current),sz=try rw.solve(rhs:r16before.gradientNewton,generation:ur.linear.generation)
        kb0Hashes["realR16"]=matrixHash(rp,rw.lowerValues)
        let pz=norm(sub(try rw.product(sz.vector),r16before.gradientNewton))/norm(r16before.gradientNewton)
        let r16after=try r16.evaluate(positions:current)
        try require(pz<1e-8 && r16before.energyJoules==r16after.energyJoules && r16before.gradientNewton==r16after.gradientNewton,"Real P solve preserves true objective")
        results["actualSource"]=["vertices":physical.massesKg.count,"triangles":source.referenceTriangles.count/3,"sewingRows":real.sewingRows.count,"lowerNNZ":rp.rowIndices.count,"independentInitialHvRelativeError":matrixVectorError,"maximumInitialEntryError":maximumEntryError,"r16PzRelativeResidual":pz,"r16Rz":sz.linear.quadraticForm,"r16PolarOrthogonalityError":ur.maximumPolarOrthogonalityError,"r16PhiUnchanged":true,"factorBytesMinimum":ur.linear.factorBytesMinimum,"numericWorkspaceBytes":ur.linear.numericWorkspaceBytes]
        let realHingeMaterial=try J.H.Material(bendingStiffnessNewtonMeter:0.0001)
        let realB=try J.Prepared(referencePositions:source.referencePositions,referenceTriangles:source.referenceTriangles,panelGroups:source.panelGroups,massesKg:physical.massesKg,stitches:sewing.constraints,material:material,strainBarrier:barrier,bendingMaterial:realHingeMaterial,sewingComplianceMetersPerNewton:1e-8)
        let rbPlan=try P.Plan(prepared:realB),rbWork=try rbPlan.makeWorkspace()
        let rbFrame=try realB.frame(predictor:previous,timeStepSeconds:1/240,sewingRamp:16/480)
        let rbBefore=try rbFrame.evaluate(positions:current),rbHvBefore=try rbFrame.hessianProduct(positions:current,direction:oracle.direction)
        let rbUpdate=try rbWork.update(frame:rbFrame,positions:current)
        let realGN=try realB.bending.hessianProduct(positions:current,direction:oracle.direction,material:realHingeMaterial,mode:.gaussNewtonPSD)
        let withoutHinge=try rw.product(oracle.direction),withHinge=try rbWork.product(oracle.direction)
        let realGNError=norm(sub(sub(withHinge,withoutHinge),realGN)),realGNNorm=norm(realGN)
        let cancellationRoundoffBound=128*Double.ulpOfOne*(norm(withHinge)+norm(withoutHinge)+realGNNorm)
        try require(realGNError<=cancellationRoundoffBound,"Real GN addition differs beyond represented-matrix subtraction roundoff: \(realGNError), bound \(cancellationRoundoffBound)")
        let rbSolved=try rbWork.solve(rhs:rbBefore.gradientNewton,generation:rbUpdate.linear.generation)
        let rbResidual=norm(sub(try rbWork.product(rbSolved.vector),rbBefore.gradientNewton))/norm(rbBefore.gradientNewton)
        let rbAfter=try rbFrame.evaluate(positions:current),rbHvAfter=try rbFrame.hessianProduct(positions:current,direction:oracle.direction)
        try require(rbResidual<1e-8 && rbBefore.energyJoules==rbAfter.energyJoules && rbBefore.gradientNewton==rbAfter.gradientNewton && rbHvBefore==rbHvAfter,"Real source hinge P must be SPD and leave actual Phi/g/exactHv unchanged")
        try require(rbUpdate.hingeGaussNewtonCount==realB.bending.hinges.count && rbPlan.rowIndices.count>rp.rowIndices.count,"Real full source hinge graph missing")
        results["actualSourceHingeGN"]=["hinges":realB.bending.hinges.count,"oldLowerNNZ":rp.rowIndices.count,"newLowerNNZ":rbPlan.rowIndices.count,"GNProductAbsoluteError":realGNError,"GNProductNorm":realGNNorm,"representedSubtractionRoundoffBound":cancellationRoundoffBound,"PzRelativeResidual":rbResidual,"hingeAssemblySeconds":rbUpdate.hingeAssemblySeconds,"totalAssemblySeconds":rbUpdate.assemblySeconds,"refactorSeconds":rbUpdate.refactorSeconds,"factorBytesMinimum":rbUpdate.linear.factorBytesMinimum,"numericWorkspaceBytes":rbUpdate.linear.numericWorkspaceBytes,"trueEnergyGradientExactHvUnchanged":true]
        results["passed"]=true
        let hashFixture=fixture.appendingPathComponent("legacy-kb0-matrix-hashes.json")
        if FileManager.default.fileExists(atPath:hashFixture.path) {
            let original=try JSONSerialization.jsonObject(with:Data(contentsOf:hashFixture)) as! [String:Any]
            try require(kb0Hashes == original["hashes"] as! [String:String],"kb0 CSC/value bytes changed from original production P")
        }
        results["kb0MatrixHashes"]=kb0Hashes
        try JSONSerialization.data(withJSONObject:kb0Hashes,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("kb0-matrix-hashes.json"))
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("joint-preconditioner-summary.json"))
        print("JointPreconditioner PASS",matrixVectorError,pz)
    }
}
