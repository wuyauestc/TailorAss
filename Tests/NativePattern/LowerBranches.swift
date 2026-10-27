import Foundation
import CryptoKit

@main @MainActor struct LowerBranchesRegression {
    struct Override:Decodable{let path:[String];let value:JSONValue}
    struct Case:Decodable{let id:String;let overrides:[Override];let expected:GarmentCodePatternFile}
    struct Source:Decodable{let commit:String;let sourceFileSHA256:[String:String];let generatorSHA256:String}
    struct Fixture:Decodable{let format:String;let source:Source;let body:[String:Double];let cases:[Case]}
    enum Failure:Error{case check(String)}
    static func require(_ condition:Bool,_ message:String)throws{if !condition{throw Failure.check(message)}}
    static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)}
    static func seams(_ document:GarmentCodePatternFile)->[[String]] {
        document.pattern.stitches.map{$0.sides.map{"\($0.panel)#\($0.edge)"}.sorted()+($0.rightWrong ? ["right_wrong"]:[])}.sorted{$0.lexicographicallyPrecedes($1)}
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input=root.appendingPathComponent("Tests/NativePattern/Fixtures/lower-branch-oracles.json"),bytes=try Data(contentsOf:input)
        let fixture=try JSONDecoder().decode(Fixture.self,from:bytes)
        try require(fixture.format=="GarmentCodeNativeLowerBranchOracles/v1" && fixture.source.commit==GarmentCodeLowerPlacement.upstreamCommit,"oracle provenance differs")
        let generatorBytes=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/GenerateLowerBranchGoldens.py"))
        try require(fixture.source.generatorSHA256==SHA256.hash(data:generatorBytes).map{String(format:"%02x",$0)}.joined(),"oracle regeneration script changed without refreshing its fixture provenance")
        try require(fixture.cases.count==25 && fixture.source.sourceFileSHA256["assets/garment_programs/meta_garment.py"] != nil,"official case matrix incomplete")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:fixture.body)
        var rows:[[String:Any]]=[],patternBytes:[String:Data]=[:],maximum=0.0,maxPlacement=0.0
        for item in fixture.cases {
            var design=GarmentCodeDesignParameters(catalog:catalog)
            for key in ["upper","bottom","wb"]{_=design.setValue(.null,at:["meta",key])}
            for edit in item.overrides{try require(design.setValue(edit.value,at:edit.path),"unknown oracle input parameter")}
            let before=design.jsonValue,actual=try GarmentCodeNativeGenerator.generate(body:body,design:design),expected=item.expected
            try require(actual.parameters?["design"]==before && actual.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),"caller inputs lost from provenance")
            try require(Set(actual.pattern.panels.keys)==Set(expected.pattern.panels.keys) && seams(actual)==seams(expected),"\(item.id): full panel set or actual source seam references differ")
            let a=try actual.geometryPanels(),b=try expected.geometryPanels()
            var error=0.0,count=0
            for id in a.keys.sorted() {
                let x=a[id]!,y=b[id]!
                try require(x.label==y.label && x.edges.count==y.edges.count && (x.signedArea<0)==(y.signedArea<0),"\(item.id)/\(id): source metadata, topology or winding differs")
                for (left,right) in zip(x.edges,y.edges) {
                    try require(left.label==right.label && left.curvature?.type==right.curvature?.type,"\(item.id)/\(id): source edge role differs")
                    for i in 0...100{error=max(error,left.point(at:Double(i)/100).distance(to:right.point(at:Double(i)/100)))}
                    error=max(error,abs(left.length(tolerance:1e-10)-right.length(tolerance:1e-10)));count += 1
                }
            }
            try require(error<0.0001,"\(item.id): official geometry delta \(error)cm")
            let placed=try GarmentCodeLowerPlacement.prepare(document:actual,body:body,design:design,targetEdgeMeters:0.08)
            let expectedTransforms=try GarmentCodePanelPlacement.importedTransforms(document:expected,waistLevelCentimeters:body["_waist_level"]!)
            var placementError=0.0
            for id in placed.panels.keys {
                let transform=placed.panels[id]!.transform,oracle=expectedTransforms[id]!
                placementError=max(placementError,(transform.translationMeters-oracle.translationMeters).length)
                for v in [GarmentCodeCircleDrape.Vector3(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1)] {
                    try require((try transform.direction(v)-oracle.direction(v)).length<1e-9,"official placement rotation differs")
                }
            }
            try require(placementError<1e-6,"\(item.id): full native placement delta \(placementError)m")
            maximum=max(maximum,error);maxPlacement=max(maxPlacement,placementError)
            patternBytes[item.id]=try encode(actual.pattern)
            rows.append(["case":item.id,"sourcePanelCount":actual.pattern.panels.count,"sourceEdgeCount":count,"maximumGeometryErrorCm":error,"maximumPlacementTranslationErrorMeters":placementError,"sourceSHA256":placed.sourceSHA256,"completeOriginalInputsRetained":true])
            print("PASS",item.id,"geometry delta cm",error,"placement delta m",placementError)
        }
        for wb in ["StraightWB","FittedWB"] {for rise in ["0.5","0.75","1.0"] {
            try require(patternBytes["pants-\(wb)-rise\(rise)-skirt0.5"]==patternBytes["pants-\(wb)-rise\(rise)-skirt1.0"],"unrelated skirt.rise changed pants or waistband paper")
        }}
        let baseline=patternBytes["godet-no-slits"]!
        for row in fixture.cases where row.id.hasPrefix("godet-") && !row.id.contains("WB") {
            try require(patternBytes[row.id]==baseline,"Godet must suppress real source slits without erasing input provenance")
        }
        try require(patternBytes["pencil-front_slit"] != patternBytes["pencil-back_slit"] && patternBytes["pencil-left_slit"] != patternBytes["pencil-right_slit"],"ordinary Pencil slit branches were disabled")
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_LOWER_BRANCH_OUTPUT"] ?? "/private/tmp/TailorAssLowerBranches")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let result:[String:Any]=["passed":true,"upstreamCommit":fixture.source.commit,"fixtureSHA256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),"caseCount":rows.count,"maximumGeometryErrorCm":maximum,"maximumPlacementTranslationErrorMeters":maxPlacement,"scope":"Original 2D source geometry/topology, exact input provenance and complete native initial placement; no physical gate changes or drape completion claim.","rows":rows]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("lower-branch-proof.json"))
        print("PASS LowerBranches",rows.count,"official cases; max geometry cm",maximum,"max placement m",maxPlacement)
    }
}
