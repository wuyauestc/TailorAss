import Foundation

/// Actual complete-source controls for group children named `type`. This is
/// separate from source generation: no synthetic stable state or 3D work.
@MainActor enum JointParameterRestoreControls {
    typealias F=GenerateNativeCatalogInputs
    static func run(catalog:GarmentCodeParameterCatalog,profiles:[String:[String:Double]])throws->[String:Any] {
        var positives:[String]=[],negatives:[String]=[],childTypeGroups:[String]=[],leafCount=0
        func inspect(_ node:GarmentCodeParameterNode,_ path:[String]) {
            if node.hasValueKey {leafCount += 1}
            if node.type==nil,node.children["type"] != nil {childTypeGroups.append(path.joined(separator:"."))}
            for key in node.children.keys.sorted() {inspect(node.children[key]!,path+[key])}
        }
        for key in catalog.design.keys.sorted() {inspect(catalog.design[key]!,[key])}
        try F.require(Set(childTypeGroups)==Set(["sleeve.cuff","pants.cuff","left.sleeve.cuff"]),
            "Review every catalog group with a child named type: "+childTypeGroups.joined(separator:","))
        var exemplar:GarmentCodePatternFile?
        for profile in profiles.keys.sorted() {
            for family in ["Shirt","Pants","Shirt-left"] {
                for cuff in [JSONValue.null,.string("CuffBand"),.string("CuffSkirt"),.string("CuffBandSkirt")] {
                    var design=GarmentCodeDesignParameters(catalog:catalog)
                    _=design.setValue(family=="Pants" ? .null : .string("Shirt"),at:["meta","upper"])
                    _=design.setValue(family=="Pants" ? .string(family) : .null,at:["meta","bottom"])
                    _=design.setValue(.null,at:["meta","wb"])
                    _=design.setValue(.bool(false),at:["sleeve","sleeveless"])
                    if family=="Shirt-left" {
                        _=design.setValue(.bool(true),at:["left","enable_asym"])
                        _=design.setValue(.bool(false),at:["left","sleeve","sleeveless"])
                    }
                    let path=family=="Pants" ? ["pants","cuff","type"] :
                        (family=="Shirt-left" ? ["left","sleeve","cuff","type"] : ["sleeve","cuff","type"])
                    try F.require(design.setValue(cuff,at:path),"Unknown actual cuff leaf")
                    let original=try GarmentCodeNativeGenerator.generate(body:.init(values:profiles[profile]!),design:design)
                    let paper=try F.encoded(original,pretty:true)
                    let decoded=try JSONDecoder().decode(GarmentCodePatternFile.self,from:paper)
                    let restored=try GarmentCodeJointParameters.restore(document:decoded,catalog:catalog)
                    let rebuilt=try GarmentCodeNativeGenerator.generate(body:restored.body,design:restored.design)
                    try F.require(try F.encoded(original)==F.encoded(rebuilt),"Cuff restore changed full original source")
                    positives.append(profile+":"+family+":"+String(decoding:try F.encoded(cuff),as:UTF8.self))
                    if family=="Shirt",cuff == .string("CuffBand") {exemplar=decoded}
                }
            }
        }
        let original=exemplar!
        func altered(_ path:[String],_ value:JSONValue?=nil)throws->GarmentCodePatternFile {
            var parameters=original.parameters!
            func replace(_ object:inout [String:JSONValue],_ path:ArraySlice<String>)throws {
                guard let key=path.first else {throw F.Failure.check("Empty mutation path")}
                if path.count==1 {object[key]=value;return}
                guard case var .object(nested)?=object[key] else {throw F.Failure.check("Mutation is not an original object: "+key)}
                try replace(&nested,path.dropFirst());object[key] = .object(nested)
            }
            try replace(&parameters,path[...])
            return .init(pattern:original.pattern,parameters:parameters,parameterOrder:original.parameterOrder,properties:original.properties)
        }
        let mutations:[(String,[String],JSONValue?)]=[
            ("leaf-type-metadata",["design","sleeve","cuff","type","type"],.string("float")),
            ("leaf-range-metadata",["design","sleeve","cuff","type","range"],.array([.string("Other")])),
            ("default-prob-metadata",["design","pencil-skirt","style_side_cut","default_prob"],.number(0.25)),
            ("missing-child-type",["design","sleeve","cuff","type"],nil),
            ("illegal-enum",["design","sleeve","cuff","type","v"],.string("UnknownCuff")),
            ("group-child-replaced-by-metadata",["design","sleeve","cuff","type"],.string("select")),
            ("unknown-child",["design","sleeve","cuff","unexpected"],.null),
            ("missing-value",["design","sleeve","cuff","type","v"],nil),
            ("missing-body-waist",["body","waist"],nil)]
        for (id,path,value) in mutations {
            let changed=try altered(path,value)
            var rejected=false
            do {_=try GarmentCodeJointParameters.restore(document:changed,catalog:catalog)} catch {rejected=true}
            try F.require(rejected,"Accepted altered source metadata/child/value: "+id)
            negatives.append(id)
        }
        // A legal changed control may restore, but cannot authenticate the old
        // geometry. Full regeneration remains a separate mandatory check.
        let mismatched=try altered(["design","sleeve","cuff","type","v"],.string("CuffSkirt"))
        let changed=try GarmentCodeJointParameters.restore(document:mismatched,catalog:catalog)
        let expected=try GarmentCodeNativeGenerator.generate(body:changed.body,design:changed.design)
        try F.require(try F.encoded(expected) != F.encoded(mismatched),"Legal parameter tampering was mistaken for source identity")
        negatives.append("legal-control-with-stale-geometry-fails-full-source-regeneration")
        return ["passed":true,"positiveActualCompleteSources":positives,"negativeControls":negatives,
            "catalogChildTypeGroups":childTypeGroups.sorted(),"catalogValueLeafCount":leafCount,
            "scope":"Parameter/source identity only; no 3D physical acceptance"]
    }
}
