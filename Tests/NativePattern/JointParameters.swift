import Foundation
@main @MainActor struct JointParametersRegression {
    enum Failure:Error {case check(String)}
    static func check(_ b:Bool,_ m:String)throws{if !b{throw Failure.check(m)}}
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        var body=GarmentCodeBodyParameters(values:catalog.body)
        body.set((body["waist"] ?? 0)*1.03,for:"waist")
        body.set((body["hips"] ?? 0)*1.02,for:"hips")
        var documents:[GarmentCodePatternFile]=[]
        for kind in ["Shirt","FittedShirt","circle"] {
            var design=GarmentCodeDesignParameters(catalog:catalog)
            _=design.setValue(kind=="circle" ? .null:.string(kind),at:["meta","upper"])
            _=design.setValue(kind=="circle" ? .string("StraightWB"):.null,at:["meta","wb"])
            _=design.setValue(kind=="circle" ? .string("SkirtCircle"):.null,at:["meta","bottom"])
            if kind != "circle" {
                _=design.setValue(.bool(false),at:["sleeve","sleeveless"])
                _=design.setValue(.number(1.17),at:["shirt","width"])
                _=design.setValue(.number(1.35),at:["shirt","length"])
                _=design.setValue(.number(0.45),at:["sleeve","length"])
            } else {
                _=design.setValue(.number(0.63),at:["flare-skirt","suns"])
                _=design.setValue(.number(0.26),at:["waistband","width"])
            }
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            let restored=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
            try check(restored.design.jsonValue==design.jsonValue,"complete original design tree not preserved")
            try check(restored.body.values==body.values,"complete raw/derived body not preserved")
            let regenerated=try GarmentCodeNativeGenerator.generate(body:restored.body,design:restored.design)
            try check(GarmentCodeJointParameters.signature(document)==GarmentCodeJointParameters.signature(regenerated),"native source roundtrip changed full document")
            try check(restored.panelNames.count==document.pattern.panels.count && restored.panelNames.values.allSatisfy{!$0.isEmpty},"complete Chinese panel mapping")
            documents.append(document)
        }
        let original=documents[0];var rejected:[String]=[]
        func malformed(_ label:String,_ transform:([String:JSONValue])->[String:JSONValue]?)throws {
            let bad=GarmentCodePatternFile(pattern:original.pattern,parameters:transform(original.parameters!),parameterOrder:original.parameterOrder,properties:original.properties)
            do{_=try GarmentCodeJointParameters.restore(document:bad,catalog:catalog);throw Failure.check("malformed accepted: "+label)}catch is GarmentCodeJointParameters.RestoreError {rejected.append(label)}
        }
        try malformed("no provenance"){_ in nil}
        try malformed("no design"){p in var p=p;p.removeValue(forKey:"design");return p}
        try malformed("missing raw body even unused by this style"){p in var p=p,b=p["body"]!.objectValue!;b.removeValue(forKey:"crotch_hip_diff");p["body"] = .object(b);return p}
        try malformed("body wrong JSON type"){p in var p=p,b=p["body"]!.objectValue!;b["height"] = .string("171.99");p["body"] = .object(b);return p}
        try malformed("missing derived body"){p in var p=p,b=p["body"]!.objectValue!;b.removeValue(forKey:"_waist_level");p["body"] = .object(b);return p}
        try malformed("inconsistent derived body"){p in var p=p,b=p["body"]!.objectValue!;b["_waist_level"] = .number(1);p["body"] = .object(b);return p}
        try malformed("nonfinite body"){p in var p=p,b=p["body"]!.objectValue!;b["height"] = .number(.nan);p["body"] = .object(b);return p}
        func changeDesign(_ p:[String:JSONValue],_ edit:(inout [String:JSONValue])->Void)->[String:JSONValue] {var p=p,d=p["design"]!.objectValue!;edit(&d);p["design"] = .object(d);return p}
        try malformed("missing design subtree"){p in changeDesign(p){$0.removeValue(forKey:"left")}}
        try malformed("unknown design subtree"){p in changeDesign(p){$0["extra"] = .object([:])}}
        try malformed("missing actual leaf value"){p in changeDesign(p){d in var shirt=d["shirt"]!.objectValue!,width=shirt["width"]!.objectValue!;width.removeValue(forKey:"v");shirt["width"] = .object(width);d["shirt"] = .object(shirt)}}
        try malformed("changed catalog metadata"){p in changeDesign(p){d in var shirt=d["shirt"]!.objectValue!,width=shirt["width"]!.objectValue!;width["range"] = .array([.number(0),.number(999)]);shirt["width"] = .object(width);d["shirt"] = .object(shirt)}}
        try malformed("out of original value range"){p in changeDesign(p){d in var shirt=d["shirt"]!.objectValue!,width=shirt["width"]!.objectValue!;width["v"] = .number(999);shirt["width"] = .object(width);d["shirt"] = .object(shirt)}}
        let summary:[String:Any]=["passed":true,"fullNativeRoundtrips":documents.count,"nondefaultBodyAndDesignEditsPreserved":true,"rejected":rejected,"catalogDefaultsUsedForMissingValues":false,"catalogMetadataPreserved":true,"scope":"Source parameter restoration only; not native3D preparation, physical acceptance, UI execution or garment output."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-parameters-summary.json"));print(summary)
    }
}
