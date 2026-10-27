import Foundation

@main @MainActor struct CompositionPlacementRegression {
    typealias C=GarmentCodeCompositionPlacement
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error {case check(String)}
    static func require(_ b:@autoclosure()throws->Bool,_ s:String)throws {if try !b(){throw Failure.check(s)}}
    static func encode<T:Encodable>(_ value:T)throws->Data {
        let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)
    }
    static func official(_ object:Any)throws->GarmentCodePatternFile {
        try GarmentCodePatternFile.validatedImport(from:JSONSerialization.data(withJSONObject:object))
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        var rows:[[String:Any]]=[],maximum=0.0,panelCount=0,failures:[String]=[]
        var contractSource:GarmentCodePatternFile?,contractDesign:GarmentCodeDesignParameters?,contractBody:GarmentCodeBodyParameters?,contractComponents:[C.Component]?
        for filename in ["meta-grid-defaults","meta-grid-female"] {
            let data=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/"+filename+".json"))
            let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let patterns=(object["patterns"] as? [String:Any]) ?? object
            let body=(object["body"] as? [String:Double]).map{GarmentCodeBodyParameters(values:$0)} ?? GarmentCodeBodyParameters(values:catalog.body)
            let waist=body["_waist_level"]!
            var solo:[String:[String:C.Transform]]=[:]
            for key in patterns.keys.sorted() {
                let parts=key.components(separatedBy:"|")
                guard parts.count==3,parts.filter({$0 != "None"}).count==1 else {continue}
                let file=try official(patterns[key]!)
                solo[key]=try GarmentCodePanelPlacement.importedTransforms(document:file,waistLevelCentimeters:waist)
            }
            for key in patterns.keys.sorted() {
                do {
                    let parts=key.components(separatedBy:"|")
                    try require(parts.count==3,"Bad official meta key")
                    var design=GarmentCodeDesignParameters(catalog:catalog)
                    for (i,path) in ["upper","wb","bottom"].enumerated() {
                        try require(design.setValue(parts[i]=="None" ? .null:.string(parts[i]),at:["meta",path]),"Bad native meta parameter")
                    }
                    let source=try GarmentCodeNativeGenerator.generate(body:body,design:design),bytes=try encode(source)
                    let reference=try official(patterns[key]!)
                    let expected=try GarmentCodePanelPlacement.importedTransforms(document:reference,waistLevelCentimeters:waist)
                    var components:[C.Component]=[]
                    for i in 0..<3 where parts[i] != "None" {
                        var values=["None","None","None"];values[i]=parts[i]
                        let componentKey=values.joined(separator:"|")
                        guard let transforms=solo[componentKey] else {throw Failure.check("Missing official isolated component")}
                        components.append(.init(kind:[C.Kind.upper,.waistband,.lower][i],transforms:transforms))
                    }
                    let placed=try C.prepare(document:source,body:body,design:design,components:components)
                    try require(Set(placed.transforms.keys)==Set(source.pattern.panels.keys),"Composition omitted a source panel")
                    try require(placed.steps.count==components.count-1,"Composition omitted or invented a stacking step")
                    var error=0.0
                    for id in expected.keys.sorted() {
                        guard let actual=placed.transforms[id] else {throw Failure.check("Missing component child \(id)")}
                        for p in [V.zero,.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1)] {
                            error=max(error,try (actual.point(p)-expected[id]!.point(p)).length)
                        }
                    }
                    try require(bytes==encode(source),"Composition mutated the original complete source")
                    try require(error<5e-8,"Official complete component-transform mismatch \(error)m")
                    maximum=max(maximum,error);panelCount += placed.transforms.count
                    rows.append(["case":filename+":"+key,"passed":true,"panels":placed.transforms.count,
                        "maximumBasisPointDifferenceMeters":error,"sourceSHA256":placed.sourceSHA256,
                        "steps":try JSONSerialization.jsonObject(with:encode(placed.steps))])
                    if key=="Shirt|StraightWB|SkirtCircle",filename=="meta-grid-defaults" {
                        contractSource=source;contractBody=body;contractDesign=design;contractComponents=components
                    }
                    print("PASS \(filename):\(key) \(placed.transforms.count) complete source panels")
                } catch {
                    let message=filename+":"+key+": "+String(describing:error)
                    failures.append(message);FileHandle.standardError.write(Data(("FAIL "+message+"\n").utf8))
                }
            }
        }
        var refused=0
        if let source=contractSource,let body=contractBody,let design=contractDesign,let components=contractComponents {
            let before=try encode(source)
            for bad in [Array(components.dropLast()),Array(components.reversed()),components+[components[0]]] {
                do{_=try C.prepare(document:source,body:body,design:design,components:bad)}catch{refused += 1}
            }
            var incomplete=components
            var transforms=incomplete[0].transforms;transforms.removeValue(forKey:transforms.keys.sorted()[0])
            incomplete[0] = .init(kind:.upper,transforms:transforms)
            do{_=try C.prepare(document:source,body:body,design:design,components:incomplete)}catch{refused += 1}
            do{_=try C.prepare(document:source,body:body,design:design,components:components,gapMeters:.nan)}catch{refused += 1}
            do{_=try C.prepare(document:source,body:body,design:design,components:components,isCancelled:{true})}catch is CancellationError{refused += 1}
            var altered=source.properties ?? [:];altered["unknown-source"] = .bool(true)
            let unknown=GarmentCodePatternFile(pattern:source.pattern,parameters:source.parameters,
                parameterOrder:source.parameterOrder,properties:altered)
            do{_=try C.prepare(document:unknown,body:body,design:design,components:components)}catch{refused += 1}
            try require(try encode(source)==before,"Failure path mutated the complete source")
        }
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_COMPOSITION_OUTPUT"] ?? "/private/tmp/TailorAssCompositionPlacement")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let summary:[String:Any]=["passed":failures.isEmpty && rows.count==160 && refused==7,"cases":rows,"failures":failures,
            "caseCount":rows.count,"panelCount":panelCount,"invalidAndCancellationCasesRejected":refused,
            "maximumBasisPointDifferenceMeters":maximum,
            "scope":"Native complete-source MetaGarment interface stacking from independently given official isolated-component transforms. This does not prove native upper component recipe coverage, sewing, body fit, physics, App routing or phone performance."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("composition-placement-summary.json"))
        try require(failures.isEmpty && rows.count==160 && refused==7,"Meta composition matrix or refusal contracts failed")
        print("PASS160 complete native compositions; no sewn-garment acceptance claim")
    }
}
