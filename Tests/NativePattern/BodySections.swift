import Foundation
import Synchronization

@main @MainActor struct BodySectionsRegression {
    typealias B=GarmentCodeBodySections
    typealias V=B.V
    nonisolated struct Mesh:Sendable {let p:[V],t:[UInt32]}
    enum Failure:Error{case check(String)}
    static func require(_ x:@autoclosure()throws->Bool,_ m:String)throws{if try !x(){throw Failure.check(m)}}
    static func box(center:V = .zero)->Mesh{
        let p:[V]=[.init(x:-1,y:-1,z:-1),.init(x:1,y:-1,z:-1),.init(x:1,y:-1,z:1),.init(x:-1,y:-1,z:1),.init(x:-1,y:1,z:-1),.init(x:1,y:1,z:-1),.init(x:1,y:1,z:1),.init(x:-1,y:1,z:1)]
        return .init(p:p.map{$0+center},t:[0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,7,3,3,7,4,3,4,0])
    }
    static func cylinder(_ n:Int)->Mesh{
        var p:[V]=[]
        for y in [-1.0,1.0]{for i in 0..<n{let a=2*Double.pi*Double(i)/Double(n);p.append(.init(x:cos(a),y:y,z:sin(a)))}}
        p += [.init(x:0,y:-1,z:0),.init(x:0,y:1,z:0)]
        var t:[UInt32]=[]
        for i in 0..<n{let j=(i+1)%n;t += [2*n,i,j,2*n+1,n+j,n+i,i,n+i,n+j,i,n+j,j].map(UInt32.init)}
        return .init(p:p,t:t)
    }
    static func join(_ a:Mesh,_ b:Mesh)->Mesh{.init(p:a.p+b.p,t:a.t+b.t.map{$0+UInt32(a.p.count)})}
    static func reject(_ name:String,_ f:()throws->Void)throws{do{try f()}catch{return};throw Failure.check("accepted invalid "+name)}
    static func encode<T:Encodable>(_ x:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes];return try e.encode(x)}
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func main()async throws{
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_BODY_SECTIONS_OUTPUT"]!)
        let plane=try B.Plane(origin:.init(x:0,y:0.17,z:0),normal:.init(x:0,y:1,z:0)),cube=box()
        let square=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:plane)
        try require(square.status == .complete && square.loops.count==1,"box contour not complete")
        try require(abs(square.loops[0].perimeterMeters-8)<1e-12 && abs(square.loops[0].areaSquareMeters-4)<1e-12,"box analytic measurements")
        let diagonal=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:.init(origin:.init(x:0.1,y:0,z:0),normal:.init(x:1,y:1,z:0)))
        try require(diagonal.status == .complete && diagonal.loops.count==1,"oblique plane contour")
        try require(abs(diagonal.loops[0].areaSquareMeters-3.8*sqrt(2))<1e-12 && abs(diagonal.loops[0].perimeterMeters-2*(1.9*sqrt(2)+2))<1e-12,"oblique plane independent rectangle")
        var cylinderRows:[[String:Double]]=[]
        for n in [32,128,512]{
            let c=cylinder(n),s=try B.slice(positions:c.p,triangleIndices:c.t,plane:plane)
            let perimeter=2*Double(n)*sin(Double.pi/Double(n)),area=Double(n)*sin(2*Double.pi/Double(n))/2
            try require(s.status == .complete && s.loops.count==1,"polygonal cylinder contour")
            try require(abs(s.loops[0].perimeterMeters-perimeter)<1e-11 && abs(s.loops[0].areaSquareMeters-area)<1e-11,"independent regular polygon measurement")
            cylinderRows.append(["segments":Double(n),"perimeter":s.loops[0].perimeterMeters,"analyticPolygonPerimeter":perimeter,"area":s.loops[0].areaSquareMeters,"analyticPolygonArea":area,"circlePerimeterError":2*Double.pi-perimeter,"circleAreaError":Double.pi-area])
        }
        let two=join(box(center:.init(x:-2,y:0,z:0)),box(center:.init(x:2,y:0,z:0)))
        let twins=try B.slice(positions:two.p,triangleIndices:two.t,plane:plane)
        try require(twins.status == .complete && twins.loops.count==2 && twins.loops.allSatisfy{abs($0.perimeterMeters-8)<1e-12 && abs($0.areaSquareMeters-4)<1e-12},"disconnected loops merged or selected")
        let feature=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:.init(origin:.init(x:0,y:1,z:0),normal:.init(x:0,y:1,z:0)))
        try require(feature.status == .indeterminate && feature.loops.isEmpty && feature.issue != nil,"coplanar/vertex plane silently offset")
        let empty=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:.init(origin:.init(x:0,y:2,z:0),normal:.init(x:0,y:1,z:0)))
        try require(empty.status == .complete && empty.loops.isEmpty,"empty section invalid")
        try reject("open mesh"){_=try B.slice(positions:cube.p,triangleIndices:Array(cube.t.dropLast(3)),plane:plane)}
        var flipped=cube.t;flipped.swapAt(1,2)
        try reject("flipped face"){_=try B.slice(positions:cube.p,triangleIndices:flipped,plane:plane)}
        try reject("duplicate face"){_=try B.slice(positions:cube.p,triangleIndices:cube.t+Array(cube.t.prefix(3)),plane:plane)}
        var invalid=cube.p;invalid[0].x = .nan
        try reject("nonfinite"){_=try B.slice(positions:invalid,triangleIndices:cube.t,plane:plane)}
        try reject("unused vertex"){_=try B.slice(positions:cube.p+[.zero],triangleIndices:cube.t,plane:plane)}
        try reject("index"){_=try B.slice(positions:cube.p,triangleIndices:cube.t+[0,1,999],plane:plane)}
        var limits=B.Limits();limits.maximumSegments=3
        try reject("segment budget"){_=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:plane,limits:limits)}
        try reject("cancel"){_=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:plane,isCancelled:{true})}
        var pairLimit=B.Limits();pairLimit.maximumContourPairTests=1
        try reject("contour pair budget"){_=try B.slice(positions:cube.p,triangleIndices:cube.t,plane:plane,limits:pairLimit)}
        var loopLimit=B.Limits();loopLimit.maximumLoops=1
        try reject("loop budget"){_=try B.slice(positions:two.p,triangleIndices:two.t,plane:plane,limits:loopLimit)}
        let overlap=join(box(),box(center:.init(x:1,y:0,z:0)))
        let ambiguous=try B.slice(positions:overlap.p,triangleIndices:overlap.t,plane:plane)
        try require(ambiguous.status == .indeterminate && ambiguous.loops.isEmpty,"crossing contours repaired or combined")
        let touch=join(box(),box(center:.init(x:-2,y:2,z:2)))
        var pinchedPoints=touch.p;pinchedPoints.remove(at:9)
        let pinchedIDs=touch.t.map{v -> UInt32 in let i=v==9 ? UInt32(7):v;return i>9 ? i-1:i}
        try reject("pinched vertex fan"){_=try B.slice(positions:pinchedPoints,triangleIndices:pinchedIDs,plane:plane)}
        let translated=box(center:.init(x:0.1,y:0,z:0))
        let moved=try B.slice(positions:translated.p,triangleIndices:translated.t,plane:plane)
        try require(moved.bodyGeometrySHA256 != square.bodyGeometrySHA256,"geometry hash did not bind exact source")
        let counts=Mutex(0),large=cylinder(512)
        do{_=try B.slice(positions:large.p,triangleIndices:large.t,plane:plane,isCancelled:{counts.withLock{$0 += 1;return $0>=20}});throw Failure.check("mid preparation not cancelled")}catch is CancellationError{}
        let first=Task.detached{try B.slice(positions:two.p,triangleIndices:two.t,plane:plane)}
        let second=Task.detached{try B.slice(positions:two.p,triangleIndices:two.t,plane:plane)}
        let pair=try await(first.value,second.value)
        try require(encode(pair.0)==encode(pair.1),"concurrent deterministic contours differ")
        struct Upper:Decodable{struct Item:Decodable{let id:String,body:[String:Double]};let cases:[Item]}
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let upper=try JSONDecoder().decode(Upper.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json")))
        var bodyRows:[[String:Any]]=[]
        for (name,values) in [("default",catalog.body),("female",upper.cases.first{$0.id=="female-Shirt-default"}!.body)]{
            let body=GarmentCodeBodyParameters(values:values),snapshot=try GarmentCodeStandardBody.load(body:body,resourceDirectory:root.appendingPathComponent("TrailorAss/Resources"))
            let heights:[(String,Double,String,Double?)]=[
                ("waist",0,"Visible mesh +Y origin is the configured waist level; no plane offset",body["waist"]!/100),
                ("hips",-body["hips_line"]!/100,"y = -hips_line / 100",body["hips"]!/100),
                ("bust-reference",(body["waist_line"]!-body["_bust_line"]!)/100,"y = (waist_line - derived _bust_line) / 100; GarmentCode vertical reference, not an independently certified anatomical landmark",body["bust"]!/100),
                ("upper-0.30m",0.30,"Explicit y = +0.30 m probe to retain torso/arm components",nil),
                ("legs",-body["hips_line"]!/100-0.25,"Explicit y = -hips_line / 100 - 0.25 m probe to retain both legs",nil)]
            var sections:[[String:Any]]=[]
            for (label,y,source,target) in heights{
                let s=try B.slice(positions:snapshot.positions,triangleIndices:snapshot.triangleIndices,plane:.init(origin:.init(x:0,y:y,z:0),normal:.init(x:0,y:1,z:0)))
                let object=try JSONSerialization.jsonObject(with:encode(s))
                sections.append(["label":label,"heightMeters":y,"heightSource":source,"configuredCircumferenceMeters":target as Any? ?? NSNull(),"section":object,"anatomicalLoopSelection":"none; every loop retained","bodyFittingApplied":false])
                print("BODY \(name) \(label): \(s.status.rawValue), \(s.loops.count) loops, perimeters=\(s.loops.map(\.perimeterMeters))")
                try require(s.status == .complete,"real requested plane is indeterminate; explicit issue retained, no silent offset")
            }
            let data:[String:Any]=["bodyName":name,"sourcePositions":try JSONSerialization.jsonObject(with:encode(snapshot.positions)),"sourceTriangleIndices":snapshot.triangleIndices,"inputBodyValues":body.values,"sections":sections,"dimensionsFitted":false]
            try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(name+"-sections.json"))
            bodyRows.append(["name":name,"sectionCount":sections.count,"dimensionsFitted":false])
        }
        let summary:[String:Any]=["passed":true,"scope":"Exact visible mesh plane intersections only; all loops retained, no anatomical selection or 26-measurement body fit","boxPerimeterMeters":8,"boxAreaSquareMeters":4,"disconnectedLoopCount":twins.loops.count,"cylinders":cylinderRows,"coplanarIndeterminate":true,"invalidAndCancellationCases":12,"bodyCases":bodyRows]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("swift-summary.json"))
    }
}
