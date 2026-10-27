import Foundation
import CryptoKit

@main @MainActor struct NativeAssemblyRegression {
    typealias A=GarmentCodeNativeAssembly
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias S=GarmentCodeSewing
    enum Failure:Error{case check(String)}
    struct Edit:Decodable{let path:[String];let value:JSONValue}
    struct OracleCase:Decodable{let id:String;let body:[String:Double];let overrides:[Edit]}
    struct KnownFailure:Decodable{let id:String;let error:String}
    struct UpperFixture:Decodable{let cases:[OracleCase];let nativeReplayFailures:[KnownFailure]}
    nonisolated final class CancellationCounter:@unchecked Sendable{
        private let lock=NSLock()
        private var count=0
        let limit:Int
        init(limit:Int){self.limit=limit}
        func cancelled()->Bool{lock.lock();defer{lock.unlock()};count += 1;return count>=limit}
    }
    struct SavedInput:Encodable{
        let positions:[V],referencePositions:[V],triangleIndices:[UInt32],referenceTriangles:[UInt32],pinned:[Bool],inverseMasses:[Double]
        let massesKg:[Double],sourceSHA256:String
        let isConstructionPreparationOnly:Bool
    }
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func require(_ b:@autoclosure()throws->Bool,_ reason:String)throws{if try !b(){throw Failure.check(reason)}}
    static func encode<T:Encodable>(_ x:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(x)}
    static func object<T:Encodable>(_ x:T)throws->Any{try JSONSerialization.jsonObject(with:encode(x))}
    static func log(_ s:String){FileHandle.standardError.write(Data((s+"\n").utf8))}
    static func settings()->K.Settings{
        var s=K.Settings();s.targetEdgeMeters=0.04;s.bodyMode = .standardMannequin;s.material = .medium
        s.useSurfaceCollision=true;s.useBodySurfaceCollision=true;s.solverIterations=32;s.sourceStrainLimit=0.05;s.sourceStrainLimitPasses=40
        s.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources");return s
    }
    static func check(_ prepared:GarmentCodeSewnDrape.PreparedInput,document:GarmentCodePatternFile)throws->[String:Any]{
        let input=prepared.cloth,n=input.positions.count,source=try document.geometryPanels()
        try require(prepared.sourceSHA256==GarmentCodeSewnDrape.canonicalSourceSHA256(document:document) && prepared.plan.sourceSHA256==prepared.sourceSHA256,"Complete source hash differs")
        try require(Set(prepared.panelBindings.map{$0.mesh.panelID})==Set(source.keys) && prepared.panelBindings.count==source.count,"Source components were omitted/duplicated")
        try require(input.referenceToSimulation==Array(0..<n) && input.seamVertexPairs.isEmpty && input.pinned.allSatisfy{!$0} && input.inverseMasses.allSatisfy{$0>0},"Native source DOFs welded or artificial supports added")
        let strains=(input.springs+input.bendingSprings).map{abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1)}
        let maximum=strains.max() ?? 0
        try require(maximum<1e-10,"Rigid native placement introduced source edge prestrain")
        var seen=Set<Int>(),seenFaces=Set<Int>(),areas=Array(repeating:0.0,count:n),maximumNormalError=0.0
        for binding in prepared.panelBindings{
            let mesh=binding.mesh,normalSign=mesh.sourceClockwise ? -1.0:1.0
            try require(mesh.sourceClockwise == (source[mesh.panelID]!.signedArea<0),"Original fabric-side winding changed")
            for(i,id) in binding.vertexIDs.enumerated(){try require(seen.insert(id).inserted && input.referencePositions[id]==mesh.flatPositions[i],"Original flat vertex changed or repeated")}
            var firstNormal:V?
            for local in binding.triangleIDs.indices{
                let ids=(0..<3).map{binding.vertexIDs[Int(mesh.triangleIndices[local*3+$0])]},slot=binding.triangleIDs[local]*3
                try require(seenFaces.insert(slot/3).inserted && (0..<3).allSatisfy{Int(input.referenceTriangles[slot+$0])==ids[$0]},"Reference topology changed")
                var facing=ids;if mesh.sourceClockwise{facing.swapAt(1,2)}
                try require((0..<3).allSatisfy{Int(input.triangleIndices[slot+$0])==facing[$0]},"Original source fabric normal was flipped")
                let a=input.referencePositions[ids[0]],b=input.referencePositions[ids[1]],c=input.referencePositions[ids[2]],area=(b-a).cross(c-a).z/2
                try require(area>1e-14,"Source triangle not positive CCW")
                for i in ids{areas[i] += area/3}
                let aa=input.positions[ids[0]],bb=input.positions[ids[1]],cc=input.positions[ids[2]],world=(bb-aa).cross(cc-aa),normal=world/max(1e-30,world.length)*normalSign
                try require(abs(world.length/2-area)<max(1e-13,area*1e-9),"Rigid placement changed source triangle area")
                if let firstNormal{maximumNormalError=max(maximumNormalError,(normal-firstNormal).length)}else{firstNormal=normal}
            }
        }
        try require(seen.count==n && seenFaces.count==input.triangleIndices.count/3 && maximumNormalError<1e-8,"A native panel was deformed, folded or omitted")
        let density=input.settings.material!.parameters.arealDensityKgPerSquareMeter,totalArea=areas.reduce(0,+),mass=totalArea*density,mean=mass/Double(n)
        try require(abs(mass-input.totalFabricMassKg!)<1e-12 && abs(totalArea-input.referenceAreaSquareMeters)<1e-12 && abs(mean-input.meanParticleMassKg)<1e-14,"Source physical mass was modified")
        for i in 0..<n{try require(abs(input.inverseMasses[i]-mean/(areas[i]*density))<max(1e-12,input.inverseMasses[i]*1e-9),"Independent source mass integration differs")}
        try require(Set(prepared.plan.anchors.map(\.stitchIndex))==Set(document.pattern.stitches.indices),"Some original source stitches were lost")
        let origins=prepared.plan.constraints.flatMap(\.origins)
        for origin in origins{
            let original=document.pattern.stitches[origin.stitchIndex]
            try require(origin.rightWrong==original.rightWrong && origin.aDirection==(original.rightWrong ? .forward:.reverse) && origin.bDirection == .forward,"Upstream ordinary/right_wrong direction contract changed")
        }
        let attached=Set(prepared.plan.constraints.flatMap{$0.a.vertexIDs+$0.b.vertexIDs})
        for fold in prepared.plan.foldIntervals{try require(fold.untackedBoundaryVertexIDs.count>=fold.minimumFreeBoundaryNodes && fold.untackedBoundaryVertexIDs.allSatisfy{!attached.contains($0) && !input.pinned[$0]},"Source ease/gather folds lost free nodes")}
        var intent:[String:Any]=[:]
        for index in document.pattern.stitches.indices{
            let stitchOrigins=origins.filter{$0.stitchIndex==index}
            guard let first=stitchOrigins.first else {throw Failure.check("Missing source intent")}
            intent[String(index)]=["a":try object(first.a.edge),"b":try object(first.b.edge),"sourceLengthA":first.a.sourceLengthMeters,"sourceLengthB":first.b.sourceLengthMeters,"intent":try object(first.intent),"rightWrong":first.rightWrong]
        }
        return ["passed":true,"sourceSHA256":prepared.sourceSHA256,"panels":source.count,"vertices":n,"triangles":input.triangleIndices.count/3,"sourceStitches":document.pattern.stitches.count,"sourceMassKg":mass,"sourceAreaSquareMeters":totalArea,"maximumInitialSourceStrain":maximum,"maximumWithinPanelNormalVariation":maximumNormalError,"fixedParticles":0,"sourceWelded":false,"allRealStitchIntents":intent,"warnings":input.preparationWarnings]
    }
    static func main()throws{
        let env=ProcessInfo.processInfo.environment,out=URL(fileURLWithPath:env["GARMENTCODE_NATIVE_OUTPUT"] ?? "/private/tmp/TailorAssNativeAssembly")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let filter=env["GARMENTCODE_NATIVE_FILTER"],catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        var rows:[[String:Any]]=[],failures:[[String:String]]=[],incomplete:[[String:String]]=[],defaultCount=0,contract:(GarmentCodePatternFile,GarmentCodeBodyParameters,GarmentCodeDesignParameters)?
        func run(_ id:String,_ body:GarmentCodeBodyParameters,_ design:GarmentCodeDesignParameters,known:String?=nil,expectedPlacement:GarmentCodePatternFile?=nil)throws{
            if let filter,!id.contains(filter){return}
            log("START "+id)
            let document:GarmentCodePatternFile
            do{document=try GarmentCodeNativeGenerator.generate(body:body,design:design)}catch{
                if let known,String(describing:error)==known{incomplete.append(["case":id,"stage":"existing native 2D generation","error":known]);log("INCOMPLETE known source "+id);return}
                throw error
            }
            let before=try encode(document)
            let prepared:GarmentCodeSewnDrape.PreparedInput
            do{prepared=try A.prepare(document:document,body:body,design:design,settings:settings())}
            catch{
                let safe=id.map{$0.isLetter || $0.isNumber || $0=="-" || $0=="_" ? $0:"_"}.map(String.init).joined()
                try before.write(to:out.appendingPathComponent(safe+"-incomplete-source.json"))
                try encode(body).write(to:out.appendingPathComponent(safe+"-incomplete-body.json"))
                try encode(design.jsonValue).write(to:out.appendingPathComponent(safe+"-incomplete-design.json"))
                throw error
            }
            var row=try check(prepared,document:document);row["case"]=id
            if let expectedPlacement{
                let expected=try GarmentCodePanelPlacement.importedTransforms(document:expectedPlacement,waistLevelCentimeters:body["_waist_level"]!)
                try require(Set(expected.keys)==Set(prepared.panelBindings.map{$0.mesh.panelID}),"Official rise oracle omits complete source components")
                var maximum=0.0
                for binding in prepared.panelBindings{for(local,global) in binding.vertexIDs.enumerated(){maximum=max(maximum,try (prepared.cloth.positions[global]-expected[binding.mesh.panelID]!.point(binding.mesh.flatPositions[local])).length)}}
                row["maximumOfficialPlacementPointDifferenceMeters"]=maximum
                try require(maximum<1e-6,"Nondefault Levels official full rigid placement mismatch \(maximum)m")
            }
            rows.append(row)
            try require(before==encode(document),"Factory mutated source")
            if id.contains("meta-grid"){defaultCount += 1}
            if id=="meta-grid-defaults:None|StraightWB|SkirtCircle"{
                contract=(document,body,design)
                try before.write(to:out.appendingPathComponent("native-example-source.json"));try encode(prepared.plan).write(to:out.appendingPathComponent("native-example-plan.json"))
                let input=prepared.cloth,masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:input.referencePositions.map{SIMD3<Double>($0.x,$0.y,$0.z)},triangleIndices:input.referenceTriangles,arealDensity:input.settings.material!.parameters.arealDensityKgPerSquareMeter)
                try encode(SavedInput(positions:input.positions,referencePositions:input.referencePositions,triangleIndices:input.triangleIndices,referenceTriangles:input.referenceTriangles,pinned:input.pinned,inverseMasses:input.inverseMasses,massesKg:masses.massesKg,sourceSHA256:prepared.sourceSHA256,isConstructionPreparationOnly:true)).write(to:out.appendingPathComponent("native-example-input.json"))
            }
            log("PASS "+id+" \(prepared.cloth.positions.count)V rigid all source, 0pins")
        }
        for filename in ["meta-grid-defaults","meta-grid-female"]{
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/\(filename).json"))) as! [String:Any]
            let patterns=(object["patterns"] as? [String:Any]) ?? object,body=(object["body"] as? [String:Double]).map{GarmentCodeBodyParameters(values:$0)} ?? GarmentCodeBodyParameters(values:catalog.body)
            for key in patterns.keys.sorted(){
                let id=filename+":"+key
                if let filter,!id.contains(filter){continue}
                do{
                    var design=GarmentCodeDesignParameters(catalog:catalog)
                    for(i,value) in key.components(separatedBy:"|").enumerated(){_=design.setValue(value=="None" ? .null:.string(value),at:["meta",["upper","wb","bottom"][i]])}
                    let official=try GarmentCodePatternFile.validatedImport(from:JSONSerialization.data(withJSONObject:patterns[key]!))
                    try run(id,body,design,expectedPlacement:official)
                }catch{failures.append(["case":id,"error":String(describing:error)]);log("FAIL "+id+": "+String(describing:error))}
            }
        }
        let upper=try JSONDecoder().decode(UpperFixture.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json")))
        let suffixes=["-sleeved","-connect-ruffle","-CuffBand","-CuffSkirt","-CuffBandSkirt","-sleeved-Turtle","-sleeved-SimpleLapel","-sleeved-Hood2Panels","-standing"]
        for item in upper.cases where suffixes.contains(where:item.id.hasSuffix){
            let id="upper:"+item.id
            if let filter,!id.contains(filter){continue}
            do{
                var design=GarmentCodeDesignParameters(catalog:catalog)
                for edit in item.overrides{_=design.setValue(edit.value,at:edit.path)}
                try run(id,GarmentCodeBodyParameters(values:item.body),design,known:upper.nativeReplayFailures.first{$0.id==item.id}?.error)
            }catch{failures.append(["case":id,"error":String(describing:error)]);log("FAIL "+id+": "+String(describing:error))}
        }
        for cuff in ["CuffBand","CuffSkirt","CuffBandSkirt"]{
            let id="pants:"+cuff
            if let filter,!id.contains(filter){continue}
            do{
                var d=GarmentCodeDesignParameters(catalog:catalog)
                _=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.string("Pants"),at:["meta","bottom"]);_=d.setValue(.string("StraightWB"),at:["meta","wb"])
                _=d.setValue(.string(cuff),at:["pants","cuff","type"]);_=d.setValue(.number(1.2),at:["pants","cuff","top_ruffle"]);_=d.setValue(.number(1.3),at:["pants","cuff","skirt_ruffle"])
                try run(id,GarmentCodeBodyParameters(values:catalog.body),d)
            }catch{failures.append(["case":id,"error":String(describing:error)]);log("FAIL "+id+": "+String(describing:error))}
        }
        let levelsBytes=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/native-assembly-levels-oracles.json"))
        let levels=try JSONSerialization.jsonObject(with:levelsBytes) as! [String:Any],levelCases=levels["cases"] as! [[String:Any]],levelBodies=levels["bodies"] as! [String:[String:Double]],levelSource=levels["source"] as! [String:Any]
        try require(levels["format"] as? String=="GarmentCodeNativeAssemblyLevelsOracles/v1" && levelCases.count==12 && levelSource["commit"] as? String==GarmentCodeUpperPlacement.upstreamCommit,"Independent Levels oracle provenance differs")
        let generatorBytes=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/GenerateNativeAssemblyLevelsGoldens.py")),generatorHash=SHA256.hash(data:generatorBytes).map{String(format:"%02x",$0)}.joined()
        try require(levelSource["generatorSHA256"] as? String==generatorHash && levelSource["allImportedFilesMatchPinnedGitObjects"] as? Bool==true,"Independent Levels oracle generator/source proof changed")
        for item in levelCases{
            let id="levels-rise:"+(item["id"] as! String)
            if let filter,!id.contains(filter){continue}
            do{
                var design=GarmentCodeDesignParameters(catalog:catalog)
                let edits=try JSONDecoder().decode([Edit].self,from:JSONSerialization.data(withJSONObject:item["overrides"]!))
                for e in edits{_=design.setValue(e.value,at:e.path)}
                let body=GarmentCodeBodyParameters(values:levelBodies[item["bodyName"] as! String]!)
                let official=try GarmentCodePatternFile.validatedImport(from:JSONSerialization.data(withJSONObject:item["expected"]!))
                try run(id,body,design,expectedPlacement:official)
                var component=design;_=component.setValue(.null,at:["meta","upper"]);_=component.setValue(.null,at:["meta","wb"])
                let map=try GarmentCodeLowerPlacement.componentMap(body:body,design:component,requestedRise:1)
                try require(map.constructionRiseOverride==1 && map.document.parameters?["design"]==component.jsonValue,"Requested-rise source was mislabeled as default lower input")
            }catch{failures.append(["case":id,"error":String(describing:error)]);log("FAIL "+id+": "+String(describing:error))}
        }
        var rejected=0
        if let(source,body,design)=contract{
            func reject(_ work:()throws->Void)throws{do{try work();throw Failure.check("Invalid NativeAssembly input accepted")}catch is Failure{throw Failure.check("Invalid NativeAssembly input accepted")}catch{rejected += 1}}
            try reject{_=try A.prepare(document:source,body:body,design:design,settings:settings(),isCancelled:{true})}
            let during=CancellationCounter(limit:50)
            try reject{_=try A.prepare(document:source,body:body,design:design,settings:settings(),isCancelled:{during.cancelled()})}
            var properties=source.properties ?? [:];properties["unknown-native-source"] = .bool(true)
            let unknown=GarmentCodePatternFile(pattern:source.pattern,parameters:source.parameters,parameterOrder:source.parameterOrder,properties:properties)
            try reject{_=try A.prepare(document:unknown,body:body,design:design,settings:settings())}
            var wrongBody=body;wrongBody.set(body["waist"]!+1,for:"waist")
            try reject{_=try A.prepare(document:source,body:wrongBody,design:design,settings:settings())}
            var tiny=A.Limits();tiny.maximumVertices=3
            try reject{_=try A.prepare(document:source,body:body,design:design,settings:settings(),limits:tiny)}
            var bad=A.Limits();bad.maximumPanels=0
            try reject{_=try A.prepare(document:source,body:body,design:design,settings:settings(),limits:bad)}
            var invalid=settings();invalid.targetEdgeMeters = .nan
            try reject{_=try A.prepare(document:source,body:body,design:design,settings:invalid)}
        }
        let scope=filter == nil ? "Full160 default native meta/body combinations plus representative true upper components and pant cuffs":"Explicit filtered diagnostic only: "+filter!
        let summary:[String:Any]=["passedAvailableSourceChecks":failures.isEmpty && (filter != nil || defaultCount==160),"complete":failures.isEmpty && incomplete.isEmpty && filter==nil,"scope":scope,"defaultCaseCount":defaultCount,"caseCount":rows.count,"cases":rows,"unexpectedFailures":failures,"knownIncompleteSources":incomplete,"invalidCancellationBudgetUnknownRejected":rejected,"noPhysicsRequested":true,"noAppIntegration":true]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("native-assembly-summary.json"))
        try require(failures.isEmpty && (filter != nil || defaultCount==160),"Native source preparation has unresolved failures; complete evidence retained")
    }
}
