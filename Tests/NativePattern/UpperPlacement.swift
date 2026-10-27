import Foundation
import CryptoKit

/// Strict placement checks use unmodified upstream rigid operations on the
/// identical native source. Original official source differences stay visible.
@main @MainActor struct UpperPlacementRegression {
    typealias U=GarmentCodeUpperPlacement
    typealias V=GarmentCodeCircleDrape.Vector3
    struct Edit:Decodable{let path:[String];let value:JSONValue}
    struct Matrix:Decodable{let translation:[Double];let rotation:[Double]}
    struct Replay:Decodable{let sourceSHA256:String;let transforms:[String:Matrix];let method:String}
    struct Case:Decodable{let id:String;let body:[String:Double];let overrides:[Edit];let expected:GarmentCodePatternFile;let nativeReplay:Replay?}
    struct Source:Decodable{let commit:String;let generatorSHA256:String;let nativeReplayGeneratorSHA256:String;let sourceFileSHA256:[String:String]}
    struct KnownFailure:Decodable{let id:String;let error:String}
    struct Fixture:Decodable{let format:String;let source:Source;let cases:[Case];let nativeReplayFailures:[KnownFailure]}
    struct ExportCase:Decodable{let id:String;let body:[String:Double];let overrides:[Edit]}
    struct ExportFixture:Decodable{let cases:[ExportCase]}
    enum Failure:Error{case check(String)}
    static func require(_ condition:Bool,_ message:String)throws{if !condition{throw Failure.check(message)}}
    static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)}
    static func digest(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// Regeneration-only export calls the existing 2D generator, never the
    /// placement implementation. ReplayUpperPlacement.py consumes these bytes.
    static func exportNativeSources(_ bytes:Data,to out:URL)throws {
        let cases=try JSONDecoder().decode(ExportFixture.self,from:bytes).cases
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),native=out.appendingPathComponent("native")
        try FileManager.default.createDirectory(at:native,withIntermediateDirectories:true)
        var exports:[[String:Any]]=[],failures:[[String:Any]]=[]
        for item in cases {
            let body=GarmentCodeBodyParameters(values:item.body);var design=GarmentCodeDesignParameters(catalog:catalog)
            for edit in item.overrides{try require(design.setValue(edit.value,at:edit.path),"unknown native export input")}
            do {
                let data=try encode(GarmentCodeNativeGenerator.generate(body:body,design:design)),file=item.id+"-source.json"
                try data.write(to:native.appendingPathComponent(file));exports.append(["id":item.id,"sourceSHA256":digest(data),"file":file])
            }catch{failures.append(["id":item.id,"error":String(describing:error)])}
        }
        var hashes:[String:String]=[:]
        for name in ["PatternDesignModels.swift","GarmentCodeGeometry.swift","GarmentCodePrograms.swift","GarmentCodeNativeGenerator.swift"] {
            hashes[name]=try digest(Data(contentsOf:root.appendingPathComponent("TrailorAss/Models/"+name)))
        }
        let manifest:[String:Any]=["scope":"2D source only. UpperPlacement was not called.","nativeModelSHA256":hashes,"fixtureSHA256":digest(bytes)]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("source-manifest.json"))
        try JSONSerialization.data(withJSONObject:["exports":exports,"failures":failures],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("exports.json"))
        print("EXPORTED native sources",exports.count,"existing 2D failures",failures.count)
    }
    static func main()throws {
        let fixtureBytes=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json"))
        if let directory=ProcessInfo.processInfo.environment["GARMENTCODE_UPPER_EXPORT_NATIVE"] {
            try exportNativeSources(fixtureBytes,to:URL(fileURLWithPath:directory));return
        }
        let fixture=try JSONDecoder().decode(Fixture.self,from:fixtureBytes)
        try require(fixture.format=="GarmentCodeNativeUpperPlacementOracles/v1" && fixture.source.commit==U.upstreamCommit,"fixed official provenance differs")
        for (name,hash) in [("GenerateUpperPlacementGoldens.py",fixture.source.generatorSHA256),("ReplayUpperPlacement.py",fixture.source.nativeReplayGeneratorSHA256)] {
            try require(digest(Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/"+name)))==hash,"oracle script changed without refreshing provenance")
        }
        try require(fixture.cases.count==108 && fixture.source.sourceFileSHA256["assets/garment_programs/bodice.py"] != nil,"official matrix incomplete")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_UPPER_OUTPUT"] ?? "/private/tmp/TailorAssUpperPlacement")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        var rows:[[String:Any]]=[],blocked:[[String:Any]]=[],strictFailures:[String]=[],meshRows:[[String:Any]]=[]
        var maximum=0.0,originalMaximum=0.0,checked=0
        let meshTags=Set(["all-Shirt-default","all-FittedShirt-default","all-Shirt-sleeved","all-FittedShirt-sleeved","all-Shirt-sleeved-Turtle","all-FittedShirt-sleeved-Turtle","all-Shirt-sleeved-SimpleLapel","all-FittedShirt-sleeved-SimpleLapel","all-Shirt-sleeved-Hood2Panels","all-FittedShirt-sleeved-Hood2Panels"])
        for item in fixture.cases {
            FileHandle.standardError.write(Data(("START "+item.id+"\n").utf8))
            let body=GarmentCodeBodyParameters(values:item.body)
            var design=GarmentCodeDesignParameters(catalog:catalog)
            for edit in item.overrides{try require(design.setValue(edit.value,at:edit.path),"unknown oracle parameter")}
            let document:GarmentCodePatternFile
            do{document=try GarmentCodeNativeGenerator.generate(body:body,design:design)}catch{
                guard let known=fixture.nativeReplayFailures.first(where:{$0.id==item.id}),String(describing:error)==known.error else{throw error}
                blocked.append(["case":item.id,"error":String(describing:error),"stage":"existing native 2D source generation; no paper exists to place"])
                try encode(design.jsonValue).write(to:out.appendingPathComponent(item.id+"-blocked-design.json"));try encode(body).write(to:out.appendingPathComponent(item.id+"-blocked-body.json"));try encode(item.expected).write(to:out.appendingPathComponent(item.id+"-official-source.json"))
                print("BLOCKED EXISTING 2D",item.id,String(describing:error));continue
            }
            guard let replay=item.nativeReplay else{throw Failure.check("New native source requires refreshing the independent replay: \(item.id)")}
            let before=try encode(document),hash=digest(before)
            try require(hash==replay.sourceSHA256,"\(item.id): native paper changed since upstream replay; regenerate this explicit source oracle")
            let mapping=try U.sourceMap(document:document,body:body,design:design),geometry=try document.geometryPanels()
            try require(mapping.sourceSHA256==hash && Set(mapping.panels.keys)==Set(document.pattern.panels.keys) && Set(mapping.panels.keys)==Set(replay.transforms.keys),"complete canonical source map differs")
            let original=try GarmentCodePanelPlacement.importedTransforms(document:item.expected,waistLevelCentimeters:body["_waist_level"]!)
            var caseError=0.0,caseOriginal=0.0
            for id in mapping.panels.keys.sorted() {
                let panel=mapping.panels[id]!,m=replay.transforms[id]!
                let expected=try GarmentCodePanelPlacement.Transform(rotationDegrees:m.rotation,translation:m.translation,unitsInMeter:100,waistLevelCentimeters:body["_waist_level"]!)
                let error=(panel.transform.translationMeters-expected.translationMeters).length
                let basis=try [V(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1)].map{(try panel.transform.direction($0)-expected.direction($0)).length}.max()!
                let originalError=(panel.transform.translationMeters-original[id]!.translationMeters).length
                if error>=1e-6 || basis>=1e-9{strictFailures.append("\(item.id)/\(id) native replay translation \(error)m rotation \(basis)")}
                let native=document.pattern.panels[id]!
                try require(panel.sourceVertexPositions.count==native.vertices.count,"source vertices omitted")
                for (vertex,position) in zip(native.vertices,panel.sourceVertexPositions) {
                    let expectedPosition=try expected.point(.init(x:vertex[0]/100,y:vertex[1]/100,z:0))
                    try require((expectedPosition-position).length<1e-6,"native paper vertex map differs from independent rigid replay")
                }
                let normal=try expected.direction(.init(x:0,y:0,z:geometry[id]!.signedArea<0 ? -1:1))
                try require((normal-panel.fabricNormal).length<1e-9,"original native fabric normal changed")
                caseError=max(caseError,error);caseOriginal=max(caseOriginal,originalError);maximum=max(maximum,error);originalMaximum=max(originalMaximum,originalError);checked += 1
                rows.append(["case":item.id,"panel":id,"sourceSHA256":hash,"nativeReplayTranslationErrorMeters":error,"nativeReplayBasisError":basis,"originalOfficialSourceTranslationDifferenceMeters":originalError,"sourceVertexCount":native.vertices.count,"translationMeters":[panel.transform.translationMeters.x,panel.transform.translationMeters.y,panel.transform.translationMeters.z],"rotationDegrees":panel.transform.rotationDegrees])
            }
            try require(try encode(document)==before,"mapping changed complete source")
            if meshTags.contains(item.id) {
                let mesh=try U.prepare(document:document,body:body,design:design,targetEdgeMeters:0.04)
                try require(Set(mesh.panels.keys)==Set(mapping.panels.keys),"meshing silently omitted a component")
                for id in mesh.panels.keys {
                    let panel=mesh.panels[id]!
                    try require((panel.transform.translationMeters-mapping.panels[id]!.transform.translationMeters).length<1e-12,"mesh path changed the source recipe")
                    let expectedPoints=try panel.mesh.flatPositions.map{try panel.transform.point($0)}
                    try require(expectedPoints==panel.placed.positions,"source mesh vertices changed or were omitted")
                }
                meshRows.append(["case":item.id,"completePanelCount":mesh.panels.count,"sourceMeshVertexCount":mesh.panels.values.reduce(0){$0+$1.mesh.flatPositions.count}])
            }
            if caseOriginal>1e-6{try before.write(to:out.appendingPathComponent(item.id+"-native-source.json"));try encode(design.jsonValue).write(to:out.appendingPathComponent(item.id+"-design.json"))}
            print("CHECK",item.id,"replay delta m",caseError,"original source delta m",caseOriginal)
        }
        let body=GarmentCodeBodyParameters(values:catalog.body)
        var design=GarmentCodeDesignParameters(catalog:catalog)
        _=design.setValue(.string("Shirt"),at:["meta","upper"]);_=design.setValue(.null,at:["meta","bottom"]);_=design.setValue(.null,at:["meta","wb"])
        let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        func rejected(_ name:String,_ work:()throws->Void)throws{do{try work()}catch{print("PASS reject",name);return};throw Failure.check("accepted invalid \(name)")}
        try rejected("cancellation"){_=try U.sourceMap(document:document,body:body,design:design,isCancelled:{true})}
        var wrongBody=body;wrongBody.set(body["waist"]!+1,for:"waist")
        try rejected("different body provenance"){_=try U.sourceMap(document:document,body:wrongBody,design:design)}
        var wrongDesign=design;_=wrongDesign.setValue(.number(1.2),at:["shirt","width"])
        try rejected("different design provenance"){_=try U.sourceMap(document:document,body:body,design:wrongDesign)}
        for kind in ["wb","bottom"] {
            var combined=design;_=combined.setValue(.string(kind=="wb" ? "StraightWB":"Skirt2"),at:["meta",kind])
            let full=try GarmentCodeNativeGenerator.generate(body:body,design:combined)
            try rejected("no silent \(kind) omission"){_=try U.sourceMap(document:full,body:body,design:combined)}
        }
        let report:[String:Any]=["formulaChecksPassed":strictFailures.isEmpty,"fullNativeInputCoverageComplete":blocked.isEmpty,"officialCaseCount":fixture.cases.count,"mappedNativeCases":fixture.cases.count-blocked.count,"checkedSourcePanels":checked,"maximumNativeReplayTranslationErrorMeters":maximum,"maximumOriginalOfficialSourceTranslationDifferenceMeters":originalMaximum,"knownNative2DSourceFailures":blocked,"strictFormulaFailures":strictFailures,"sourceMeshes":meshRows,"rows":rows,"scope":"Strict unmodified-upstream rigid placement operations on identical native source; original official source differences separately reported. Source vertices are not a sewn or triangulated simulation mesh. Ten complete source meshes are independently exercised. No physical gates or original 2D sources changed."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("placement-proof.json"))
        for failure in strictFailures{print("FAIL",failure)}
        try require(strictFailures.isEmpty,"source placement differs from independent upstream replay")
        print("PASS source placement formulas",checked,"panels; known existing native 2D failures",blocked.count,"catalogue complete",blocked.isEmpty)
    }
}
