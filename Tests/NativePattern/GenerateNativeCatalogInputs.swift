import Foundation
import CryptoKit

/// Complete native PaperJSON export only. No mesh, body, collision or simulation
/// modules are linked into this executable.
@main @MainActor struct GenerateNativeCatalogInputs {
    enum Failure:Error {case check(String)}
    static func require(_ condition:Bool,_ message:String)throws {
        if !condition {throw Failure.check(message)}
    }
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func encoded<T:Encodable>(_ value:T,pretty:Bool=false)throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=pretty ? [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes] : [.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:encoded(value),options:[.fragmentsAllowed])}
    static func write(_ value:Any,to url:URL)throws {
        try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:url,options:.atomic)
    }
    static func text(_ value:JSONValue?)->String? {
        guard case let .string(s)?=value else{return nil};return s
    }
    static func activeSelections(_ design:GarmentCodeDesignParameters,paths:[[String]])->[String:JSONValue] {
        let upper=text(design.value(at:["meta","upper"])),bottom=text(design.value(at:["meta","bottom"]))
        let sleeveEnabled=upper != nil && design.value(at:["sleeve","sleeveless"]) == .bool(false)
        var result:[String:JSONValue]=[:]
        for path in paths {
            let key=path.joined(separator:".");let active:Bool
            switch path[0] {
            case "collar":active=upper != nil && design.value(at:["shirt","strapless"]) != .bool(true)
            case "sleeve":active=sleeveEnabled
            case "left":
                let asym=upper != nil && design.value(at:["left","enable_asym"]) == .bool(true)
                if path[1]=="sleeve" {
                    active=asym && design.value(at:["left","sleeve","sleeveless"]) == .bool(false)
                } else {
                    active=asym && design.value(at:["left","shirt","strapless"]) != .bool(true)
                }
            case "pants":active=bottom=="Pants"
            case "levels-skirt":active=bottom=="SkirtLevels"
            case "godet-skirt":active=bottom=="GodetSkirt"
            case "pencil-skirt":active=bottom=="PencilSkirt" ||
                (bottom=="GodetSkirt" && text(design.value(at:["godet-skirt","base"]))=="PencilSkirt") ||
                (bottom=="SkirtLevels" && text(design.value(at:["levels-skirt","base"]))=="PencilSkirt")
            case "flare-skirt":active=bottom=="SkirtManyPanels"
            default:active=false
            }
            // Catalog decode represents a literal null `v` as nil. These are
            // known leaf paths, so nil here is the explicit null selection.
            if active {result[key]=design.value(at:path) ?? .null}
        }
        return result
    }
    static func main()throws {
        guard CommandLine.arguments.count==3 else {throw Failure.check("Usage: generator SNAPSHOT_ROOT OUTPUT_DIRECTORY")}
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let definitions=try NativeCatalogCases.load(root:root,catalog:catalog)
        let fm=FileManager.default
        for path in [out,out.appendingPathComponent("patterns"),out.appendingPathComponent("parameters")] {
            try fm.createDirectory(at:path,withIntermediateDirectories:true)
        }
        try write(JointParameterRestoreControls.run(catalog:catalog,profiles:definitions.profiles),
            to:out.appendingPathComponent("parameter-restore-controls.json"))
        let limits:[String:Int]=["maximumCases":2048,"maximumPanelsPerSource":128,"maximumSourceVertices":8192,
            "maximumSourceEdges":8192,"maximumSourceStitches":4096,"maximumPaperJSONBytes":2*1024*1024,
            "maximumUniquePaperJSONBytes":64*1024*1024,"maximumParameterJSONBytes":512*1024]
        var rows:[[String:Any]]=[],uniquePapers:[String:(String,String,Int)]=[:],uniqueBytes=0
        var requestedValues:[String:[String:Set<String>]]=[:],generatedValues:[String:[String:Set<String>]]=[:]
        var standaloneRequested:[String:Set<String>]=[:],standaloneGenerated:[String:Set<String>]=[:]
        func observe(_ values:[String:JSONValue],profile:String,table:inout [String:[String:Set<String>]])throws {
            for (path,value) in values {
                table[profile,default:[:]][path,default:[]].insert(String(decoding:try encoded(value),as:UTF8.self))
            }
        }
        for (index,spec) in definitions.cases.enumerated() {
            var design=GarmentCodeDesignParameters(catalog:catalog),phase="apply-original-definition"
            var row:[String:Any]=["caseID":spec.id,"profile":spec.profile,"origins":spec.origins,"tags":spec.tags,
                "original211Definition":definitions.baseline211IDs.contains(spec.id),"inputOnly":true,
                "sourceGenerated":false,"rParameterRestorePassed":false,"completeGarmentAccepted":false,
                "meshingPerformed":false,"simulationPerformed":false]
            if let historical=spec.historicalFailure {row["historicalNativeReplayFailure"]=historical}
            do {
                for edit in spec.edits {
                    try require(design.setValue(edit.value,at:edit.path),"Unknown original catalog path "+edit.path.joined(separator:"."))
                }
                let body=GarmentCodeBodyParameters(values:spec.body)
                let selections=activeSelections(design,paths:definitions.discretePaths)
                try observe(selections,profile:spec.profile,table:&requestedValues)
                row["activeDiscreteSelections"]=try object(selections)
                let styles=[text(design.value(at:["meta","upper"])),text(design.value(at:["meta","wb"])),text(design.value(at:["meta","bottom"]))].compactMap{$0}
                row["styles"]=styles;row["standalone"]=styles.count==1
                if styles.count==1 {standaloneRequested[spec.profile,default:[]].insert(styles[0])}
                let parameterPath="parameters/"+hash(Data(spec.id.utf8))+".json"
                let parameters:[String:Any]=["caseID":spec.id,"profile":spec.profile,"origins":spec.origins,
                    "originalBodyValues":spec.body,"evaluatedBodyValues":body.values,
                    "originalOverrides":try object(spec.edits),"design":try object(design.jsonValue),
                    "bodyProfileDifferences":body.values.filter{definitions.profiles[spec.profile]?[$0.key] != $0.value}]
                let parameterBytes=try JSONSerialization.data(withJSONObject:parameters,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
                try require(parameterBytes.count<=limits["maximumParameterJSONBytes"]!,"Original parameter sidecar exceeds explicit byte budget")
                try parameterBytes.write(to:out.appendingPathComponent(parameterPath),options:.atomic)
                row["parameterFile"]=parameterPath;row["parameterJSONBytesSHA256"]=hash(parameterBytes)
                row["parameterValidationMessages"]=design.validationMessages()
                phase="native-generation"
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
                row["sourceGenerated"]=true
                phase="complete-paper-validation"
                try document.validateForPreview()
                let geometry=try document.geometryPanels()
                let names=document.pattern.panels.keys.sorted()
                try require(Set(geometry.keys)==Set(names),"Geometry conversion omitted or added a real source panel")
                let panelCount=names.count,vertices=document.pattern.panels.values.reduce(0){$0+$1.vertices.count}
                let edges=document.pattern.panels.values.reduce(0){$0+$1.edges.count},stitches=document.pattern.stitches.count
                row["panelIDs"]=names;row["panelCount"]=panelCount;row["sourceVertexCount"]=vertices
                row["sourceEdgeCount"]=edges;row["sourceStitchCount"]=stitches
                let canonical=try encoded(document),sourceSHA=hash(canonical),paper=try encoded(document,pretty:true)
                try require(sourceSHA==GarmentCodeJointParameters.signature(document),"Canonical source and UI document-signature encoders diverged")
                row["sourceSHA256"]=sourceSHA;row["paperJSONBytesSHA256"]=hash(paper)
                row["uiDocumentSignatureSHA256"]=try GarmentCodeJointParameters.signature(document)
                row["canonicalPaperBytes"]=canonical.count;row["paperJSONBytes"]=paper.count
                phase="source-resource-budget"
                try require(panelCount<=limits["maximumPanelsPerSource"]! && vertices<=limits["maximumSourceVertices"]! &&
                    edges<=limits["maximumSourceEdges"]! && stitches<=limits["maximumSourceStitches"]!,"Complete paper exceeds explicit source topology budget")
                try require(paper.count<=limits["maximumPaperJSONBytes"]!,"Complete paper exceeds per-file byte budget")
                if uniquePapers[sourceSHA]==nil {try require(uniqueBytes+paper.count<=limits["maximumUniquePaperJSONBytes"]!,"Unique complete-paper byte budget exhausted")}
                let patternPath="patterns/"+sourceSHA+".json"
                if let previous=uniquePapers[sourceSHA] {
                    try require(previous.1==hash(paper) && previous.2==paper.count,"Same source SHA produced different export bytes")
                } else {
                    try paper.write(to:out.appendingPathComponent(patternPath),options:.atomic)
                    uniquePapers[sourceSHA]=(patternPath,hash(paper),paper.count);uniqueBytes += paper.count
                }
                // Preserve the actual complete generated paper even if a
                // subsequent strict parameter-import check rejects it.
                row["generatedPatternFile"]=patternPath
                phase="strict-original-parameter-restore"
                let decoded=try GarmentCodePatternFile.validatedImport(from:paper)
                let restored=try GarmentCodeJointParameters.restore(document:decoded,catalog:catalog)
                row["rParameterRestorePassed"]=true
                phase="regenerate-full-source-sha"
                let regenerated=try GarmentCodeNativeGenerator.generate(body:restored.body,design:restored.design)
                try require(try encoded(regenerated)==canonical,"Original body/design did not regenerate every panel/stitch/metadata byte")
                // The generator's own input is also immutable across regeneration.
                try require(try encoded(document)==canonical,"Source changed during verification")
                row["patternFile"]=patternPath;row["status"]="ready-for-independent-R-input-validation"
                row["fullRegenerationSHA256"]=sourceSHA;row["historicalFailureResolvedAtSourceGeneration"]=spec.historicalFailure != nil
                try observe(selections,profile:spec.profile,table:&generatedValues)
                if styles.count==1 {standaloneGenerated[spec.profile,default:[]].insert(styles[0])}
            } catch {
                row["status"]="rejected";row["rejectionPhase"]=phase
                row["reason"]=String(describing:error);row["localizedReason"]=(error as NSError).localizedDescription
                row["errorType"]=String(reflecting:type(of:error))
                print("REJECT \(spec.id) [\(phase)]: \(error)")
            }
            rows.append(row)
            if (index+1)%50==0 {print("INPUT \(index+1)/\(definitions.cases.count); no mesh or simulation")}
        }
        let allStyles=(catalog.garmentOptions.upper+catalog.garmentOptions.waistband+catalog.garmentOptions.bottom).sorted()
        try require(allStyles.count==12,"The main catalog changed from 12 styles; explicitly review coverage")
        var discrete:[[String:Any]]=[]
        for profile in definitions.profiles.keys.sorted() {
            for path in definitions.discretePaths {
                let key=path.joined(separator:".");var expected=catalog.node(at:path)?.range ?? []
                if catalog.node(at:path)?.type?.contains("null")==true {expected.append(.null)}
                let wanted=try Set(expected.map{String(decoding:try encoded($0),as:UTF8.self)})
                let requested=requestedValues[profile]?[key] ?? [],generated=generatedValues[profile]?[key] ?? []
                discrete.append(["profile":profile,"path":key,"catalogValues":wanted.sorted(),"requestedValues":requested.sorted(),
                    "readyInputValues":generated.sorted(),"missingDefinitions":wanted.subtracting(requested).sorted(),
                    "missingReadyInputs":wanted.subtracting(generated).sorted()])
            }
        }
        let ready=rows.filter{$0["patternFile"] != nil},rejected=rows.filter{$0["status"] as? String=="rejected"}
        let baselineRows=rows.filter{$0["original211Definition"] as? Bool==true}
        let coverage:[String:Any]=[
            "mainStyles":allStyles,"mainStylesByProfile":definitions.profiles.keys.sorted().map{profile in
                ["profile":profile,"requestedStandalone":Array(standaloneRequested[profile] ?? []).sorted(),
                 "readyStandalone":Array(standaloneGenerated[profile] ?? []).sorted(),
                 "missingReadyStandalone":allStyles.filter{!(standaloneGenerated[profile] ?? []).contains($0)}] as [String:Any]
            },"discreteOptionsByProfile":discrete,"original211DefinitionsIndexed":baselineRows.count==211,
            "original211ReadyCount":baselineRows.filter{$0["patternFile"] != nil}.count,
            "original27DefinitionIDs":definitions.sourceMesh27IDs.sorted(),
            "original27ProfilesIndexed":rows.filter{($0["tags"] as? [String] ?? []).contains("original-27")}.count,
            "continuousSpaceExhaustive":false,"allCrossProductsExhaustive":false]
        let summary:[String:Any]=[
            "format":"GarmentCodeNativeCatalogInputs/v1","generationJobCompleted":true,
            "allRequestedSourcesReady":ready.count==rows.count,"requestedCaseCount":rows.count,"readyInputCount":ready.count,
            "rejectedCaseCount":rejected.count,"uniquePaperJSONCount":uniquePapers.count,"uniquePaperJSONBytes":uniqueBytes,
            "inputOnly":true,"meshingPerformed":false,"initializationPerformed":false,"simulationPerformed":false,
            "completeGarmentAccepted":false,"limits":limits,"coverage":coverage,
            "assemblyMeshBudgets":["maximumVertices":20000,"maximumTriangles":40000,"evaluated":false],
            "hashDefinitions":["paperJSONBytesSHA256":"SHA256 of exact exported pretty PaperJSON bytes",
                "sourceSHA256":"SHA256 of the complete decoded PaperJSON re-encoded sortedKeys/withoutEscapingSlashes, including every panel/stitch/body/design/provenance field",
                "uiDocumentSignatureSHA256":"GarmentCodeJointParameters.signature(document); currently the same complete canonical encoder as sourceSHA256",
                "uiConfigurationID":"Not generated: the live UI also appends runtime body-resource and catalog URLs; it is not a portable paper hash"],
            "meaningOfReadyInput":"Complete source generation, preview geometry, original-parameter restore and full-source regeneration passed. No 3D acceptance is implied.",
            "rejections":rejected,"cases":rows]
        try write(summary,to:out.appendingPathComponent("catalog-input-manifest.json"))
        try write(coverage,to:out.appendingPathComponent("coverage.json"))
        print("COMPLETE inputs \(ready.count)/\(rows.count), unique \(uniquePapers.count), rejected \(rejected.count); 3D not evaluated")
    }
}
