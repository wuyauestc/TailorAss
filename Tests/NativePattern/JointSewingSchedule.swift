import Foundation
import NativeClothCollision

@main @MainActor struct JointSewingScheduleRegression {
 enum Failure:Error {case failed(String)}
 static func require(_ value:Bool,_ message:String)throws {if !value {throw Failure.failed(message)}}
 static func v(_ a:Double,_ b:Double,_ c:Double)->V {.init(x:a,y:b,z:c)}
 static func dot(_ a:[V],_ b:[V])->Double {zip(a,b).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}}
 static func norm(_ a:[V])->Double {sqrt(dot(a,a))}
 static func sub(_ a:[V],_ b:[V])->[V] {zip(a,b).map{$0-$1}}
 static func bits(_ a:[V],_ b:[V])throws {
  try require(a.count==b.count,"count")
  for(a,b) in zip(a,b) {try require(a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern,"r1 exact derivative bytes")}
 }
 static func rejected(_ label:String,_ f:()throws->Void)throws {do{try f()}catch{return};throw Failure.failed("Accepted "+label)}
 static func exactQuadratic(_ rows:[J.SewingRow],_ p:[V],_ k:Double)->[V] {
  var out=Array(repeating:V.zero,count:p.count)
  for row in rows {let q=zip(row.vertexIDs,row.coefficients).reduce(V.zero){$0+p[$1.0]*$1.1}
   for(id,c) in zip(row.vertexIDs,row.coefficients) {out[id]=out[id]+q*(k*c)}
  };return out
 }
 static func main()throws {
  // Run the original production P regression as a separate named helper. Its
  // three pinned kb0 matrix hashes remain the independent legacy byte oracle.
  try LegacyJointPreconditionerRegression.main()
  let out=URL(fileURLWithPath:CommandLine.arguments[2])
  let square=[v(0,0,0),v(0.1,0,0),v(0.1,0.1,0),v(0,0.1,0)],ref=square+square,tri:[UInt32]=[0,1,2,0,2,3,4,5,6,4,6,7]
  let groups=[J.H.PanelGroup(panelID:"a",vertexIDs:[0,1,2,3],triangleIDs:[0,1]),J.H.PanelGroup(panelID:"b",vertexIDs:[4,5,6,7],triangleIDs:[2,3])]
  let row=try GarmentCodeSewing.Constraint(a:.init(vertexIDs:[1,2],weights:[0.25,0.75]),b:.init(vertexIDs:[4,7],weights:[0.4,0.6]),initialGapMeters:0.12)
  func make(_ rows:[GarmentCodeSewing.Constraint])throws->J.Prepared {
   try .init(referencePositions:ref,referenceTriangles:tri,panelGroups:groups,massesKg:Array(repeating:0.00045,count:8),stitches:rows,
    material:.init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
    strainBarrier:.init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
    bendingMaterial:.init(bendingStiffnessNewtonMeter:0),sewingComplianceMetersPerNewton:1e-8)
  }
  let sewn=try make([row]),unsewn=try make([]),plan=try P.Plan(prepared:sewn),basePlan=try P.Plan(prepared:unsewn)
  let work=try plan.makeWorkspace(),base=try basePlan.makeWorkspace()
  let x=ref.enumerated().map{i,p in p+v(i<4 ? 0:0.25,0.03,0.02)},p=(0..<8).map{i in v(sin(Double(i)+0.3),cos(Double(i)+0.7),sin(Double(i*3)+0.1))}
  var reports:[[String:Any]]=[],deltaControls:[[String:Any]]=[],maxP=0.0,maxRaw=0.0
  for initial in [0.001,1.0,1e8] {
   var previous=0.0
   for r in [0.0,1e-8,0.01,0.1,0.5,0.9,0.999999,1.0] {
    let f=try sewn.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:r,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:initial))
    let zero=try unsewn.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:r,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:initial))
    let k=f.sewingStiffnessNewtonPerMeter
    try require(f.prepared.sewingRows.allSatisfy{f.sewingTargetMeters($0)==0},"quadratic target is always zero")
    try require(k>=initial*(1-8*Double.ulpOfOne) && k<=1e8*(1+8*Double.ulpOfOne),"finite interval coefficient")
    if r==0 {try require(k.bitPattern==initial.bitPattern,"exact initial coefficient")}
    if r==1 {try require(k.bitPattern==sewn.sewingStiffnessNewtonPerMeter.bitPattern,"exact original final coefficient")}
    try require(k>=previous*(1-8*Double.ulpOfOne),"exponential coefficient monotonic up to represented transcendental rounding");previous=k
    _ = try work.update(frame:f,positions:x);_ = try base.update(frame:zero,positions:x)
    let a=try work.product(p),b=try base.product(p),expected=exactQuadratic(sewn.sewingRows,p,k),increment=sub(a,b)
    let error=norm(sub(increment,expected)),bound=128*Double.ulpOfOne*(norm(a)+norm(b)+norm(expected))
    try require(error<=bound,"P sewing increment differs from same-k exact quadratic: \(initial) \(r) \(error) > \(bound)")
    maxP=max(maxP,error/max(1e-300,norm(expected)))
    let raw=try f.hessianProduct(positions:x,direction:p),raw0=try zero.hessianProduct(positions:x,direction:p),rawDelta=sub(raw,raw0)
    let rawError=norm(sub(rawDelta,expected)),rawBound=128*Double.ulpOfOne*(norm(raw)+norm(raw0)+norm(expected))
    try require(rawError<=rawBound,"true raw quadratic Hessian disagrees with coefficient/frame target")
    maxRaw=max(maxRaw,rawError/max(1e-300,norm(expected)))
    let e=try f.evaluate(positions:x);try require(e.sewingJoules.isFinite && e.maximumSewingTargetResidualMeters==e.maximumSewingGapMeters,"zero target metrics")
    if r==1 {
     let legacy=try sewn.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:1),old=try plan.makeWorkspace();_ = try old.update(frame:legacy,positions:x)
     try require(work.lowerValues.map(\.bitPattern)==old.lowerValues.map(\.bitPattern),"r1 original P CSC/value bytes")
     let oldE=try legacy.evaluate(positions:x);try require(e.energyJoules.bitPattern==oldE.energyJoules.bitPattern && e.sewingJoules.bitPattern==oldE.sewingJoules.bitPattern,"r1 original Phi exact")
     try bits(e.gradientNewton,oldE.gradientNewton);try bits(raw,legacy.hessianProduct(positions:x,direction:p))
     // At target0 the new stable quadratic increment and historical radial
     // increment are algebraically equal, but need not round bitwise alike.
     // Preserve both, and verify the quadratic against an independent Decimal
     // oracle over the actual rounded x/y in the runner, not an energy slack.
     for sign in [-1.0,1.0] {
      let next=zip(x,p).map{$0+$1*(sign*1e-8)},d1=try f.energyDelta(from:x,to:next),d0=try legacy.energyDelta(from:x,to:next)
      deltaControls.append(["initialK":initial,"k":k,"x":x.map{[$0.x,$0.y,$0.z]},"y":next.map{[$0.x,$0.y,$0.z]},"rows":sewn.sewingRows.map{["ids":$0.vertexIDs,"coefficients":$0.coefficients]},"quadraticSewingDelta":d1.nonelastic.sewingJoules,"legacyRadialSewingDelta":d0.nonelastic.sewingJoules])
     }
    }
    reports.append(["initialK":initial,"r":r,"effectiveK":k,"PIncrementError":error,"representedSubtractionBound":bound,"rawIncrementError":rawError])
   }
  }
  // A positive initial gap at exact coincidence is singular in distanceTarget;
  // zero-target continuation remains smooth kI at EVERY continuation value.
  let coincidentRow=try GarmentCodeSewing.Constraint(a:.init(vertexID:0),b:.init(vertexID:4),initialGapMeters:0.2),coincident=try make([coincidentRow]),cw=try P.Plan(prepared:coincident).makeWorkspace()
  for r in [0.0,0.25,0.5,1.0] {
   let f=try coincident.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:r,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:0.001)),f0=try unsewn.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:r,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:0.001))
   _ = try f.evaluate(positions:ref);_ = try cw.update(frame:f,positions:ref);_ = try base.update(frame:f0,positions:ref)
   let expected=exactQuadratic(coincident.sewingRows,p,f.sewingStiffnessNewtonPerMeter),a=try cw.product(p),b=try base.product(p),error=norm(sub(sub(a,b),expected))
   try require(error<=128*Double.ulpOfOne*(norm(a)+norm(b)+norm(expected)),"smooth coincidence P")
  }
  let legacySingular=try coincident.frame(predictor:ref,timeStepSeconds:1/240,sewingRamp:0)
  try rejected("old nonsmooth branch remains explicit"){_ = try cw.update(frame:legacySingular,positions:ref)}
  for invalid in [0.0,-1.0,Double.nan,Double.infinity,1e8*1.01] {
   try rejected("invalid continuation coefficient"){_ = try sewn.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:0.5,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:invalid))}
  }
  try rejected("NaN ramp"){_ = try sewn.frame(predictor:x,timeStepSeconds:1/240,sewingRamp:.nan,sewingSchedule:.quadraticStiffness(initialNewtonPerMeter:0.001))}
  let report:[String:Any]=["passed":true,"scope":"P/new Frame sewing coefficient and target consistency only; no Newton/physical garment acceptance","controls":reports,"maxPIncrementRelativeError":maxP,"maxRawIncrementRelativeError":maxRaw,"exactFinalPAndPhiGradientRawHv":true,"finalDeltaControls":deltaControls,"legacyDefaultThreeMatrixHashesVerified":true,"smoothZeroTargetCoincidence":true]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("sewing-schedule-summary.json"))
 }
}
