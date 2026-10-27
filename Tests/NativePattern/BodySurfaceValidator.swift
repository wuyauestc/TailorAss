import Foundation
import Synchronization
#if os(macOS)
import Darwin
#endif

@main @MainActor struct BodySurfaceValidatorChecks {
    typealias B=GarmentCodeBodySurfaceValidator
    typealias V=B.V
    struct Case:Codable {let name:String,positions:[V],triangleIndices:[UInt32],expectedClear:Bool}
    struct Golden:Decodable {let bodyValues:[String:Double],controls:[Double]}
    struct PoseGolden:Decodable {let name:String,geometrySHA256:String,candidateTrianglePairs:Int,expectedTopologicalTouchPairs:Int}
    enum Failure:Error {case failed(String)}
    static func require(_ x:Bool,_ s:String)throws {if !x{throw Failure.failed(s)}}
    static func write<T:Encodable>(_ x:T,_ p:URL)throws {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];try e.encode(x).write(to:p)}
    static func main()async throws {
        let resources=URL(fileURLWithPath:CommandLine.arguments[1]),fixtures=URL(fileURLWithPath:CommandLine.arguments[2]),out=URL(fileURLWithPath:CommandLine.arguments[3])
        func v(_ x:Double,_ y:Double,_ z:Double=0)->V {.init(x:x,y:y,z:z)}
        let a=[v(0,0),v(2,0),v(0,2)]
        var cases:[Case]=[]
        func add(_ n:String,_ p:[V],_ ids:[UInt32],_ clear:Bool){cases.append(.init(name:n,positions:p,triangleIndices:ids,expectedClear:clear))}
        add("disjoint-AABB",a+[v(0,0,1),v(2,0,1),v(0,2,1)],[0,1,2,3,4,5],true)
        add("coplanar-disjoint-overlapping-AABB",a+[v(1.5,1.5),v(2,1.5),v(1.5,2)],[0,1,2,3,4,5],true)
        add("proper-crossing",a+[v(0.25,0.25,-1),v(0.25,0.25,1),v(1,0.25)],[0,1,2,3,4,5],false)
        add("coplanar-positive-area",a+[v(0.2,0.2),v(1,0.2),v(0.2,1)],[0,1,2,3,4,5],false)
        add("distinct-ID-point-touch",a+[v(0,0),v(0,0,1),v(-1,0,1)],[0,1,2,3,4,5],false)
        add("distinct-ID-edge-touch",a+[v(0,0),v(2,0),v(0,-2)],[0,1,2,3,4,5],false)
        add("shared-edge-perpendicular",a+[v(0,0,1)],[0,1,2,0,1,3],true)
        add("shared-edge-flat-opposite",a+[v(0,-2)],[0,1,2,0,1,3],true)
        add("shared-edge-flat-fold",a+[v(0.5,0.5)],[0,1,2,0,1,3],false)
        add("shared-vertex-flat-disjoint",a+[v(-1,0),v(0,-1)],[0,1,2,0,3,4],true)
        add("shared-vertex-extra-intersection",a+[v(0.5,0.5,-1),v(0.5,0.5,1)],[0,1,2,0,3,4],false)
        add("shared-vertex-coplanar-fold",a+[v(0.5,0.5),v(-1,0)],[0,1,2,0,3,4],false)
        add("coplanar-segment-plane-contact",a+[v(-1,1),v(3,1),v(-1,1,1)],[0,1,2,3,4,5],false)
        add("one-vertex-on-other-interior",a+[v(0.5,0.5),v(0.5,0.5,1),v(1,0.5,1)],[0,1,2,3,4,5],false)
        add("tiny-positive-distance",a+[v(0,0,1e-300),v(2,0,1e-300),v(0,2,1e-300)],[0,1,2,3,4,5],true)
        add("extreme-exponents",[v(-1e300,0),v(1e300,0),v(0,1e300),v(-1e300,0,1e-300),v(1e300,0,1e-300),v(0,1e300,1e-300)],[0,1,2,3,4,5],true)
        let originals=Array(cases.prefix(14))
        for factor in [1e-200,1e-100,1e100,1e150] {for c in originals {add(c.name+"-scale-"+String(factor),c.positions.map{$0*factor},c.triangleIndices,c.expectedClear)}}
        for c in originals {add(c.name+"-reversed",c.positions,Array(c.triangleIndices.prefix(3).reversed())+Array(c.triangleIndices.dropFirst(3).reversed()),c.expectedClear)}
        for c in originals {add(c.name+"-translated",c.positions.map{$0+v(1e10,-1e10,1e10)},c.triangleIndices,c.expectedClear)}
        var checked=0
        for c in cases {
            do {let cert=try B.validate(positions:c.positions,triangleIndices:c.triangleIndices);try require(c.expectedClear,"False clear "+c.name);try cert.verify(positions:c.positions,triangleIndices:c.triangleIndices);try require(cert.report.completedAllPairs,"Incomplete report")}
            catch let e as B.ValidationError {guard !c.expectedClear else{throw e};guard case .intersection=e else{throw e}}
            checked+=1
        }
        // Deterministic finite random inputs are separately checked using the
        // Fraction closed-triangle oracle, not only implementation self-tests.
        var seed:UInt64=718
        func random()->Double {seed=seed &* 6364136223846793005 &+ 1442695040888963407;return Double(Int((seed>>32)%33)-16)/8}
        for n in 0..<160 {
            var ps=(0..<6).map{_ in v(random(),random(),n%2==0 ? 0:random())}
            if n%4==0 {ps[3]=ps[0]}
            let ids:[UInt32]=n%5==0 ? [0,1,2,0,4,5]:[0,1,2,3,4,5]
            do {_ = try B.validate(positions:ps,triangleIndices:ids);add("random-\(n)",ps,ids,true)}
            catch B.ValidationError.intersection {add("random-\(n)",ps,ids,false)}
            catch B.ValidationError.degenerateTriangle {continue}
        }
        try write(cases,out.appendingPathComponent("analytic-cases.json"))
        let bitRows=cases.map {c in ["name":c.name,"positions":c.positions.map{v in [v.x,v.y,v.z].map{String(format:"%016llx",$0.bitPattern)}}] as [String:Any]}
        try JSONSerialization.data(withJSONObject:bitRows,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("analytic-runtime-bits.json"))
        let good=cases.first{$0.name=="shared-edge-flat-opposite"}!,cert=try B.validate(positions:good.positions,triangleIndices:good.triangleIndices)
        var negatives=0
        func reject(_ label:String,_ f:()throws->Void)throws {do{try f()}catch{negatives+=1;return};throw Failure.failed("Accepted "+label)}
        var changed=good.positions;changed[0].x = -0.0
        try reject("certificate signed-zero tamper"){try cert.verify(positions:changed,triangleIndices:good.triangleIndices)}
        try reject("certificate triangle IDs"){try cert.verify(positions:good.positions,triangleIndices:[0,2,1,0,1,3])}
        try reject("duplicate face"){_ = try B.validate(positions:a,triangleIndices:[0,1,2,2,1,0])}
        try reject("degenerate triangle"){_ = try B.validate(positions:[v(0,0),v(1,0),v(2,0)],triangleIndices:[0,1,2])}
        try reject("invalid index"){_ = try B.validate(positions:a,triangleIndices:[0,1,3])}
        try reject("incomplete index"){_ = try B.validate(positions:a,triangleIndices:[0,1])}
        try reject("nonfinite input"){_ = try B.validate(positions:[v(.nan,0),v(1,0),v(0,1)],triangleIndices:[0,1,2])}
        for key in 0..<7 {var l=B.Limits();switch key {case 0:l.maximumVertices=1;case 1:l.maximumBVHWork=1;case 2:l.maximumPredicates=1;case 3:l.maximumExactWordOperations=1;case 4:l.maximumEstimatedWorkingBytes=1;case 5:l.maximumExactWords=8;default:l.maximumCandidatePairs=1}
            let fan=[v(0,0),v(1,0),v(0,1),v(-1,0),v(0,-1)],ids:[UInt32]=[0,1,2,0,2,3,0,3,4]
            let c=key==5 ? cases.first{$0.name=="extreme-exponents"}!:Case(name:"budget",positions:fan,triangleIndices:ids,expectedClear:true)
            try reject("budget \(key)"){_ = try B.validate(positions:c.positions,triangleIndices:c.triangleIndices,limits:l)}
        }
        let calls=Mutex(0)
        do{_ = try B.validate(positions:good.positions,triangleIndices:good.triangleIndices,isCancelled:{calls.withLock{$0+=1;return $0>=4}});throw Failure.failed("Cancellation not thrown")}catch is CancellationError{negatives+=1}
        let allCalls=Mutex(0)
        _ = try B.validate(positions:good.positions,triangleIndices:good.triangleIndices,isCancelled:{allCalls.withLock{$0+=1};return false})
        let lastCheckpoint=allCalls.withLock{$0},late=Mutex(0)
        do{_ = try B.validate(positions:good.positions,triangleIndices:good.triangleIndices,isCancelled:{late.withLock{$0+=1;return $0>=lastCheckpoint}});throw Failure.failed("Late publication cancellation")}
        catch is CancellationError{negatives+=1}
        #if os(macOS)
        let mode=fegetround()
        do{_ = try B.validate(positions:good.positions,triangleIndices:good.triangleIndices,isCancelled:{_ = fesetround(FE_UPWARD);return false});_ = fesetround(mode);throw Failure.failed("Callback changed RNE")}
        catch B.ValidationError.unsupportedRounding{_ = fesetround(mode);negatives+=1}
        #endif
        func data(_ name:String)throws->Data{try Data(contentsOf:resources.appendingPathComponent(name))}
        let replay=try GarmentCodeFitDeformationReplay.Prepared(templateData:data("GarmentCodeStandardBody.json"),rigData:data("GarmentCodeStandardBodyRig/rig.json"),contractData:data("GarmentCodeBodySurfaceMeasurements.json"),auxiliaryWeightsData:data("GarmentCodeBodyFitAuxiliaryWeights.json"))
        let decoder=JSONDecoder(),goldens=try decoder.decode([PoseGolden].self,from:Data(contentsOf:fixtures.appendingPathComponent("pose-goldens.json")))
        var rows:[B.Report]=[]
        for profile in ["default","female"] {
            let input=try decoder.decode(Golden.self,from:Data(contentsOf:fixtures.appendingPathComponent(profile+"-replay-golden.json")))
            let source=try GarmentCodeStandardBody.load(body:.init(values:input.bodyValues),resourceDirectory:resources)
            let context=try replay.context(sourcePositions:source.positions,triangleIndices:source.triangleIndices,bodyValues:input.bodyValues)
            let shape=try context.deform(controls:input.controls)
            for degree in [30.0,45.0,60.0] {
                let pose=try context.pose(shape,pose:.arms(alphaDegrees:degree)),name=profile+"-pose-"+String(Int(degree)),start=ContinuousClock.now
                let cert=try await Task.detached {try B.validate(positions:pose.visiblePositions,triangleIndices:pose.triangleIndices)}.value
                try cert.verify(positions:pose.visiblePositions,triangleIndices:pose.triangleIndices)
                guard let golden=goldens.first(where:{$0.name==name}) else{throw Failure.failed("Missing independent six-case golden")}
                try require(cert.geometrySHA256==pose.geometrySHA256 && cert.geometrySHA256==golden.geometrySHA256,"Actual posed visible SHA")
                try require(cert.report.candidateTrianglePairs==golden.candidateTrianglePairs && cert.report.expectedTopologicalTouchPairs==golden.expectedTopologicalTouchPairs,"Independent all-pair Fraction classification count")
                rows.append(cert.report);try write(cert.report,out.appendingPathComponent(name+"-report.json"))
                print("BODY_SURFACE_ACTUAL",name,cert.report.candidateTrianglePairs,GarmentCodeJointTiming.seconds(since:start))
            }
        }
        let summary:[String:Any]=["passed":true,"analyticChecks":checked,"fractionControlInputs":cases.count,"negativeControls":negatives,"actualFullMeshes":rows.count,"geometryValidatorOnly":true,"bodyReceiptIssuedHere":false,"clothSimulationRun":false]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("swift-summary.json"));print("BODY_SURFACE_VALIDATOR_PASS",checked,negatives,rows.count)
    }
}
// Avoid a dependency on the simulation layer for a timing diagnostic.
private enum GarmentCodeJointTiming {static func seconds(since t:ContinuousClock.Instant)->Double {let x=t.duration(to:.now).components;return Double(x.seconds)+Double(x.attoseconds)*1e-18}}
