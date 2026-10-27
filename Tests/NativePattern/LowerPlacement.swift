import Foundation
import CryptoKit

@main @MainActor struct LowerPlacementRegression {
    typealias L=GarmentCodeLowerPlacement
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error{case check(String)}
    static func require(_ value:Bool,_ message:String)throws{if !value{throw Failure.check(message)}}
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func recordKnown2DBranches(catalog:GarmentCodeParameterCatalog,body:GarmentCodeBodyParameters,out:URL)throws {
        let directory=out.appendingPathComponent("known-2d-branches");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted,.withoutEscapingSlashes]
        func design(_ bottom:String,_ wb:JSONValue = .null)->GarmentCodeDesignParameters {
            var d=GarmentCodeDesignParameters(catalog:catalog);_=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.string(bottom),at:["meta","bottom"]);_=d.setValue(wb,at:["meta","wb"]);return d
        }
        var godet=design("GodetSkirt");_=godet.setValue(.string("PencilSkirt"),at:["godet-skirt","base"]);_=godet.setValue(.number(0.2),at:["pencil-skirt","front_slit"])
        var suppressed=godet;_=suppressed.setValue(.number(0),at:["pencil-skirt","front_slit"])
        let actualGodet=try GarmentCodeNativeGenerator.generate(body:body,design:godet),expectedGodet=try GarmentCodeNativeGenerator.generate(body:body,design:suppressed)
        try encoder.encode(godet.jsonValue).write(to:directory.appendingPathComponent("godet-front-slit-design.json"))
        try encoder.encode(body).write(to:directory.appendingPathComponent("default-body.json"))
        try encoder.encode(actualGodet).write(to:directory.appendingPathComponent("godet-front-slit-native-source.json"))
        try encoder.encode(expectedGodet).write(to:directory.appendingPathComponent("godet-upstream-slit-false-expected-source.json"))
        let godetResolved=try encoder.encode(actualGodet.pattern)==encoder.encode(expectedGodet.pattern)
        var pants=design("Pants",.string("FittedWB"));_=pants.setValue(.number(0.75),at:["pants","rise"]);_=pants.setValue(.number(1),at:["skirt","rise"])
        let actualPants=try GarmentCodeNativeGenerator.generate(body:body,design:pants)
        let expectedBand=try GarmentCodePrograms.waistband(body:body,design:pants,rise:0.75)
        try encoder.encode(pants.jsonValue).write(to:directory.appendingPathComponent("pants-low-rise-fitted-wb-design.json"))
        try encoder.encode(actualPants).write(to:directory.appendingPathComponent("pants-low-rise-fitted-wb-native-source.json"))
        try encoder.encode(expectedBand).write(to:directory.appendingPathComponent("pants-rise-point75-expected-wb-source.json"))
        func topLength(_ document:GarmentCodePatternFile)throws->Double {
            try document.geometryPanels().filter{$0.key.hasPrefix("wb_")}.values.reduce(0){sum,panel in sum+panel.edges.filter{$0.label=="lower_interface"}.reduce(0){$0+$1.length(tolerance:1e-10)}}
        }
        let actualTop=try topLength(actualPants),expectedTop=try topLength(expectedBand)
        let report:[String:Any]=[
            "upstreamCommit":L.upstreamCommit,
            "godetPencilSlit":["minimalOverrides":["meta.upper":NSNull(),"meta.bottom":"GodetSkirt","meta.wb":NSNull(),"godet-skirt.base":"PencilSkirt","pencil-skirt.front_slit":0.2],"upstreamBranch":"godet.py GodetSkirt calls base_skirt(...slit=False); PencilSkirt passes front_slit=0 when slit is false. Changing front_slit must not change the Godet source geometry.","nativeBranch":"GarmentCodePrograms.godetSkirt passes baseDesign directly to pencilSkirt without suppressing the four slit values.","resolved":godetResolved,"nativeFrontEdges":actualGodet.pattern.panels["skirt_front"]!.edges.count,"expectedFrontEdges":expectedGodet.pattern.panels["skirt_front"]!.edges.count],
            "pantsWaistbandRise":["minimalOverrides":["meta.upper":NSNull(),"meta.bottom":"Pants","meta.wb":"FittedWB","pants.rise":0.75,"skirt.rise":1.0],"upstreamBranch":"MetaGarment constructs Belt with Lower.get_rise(); Pants.get_rise delegates to its right PantsHalf, whose rise is pants.rise.","nativeBranch":"GarmentCodeNativeGenerator lower-only risePath switch omits Pants and falls back to skirt.rise.","nativeWbTopLengthCm":actualTop,"expectedWbTopLengthCm":expectedTop,"resolved":abs(actualTop-expectedTop)<1e-7]
        ]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("minimal-reproductions.json"))
        print("KNOWN 2D branch status: Godet slit resolved",godetResolved,"Pants WB top delta cm",actualTop-expectedTop)
    }
    static func main()throws {
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        var cases:[(String,String,[([String],JSONValue)])]=[
            ("Pants","pants",[]),("Pants","pants-varied",[( ["pants","rise"],.number(0.75)),(["pants","length"],.number(0.55)),(["pants","width"],.number(1.2)),(["pants","flare"],.number(1.1))]),
            ("Skirt2","skirt-two-panel",[]),("Skirt2","skirt-two-panel-cut",[(["skirt","bottom_cut"],.number(0.5))]),
            ("PencilSkirt","pencil-skirt",[]),("SkirtCircle","skirt-circle",[]),("AsymmSkirtCircle","skirt-asymmetric-circle",[]),
            ("GodetSkirt","godet-skirt",[]),("GodetSkirt","godet-skirt-Skirt2",[(["godet-skirt","base"],.string("Skirt2"))]),
            ("GodetSkirt","godet-skirt-varied",[(["godet-skirt","num_inserts"],.number(8)),(["godet-skirt","insert_w"],.number(20)),(["godet-skirt","insert_depth"],.number(25))]),
            ("SkirtLevels","skirt-levels",[]),("SkirtLevels","skirt-levels-varied",[(["levels-skirt","num_levels"],.number(3)),(["levels-skirt","level_ruffle"],.number(1.3))]),
            ("SkirtLevels","skirt-levels-rise",[(["levels-skirt","rise"],.number(0.75))]),
            ("SkirtManyPanels","skirt-many-panels",[]),("SkirtManyPanels","skirt-many-panels-curved",[(["flare-skirt","skirt-many-panels","panel_curve"],.number(0.25))])]
        for cuff in ["CuffBand","CuffSkirt","CuffBandSkirt"]{cases.append(("Pants","pants-"+cuff,[(["pants","cuff","type"],.string(cuff))]))}
        for (tag,flare,angle,rise) in [("narrow-low",0.8,20.0,0.7),("wide-low",1.2,-15.0,0.8),("wide-high",1.4,20.0,1.0)] {
            cases.append(("PencilSkirt","pencil-skirt-"+tag,[(["pencil-skirt","flare"],.number(flare)),(["pencil-skirt","low_angle"],.number(angle)),(["pencil-skirt","rise"],.number(rise))]))
        }
        for flare in [0.8,1.2] {cases.append(("PencilSkirt","pencil-skirt-flare-\(flare)",[(["pencil-skirt","flare"],.number(flare))]))}
        cases += [("SkirtCircle","skirt-circle-cut",[(["flare-skirt","cut","add"],.bool(true))]),("AsymmSkirtCircle","skirt-asymmetric-circle-cut",[(["flare-skirt","cut","add"],.bool(true))]),("PencilSkirt","pencil-skirt-Sun",[(["pencil-skirt","style_side_cut"],.string("Sun"))]),("PencilSkirt","pencil-skirt-SIGGRAPH_logo",[(["pencil-skirt","style_side_cut"],.string("SIGGRAPH_logo"))])]
        for base in ["Skirt2","PencilSkirt","SkirtCircle","AsymmSkirtCircle"] {
            for level in ["Skirt2","SkirtCircle","AsymmSkirtCircle"] where !(base=="PencilSkirt" && level=="Skirt2") {
                cases.append(("SkirtLevels","skirt-levels-"+base+"-"+level,[(["levels-skirt","base"],.string(base)),(["levels-skirt","level"],.string(level))]))
            }
        }
        var checked=0,worst=0.0,rows:[[String:Any]]=[]
        func verify(_ document:GarmentCodePatternFile,_ design:GarmentCodeDesignParameters,_ body:GarmentCodeBodyParameters,_ official:GarmentCodePatternFile,_ tag:String)throws {
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
            let before=try encoder.encode(document)
            let placed=try L.prepare(document:document,body:body,design:design,targetEdgeMeters:0.08)
            let oracle=try GarmentCodePanelPlacement.importedTransforms(document:official,waistLevelCentimeters:body["_waist_level"]!)
            try require(Set(placed.panels.keys)==Set(document.pattern.panels.keys) && Set(placed.panels.keys)==Set(official.pattern.panels.keys),"missing real source panel")
            for id in placed.panels.keys.sorted() {
                let panel=placed.panels[id]!,actual=panel.transform,expected=oracle[id]!
                let translation=(actual.translationMeters-expected.translationMeters).length
                let basis=try [V(x:1,y:0,z:0),V(x:0,y:1,z:0),V(x:0,y:0,z:1)].map{(try actual.direction($0)-expected.direction($0)).length}.max()!
                worst=max(worst,translation)
                try require(translation<1e-6 && basis<1e-9,"\(tag)/\(id) translation delta \(translation)m rotation delta \(basis)")
                let points=try panel.mesh.flatPositions.map{try actual.point($0)}
                try require(points==panel.placed.positions && panel.mesh.flatPositions.count==points.count,"placed source vertex map changed or omitted particles")
                let normal=try expected.direction(.init(x:0,y:0,z:panel.mesh.sourceClockwise ? -1:1))
                try require((normal-panel.placed.fabricNormal).length<1e-9,"fabric normal rotation differs")
                rows.append(["case":tag,"panel":id,"translationErrorMeters":translation,"basisError":basis,"sourceVertexCount":points.count,"translationMeters":[actual.translationMeters.x,actual.translationMeters.y,actual.translationMeters.z],"rotationDegrees":actual.rotationDegrees,"sourceSHA256":placed.sourceSHA256])
                checked += 1
            }
            let hash=SHA256.hash(data:before).map{String(format:"%02x",$0)}.joined()
            try require(placed.sourceSHA256==hash,"canonical source hash differs from independent sorted encoding")
            try require(try encoder.encode(document)==before,"placement mutated source document")
            print("PASS",tag,placed.panels.count,"complete source panels")
        }
        for (style,fixture,changes) in cases {
            var d=GarmentCodeDesignParameters(catalog:catalog)
            _=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.null,at:["meta","wb"]);_=d.setValue(.string(style),at:["meta","bottom"])
            for (path,value) in changes{try require(d.setValue(value,at:path),"unknown test parameter")}
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:d)
            let official=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/"+fixture+".json")))
            try verify(document,d,body,official,fixture)
        }
        for fixture in ["meta-grid-defaults","meta-grid-female"] {
            let data=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/"+fixture+".json")),object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let patterns=(object["patterns"] as? [String:Any]) ?? object
            let b=(object["body"] as? [String:Double]).map{GarmentCodeBodyParameters(values:$0)} ?? body
            for key in patterns.keys.sorted() {
                let parts=key.components(separatedBy:"|")
                guard parts.count==3,parts[0]=="None",parts[2] != "None" else {continue}
                var d=GarmentCodeDesignParameters(catalog:catalog)
                _=d.setValue(.null,at:["meta","upper"]);_=d.setValue(parts[1]=="None" ? .null:.string(parts[1]),at:["meta","wb"]);_=d.setValue(.string(parts[2]),at:["meta","bottom"])
                let document=try GarmentCodeNativeGenerator.generate(body:b,design:d)
                let official=try GarmentCodePatternFile.validatedImport(from:JSONSerialization.data(withJSONObject:patterns[key]!))
                try verify(document,d,b,official,fixture+":"+key)
            }
        }
        var sample=GarmentCodeDesignParameters(catalog:catalog)
        _=sample.setValue(.null,at:["meta","upper"]);_=sample.setValue(.null,at:["meta","wb"]);_=sample.setValue(.string("Pants"),at:["meta","bottom"])
        let source=try GarmentCodeNativeGenerator.generate(body:body,design:sample)
        func rejected(_ tag:String,_ work:()throws->Void)throws {
            do{try work()}catch{print("PASS reject",tag);return};throw Failure.check("accepted invalid \(tag)")
        }
        try rejected("cancelled placement"){_=try L.prepare(document:source,body:body,design:sample,isCancelled:{true})}
        try rejected("invalid mesh budget"){_=try L.prepare(document:source,body:body,design:sample,targetEdgeMeters:0.001)}
        var wrongBody=body;wrongBody.set(body["waist"]!+1,for:"waist")
        try rejected("different body provenance"){_=try L.prepare(document:source,body:wrongBody,design:sample)}
        var wrongDesign=sample;_=wrongDesign.setValue(.number(1.2),at:["pants","width"])
        try rejected("different design provenance"){_=try L.prepare(document:source,body:body,design:wrongDesign)}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        var object=try JSONSerialization.jsonObject(with:encoder.encode(source)) as! [String:Any]
        var properties=object["properties"] as! [String:Any],generator=properties["tailorass_generator"] as! [String:Any]
        generator["upstream_commit"]="unknown";properties["tailorass_generator"]=generator;object["properties"]=properties
        let wrongSource=try JSONDecoder().decode(GarmentCodePatternFile.self,from:JSONSerialization.data(withJSONObject:object))
        try rejected("unverified source commit"){_=try L.prepare(document:wrongSource,body:body,design:sample)}
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_LOWER_OUTPUT"] ?? "/private/tmp/TailorAssLowerPlacement")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let result:[String:Any]=["passed":true,"upstreamCommit":L.upstreamCommit,"checkedPanels":checked,"maximumTranslationErrorMeters":worst,"scope":"Complete native lower-garment source initial transforms and source mesh positions only; not sewing, fit, collision or drape acceptance.","rows":rows]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("placement-proof.json"))
        try recordKnown2DBranches(catalog:catalog,body:body,out:out)
        print("PASS LowerPlacement",checked,"official source panels; maximum translation error meters",worst)
    }
}
