import Foundation
import CryptoKit

/// The official raw-curve oracle isolates redistribution from the existing
/// simplex-vs-L-BFGS sleeve fitting difference. Complete garments are also
/// generated and validated; their official shape difference is reported.
@main @MainActor struct InverseSleeveRegression {
    typealias P=GarmentCodePoint
    typealias E=GarmentCodeGeometryEdge
    struct Edit:Decodable{let path:[String];let value:JSONValue}
    struct Redistribution:Decodable{
        let front:[[[Double]]],back:[[[Double]]]
        let resultFront:[[[Double]]],resultBack:[[[Double]]]
        let intersections:[[Double]]
    }
    struct Case:Decodable{
        let id:String,body:[String:Double],overrides:[Edit]
        let expected:GarmentCodePatternFile
        let redistributions:[Redistribution]
        let nativeReplay:Replay?
    }
    struct Matrix:Decodable{let translation:[Double],rotation:[Double]}
    struct Replay:Decodable{let sourceSHA256:String,transforms:[String:Matrix]}
    struct Source:Decodable{let commit:String,generatorSHA256:String;let nativeReplayGeneratorSHA256:String?}
    struct Fixture:Decodable{let format:String,source:Source,cases:[Case]}
    enum Failure:Error{case check(String)}
    static func require(_ condition:Bool,_ message:String)throws{if !condition{throw Failure.check(message)}}
    static func point(_ a:[Double])->P{.init(x:a[0],y:a[1])}
    static func edge(_ p:[[Double]],_ id:String)->E {
        let cp=p.map(point)
        return .init(id:id,start:cp.first!,end:cp.last!,curvature:E.curvature(for:cp))
    }
    static func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func encoded<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)}
    static func compare(_ a:[E],_ b:[[[Double]]])throws->Double{
        try require(a.count==b.count,"redistribution changed source edge count")
        var error=0.0
        for (i,pair) in zip(a,b).enumerated(){let expected=edge(pair.1,"oracle-\(i)")
            for k in 0...100{error=max(error,pair.0.point(at:Double(k)/100).distance(to:expected.point(at:Double(k)/100)))}
            error=max(error,abs(pair.0.length(tolerance:1e-10)-expected.length(tolerance:1e-10)))
        };return error
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("Tests/NativePattern/Fixtures/inverse-sleeve-oracles.json")
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:file))
        try require(fixture.format=="GarmentCodeInverseSleeveOracles/v1" && fixture.source.commit=="d449629979028123a5c4dc9e732a2ec19b7fce31","wrong independent oracle")
        try require(try hash(Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/GenerateInverseSleeveGoldens.py")))==fixture.source.generatorSHA256,"oracle generator SHA differs")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let export=ProcessInfo.processInfo.environment["GARMENTCODE_INVERSE_EXPORT_NATIVE"].map{URL(fileURLWithPath:$0)}
        if let export{try FileManager.default.createDirectory(at:export.appendingPathComponent("native"),withIntermediateDirectories:true)}
        else{try require(fixture.source.nativeReplayGeneratorSHA256 == hash(Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/ReplayUpperPlacement.py"))),"independent replay provenance changed")}
        var rows:[[String:Any]]=[],maxError=0.0,maxFrameError=0.0,framePanels=0,empty=0,intersected=0,exports:[[String:Any]]=[]
        for item in fixture.cases {
            var rowError=0.0
            for r in item.redistributions {
                let front=r.front.enumerated().map{edge($0.element,"front-\($0.offset)")},back=r.back.enumerated().map{edge($0.element,"back-\($0.offset)")}
                let original=front.map{$0.length()}.reduce(0,+)+back.map{$0.length()}.reduce(0,+)
                let actual=try GarmentCodeSleeveGeometry.evenOpenings(front:front,back:back)
                let error=max(try compare(actual.front,r.resultFront),try compare(actual.back,r.resultBack))
                try require(error<1e-7,"\(item.id): original official redistribution delta \(error) cm")
                let after=actual.front.map{$0.length()}.reduce(0,+)+actual.back.map{$0.length()}.reduce(0,+)
                try require(abs(after-original)<1e-7,"redistribution changed total original source arc length")
                if r.intersections.isEmpty {empty += 1;try require(actual.front.count==front.count && actual.back.count==back.count,"no-hit branch added or removed an edge")}
                else{intersected += 1}
                rowError=max(rowError,error);maxError=max(maxError,error)
            }
            var design=GarmentCodeDesignParameters(catalog:catalog)
            for edit in item.overrides{try require(design.setValue(edit.value,at:edit.path),"unknown explicit input")}
            let body=GarmentCodeBodyParameters(values:item.body)
            let native=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            try native.validateForPreview()
            try require(native.parameters?["design"]==design.jsonValue && native.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),"original input provenance changed")
            try require(Set(native.pattern.panels.keys)==Set(item.expected.pattern.panels.keys),"complete upper source omitted a panel")
            let geometry=try native.geometryPanels(),official=try item.expected.geometryPanels()
            var sourceDifference=0.0,sourceEdgeCount=0
            for id in geometry.keys {
                let a=geometry[id]!,b=official[id]!;sourceEdgeCount += a.edges.count
                if a.edges.count==b.edges.count {
                    for pair in zip(a.edges,b.edges){for k in 0...100{sourceDifference=max(sourceDifference,pair.0.point(at:Double(k)/100).distance(to:pair.1.point(at:Double(k)/100)))}}
                }
                try require(a.isClosed && a.edges.allSatisfy{$0.length().isFinite && $0.length()>0},"generated native source is not a valid finite closed loop")
            }
            let bytes=try encoded(native),sourceHash=hash(bytes)
            var frameError=0.0
            if let export {
                let name=item.id+"-source.json";try bytes.write(to:export.appendingPathComponent("native/"+name))
                exports.append(["id":item.id,"sourceSHA256":sourceHash,"file":name])
            } else {
                guard let replay=item.nativeReplay else{throw Failure.check("missing independent same-native-source frame")}
                try require(replay.sourceSHA256==sourceHash,"native source changed since independent replay")
                let mapping=try GarmentCodeUpperPlacement.sourceMap(document:native,body:body,design:design)
                try require(mapping.sourceSHA256==sourceHash && Set(mapping.panels.keys)==Set(replay.transforms.keys),"complete native frame omitted source")
                for id in mapping.panels.keys {
                    let panel=mapping.panels[id]!,m=replay.transforms[id]!
                    let expected=try GarmentCodePanelPlacement.Transform(rotationDegrees:m.rotation,translation:m.translation,unitsInMeter:100,waistLevelCentimeters:body["_waist_level"]!)
                    frameError=max(frameError,(expected.translationMeters-panel.transform.translationMeters).length)
                    for v in [GarmentCodeCircleDrape.Vector3(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1)] {
                        try require((expected.direction(v)-panel.transform.direction(v)).length<1e-9,"basis frame differs")
                    }
                    let sourceVertices=native.pattern.panels[id]!.vertices
                    try require(sourceVertices.count==panel.sourceVertexPositions.count,"frame lost source vertices")
                    for (p,v) in zip(sourceVertices,panel.sourceVertexPositions){try require((expected.point(.init(x:p[0]/100,y:p[1]/100,z:0))-v).length<1e-6,"source vertex frame differs")}
                    let normal=try expected.direction(.init(x:0,y:0,z:geometry[id]!.signedArea<0 ? -1:1))
                    try require((normal-panel.fabricNormal).length<1e-9,"original fabric normal differs")
                    framePanels += 1
                }
                try require(frameError<1e-6 && encoded(native)==bytes,"native frame changed source or differs from oracle")
                maxFrameError=max(maxFrameError,frameError)
            }
            rows.append(["case":item.id,"officialRedistributionErrorCentimeters":rowError,"generatedCompletePanelCount":native.pattern.panels.count,"generatedSourceEdgeCount":sourceEdgeCount,"sourceSHA256":sourceHash,"nativeReplayFrameErrorMeters":frameError,"existingNativeVsOfficialMatchedEdgeSampleDifferenceCentimeters":sourceDifference])
            print("PASS",item.id,"official redistribution",rowError,"cm; full source",native.pattern.panels.count,"panels; existing native shape difference",sourceDifference,"cm")
        }
        try require(fixture.cases.count==12 && empty>0 && intersected>0,"missing two-body or no-hit/hit branch coverage")
        if let export {
            let record:[String:Any]=["exports":exports,"failures":[]]
            try JSONSerialization.data(withJSONObject:record,options:[.sortedKeys,.prettyPrinted]).write(to:export.appendingPathComponent("exports.json"))
            var hashes:[String:String]=[:]
            for name in ["PatternDesignModels.swift","GarmentCodeGeometry.swift","GarmentCodePrograms.swift","GarmentCodeNativeGenerator.swift"]{hashes[name]=try hash(Data(contentsOf:root.appendingPathComponent("TrailorAss/Models/"+name)))}
            try JSONSerialization.data(withJSONObject:["scope":"Source export only; UpperPlacement not called","nativeModelSHA256":hashes],options:[.sortedKeys,.prettyPrinted]).write(to:export.appendingPathComponent("source-manifest.json"))
            print("EXPORTED",exports.count,"complete native source inputs; no placement invoked");return
        }
        try require(framePanels==96,"not all twelve complete source frames were mapped")
        let report:[String:Any]=["passed":true,"caseCount":fixture.cases.count,"noIntersectionChecks":empty,"intersectionChecks":intersected,"maximumOfficialRedistributionErrorCentimeters":maxError,"sameNativeSourceFramePanelCount":framePanels,"maximumNativeReplayFrameErrorMeters":maxFrameError,"rows":rows,"scope":"Exact original official redistribution, including no intersection, and independent unmodified-upstream frames on identical native paper. Complete native sources validated without changing optimizer, parameters, provenance or panel validity; preexisting native-vs-official fitting differences remain separately visible. This does not assert sewn garment acceptance."]
        let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_INVERSE_OUTPUT"] ?? "/private/tmp/TailorAssInverseSleeve")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("inverse-proof.json"))
        print("PASS all official inverse no-hit/hit branches",empty,intersected)
    }
}
