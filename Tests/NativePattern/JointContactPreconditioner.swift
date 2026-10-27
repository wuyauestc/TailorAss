import Foundation
import NativeClothCollision
import CryptoKit

typealias CP=GarmentCodeJointContactPreconditioner
typealias P=GarmentCodeJointPreconditioner
typealias J=GarmentCodeJointObjective
typealias V=J.V
nonisolated final class CPCalls:@unchecked Sendable {
 private let lock=NSLock();private var n=0
 func next()->Int {lock.lock();defer{lock.unlock()};n+=1;return n}
 func value()->Int {lock.lock();defer{lock.unlock()};return n}
}
@main @MainActor struct JointContactPreconditionerRegression {
 enum Failure:Error {case failed(String)}
 struct NativeShirt:Decodable {
  let sourceSHA256:String,panelNames:[String],referencePositions:[V],positions:[V],triangleIndices:[UInt32],vertexPanelIDs:[Int],trianglePanelIDs:[Int]
 }
 struct BodyCase:Decodable {
  let name:String,clothRest:[[Double]],clothCurrent:[[Double]],bodyPositions:[[Double]],clothTriangles:[UInt32],bodyTriangles:[UInt32],kappa:Double,dmin:Double,h:Double
 }
 struct BodyCases:Decodable {let cases:[BodyCase]}
 struct ClothCase:Decodable {let rest:[[Double]],current:[[Double]],triangles:[UInt32]}
 struct CorrectedGolden:Decodable {
  let energy:Double,gradient:[Double],stencilCount:Int,negativeStencilCount:Int
 }
 struct CorrectedEnvelope:Decodable {let `case`:CorrectedGolden}
 static func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
 static func native(_ a:V)->SIMD3<Double> {.init(a.x,a.y,a.z)}
 static func app(_ a:SIMD3<Double>)->V {v(a.x,a.y,a.z)}
 static func dot(_ a:[V],_ b:[V])->Double {zip(a,b).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}}
 static func norm(_ x:[V])->Double {sqrt(dot(x,x))}
 static func sub(_ a:[V],_ b:[V])->[V] {zip(a,b).map{$0-$1}}
 static func direction(_ n:Int,_ seed:Int=0)->[V] {(0..<n).map{i in v(sin(Double(i*7+seed)+0.3),cos(Double(i*11+seed)+0.7),sin(Double(i*13+seed)+0.9))}}
 static func require(_ b:Bool,_ text:String)throws {if !b{throw Failure.failed(text)}}
 static func bits(_ a:[V],_ b:[V])throws {
  try require(a.count==b.count,"vector size")
  for(a,b) in zip(a,b) {try require(a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern,"bitwise baseline changed")}
 }
 static func reject(_ text:String,_ f:()throws->Void)throws->String {do{try f()}catch{return String(describing:error)};throw Failure.failed("accepted "+text)}
 static func core(_ ref:[V],_ tri:[UInt32],_ groups:[J.H.PanelGroup],_ rows:[GarmentCodeSewing.Constraint]=[],kb:Double=0)throws->J.Prepared {
  let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:ref.map(native),triangleIndices:tri,arealDensity:0.18)
  return try .init(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,massesKg:masses.massesKg,stitches:rows,
   material:.init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
   strainBarrier:.init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
   bendingMaterial:.init(bendingStiffnessNewtonMeter:kb),sewingComplianceMetersPerNewton:1e-8)
 }
 static func rank(_ ids:[Int],_ seed:Double=0,_ kind:CP.Kind = .cloth)->CP.Block {
  let d=ids.count*3,q=(0..<d).map{sin(Double($0)+seed+0.3)}
  return .init(kind:kind,vertexIDs:ids,hessian:(0..<d).flatMap{i in (0..<d).map{j in 13*q[i]*q[j]}})
 }
 static func blockProduct(_ blocks:[CP.Block],_ p:[V])->[V] {
  var out=Array(repeating:V.zero,count:p.count)
  for b in blocks {let n=b.vertexIDs.count*3
   for i in 0..<n {var a=0.0;for j in 0..<n {let id=b.vertexIDs[j/3];a+=b.hessian[i*n+j]*[p[id].x,p[id].y,p[id].z][j%3]}
    let id=b.vertexIDs[i/3];switch i%3{case 0:out[id].x+=a;case 1:out[id].y+=a;default:out[id].z+=a}
   }
  };return out
 }
 static func verify(_ cp:CP.Workspace,_ base:P.Workspace,_ token:UInt64,_ blocks:[CP.Block],_ p:[V],expected:[V]?=nil)throws->(Double,Double) {
  let product=try cp.product(p),delta=sub(product,try base.product(p)),native=expected ?? blockProduct(blocks,p)
  let error=norm(sub(delta,native))/max(1,norm(native))
  try require(error<1e-9,"complete cross-panel PSD increment: \(error)")
  try require(dot(p,product)>0 && dot(p,native)>=(-1e-8)*max(1,norm(p)*norm(native)),"full P SPD / contact PSD quadratic")
  let z=try cp.solve(rhs:p,generation:token),residual=norm(sub(try cp.product(z),p))/norm(p)
  try require(residual<1e-8,"true Pz residual \(residual)")
  for dof in Set([0,3*p.count/2,3*p.count-1]) {
   var unit=Array(repeating:V.zero,count:p.count)
   switch dof%3 {case 0:unit[dof/3].x=1;case 1:unit[dof/3].y=1;default:unit[dof/3].z=1}
   let v=try cp.product(unit)[dof/3],expected=[v.x,v.y,v.z][dof%3]
   try require(try cp.diagonal(at:dof,generation:token).bitPattern==expected.bitPattern,"Current diagonal differs from complete P product")
  }
  return(error,residual)
 }
 static func synthetic()throws->[String:Any] {
  let square=[v(0,0,0),v(0.1,0,0),v(0.1,0.1,0),v(0,0.1,0)],ref=square+square,tri:[UInt32]=[0,1,2,0,2,3,4,5,6,4,6,7]
  let groups=[J.H.PanelGroup(panelID:"a",vertexIDs:[0,1,2,3],triangleIDs:[0,1]),J.H.PanelGroup(panelID:"b",vertexIDs:[4,5,6,7],triangleIDs:[2,3])]
  let j=try core(ref,tri,groups,kb:2e-4),x=ref.enumerated().map{i,p in p+v(i<4 ? 0:0.2,0,0)},frame=try j.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.5)
  let plan=try P.Plan(prepared:j),base=try plan.makeWorkspace(),cp=CP.Workspace(base:try plan.makeWorkspace()),p=direction(8)
  _ = try base.update(frame:frame,positions:x)
  let before=try frame.evaluate(positions:x),hvBefore=try frame.hessianProduct(positions:x,direction:p)
  let nativeA=try NativeSparseCholesky(dimension:3,columnStarts:[0,1,2,3],rowIndices:[0,1,2])
  let nativeB=try NativeSparseCholesky(dimension:3,columnStarts:[0,1,2,3],rowIndices:[0,1,2])
  let nativeGenerationA=try nativeA.refactor(values:[1,2,3]).generation,nativeGenerationB=try nativeB.refactor(values:[2,3,4]).generation
  try require(nativeGenerationA==1 && nativeGenerationB==1,"fresh native factors really restart generation at1")
  var tokens:[UInt64]=[];let none=try cp.update(frame:frame,positions:x,blocks:[]);tokens.append(none)
  try require(cp.base.lowerValues.map(\.bitPattern)==base.lowerValues.map(\.bitPattern),"zero-contact CSC numeric bytes")
  try bits(cp.product(p),base.product(p))
  let baseline=try cp.base.solve(rhs:p,generation:cp.base.latest!.linear.generation).vector
  try bits(cp.solve(rhs:p,generation:none),baseline)
  _ = try reject("negative diagonal index"){_ = try cp.diagonal(at:-1,generation:none)}
  _ = try reject("diagonal past dimension"){_ = try cp.diagonal(at:3*p.count,generation:none)}
  let a=[rank([0,4])],b=[rank([1,7],0.5,.body)],c=[rank([2,5],1.2),rank([3,6],0.8,.body)]
  var errors:[Double]=[],residuals:[Double]=[],rebuilds=0
  for blocks in [a,a,b,c,[],a] {
   let token=try cp.update(frame:frame,positions:x,blocks:blocks);try require(token>tokens.last!,"monotonic wrapper token despite native rebuild")
   for old in tokens {
    _ = try reject("old factor token"){_ = try cp.solve(rhs:p,generation:old)}
    _ = try reject("old diagonal token"){_ = try cp.diagonal(at:0,generation:old)}
   }
   tokens.append(token);if cp.report!.rebuiltSymbolicPattern {rebuilds+=1}
   let e=try verify(cp,base,token,blocks,p);errors.append(e.0);residuals.append(e.1)
  }
  try require(rebuilds>=3,"distinct contact graphs exercised native replacement")
  var failures:[String:String]=[:]
  func badUpdate(_ name:String,_ blocks:[CP.Block],cancel:@Sendable()->Bool={false})throws {
   let old=try cp.update(frame:frame,positions:x,blocks:a)
   failures[name]=try reject(name){_ = try cp.update(frame:frame,positions:x,blocks:blocks,isCancelled:cancel)}
   try require(cp.report==nil,"failed update report cannot leak success")
   _ = try reject("product after "+name){_ = try cp.product(p)}
   _ = try reject("solve after "+name){_ = try cp.solve(rhs:p,generation:old)}
   _ = try reject("diagonal after "+name){_ = try cp.diagonal(at:0,generation:old)}
   let next=try cp.update(frame:frame,positions:x,blocks:b);try require(next>old,"failed generation not reused")
  }
  try badUpdate("duplicate IDs",[.init(kind:.cloth,vertexIDs:[0,0],hessian:Array(repeating:0,count:36))])
  try badUpdate("out of range",[.init(kind:.body,vertexIDs:[8],hessian:Array(repeating:0,count:9))])
  try badUpdate("wrong block size",[.init(kind:.cloth,vertexIDs:[0],hessian:[1])])
  try badUpdate("NaN block",[.init(kind:.cloth,vertexIDs:[0],hessian:Array(repeating:.nan,count:9))])
  var asym=rank([0,4]);var matrix=asym.hessian;matrix[1]+=0.01;asym = .init(kind:.cloth,vertexIDs:asym.vertexIDs,hessian:matrix)
  try badUpdate("asymmetric block",[asym])
  let negative=CP.Block(kind:.body,vertexIDs:[0],hessian:[-1e12,0,0,0,-1e12,0,0,0,-1e12])
  try badUpdate("factor not SPD",[negative])
  try badUpdate("cancel at start",a,cancel:{true})
  let calls=CPCalls();_ = try cp.update(frame:frame,positions:x,blocks:a,isCancelled:{_ = calls.next();return false})
  let reusedCalls=CPCalls();_ = try cp.update(frame:frame,positions:x,blocks:a,isCancelled:{_ = reusedCalls.next();return false})
  let stop=max(2,reusedCalls.value()-1),late=CPCalls()
  // Use an identical graph so the callback sequence follows the observed reused
  // native path. A late abort must hide even a newly created numeric factor.
  let old=cp.generation
  failures["late reused factor cancel"]=try reject("late cancellation"){_ = try cp.update(frame:frame,positions:x,blocks:a,isCancelled:{late.next()>=stop})}
  try require(late.value()>=stop && cp.report==nil,"late cancellation actually reached")
  _ = try reject("late factor product"){_ = try cp.product(p)};_ = try reject("late token"){_ = try cp.solve(rhs:p,generation:old)}
  _ = try cp.update(frame:frame,positions:x,blocks:a)
  var nan=p;nan[0].x = .nan;let token=cp.generation
  failures["NaN rhs"]=try reject("NaN rhs"){_ = try cp.solve(rhs:nan,generation:token)}
  _ = try reject("invalid solve clears readiness"){_ = try cp.product(p)}
  let tooMany=Array(repeating:a[0],count:400_001);try badUpdate("block count budget",tooMany)
  let large=rank([0,1,4,5]),byteCount=128*1_024*1_024/(144*8)+1
  try badUpdate("staged block bytes",Array(repeating:large,count:byteCount))
  var limits=P.Limits();limits.linear.maximumLowerNonzeros=plan.rowIndices.count
  let bounded=CP.Workspace(base:try P.Plan(prepared:j,limits:limits).makeWorkspace())
  _ = try bounded.update(frame:frame,positions:x,blocks:[])
  failures["new graph budget"]=try reject("extended lower pattern"){_ = try bounded.update(frame:frame,positions:x,blocks:a)}
  _ = try reject("budget stale product"){_ = try bounded.product(p)}
  let after=try frame.evaluate(positions:x);try require(before.energyJoules.bitPattern==after.energyJoules.bitPattern,"true Phi unchanged");try bits(before.gradientNewton,after.gradientNewton);try bits(hvBefore,frame.hessianProduct(positions:x,direction:p))
  return ["zeroContactBitwise":true,"freshNativeGenerations":[nativeGenerationA,nativeGenerationB],"nativeGraphRebuilds":rebuilds,"wrapperTokens":tokens,"maxContactIncrementRelativeError":errors.max()!,"maxTruePzResidual":residuals.max()!,"failures":failures,"lateCancellationCalls":late.value(),"truePhiGradientRawHvUnchanged":true]
 }
 static func body(_ root:URL)throws->[String:Any] {
  let d=JSONDecoder(),all=try d.decode(BodyCases.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativeClothCollisionTests/Fixtures/IPCBodyContact/generic-fd-cases.json"))).cases,c=all[0]
  let ref=c.clothRest.map{v($0[0],$0[1],0)},x=c.clothCurrent.map{v($0[0],$0[1],$0[2])},groups=[J.H.PanelGroup(panelID:"paper",vertexIDs:Array(ref.indices),triangleIDs:Array(0..<c.clothTriangles.count/3))]
  let j=try core(ref,c.clothTriangles,groups,kb:2e-4),frame=try j.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.5),plan=try P.Plan(prepared:j)
  let body=try ContinuousBodyContact.Prepared(bodyPositions:c.bodyPositions.map{SIMD3($0[0],$0[1],$0[2])},triangleIndices:c.bodyTriangles),potential=try BodyContactPotential.Prepared(clothRestPositions:ref.map(native),clothTriangleIndices:c.clothTriangles,body:body)
  let raw=try potential.evaluate(clothPositions:x.map(native),parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h))
  let psd=try potential.evaluate(clothPositions:x.map(native),parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h,hessianMode:.clampPositiveSemidefinite))
  let blocks=try CP.blocks(body:psd),base=try plan.makeWorkspace(),cp=CP.Workspace(base:try plan.makeWorkspace()),p=direction(x.count)
  try require(!blocks.isEmpty && psd.energyJoules==raw.energyJoules && psd.clothGradientNewtons==raw.clothGradientNewtons,"active native body PSD retains Phi/g")
  _ = try reject("raw body mode"){_ = try CP.blocks(body:raw)}
  let before=try frame.evaluate(positions:x),rawHv=try raw.hessianProduct(direction:p.map(native))
  _ = try base.update(frame:frame,positions:x);let token=try cp.update(frame:frame,positions:x,blocks:blocks)
  let result=try verify(cp,base,token,blocks,p,expected:psd.hessianProduct(direction:p.map(native)).map(app))
  let after=try potential.evaluate(clothPositions:x.map(native),parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h))
  try require(after.energyJoules==raw.energyJoules && after.clothGradientNewtons==raw.clothGradientNewtons && after.hessianProduct(direction:p.map(native))==rawHv,"body true E/g/rawHv unchanged")
  try bits(before.gradientNewton,frame.evaluate(positions:x).gradientNewton)
  try require(cp.report!.additionalLowerNonzeros==0,"body restricted stencils all belong to source triangle pattern")
  return ["case":c.name,"bodyStencils":blocks.count,"negativeNativeStencils":psd.statistics.negativeStencils,"contactIncrementRelativeError":result.0,"PzResidual":result.1,"additionalLowerNonzeros":cp.report!.additionalLowerNonzeros,"rawModeRejected":true,"trueBodyPhiGradientRawHvUnchanged":true]
 }
 static func shirt(_ root:URL)throws->[String:Any] {
  let fixture=root.appendingPathComponent("AppFixtures/3d-contact-preconditioner"),d=JSONDecoder(),source=try d.decode(NativeShirt.self,from:Data(contentsOf:fixture.appendingPathComponent("shirt-native-input.json"))),sews=try d.decode(GarmentCodeSewing.Plan.self,from:Data(contentsOf:fixture.appendingPathComponent("shirt-native-plan.json")))
  let hash=SHA256.hash(data:try Data(contentsOf:fixture.appendingPathComponent("shirt-paper-source.json"))).map{String(format:"%02x",$0)}.joined()
  try require(hash==source.sourceSHA256 && hash==sews.sourceSHA256,"full actual canonical source SHA")
  var reference=source.triangleIndices
  for t in stride(from:0,to:reference.count,by:3) {let a=source.referencePositions[Int(reference[t])],b=source.referencePositions[Int(reference[t+1])],c=source.referencePositions[Int(reference[t+2])],cross=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);try require(cross != 0,"no source area repair");if cross<0 {reference.swapAt(t+1,t+2)}}
  let groups=source.panelNames.indices.map{i in J.H.PanelGroup(panelID:source.panelNames[i],vertexIDs:source.vertexPanelIDs.indices.filter{source.vertexPanelIDs[$0]==i},triangleIDs:source.trianglePanelIDs.indices.filter{source.trianglePanelIDs[$0]==i})}
  let x=source.positions,j=try core(source.referencePositions,reference,groups,sews.constraints,kb:2e-4),frame=try j.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.25),plan=try P.Plan(prepared:j)
  let potential=try ClothContactPotential.Prepared(restPositions:source.referencePositions.map(native),triangleIndices:source.triangleIndices)
  let raw=try potential.evaluate(positions:x.map(native),parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005)),psd=try potential.evaluate(positions:x.map(native),parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005,hessianMode:.clampPositiveSemidefinite))
  let nativeFixture=root.appendingPathComponent("Tests/NativeClothCollisionTests/Fixtures")
  let originalCase=try d.decode(ClothCase.self,from:Data(contentsOf:nativeFixture.appendingPathComponent("IPCClothContact/shirt-case.json")))
  try require(originalCase.rest==source.referencePositions.map{[$0.x,$0.y,$0.z]} &&
   originalCase.current==x.map{[$0.x,$0.y,$0.z]} && originalCase.triangles==source.triangleIndices,"corrected oracle uses the complete identical source")
  let correctedPath="IPCOrientationIdentity/shirt-golden.json"
  let golden=try d.decode(CorrectedEnvelope.self,from:Data(contentsOf:nativeFixture.appendingPathComponent(correctedPath))).case
  try require(raw.statistics.stencils==golden.stencilCount && raw.statistics.negativeStencils==golden.negativeStencilCount &&
   psd.statistics.stencils==golden.stencilCount && psd.statistics.negativeStencils==golden.negativeStencilCount &&
   psd.energyJoules==raw.energyJoules && psd.gradientNewtons==raw.gradientNewtons,"complete corrected native signed source and unchanged PSD force")
  let gradient=raw.gradientNewtons.flatMap{[$0.x,$0.y,$0.z]}
  try require(abs(raw.energyJoules-golden.energy)<=1e-15 && gradient.count==golden.gradient.count &&
   zip(gradient,golden.gradient).allSatisfy{abs($0-$1)<=1e-10},"corrected independent full-builder source energy/gradient")
  let blocks=try CP.blocks(cloth:psd),cross=blocks.filter{Set($0.vertexIDs.map{source.vertexPanelIDs[$0]}).count>1}.count
  try require(cross>0 && blocks.count==golden.stencilCount,"all corrected signed contact blocks retained")
  _ = try reject("raw self mode"){_ = try CP.blocks(cloth:raw)}
  let abs=try potential.evaluate(positions:x.map(native),parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005,hessianMode:.absolutePositiveSemidefinite))
  _ = try reject("unselected absolute mode"){_ = try CP.blocks(cloth:abs)}
  let before=try frame.evaluate(positions:x),p=direction(x.count),trueSourceHv=try frame.hessianProduct(positions:x,direction:p),trueSelfHv=try raw.hessianProduct(direction:p.map(native)),base=try plan.makeWorkspace(),cp=CP.Workspace(base:try plan.makeWorkspace())
  _ = try base.update(frame:frame,positions:x);let token=try cp.update(frame:frame,positions:x,blocks:blocks)
  var errors:[Double]=[],residuals:[Double]=[]
  for seed in 0..<4 {let p=direction(x.count,seed),result=try verify(cp,base,token,blocks,p,expected:psd.hessianProduct(direction:p.map(native)).map(app));errors.append(result.0);residuals.append(result.1)}
  let after=try frame.evaluate(positions:x),afterSelf=try potential.evaluate(positions:x.map(native),parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
  try require(before.energyJoules.bitPattern==after.energyJoules.bitPattern && raw.energyJoules.bitPattern==afterSelf.energyJoules.bitPattern,"full true Phi remains original")
  try bits(before.gradientNewton,after.gradientNewton);try bits(trueSourceHv,frame.hessianProduct(positions:x,direction:p));try require(raw.gradientNewtons==afterSelf.gradientNewtons && trueSelfHv==afterSelf.hessianProduct(direction:p.map(native)),"true self gradient/rawHv unchanged")
  try require(cp.report!.additionalLowerNonzeros>0,"real source nonlocal contact graph expanded")
  return ["sourceSHA256":source.sourceSHA256,"vertices":x.count,"triangles":source.triangleIndices.count/3,"panels":groups.count,"allSourceSewingRows":sews.constraints.count,"selfStencils":raw.statistics.stencils,"negativeStencils":raw.statistics.negativeStencils,"correctedReference":correctedPath,"completeOracleInputMatched":true,"crossPanelBlocks":cross,"additionalLowerNonzeros":cp.report!.additionalLowerNonzeros,"maximumNativePSDIncrementRelativeError":errors.max()!,"maximumTruePzResidual":residuals.max()!,"truePhiGradientRawHvUnchanged":true]
 }
 static func main()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let result:[String:Any]=["passed":true,"scope":"Contact preconditioner correctness only; true objective/raw Hessian unchanged; no physical step/garment acceptance","synthetic":try synthetic(),"body":try body(root),"nativeShirt":try shirt(root)]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("contact-preconditioner-summary.json"))
 }
}
