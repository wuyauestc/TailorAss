import Foundation
import Synchronization
#if os(macOS)
import Darwin
#endif

@main @MainActor struct FitDeformationReplayChecks {
    typealias R=GarmentCodeFitDeformationReplay
    typealias V=R.V
    struct Input:Decodable {let controls:[Double],diagnosticPositions:[V]?,triangleIndices:[UInt32]?,diagnosticMeasurement:GarmentCodeBodySurfaceMeasurements.Report?,bodyValues:[String:Double]?,expectedFitGeometrySHA256:String?,sourceGeometrySHA256:String?,sourceParameterSHA256:String?}
    struct Rig:Decodable {struct Point:Decodable{let visibleVertexID:Int?};struct Joint:Decodable{let sourceVertexTableIndices:[Int]};struct Bone:Decodable{let name:String,head:Int,tail:Int};let jointSourceVertexTable:[Point],joints:[Joint],bones:[Bone]}
    enum Failure:Error {case failed(String)}
    static func require(_ b:Bool,_ s:String)throws{if !b{throw Failure.failed(s)}}
    static func same(_ a:[V],_ b:[V])->Bool{a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}}
    static func write<T:Encodable>(_ x:T,_ path:URL)throws {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];try e.encode(x).write(to:path)}
    static func main()async throws {
        let resources=URL(fileURLWithPath:CommandLine.arguments[1]),fixtures=URL(fileURLWithPath:CommandLine.arguments[2]),out=URL(fileURLWithPath:CommandLine.arguments[3]),d=JSONDecoder()
        func data(_ n:String)throws->Data{try Data(contentsOf:resources.appendingPathComponent(n))}
        let t=try data("GarmentCodeStandardBody.json"),r=try data("GarmentCodeStandardBodyRig/rig.json"),c=try data("GarmentCodeBodySurfaceMeasurements.json"),a=try data("GarmentCodeBodyFitAuxiliaryWeights.json")
        let prepared=try R.Prepared(templateData:t,rigData:r,contractData:c,auxiliaryWeightsData:a),rig=try d.decode(Rig.self,from:r)
        let measurements=try GarmentCodeBodySurfaceMeasurements.Prepared(contractData:c,templateData:t,rigData:r)
        let oldRig=try GarmentCodeBodyRig.load(resourceDirectory:resources)
        var rows:[[String:Any]]=[]
        for name in ["default","female"] {
            let input=try d.decode(Input.self,from:Data(contentsOf:fixtures.appendingPathComponent(name+"-input.json")))
            guard let values=input.bodyValues ?? input.diagnosticMeasurement?.bodyValues else{throw Failure.failed("Missing original33 values")}
            let body=GarmentCodeBodyParameters(values:values),source=try GarmentCodeStandardBody.load(body:body,resourceDirectory:resources)
            let context=try prepared.context(sourcePositions:source.positions,triangleIndices:source.triangleIndices,bodyValues:values)
            let shape=try await Task.detached {try context.deform(controls:input.controls)}.value
            if let original=input.diagnosticPositions {try require(same(shape.visiblePositions,original),"New shared visible replay must be BITWISE equal to original optimizer: "+name)}
            let expected=input.expectedFitGeometrySHA256 ?? input.diagnosticMeasurement?.geometrySHA256
            try require(shape.geometrySHA256==expected,"Complete actual original visible geometry SHA")
            try require(shape.sourceGeometrySHA256==input.sourceGeometrySHA256 && shape.sourceParameterSHA256==input.sourceParameterSHA256 && input.triangleIndices.map{shape.triangleIndices==$0} != false,"All original source/parameter/topology bindings")
            try require(shape.bodyValues==values,"Complete33 values retained")
            try require(!shape.bodyCapabilityIssued && !shape.compatibleWithLegacyInverseSDF,"Data is not a body capability or old SDF")
            var overlap=0
            for (i,p) in rig.jointSourceVertexTable.enumerated(){if let v=p.visibleVertexID{try require(same([shape.visiblePositions[v]],[shape.helperPositions[i]]),"135 overlapping point bits");overlap+=1}}
            try require(overlap==135,"All135 overlap points")
            for (i,joint) in rig.joints.enumerated(){let points=joint.sourceVertexTableIndices.map{shape.helperPositions[$0]},mean=points.reduce(V.zero,+)/Double(points.count);try require(same([mean],[shape.restJointAnchors[i]]),"Mean individually fitted helpers")}
            let fresh=try measurements.measure(positions:shape.visiblePositions,triangleIndices:shape.triangleIndices,bodyValues:values)
            let goals=fresh.measurements.filter{$0.definition.targetUse=="projectFittingReference"}
            try require(goals.count==6 && goals.allSatisfy{abs($0.observedMinusRequestedMeters)<=1e-5},"Shared replay retains six actual surface goals")
            try write(shape,out.appendingPathComponent(name+"-shape.json"))
            let identity=try context.pose(shape,pose:.identity)
            try require(same(identity.visiblePositions,shape.visiblePositions) && same(identity.helperPositions,shape.helperPositions),"Identity fitted-reference pose is bitwise")
            var poses:[[String:Any]]=[]
            for degree in [30.0,45.0,60.0] {
                let posed=try context.pose(shape,pose:.arms(alphaDegrees:degree))
                try require(!posed.bodyCapabilityIssued && !posed.compatibleWithLegacyInverseSDF && !posed.anatomicalFitCertified,"Pose data cannot enter legacy SDF or claim anatomy")
                for side in ["L","R"]{let root=rig.bones.first{$0.name=="upperarm01."+side}!,elbow=rig.bones.first{$0.name=="upperarm02."+side}!,axis=posed.posedBoneJointAnchors[elbow.tail]-posed.posedBoneJointAnchors[root.head];try require(abs(atan2(-axis.y,abs(axis.x))*180/Double.pi-degree)<1e-10,"Absolute projected fitted bone pose")}
                for (i,p) in rig.jointSourceVertexTable.enumerated(){if let v=p.visibleVertexID{try require(same([posed.visiblePositions[v]],[posed.helperPositions[i]]),"Pose135 overlap point bits")}}
                let topology=try GarmentCodeClothContact.Topology(vertexCount:posed.visiblePositions.count,triangleIndices:posed.triangleIndices)
                let diagnostic=try GarmentCodeClothContact.inspect(positions:posed.visiblePositions,topology:topology,thickness:0.0001,maximumCandidatePairs:300_000)
                try write(posed,out.appendingPathComponent(name+"-pose-"+String(Int(degree))+".json"))
                poses.append(["alpha":degree,"geometrySHA256":posed.geometrySHA256,"coarseNonadjacentCrossings":diagnostic.intersectingTrianglePairs,"coarseDegenerateTriangles":diagnostic.degenerateTriangles,"completeGeometryCapabilityIssued":false])
            }
            var rejects=0
            func reject(_ label:String,_ action:()throws->Void)throws {do{try action()}catch{rejects+=1;return};throw Failure.failed("Accepted negative control "+label)}
            var wrong=source.positions;wrong[0].x=wrong[0].x.nextUp
            try reject("arbitrary source vertex"){_ = try prepared.context(sourcePositions:wrong,triangleIndices:source.triangleIndices,bodyValues:values)}
            try reject("nonfinite controls"){_ = try context.deform(controls:[.nan,0,0,0])}
            try reject("out of fitting bounds"){_ = try context.deform(controls:[0,2,0,0])}
            try reject("pose out of range"){_ = try context.pose(shape,pose:.arms(alphaDegrees:91))}
            let other=try prepared.context(sourcePositions:source.positions,triangleIndices:source.triangleIndices,bodyValues:values)
            try reject("stale context"){_ = try other.pose(shape,pose:.identity)}
            try reject("oldRig fitted source"){_ = try oldRig.pose(visiblePositions:shape.visiblePositions,triangleIndices:shape.triangleIndices,bodyValues:values,pose:.identity)}
            try reject("old fixed-pose receipt"){_ = try GarmentCodeBodySurfaceContact.captureFixedSurface(positions:shape.visiblePositions,triangleIndices:shape.triangleIndices,expectedGeometrySHA256:shape.geometrySHA256,sourcePositions:source.positions,sourceTriangleIndices:source.triangleIndices,rigResourceSHA256:shape.rigResourceSHA256,requestedAlphaDegrees:values["arm_pose_angle"]!,templateData:t,rigData:r,bodyValues:values)}
            let calls=Mutex(0)
            do{_ = try context.deform(controls:input.controls,isCancelled:{calls.withLock{$0+=1;return $0>=10}});throw Failure.failed("Mid-replay cancel") }catch is CancellationError{rejects+=1}
            do{_ = try context.pose(shape,pose:.arms(alphaDegrees:45),isCancelled:{true});throw Failure.failed("Pose cancel")}catch is CancellationError{rejects+=1}
            #if os(macOS)
            let oldMode=fegetround()
            do {_ = try context.deform(controls:input.controls,isCancelled:{_ = fesetround(FE_UPWARD);return false});_ = fesetround(oldMode);throw Failure.failed("Changed rounding callback published replay")}
            catch is R.ReplayError {_ = fesetround(oldMode);rejects+=1}
            #endif
            try require(same(source.positions,try GarmentCodeStandardBody.load(body:body,resourceDirectory:resources).positions),"Canonical source unchanged")
            rows.append(["profile":name,"fullOriginalVisibleBitwiseComparisonExercised":input.diagnosticPositions != nil,"originalVisibleGeometrySHAEqual":true,"visibleVertices":shape.visiblePositions.count,"helpers":shape.helperPositions.count,"joints":shape.restJointAnchors.count,"overlap135Bits":true,"shapeGeometrySHA256":shape.geometrySHA256,"sixSurfaceGoalsPreserved":true,"negativeControls":rejects,"poses":poses,"bodyCapabilityIssued":false])
        }
        let summary:[String:Any]=["passed":true,"scope":"Pure source-bound finite point fitting/pose replay only. No body capability, SDF, App/default route or cloth solve.","rows":rows]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("swift-summary.json"));print("FIT_REPLAY_PASS",rows.count)
    }
}
