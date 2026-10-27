import Foundation
typealias L=GarmentCodeElasticLinearization
typealias M=L.M
typealias H=L.H
typealias V=L.V
nonisolated final class LinearizationCounter:@unchecked Sendable {
 private let lock=NSLock();private var value=0
 func count()->Int {lock.lock();defer{lock.unlock()};value+=1;return value}
}
@main @MainActor struct LinearizationRegression {
 enum TestFailure:Error {case failed(String)}
 struct Source:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[H.PanelGroup],sourceSHA256:String}
 struct State:Decodable {let positions:[V]}
 static func require(_ x:Bool,_ message:String)throws {if !x{throw TestFailure.failed(message)}}
 static func norm(_ a:[V])->Double {a.map(\.length).max() ?? 0}
 static func diff(_ a:[V],_ b:[V])->Double {zip(a,b).map{($0-$1).length}.max() ?? 0}
 static func bitwise(_ a:[V],_ b:[V])throws {
  try require(a.count==b.count,"vector count")
  for (a,b) in zip(a,b) {try require(a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern,"raw Double bits changed")}
 }
 static func bad(_ text:String,_ f:()throws->Void)throws {
  do {try f()}catch {return};throw TestFailure.failed("invalid accepted "+text)
 }
 static func cancelled(_ f:()throws->Void)throws {
  do {try f()}catch is CancellationError{return};throw TestFailure.failed("cancellation ignored")
 }
 static func material()throws->M.Material {try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170)}
 static func barrier()throws->M.StrainBarrier {try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)}
 static func vector(_ a:Double,_ b:Double,_ c:Double)->V {.init(x:a,y:b,z:c)}
 static var reports:[[String:Any]]=[]
 static func main()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]),d=JSONDecoder()
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let s=try d.decode(Source.self,from:Data(contentsOf:root.appendingPathComponent("3d-hinge/native-source-topology.json")))
  let r236=try d.decode(State.self,from:Data(contentsOf:root.appendingPathComponent("3d-elastic-linearization/actual-r236.json"))).positions
  let r237=try d.decode(State.self,from:Data(contentsOf:root.appendingPathComponent("3d-elastic-linearization/mathematical-r237.json"))).positions
  let m=try M.Prepared(referencePositions:s.referencePositions,triangleIndices:s.referenceTriangles),h=try H.Prepared(referencePositions:s.referencePositions,referenceTriangles:s.referenceTriangles,panelGroups:s.panelGroups),source=try L.Source(membrane:m,bending:h),mu=try material(),bar=try barrier(),kb=try H.Material(bendingStiffnessNewtonMeter:2e-4),zero=try H.Material(bendingStiffnessNewtonMeter:0)
  let sourceCopy=source,rebuilt=try L.Source(membrane:m,bending:h)
  try require(sourceCopy.identity==source.identity && rebuilt.identity != source.identity,"runtime source identity copy/rebuild")
  var directions=(0..<8).map{phase in (0..<m.vertexCount).map{i in let t=Double(i)+Double(phase)*0.731;return vector(sin(t*1.31+0.7),cos(t*0.83+0.4),sin(t*1.13+1.9))}}
  let actualMotion=zip(r237,r236).map{$0-$1},motionScale=norm(actualMotion);directions.append(actualMotion.map{$0/motionScale});directions.append(Array(repeating:vector(0.3,-0.4,0.5),count:m.vertexCount))
  var maxFD:[String:Double]=[:]
  for(name,x) in [("actual236",r236),("mathematical237-not-accepted",r237),("derived237-times1.04-not-actual-frame",r237.map{$0*1.04})] {
   let cache=try L.Prepared(source:source,positions:x,material:mu,barrier:bar,bendingMaterial:kb)
   try require(cache.positions==x && cache.source.identity==source.identity && cache.statistics.bendingEnabled,"snapshot binding")
   for direction in directions {
    let a=try m.neoHookeanHessianProduct(positions:x,direction:direction,material:mu),b=try m.principalBarrierHessianProduct(positions:x,direction:direction,barrier:bar),c=try h.hessianProduct(positions:x,direction:direction,material:kb,mode:.exact)
    try bitwise(a,cache.neoHookeanHessianProduct(direction:direction));try bitwise(b,cache.principalBarrierHessianProduct(direction:direction));try bitwise(c,cache.bendingHessianProduct(direction:direction))
    try bitwise(zip(zip(a,b),c).map{($0.0+$0.1)+$1},cache.hessianProduct(direction:direction))
   }
   if name.hasPrefix("derived") {try require(cache.statistics.activeBarrierTriangles==3472,"all active source control")}
   else {try require(cache.statistics.activeBarrierTriangles==0,"strictly inactive source control")}
   // Finite differences of the ORIGINAL production gradients, with two actual
   // source directions. No local Hessian or altered material acts as the oracle.
   for(directionID,direction) in [directions[0],directions[8]].enumerated() {
    let nh=try cache.neoHookeanHessianProduct(direction:direction),bp=try cache.principalBarrierHessianProduct(direction:direction),hb=try cache.bendingHessianProduct(direction:direction)
    var best=[Double.infinity,Double.infinity,Double.infinity]
    for eps in [1e-7,3e-8,1e-8,3e-9] {
     let plus=zip(x,direction).map{$0+$1*eps},minus=zip(x,direction).map{$0-$1*eps}
     let a=try m.neoHookean(positions:plus,material:mu).gradientNewton,b=try m.neoHookean(positions:minus,material:mu).gradientNewton
     let c=try m.principalBarrier(positions:plus,barrier:bar).gradientNewton,e=try m.principalBarrier(positions:minus,barrier:bar).gradientNewton
     let f=try h.evaluate(positions:plus,material:kb).gradientNewton,g=try h.evaluate(positions:minus,material:kb).gradientNewton
     for (index,pair) in [(nh,zip(a,b).map{($0-$1)/(2*eps)}),(bp,zip(c,e).map{($0-$1)/(2*eps)}),(hb,zip(f,g).map{($0-$1)/(2*eps)})].enumerated() {best[index]=min(best[index],diff(pair.0,pair.1)/max(1,norm(pair.0)))}
    }
    try require(best.allSatisfy{$0<1e-6},"original gradient FD")
    for(i,k) in ["NH","principal","hinge"].enumerated(){maxFD[k]=max(maxFD[k,default:0],best[i])}
    reports.append(["state":name,"direction":directionID==0 ? "arbitrary":"actual236-to237-normalized","bestFDRelativeErrors":best])
   }
   let disabled=try L.Prepared(source:source,positions:x,material:mu,barrier:bar,bendingMaterial:zero)
   try require(!disabled.statistics.bendingEnabled && disabled.statistics.hinges==0,"kb0 explicitly disabled")
   try bitwise(try disabled.bendingHessianProduct(direction:directions[0]),Array(repeating:.zero,count:x.count))
   try bitwise(try disabled.hessianProduct(direction:directions[0]),zip(m.neoHookeanHessianProduct(positions:x,direction:directions[0],material:mu),m.principalBarrierHessianProduct(positions:x,direction:directions[0],barrier:bar)).map{$0+$1})
  }
  let cache=try L.Prepared(source:source,positions:r237,material:mu,barrier:bar,bendingMaterial:kb)
  func rotate(_ a:V)->V {vector(-a.y,a.x,a.z)}
  let rigidX=r237.map{rotate($0)+vector(0.3,-0.2,0.4)},rigidD=directions[0].map(rotate)
  let rigid=try L.Prepared(source:source,positions:rigidX,material:mu,barrier:bar,bendingMaterial:kb)
  let rigidOut=try rigid.hessianProduct(direction:rigidD),originalOut=try cache.hessianProduct(direction:directions[0])
  try bitwise(try rigid.neoHookeanHessianProduct(direction:rigidD),m.neoHookeanHessianProduct(positions:rigidX,direction:rigidD,material:mu))
  try bitwise(try rigid.principalBarrierHessianProduct(direction:rigidD),m.principalBarrierHessianProduct(positions:rigidX,direction:rigidD,barrier:bar))
  try bitwise(try rigid.bendingHessianProduct(direction:rigidD),h.hessianProduct(positions:rigidX,direction:rigidD,material:kb,mode:.exact))
  let rigidRelative=diff(rigidOut,originalOut.map(rotate))/max(1,norm(originalOut))
  try require(rigidRelative<1e-9,"raw Hessian rigid covariance")
  var mutation=r237;mutation[0].x+=0.001
  try require(cache.positions==r237 && cache.positions != mutation,"CoW snapshot unchanged")
  try bad("wrong count"){_ = try cache.hessianProduct(direction:[])}
  var nan=directions[0];nan[0].x = .nan
  for action in 0..<4 {try bad("NaN never becomes zero even inactive barrier"){
   switch action {case 0:_ = try cache.hessianProduct(direction:nan);case 1:_ = try cache.principalBarrierHessianProduct(direction:nan);case 2:_ = try cache.neoHookeanHessianProduct(direction:nan);default:_ = try cache.bendingHessianProduct(direction:nan)}
  }}
  var badX=r237;badX[0].x = .infinity
  try bad("nonfinite point"){_ = try L.Prepared(source:source,positions:badX,material:mu,barrier:bar,bendingMaterial:kb)}
  try bad("wrong point count"){_ = try L.Prepared(source:source,positions:[],material:mu,barrier:bar,bendingMaterial:kb)}
  try bad("barrier domain"){_ = try L.Prepared(source:source,positions:r237.map{$0*1.2},material:mu,barrier:bar,bendingMaterial:kb)}
  try bad("material pair"){_ = try L.Prepared(source:source,positions:r237,material:mu,barrier:bar)}
  var limits=L.Limits();limits.maximumEstimatedCachedBytes=1
  try bad("byte budget"){_ = try L.Prepared(source:source,positions:r237,material:mu,barrier:bar,bendingMaterial:kb,limits:limits)}
  try cancelled{_ = try L.Source(membrane:m,bending:h,isCancelled:{true})}
  try cancelled{_ = try L.Prepared(source:source,positions:r237,material:mu,barrier:bar,bendingMaterial:kb,isCancelled:{true})}
  let counter=LinearizationCounter();try cancelled{_ = try L.Prepared(source:source,positions:r237,material:mu,barrier:bar,bendingMaterial:kb,isCancelled:{counter.count()>10})}
  for action in 0..<4 {let count=LinearizationCounter();try cancelled{
   switch action {case 0:_ = try cache.hessianProduct(direction:directions[0],isCancelled:{count.count()>3});case 1:_ = try cache.principalBarrierHessianProduct(direction:directions[0],isCancelled:{count.count()>3});case 2:_ = try cache.neoHookeanHessianProduct(direction:directions[0],isCancelled:{count.count()>3});default:_ = try cache.bendingHessianProduct(direction:directions[0],isCancelled:{count.count()>3})}
  }}
  let wrongH=try H.Prepared(referencePositions:s.referencePositions.map{$0*1.01},referenceTriangles:s.referenceTriangles,panelGroups:s.panelGroups)
  try bad("different source metric"){_ = try L.Source(membrane:m,bending:wrongH)}
  try analyticDomains(mu,bar)
  let concurrentErrors=LinearizationCounter(),expected=try cache.hessianProduct(direction:directions[0]),concurrentDirection=directions[0]
  DispatchQueue.concurrentPerform(iterations:8){_ in
   do {let result=try cache.hessianProduct(direction:concurrentDirection);if result != expected {_ = concurrentErrors.count()}}
   catch {_ = concurrentErrors.count()}
  }
  try require(concurrentErrors.count()==1,"immutable concurrent products")
  let summary:[String:Any]=["passed":true,"sourceSHA256":s.sourceSHA256,"vertices":m.vertexCount,"triangles":m.triangles.count,"hinges":h.hinges.count,"rawBitwiseDirectionsPerState":directions.count,"states":3,"actualMotionMaxMeters":motionScale,"maximumBestStepFDError":maxFD,"fd":reports,"rigidRelativeError":rigidRelative,"sourceIdentityAndCoW":true,"disabledKb0Skip":true,"concurrentReadOnlyCalls":8,"conservativeCacheByteEstimate":cache.statistics.maximumEstimatedCachedBytes,"noDynamics":true]
  try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("elastic-linearization-summary.json"))
 }
 static func analyticDomains(_ mu:M.Material,_ bar:M.StrainBarrier)throws {
  let ref=[vector(0,0,0),vector(0.21,0,0),vector(0.03,0.13,0),vector(0.07,-0.11,0)],tri:[UInt32]=[0,1,2,1,0,3],groups=[H.PanelGroup(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,1])],m=try M.Prepared(referencePositions:ref,triangleIndices:tri),kb=try H.Material(bendingStiffnessNewtonMeter:2e-4)
  let d=[vector(0.1,0.2,-0.3),vector(-0.4,0.2,0.3),vector(0.2,-0.1,0.7),vector(-0.3,0.7,0.1)]
  var x=ref;let angle=Double.pi-1e-7;x[3]=vector(0.07,-0.11*cos(angle),-0.11*sin(angle))
  var strict=H.Limits();strict.principalBranchMarginRadians=1e-4
  let strictH=try H.Prepared(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,limits:strict)
  try bad("actual H custom strict branch domain"){_ = try L.Prepared(membrane:m,bending:strictH,positions:x,material:mu,barrier:bar,bendingMaterial:kb)}
  var loose=H.Limits();loose.principalBranchMarginRadians=1e-8
  let looseH=try H.Prepared(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,limits:loose)
  let l=try L.Prepared(membrane:m,bending:looseH,positions:x,material:mu,barrier:bar,bendingMaterial:kb)
  try bitwise(try l.bendingHessianProduct(direction:d),looseH.hessianProduct(positions:x,direction:d,material:kb,mode:.exact))
  let defaultH=try H.Prepared(referencePositions:ref,referenceTriangles:tri,panelGroups:groups),zero=try H.Material(bendingStiffnessNewtonMeter:0)
  // H branch-invalid x is harmless only when the component is EXPLICITLY kb0,
  // matching the original joint objective's disabled branch.
  _ = try L.Prepared(membrane:m,bending:defaultH,positions:x,material:mu,barrier:bar,bendingMaterial:zero)
  for scale in [0.95,1.0,1.04] {
   let p=try M.Prepared(referencePositions:Array(ref.prefix(3)),triangleIndices:[0,1,2]),q=try L.Prepared(membrane:p,positions:Array(ref.prefix(3)).map{$0*scale},material:mu,barrier:bar),dir=Array(d.prefix(3))
   try bitwise(try q.principalBarrierHessianProduct(direction:dir),p.principalBarrierHessianProduct(positions:q.positions,direction:dir,barrier:bar))
  }
 }
}
