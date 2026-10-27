import Foundation
import CryptoKit

typealias F=GarmentCodeDrapeFraming
typealias E=GarmentCodeMeshExport
typealias K=GarmentCodeCircleDrape
nonisolated final class ExportCounter:@unchecked Sendable {
 private let lock=NSLock();private var n=0
 func next()->Int {lock.lock();defer{lock.unlock()};n+=1;return n}
}
@main @MainActor struct GarmentViewerExportRegression {
 enum Failure:Error {case failed(String)}
 static func require(_ p:Bool,_ text:String)throws{if !p{throw Failure.failed(text)}}
 static func bad(_ text:String,_ fn:()throws->Void)throws {do{try fn()}catch{return};throw Failure.failed("accepted "+text)}
 static func asyncBad(_ text:String,_ fn:()async throws->Void)async throws {do{try await fn()}catch{return};throw Failure.failed("accepted "+text)}
 static func bounds(_ center:SIMD3<Double>,_ half:SIMD3<Double>)throws->F.Bounds {
  try .init(points:[center-half,center+half])
 }
 static func framing()throws->Int {
  let shapes:[(String,SIMD3<Double>,SIMD3<Double>)]=[
   ("wide-sleeved-shirt",.init(0.17,0.45,-0.09),.init(0.85,0.4,0.25)),
   ("hood-high",.init(-0.11,0.85,0.16),.init(0.4,0.65,0.35)),
   ("pants",.init(0.12,-0.55,0.03),.init(0.45,0.65,0.25)),
   ("asymmetric-skirt",.init(-0.45,-0.4,0.33),.init(0.9,0.65,0.75)),
   ("many-panels",.init(0.05,-0.3,-0.15),.init(0.8,0.8,0.8)),
   ("standalone-collar",.init(0.1,0.65,-0.1),.init(0.12,0.035,0.08)),
   ("tiny-waistband",.init(-0.1,0.03,0.2),.init(0.17,0.023,0.12))]
  let body=try bounds(.init(0,0.02,0),.init(0.35,0.9,0.2));var count=0
  for(_,center,half) in shapes {let cloth=try bounds(center,half)
   for visible in [false,true] {for focus in [F.Focus.visibleGeometry,.garment] {for size in [(320.0,380.0),(1024.0,380.0),(120.0,800.0)] {for yaw in [-Double.pi/2,0,0.35,Double.pi] {for pitch in [-0.8,0,0.8] {
    var c=F.Configuration();c.showMannequin=visible;c.focus=focus;c.yaw=yaw;c.pitch=pitch
    let f=try F.frame(garment:cloth,mannequin:body,configuration:c,width:size.0,height:size.1)
    let selected=visible && focus == .visibleGeometry ? cloth.union(body):cloth
    try require(f.center==selected.center,"full xyz center")
    let tanV=tan(f.verticalFieldOfViewDegrees*Double.pi/360),tanH=tanV*f.aspect
    for p in selected.corners {let q=F.rotated(p-f.center,yaw:yaw,pitch:pitch),depth=f.distance-q.z
     try require(depth>f.nearPlane && depth<f.farPlane,"near/far complete geometry")
     try require(abs(q.x)<=depth*tanH+1e-10 && abs(q.y)<=depth*tanV+1e-10,"complete perspective frustum")
    }
    if visible && focus == .garment {for p in body.corners {let q=p-f.center;try require(f.distance>sqrt(q.x*q.x+q.y*q.y+q.z*q.z),"camera outside complete visible body")}}
    count+=1
   }}}}}
  }
  try bad("empty bounds"){_ = try F.Bounds(points:[])}
  try bad("NaN bounds"){_ = try F.Bounds(points:[.init(.nan,0,0)])}
  try bad("overflow bounds"){_ = try F.Bounds(points:[.init(1e20,0,0)])}
  let q=try bounds(.zero,.init(1,1,1))
  try bad("zero viewport"){_ = try F.frame(garment:q,mannequin:nil,configuration:.init(),width:0,height:1)}
  var c=F.Configuration();c.yaw = .nan
  try bad("NaN camera"){_ = try F.frame(garment:q,mannequin:nil,configuration:c,width:1,height:1)}
  c = .init();c.zoomScale=0
  try bad("invalid zoom"){_ = try F.frame(garment:q,mannequin:nil,configuration:c,width:1,height:1)}
  return count
 }
 static func output(grouped:Bool=true,nan:Bool=false)->K.Output {
  let points=[K.Vector3(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0.1,y:0.2,z:0.3),.init(x:0.9,y:0.2,z:0.3),.init(x:0.1,y:0.8,z:0.3)]
  var p=points;if nan {p[0].x = .nan}
  let d=K.Diagnostics(vertexCount:6,triangleCount:2,simulatedSeconds:0,computationSeconds:0,maxEdgeStrain:0,meanEdgeStrain:0,maxSpeedMetersPerSecond:0,maxBodyPenetrationMeters:0,maxSeamGapMeters:0,waistCircumferenceMeters:0,hemCircumferenceMeters:0,radialLengthMeters:0,referenceAreaSquareMeters:1,converged:false,warnings:["Synthetic serialization fixture; no garment/physics acceptance"])
  let groups:[K.PanelGroup]?=grouped ? [.init(panelID:"左 袖/前",vertexIDs:[0,1,2],triangleIDs:[0]),.init(panelID:"right_sleeve",vertexIDs:[3,4,5],triangleIDs:[1])]:nil
  return .init(positions:p,triangleIndices:[0,1,2,3,4,5],mannequinPositions:[.init(x:-1,y:-1,z:-1),.init(x:1,y:-1,z:-1),.init(x:0,y:1,z:-1)],mannequinTriangleIndices:[0,1,2],seamPaths:[[0,1],[3,4]],seamVertexPairs:[],diagnostics:d,panelGroups:groups)
 }
 static func readback(_ bytes:Data,_ o:K.Output)throws {
  let text=try XCTString(bytes),lines=text.split(separator:"\n")
  let vertices=lines.filter{$0.hasPrefix("v ")},faces=lines.filter{$0.hasPrefix("f ")}
  try require(vertices.count==o.positions.count+o.mannequinPositions.count,"OBJ complete vertices")
  try require(faces.count==(o.triangleIndices.count+o.mannequinTriangleIndices.count)/3,"OBJ complete faces")
  let expected=[[1,2,3],[4,5,6],[7,8,9]],actual=faces.map{$0.split(separator:" ").dropFirst().compactMap{Int($0)}}
  try require(actual==expected,"independent panel and mannequin global index offsets")
  if o.panelGroups != nil {try require(lines.contains{$0.hasPrefix("g panel_0_")} && lines.contains("g panel_1_right_sleeve") && lines.contains("g mannequin"),"all panel groups")}
 }
 static func XCTString(_ d:Data)throws->String {guard let s=String(data:d,encoding:.utf8) else {throw Failure.failed("UTF8")};return s}
 static func main()async throws {
  let out=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let files=out.appendingPathComponent("owned-exports",isDirectory:true);try FileManager.default.createDirectory(at:files,withIntermediateDirectories:true)
  let marker=files.appendingPathComponent("keep.txt");try Data("keep".utf8).write(to:marker)
  let frames=try framing(),o=output(),resultID=UUID()
  async let first=E.export(output:o,resultID:resultID,directory:files)
  async let second=E.export(output:o,resultID:resultID,directory:files)
  let (a,b)=try await(first,second),bytes=try Data(contentsOf:a.url)
  try require(a.resultID==resultID && b.resultID==resultID && a.exportID != b.exportID && a.url != b.url,"same result independent retries")
  try require(bytes==Data(o.objString.utf8) && bytes==Data(contentsOf:b.url),"original serializer bytes retained")
  try require(a.byteCount==bytes.count && a.sha256==b.sha256,"stable export fingerprint")
  try readback(bytes,o)
  let legacy=output(grouped:false),l=try await E.export(output:legacy,resultID:UUID(),directory:files)
  try require(Data(contentsOf:l.url)==Data(legacy.objString.utf8),"legacy serializer unchanged")
  try await asyncBad("NaN output"){_ = try await E.export(output:output(nan:true),resultID:UUID(),directory:files)}
  var invalid=o;invalid.panelGroups=[.init(panelID:"missing",vertexIDs:[0,1,2],triangleIDs:[0])]
  let badOutput=invalid
  try await asyncBad("malformed optional panel groups"){_ = try await E.export(output:badOutput,resultID:UUID(),directory:files)}
  var limit=E.Limits();limit.maximumBytes=1
  let budget=limit
  try await asyncBad("byte budget"){_ = try await E.export(output:o,resultID:UUID(),directory:files,limits:budget)}
  let before=try FileManager.default.contentsOfDirectory(atPath:files.path).sorted(),cancel=ExportCounter()
  do {_ = try await E.export(output:o,resultID:UUID(),directory:files,isCancelled:{cancel.next()>8});throw Failure.failed("late cancel ignored")}catch is CancellationError{}
  let after=try FileManager.default.contentsOfDirectory(atPath:files.path).sorted();try require(before==after,"late cancellation removes pending/committed trial")
  let task=Task{try await E.export(output:o,resultID:UUID(),directory:files)};task.cancel()
  do {_ = try await task.value;throw Failure.failed("Task cancel ignored")}catch is CancellationError{}
  let blocked=files.appendingPathComponent("not-a-directory");try Data("file".utf8).write(to:blocked)
  try await asyncBad("IO failure"){_ = try await E.export(output:o,resultID:UUID(),directory:blocked)}
  try require(Data(contentsOf:marker)==Data("keep".utf8),"unrelated file unchanged")
  try E.remove(a);try require(!FileManager.default.fileExists(atPath:a.url.path) && FileManager.default.fileExists(atPath:b.url.path),"artifact cleanup isolation")
  let report:[String:Any]=["passed":true,"pureFrustumCases":frames,"independentOBJReadback":true,"legacyAndGroupedOBJBytesUnchanged":true,"sameResultRetry":true,"lateCancellationAtomicCleanup":true,"taskCancellation":true,"UIExecuted":false,"noSimulation":true]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("viewer-export-summary.json"))
 }
}
