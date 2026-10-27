import Foundation
import CryptoKit

@main @MainActor struct CompositionRiseRegression {
    typealias C=GarmentCodeCompositionPlacement
    typealias V=GarmentCodeCircleDrape.Vector3
    struct Edit:Decodable {let path:[String];let value:JSONValue}
    struct Initial:Decodable {let kind:C.Kind;let pattern:GarmentCodePatternFile}
    struct Item:Decodable {let id:String,bodyName:String;let overrides:[Edit];let expected:GarmentCodePatternFile;let initialComponents:[Initial]}
    struct Source:Decodable {let commit:String,generatorSHA256:String;let allImportedFilesMatchPinnedGitObjects:Bool}
    struct Fixture:Decodable {let format:String;let source:Source;let bodies:[String:[String:Double]];let cases:[Item]}
    enum Failure:Error {case check(String)}
    static func check(_ b:Bool,_ s:String)throws {if !b {throw Failure.check(s)}}
    static func encode<T:Encodable>(_ v:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(v)}
    static func seams(_ f:GarmentCodePatternFile)->[[String]] {
        f.pattern.stitches.map{$0.sides.map{"\($0.panel)#\($0.edge)"}.sorted()+($0.rightWrong ? ["right_wrong"]:[])}.sorted{$0.lexicographicallyPrecedes($1)}
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureData=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/composition-rise-oracles.json"))
        let fixture=try JSONDecoder().decode(Fixture.self,from:fixtureData)
        let script=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/GenerateCompositionRiseGoldens.py"))
        try check(fixture.format=="GarmentCodeCompositionRiseOracles/v1" && fixture.cases.count==48 &&
            fixture.source.commit=="d449629979028123a5c4dc9e732a2ec19b7fce31" &&
            fixture.source.allImportedFilesMatchPinnedGitObjects &&
            fixture.source.generatorSHA256==SHA256.hash(data:script).map{String(format:"%02x",$0)}.joined(),"Official fixture provenance differs")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        var rows:[[String:Any]]=[],errors:[String]=[],patterns:[String:Data]=[:],maximum=0.0,maxPlacement=0.0,panelCount=0
        for item in fixture.cases {
            do {
                let body=GarmentCodeBodyParameters(values:fixture.bodies[item.bodyName]!)
                var design=GarmentCodeDesignParameters(catalog:catalog)
                for edit in item.overrides {try check(design.setValue(edit.value,at:edit.path),"Unknown source parameter")}
                let inputs=design.jsonValue,actual=try GarmentCodeNativeGenerator.generate(body:body,design:design),expected=item.expected
                try check(actual.parameters?["design"]==inputs && actual.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),"Original inputs were not retained")
                try check(Set(actual.pattern.panels.keys)==Set(expected.pattern.panels.keys) && seams(actual)==seams(expected),"Official source panels or seam references differ")
                let a=try actual.geometryPanels(),b=try expected.geometryPanels()
                var geometryError=0.0
                for id in a.keys.sorted() {
                    let x=a[id]!,y=b[id]!
                    try check(x.label==y.label && x.edges.count==y.edges.count && (x.signedArea<0)==(y.signedArea<0),"Source topology or winding differs")
                    for (e,f) in zip(x.edges,y.edges) {
                        try check(e.label==f.label && e.curvature?.type==f.curvature?.type,"Source edge role differs")
                        for i in 0...100 {geometryError=max(geometryError,e.point(at:Double(i)/100).distance(to:f.point(at:Double(i)/100)))}
                        geometryError=max(geometryError,abs(e.length(tolerance:1e-10)-f.length(tolerance:1e-10)))
                    }
                }
                try check(geometryError<0.0001,"Official source geometry differs by \(geometryError)cm")
                let components=try item.initialComponents.map {c -> C.Component in
                    .init(kind:c.kind,transforms:try GarmentCodePanelPlacement.importedTransforms(document:c.pattern,waistLevelCentimeters:body["_waist_level"]!))
                }
                let placed=try C.prepare(document:actual,body:body,design:design,components:components)
                let expectedTransforms=try GarmentCodePanelPlacement.importedTransforms(document:expected,waistLevelCentimeters:body["_waist_level"]!)
                var placementError=0.0
                for id in expectedTransforms.keys {
                    guard let t=placed.transforms[id] else {throw Failure.check("Missing source component")}
                    for p in [V.zero,.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1)] {
                        placementError=max(placementError,try (t.point(p)-expectedTransforms[id]!.point(p)).length)
                    }
                }
                try check(placementError<5e-8,"Official complete composition differs by \(placementError)m")
                maximum=max(maximum,geometryError);maxPlacement=max(maxPlacement,placementError);panelCount += a.count
                patterns[item.id]=try encode(actual.pattern)
                rows.append(["case":item.id,"passed":true,"panels":a.count,"maximumGeometryErrorCentimeters":geometryError,
                    "maximumPlacementErrorMeters":placementError,"sourceSHA256":placed.sourceSHA256,"originalDesignRetained":true])
                print("PASS \(item.id) geometry \(geometryError)cm composition \(placementError)m")
            } catch {
                let message=item.id+": "+String(describing:error);errors.append(message)
                FileHandle.standardError.write(Data(("FAIL "+message+"\n").utf8))
            }
        }
        if errors.isEmpty {
            for body in ["default","female"] {for lower in ["SkirtCircle","AsymmSkirtCircle","SkirtManyPanels"] {
                for wb in ["None","StraightWB","FittedWB"] {
                    let prefix="\(body)-FittedShirt-\(lower)-\(wb)-rise"
                    try check(patterns[prefix+"0.5"]==patterns[prefix+"0.75"],"Fitted upper did not force natural lower rise")
                }
                let prefix="\(body)-Shirt-\(lower)-None-rise"
                try check(patterns[prefix+"0.5"] != patterns[prefix+"0.75"],"Loose upper incorrectly disabled the lower rise parameter")
            }}
        }
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_COMPOSITION_RISE_OUTPUT"] ?? "/private/tmp/TailorAssCompositionRise")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let summary:[String:Any]=["passed":errors.isEmpty && rows.count==48,"caseCount":rows.count,"panelCount":panelCount,
            "maximumGeometryErrorCentimeters":maximum,"maximumPlacementErrorMeters":maxPlacement,"rows":rows,"failures":errors,
            "scope":"Official complete paper geometry, original design provenance and MetaGarment initial composition. Not sewing or physical drape acceptance."]
        try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys,.prettyPrinted]).write(to:out.appendingPathComponent("composition-rise-summary.json"))
        try check(errors.isEmpty && rows.count==48,"Fitted lower rise or complete composition matrix failed")
        print("PASS48 official fitted-lower-rise/control cases")
    }
}
