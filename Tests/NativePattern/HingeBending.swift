import Foundation
typealias V=GarmentCodeHingeBending.V
typealias HB=GarmentCodeHingeBending
struct SourceInput:Decodable {
 let referencePositions:[V],positions:[V],referenceTriangles:[UInt32],panelGroups:[HB.PanelGroup],sourceSHA256:String
 var reference:[V]{referencePositions}
 var triangles:[Int]{referenceTriangles.map(Int.init)}
}
private extension V {
 var norm:Double{length};var norm2:Double{lengthSquared}
 func dot(_ b:V)->Double{x*b.x+y*b.y+z*b.z}
}
nonisolated final class CancelAfter:@unchecked Sendable {
 private let lock=NSLock();private var visits=0;private let stop:Int
 init(_ stop:Int){self.stop=stop}
 func check()->Bool{lock.lock();defer{lock.unlock()};visits+=1;return visits>=stop}
}
@main @MainActor struct HingeRegression {
 enum TestFailure:Error {case invalid(String)}
 static func v(_ x:Double,_ y:Double,_ z:Double)->V{.init(x:x,y:y,z:z)}
 static var summary:[String:Any]=[:]
 static func require(_ x:Bool,_ s:String)throws{if !x{throw TestFailure.invalid("TEST: "+s)}}
 static func maxNorm(_ a:[V])->Double{a.map{$0.norm}.max() ?? 0}
 static func diff(_ a:[V],_ b:[V])->[V]{zip(a,b).map{$0-$1}}
 static func shifted(_ x:[V],_ d:[V],_ h:Double)->[V]{zip(x,d).map{$0+$1*h}}
 static func dot(_ a:[V],_ b:[V])->Double{zip(a,b).reduce(0){$0+$1.0.dot($1.1)}}
 static func rng(_ n:Int,_ phase:Double=0)->[V]{(0..<n).map{i in let t=Double(i)+phase;return v(sin(t*1.31+0.7),cos(t*0.83+0.4),sin(t*1.13+1.9))}}
 static func rotate(_ x:V)->V {let a=v(0.3,-0.2,0.8)/v(0.3,-0.2,0.8).norm,t=0.71;return x*cos(t)+a.cross(x)*sin(t)+a*(a.dot(x)*(1-cos(t)))}
 static func reject(_ label:String,_ f:()throws->Void)throws {
  do {try f()} catch is HB.HingeError{return};throw TestFailure.invalid("Accepted invalid input: "+label)
 }
 static func cancelled(_ label:String,_ f:()throws->Void)throws {
  do {try f()} catch is CancellationError{return};throw TestFailure.invalid("Cancellation did not propagate: "+label)
 }
 // Synthetic tests supply explicit named vertex membership by construction.
 // This adapter never recovers owners from geometry or connectivity.
 static func prepare(reference:[V],triangles:[Int],panelIDs:[String],limits:HB.Limits=HB.Limits(),isCancelled:@Sendable()->Bool={false})throws->HB.Prepared {
  let groups=Set(panelIDs).sorted().map{name in
   HB.PanelGroup(panelID:name,vertexIDs:panelIDs.indices.filter{panelIDs[$0]==name},triangleIDs:(0..<triangles.count/3).filter{ti in
    let id=triangles[3*ti];return panelIDs.indices.contains(id) && panelIDs[id]==name
   })
  }
  return try HB.Prepared(referencePositions:reference,referenceTriangles:triangles.map{UInt32($0)},panelGroups:groups,limits:limits,isCancelled:isCancelled)
 }
 static func fd(_ p:HB.Prepared,_ x:[V],_ d:[V],_ kb:Double,_ eps:Double)throws->(Double,Double) {
  let ev=try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),plus=try p.evaluate(positions:shifted(x,d,eps),material:try HB.Material(bendingStiffnessNewtonMeter:kb)),minus=try p.evaluate(positions:shifted(x,d,-eps),material:try HB.Material(bendingStiffnessNewtonMeter:kb))
  let fd=(plus.energyJoules-minus.energyJoules)/(2*eps),pred=dot(ev.gradientNewton,d),hv=try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)
  let fdHv=diff(plus.gradientNewton,minus.gradientNewton).map{$0/(2*eps)}
  return (abs(fd-pred)/max(1e-12,max(abs(fd),abs(pred))),maxNorm(diff(fdHv,hv))/max(1e-12,max(maxNorm(fdHv),maxNorm(hv))))
 }
 static func single()throws {
  let ref=[v(0,0,0),v(0.21,0,0),v(0.03,0.13,0),v(0.07,-0.11,0)],tri=[0,1,2,1,0,3],panels=Array(repeating:"paper",count:4),kb=2e-4
  let p=try prepare(reference:ref,triangles:tri,panelIDs:panels)
  let x=[v(0.01,0.02,0.03),v(0.22,0.025,0.04),v(0.04,0.16,0.09),v(0.08,-0.085,0.10)],ev=try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),d=rng(4),other=rng(4,2.9)
  try require(p.hinges.count==1 && p.boundaryEdgeCount==4,"single topology")
  let exact=try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact),gn=try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.gaussNewtonPSD),hV=try p.hessianProduct(positions:x,direction:other,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)
  let symmetry=abs(dot(other,exact)-dot(d,hV))/max(1,abs(dot(other,exact)))
  var maxE=0.0,maxH=0.0,maxQ=0.0
  for i in 0..<12 {
   var basis=Array(repeating:V.zero,count:4);switch i%3{case 0:basis[i/3].x=1;case 1:basis[i/3].y=1;default:basis[i/3].z=1}
   let errors=try fd(p,x,basis,kb,1e-7);maxE=max(maxE,errors.0);maxH=max(maxH,errors.1)
   let sp=try p.angle(positions:shifted(x,basis,1e-7),hingeID:0),sm=try p.angle(positions:shifted(x,basis,-1e-7),hingeID:0),s=try p.angle(positions:x,hingeID:0)
   maxQ=max(maxQ,abs((sp.angleRadians-sm.angleRadians)/2e-7-dot(s.gradientPerMeter,basis)))
  }
  let translated=x.map{$0+v(0.7,-1.1,2.3)},rotated=x.map{rotate($0)+v(0.7,-1.1,2.3)},scaled=x.map{$0*3.7}
  let t=try p.evaluate(positions:translated,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),r=try p.evaluate(positions:rotated,material:try HB.Material(bendingStiffnessNewtonMeter:kb))
  // Scaling changes source too, while preserving fixed source coefficients per run.
  let ps=try prepare(reference:ref.map{$0*3.7},triangles:tri,panelIDs:panels),s=try ps.evaluate(positions:scaled,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),hs=try ps.hessianProduct(positions:scaled,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)
  let omega=v(0.3,-0.5,0.7),rotationDirection=x.map{omega.cross($0)},translationDirection=Array(repeating:v(0.3,-0.5,0.7),count:x.count)
  let hRotation=try p.hessianProduct(positions:x,direction:rotationDirection,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact),hTranslation=try p.hessianProduct(positions:x,direction:translationDirection,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)
  let rotationIdentity=maxNorm(diff(hRotation,ev.gradientNewton.map{omega.cross($0)}))
  try require(maxNorm(hTranslation)<1e-12 && rotationIdentity<1e-12,"exact Hessian rigid identities")
  let torque=zip(x,ev.gradientNewton).reduce(V.zero){$0+$1.0.cross($1.1)},force=ev.gradientNewton.reduce(V.zero,+)
  let covariance=maxNorm(diff(r.gradientNewton,ev.gradientNewton.map{rotate($0)}))
  let scaleG=maxNorm(diff(s.gradientNewton,ev.gradientNewton.map{$0/3.7})),scaleH=maxNorm(diff(hs,exact.map{$0/(3.7*3.7)}))
  try require(maxE<1e-6 && maxH<1e-6 && maxQ<1e-7,"single FD")
  try require(abs(ev.energyJoules-t.energyJoules)<1e-14 && abs(ev.energyJoules-r.energyJoules)<1e-14 && covariance<1e-12,"rigid covariance")
  try require(abs(ev.energyJoules-s.energyJoules)<1e-14 && scaleG<1e-12 && scaleH<1e-10,"scale covariance")
  try require(force.norm<1e-12 && torque.norm<1e-12 && symmetry<1e-10,"force torque symmetry")
  try require(dot(d,gn)>=(-1e-12) && maxNorm(diff(gn,exact))>1e-4,"GN PSD and distinction")
  var matrix=[[Double]]()
  for i in 0..<12 {var b=Array(repeating:V.zero,count:4);switch i%3{case 0:b[i/3].x=1;case 1:b[i/3].y=1;default:b[i/3].z=1};let h=try p.hessianProduct(positions:x,direction:b,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact);matrix.append(h.flatMap{[$0.x,$0.y,$0.z]})}
  summary["singleHinge"]=["energyJ":ev.energyJoules,"angleRadians":ev.maximumAbsoluteAngleRadians,"maxEnergyGradientFDRelativeError":maxE,"maxExactHvFDRelativeError":maxH,"maxAngleGradientFDAbsoluteError":maxQ,"bilinearSymmetryError":symmetry,"netGradientNewton":force.norm,"netTorqueNewtonMeter":torque.norm,"rotationGradientCovarianceError":covariance,"scaleGradientError":scaleG,"scaleHessianError":scaleH,"gnQuadraticForm":dot(d,gn),"exactMinusGNMaxNorm":maxNorm(diff(exact,gn)),"exactTranslationNullError":maxNorm(hTranslation),"exactRotationalCovarianceIdentityError":rotationIdentity,"exactHessianColumns":matrix]
  // Analytic angle oracle, both sides of the principal branch cut.
  var angles:[[String:Double]]=[]
  for angle in [-Double.pi+1e-3,-1.2,-0.001,0,0.001,1.2,Double.pi-1e-3] {
   var y=ref;y[3]=v(0.07,-0.11*cos(angle),-0.11*sin(angle))
   let st=try p.angle(positions:y,hingeID:0),errors=try fd(p,y,d,kb,1e-9)
   try require(abs(st.angleRadians-angle)<1e-10 && errors.0<1e-5 && errors.1<1e-5,"branch interior FD")
   angles.append(["target":angle,"actual":st.angleRadians,"gradientFDRelativeError":errors.0,"hvFDRelativeError":errors.1])
  }
  var y=ref;y[3]=v(0.07,0.11,0)
  try reject("branch cut"){_ = try p.evaluate(positions:y,material:try HB.Material(bendingStiffnessNewtonMeter:kb))}
  summary["analyticAngles"]=angles
  let z=try p.evaluate(positions:ref,material:try HB.Material(bendingStiffnessNewtonMeter:0))
  try require(z.energyJoules==0 && maxNorm(z.gradientNewton)==0,"zero kb")
  var rejects=[String]()
  func bad(_ n:String,_ f:()throws->Void)throws{try reject(n,f);rejects.append(n)}
  try bad("collapsed current edge"){var y=x;y[1]=y[0];_ = try p.evaluate(positions:y,material:try HB.Material(bendingStiffnessNewtonMeter:kb))}
  try bad("collapsed current face"){var y=x;y[2]=y[0]+(y[1]-y[0])*0.3;_ = try p.evaluate(positions:y,material:try HB.Material(bendingStiffnessNewtonMeter:kb))}
  try bad("nonfinite current point"){var y=x;y[0].x = .nan;_ = try p.evaluate(positions:y,material:try HB.Material(bendingStiffnessNewtonMeter:kb))}
  try bad("negative kb"){_ = try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:-kb))}
  try bad("nonfinite kb"){_ = try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:.infinity))}
  try bad("wrong direction dimensions"){_ = try p.hessianProduct(positions:x,direction:[],material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)}
  try bad("nonfinite direction"){var q=d;q[0].x = .nan;_ = try p.hessianProduct(positions:x,direction:q,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact)}
  try bad("duplicate source triangle"){_ = try prepare(reference:ref,triangles:tri+[0,1,2],panelIDs:panels)}
  try bad("bad triangle index"){_ = try prepare(reference:ref,triangles:[0,1,4],panelIDs:panels)}
  try bad("wrong source orientation"){_ = try prepare(reference:ref,triangles:[0,1,2,0,1,3],panelIDs:panels)}
  try bad("welded cross panel"){_ = try prepare(reference:ref,triangles:tri,panelIDs:["a","a","a","b"])}
  try bad("nonflat rest source"){_ = try prepare(reference:x,triangles:tri,panelIDs:panels)}
  try bad("source vertex budget"){var l=HB.Limits();l.maximumVertices=3;_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,limits:l)}
  try bad("source triangle budget"){var l=HB.Limits();l.maximumTriangles=1;_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,limits:l)}
  try bad("source hinge budget"){var l=HB.Limits();l.maximumHinges=0;_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,limits:l)}
  try cancelled("cancel at prepare start"){_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,isCancelled:{true})}
  try cancelled("cancel at evaluate start"){_ = try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb),isCancelled:{true})}
  try cancelled("cancel at Hv start"){_ = try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact,isCancelled:{true})}
  // Two distinct source panels with coincident boundary positions retain independent IDs.
  let independent=[v(0,0,0),v(1,0,0),v(0,1,0),v(1,0,0),v(0,0,0),v(1,-1,0)]
  let separated=try prepare(reference:independent,triangles:[0,1,2,3,4,5],panelIDs:["a","a","a","b","b","b"])
  try require(separated.hinges.isEmpty && separated.boundaryEdgeCount==6,"no virtual sew hinges")
  try bad("nonmanifold source"){_ = try prepare(reference:ref+[v(0.1,0.2,0)],triangles:tri+[0,1,4],panelIDs:panels+["paper"])}
  try bad("unreferenced source vertex"){_ = try prepare(reference:ref+[v(0.1,0.2,0)],triangles:tri,panelIDs:panels+["paper"])}
  try bad("repeated source vertex index"){_ = try prepare(reference:ref,triangles:[0,0,2,1,0,3],panelIDs:panels)}
  try bad("nonfinite source vertex"){var y=ref;y[0].x = .nan;_ = try prepare(reference:y,triangles:tri,panelIDs:panels)}
  try bad("invalid branch margin"){var l=HB.Limits();l.principalBranchMarginRadians=0;_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,limits:l)}
  var near=ref;let nearAngle=Double.pi-5e-7;near[3]=v(0.07,-0.11*cos(nearAngle),-0.11*sin(nearAngle))
  try bad("declared branch exclusion band"){_ = try p.evaluate(positions:near,material:try HB.Material(bendingStiffnessNewtonMeter:kb))}
  try cancelled("strict prepare start"){_ = try prepare(reference:ref,triangles:tri,panelIDs:panels,isCancelled:{true})}
  try cancelled("strict evaluate start"){_ = try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb),isCancelled:{true})}
  try cancelled("strict Hv start"){_ = try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact,isCancelled:{true})}
  let full=HB.PanelGroup(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,1])
  func grouped(_ groups:[HB.PanelGroup])throws { _ = try HB.Prepared(referencePositions:ref,referenceTriangles:tri.map{UInt32($0)},panelGroups:groups) }
  try bad("missing explicit groups"){try grouped([])}
  try bad("missing vertex membership"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2],triangleIDs:[0,1])])}
  try bad("duplicate local vertex membership"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2,2],triangleIDs:[0,1])])}
  try bad("missing triangle membership"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0])])}
  try bad("duplicate triangle membership"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,0])])}
  try bad("vertex membership out of range"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2,99],triangleIDs:[0,1])])}
  try bad("triangle membership out of range"){try grouped([.init(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,99])])}
  try bad("duplicate panel name"){try grouped([full,.init(panelID:"paper",vertexIDs:[0],triangleIDs:[0])])}
  try bad("cross panel vertex membership"){try grouped([.init(panelID:"a",vertexIDs:[0,1,2],triangleIDs:[0]),.init(panelID:"b",vertexIDs:[0,3],triangleIDs:[1])])}
  try bad("face owner disagrees with explicit vertices"){try grouped([.init(panelID:"a",vertexIDs:[0,1,2],triangleIDs:[1]),.init(panelID:"b",vertexIDs:[3],triangleIDs:[0])])}
  try bad("empty panel name"){try grouped([.init(panelID:"",vertexIDs:[0,1,2,3],triangleIDs:[0,1])])}
  try bad("angle index out of range"){_ = try p.angle(positions:x,hingeID:1)}
  // Face encounter/cyclic order cannot alter a scalar energy or global forces.
  for order in [[1,0,3,0,1,2],[1,2,0,0,3,1],[0,2,1,1,3,0]] {
   let reordered=try prepare(reference:ref,triangles:order,panelIDs:panels)
   let er=try reordered.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb))
   try require(abs(er.energyJoules-ev.energyJoules)<1e-14 && maxNorm(diff(er.gradientNewton,ev.gradientNewton))<1e-12,"source face ordering covariance")
  }
  summary["rejections"]=rejects;summary["unsewnCoincidentPanels"]=["hinges":0,"boundaryEdges":6]
 }
 static func grid(_ n:Int,_ kb:Double)throws->[String:Double] {
  var ref:[V]=[],tri:[Int]=[];let width=0.4,height=0.3,R=0.5
  for j in 0...n{for i in 0...n{ref.append(v(width*Double(i)/Double(n),height*Double(j)/Double(n),0))}}
  for j in 0..<n{for i in 0..<n{let a=j*(n+1)+i,b=a+1,c=a+n+1,d=c+1;tri += [a,b,d,a,d,c]}}
  let p=try prepare(reference:ref,triangles:tri,panelIDs:Array(repeating:"grid",count:ref.count))
  let cyl=ref.map{v(R*sin($0.x/R),$0.y,R*(1-cos($0.x/R)))},ev=try p.evaluate(positions:cyl,material:try HB.Material(bendingStiffnessNewtonMeter:kb))
  let expected=3*kb*width*height/(R*R)*(1-1/Double(n))
  try require(abs(ev.energyJoules-expected)<1e-12,"grid cylinder exact discrete oracle")
  return ["cellsEachAxis":Double(n),"hinges":Double(p.hinges.count),"energyJ":ev.energyJoules,"exactDiscreteOracleJ":expected,"limitForThisGridJ":3*kb*width*height/(R*R)]
 }
 static func real(_ path:String)throws {
  let input=try JSONDecoder().decode(SourceInput.self,from:Data(contentsOf:URL(fileURLWithPath:path))),kb=2e-4,start=Date()
  let p=try HB.Prepared(referencePositions:input.referencePositions,referenceTriangles:input.referenceTriangles,panelGroups:input.panelGroups)
  let base=try p.evaluate(positions:input.reference,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),placed=try p.evaluate(positions:input.positions,material:try HB.Material(bendingStiffnessNewtonMeter:kb))
  try require(p.triangleCount==3472 && input.reference.count==2000 && p.hinges.count==4948 && p.boundaryEdgeCount==520,"actual source dimensions and complete hinge graph")
  try require(p.panelHingeCounts==["skirt_back":2408,"skirt_front":2384,"wb_back":75,"wb_front":81],"explicit actual per-panel hinge membership")
  let owner=Dictionary(uniqueKeysWithValues:input.panelGroups.flatMap{g in g.vertexIDs.map{($0,g.panelID)}})
  for h in p.hinges {try require(h.vertexIDs.allSatisfy{owner[$0]==h.panelID},"hinge crosses source panel")}

  try require(base.energyJoules<1e-20 && placed.energyJoules<1e-20,"flat reference and independently rigid panel rest")
  // Smooth source-dependent out-of-plane deformation is a derivative probe only.
  // It is not a dynamics step or a drape/fit/quality acceptance result.
  let x=input.reference.map{v($0.x,$0.y,0.012*sin(5*$0.x)*cos(4*$0.y)+0.009*$0.x*$0.y)}
  let ev=try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb)),d=rng(x.count),other=rng(x.count,2.9)
  var probes:[[String:Double]]=[]
  for eps in [1e-7,3e-8,1e-8]{let e=try fd(p,x,d,kb,eps);probes.append(["epsilonMeters":eps,"energyGradientDirectionalRelativeError":e.0,"exactHvRelativeError":e.1]);try require(e.0<1e-4 && e.1<1e-4,"real source directional FD")}
  let hd=try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact),hv=try p.hessianProduct(positions:x,direction:other,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact),gn=try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.gaussNewtonPSD)
  let symmetry=abs(dot(other,hd)-dot(d,hv))/max(1,max(abs(dot(other,hd)),abs(dot(d,hv)))),force=ev.gradientNewton.reduce(V.zero,+),torque=zip(x,ev.gradientNewton).reduce(V.zero){$0+$1.0.cross($1.1)}
  try require(symmetry<1e-10 && force.norm<1e-10 && torque.norm<1e-10,"real force torque symmetry")
  try require(dot(d,gn)>=(-1e-10),"real GN PSD")
  let r=try p.evaluate(positions:x.map{rotate($0)+v(0.7,-1.1,2.3)},material:try HB.Material(bendingStiffnessNewtonMeter:kb))
  try require(abs(r.energyJoules-ev.energyJoules)<1e-12 && maxNorm(diff(r.gradientNewton,ev.gradientNewton.map{rotate($0)}))<1e-9,"real rigid covariance")
  var checked=0,maxLocalE=0.0,maxLocalH=0.0
  for id in stride(from:0,to:x.count,by:41){
   var b=Array(repeating:V.zero,count:x.count);b[id]=v(0.4,-0.7,0.9)
   let e=try fd(p,x,b,kb,1e-7);maxLocalE=max(maxLocalE,e.0);maxLocalH=max(maxLocalH,e.1);checked+=1
  }
  try require(maxLocalE<1e-3 && maxLocalH<1e-5,"sampled real per-vertex FD")
  let prepareCancel=CancelAfter(5),evaluateCancel=CancelAfter(20),hvCancel=CancelAfter(35)
  try cancelled("cancel during source construction"){_ = try HB.Prepared(referencePositions:input.referencePositions,referenceTriangles:input.referenceTriangles,panelGroups:input.panelGroups,isCancelled:{prepareCancel.check()})}
  try cancelled("cancel during real evaluation"){_ = try p.evaluate(positions:x,material:try HB.Material(bendingStiffnessNewtonMeter:kb),isCancelled:{evaluateCancel.check()})}
  try cancelled("cancel during real Hv"){_ = try p.hessianProduct(positions:x,direction:d,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact,isCancelled:{hvCancel.check()})}
  try reject("actual source vertex budget"){var l=HB.Limits();l.maximumVertices=1999;_ = try HB.Prepared(referencePositions:input.referencePositions,referenceTriangles:input.referenceTriangles,panelGroups:input.panelGroups,limits:l)}
  try reject("actual source triangle budget"){var l=HB.Limits();l.maximumTriangles=3471;_ = try HB.Prepared(referencePositions:input.referencePositions,referenceTriangles:input.referenceTriangles,panelGroups:input.panelGroups,limits:l)}
  try reject("actual source hinge budget"){var l=HB.Limits();l.maximumHinges=4947;_ = try HB.Prepared(referencePositions:input.referencePositions,referenceTriangles:input.referenceTriangles,panelGroups:input.panelGroups,limits:l)}
  let flatD=rng(input.reference.count,0.5),flatExact=try p.hessianProduct(positions:input.reference,direction:flatD,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.exact),flatGN=try p.hessianProduct(positions:input.reference,direction:flatD,material:try HB.Material(bendingStiffnessNewtonMeter:kb),mode:.gaussNewtonPSD)
  try require(maxNorm(diff(flatExact,flatGN))==0,"exact and GN agree at flat rest only")
  summary["realSource"]=["sourceSHA256":input.sourceSHA256,"vertices":p.vertexCount,"referenceTriangles":p.triangleCount,"internalHinges":p.hinges.count,"boundaryEdgesWithoutHinges":p.boundaryEdgeCount,"hingesByPanel":p.panelHingeCounts,"referenceEnergyJ":base.energyJoules,"initialRigidPanelsEnergyJ":placed.energyJoules,"derivativeProbeEnergyJ":ev.energyJoules,"maxAbsAngleRadians":ev.maximumAbsoluteAngleRadians,"directionalFD":probes,"sampledVertexDirections":checked,"maxSampledVertexEnergyGradientRelativeError":maxLocalE,"maxSampledVertexHvRelativeError":maxLocalH,"netGradientNewton":force.norm,"netTorqueNewtonMeter":torque.norm,"bilinearSymmetryError":symmetry,"gnQuadraticForm":dot(d,gn),"exactMinusGNMaxNorm":maxNorm(diff(hd,gn)),"elapsedSecondsIncludingValidation":Date().timeIntervalSince(start),"midLoopCancellationChecks":3,"strictCancellationTypeVerified":true,"actualSourceBudgetChecks":3,"flatRestExactMinusGN":maxNorm(diff(flatExact,flatGN)),"noPinsAdded":true,"noSourceOrMassChanges":true,"noDynamicsRun":true]
 }
 static func main()throws {
  guard CommandLine.arguments.count==3 else{throw TestFailure.invalid("usage: hinge-regression fixture-directory output-directory")}
  let fixture=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  try single();summary["refinementCylinder"] = try [4,8,16,32,64].map{try grid($0,2e-4)}
  try real(fixture.appendingPathComponent("native-source-topology.json").path);summary["status"]="pass";summary["kbExperimentalNewtonMeter"]=2e-4
  summary["energyConvention"]="kb * sum(3*L0^2/(A01+A02)*theta^2), flat rest theta=0; no factor 1/2"
  summary["gnIsApproximation"]=true
  let data=try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]);try data.write(to:out.appendingPathComponent("hinge-summary.json"))
  print("HINGE BENDING PASS; report \(CommandLine.arguments[2])")
 }
}
