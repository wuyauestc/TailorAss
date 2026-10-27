import Foundation

/// Test-only source definitions. Existing fixture overrides remain authoritative;
/// the supplement enumerates catalog choices with their actual parent enabled.
@MainActor enum NativeCatalogCases {
    struct Edit: Codable {
        let path: [String]
        let value: JSONValue
        init(_ path: [String], _ value: JSONValue) { self.path=path; self.value=value }
    }
    struct Case {
        let id: String
        let profile: String
        let body: [String:Double]
        let edits: [Edit]
        let origins: [String]
        let tags: [String]
        let historicalFailure: String?
    }
    struct Definitions {
        let cases: [Case]
        let baseline211IDs: Set<String>
        let sourceMesh27IDs: Set<String>
        let profiles: [String:[String:Double]]
        let discretePaths: [[String]]
    }
    enum DefinitionError: Error { case invalid(String) }
    struct Female: Decodable { let body:[String:Double]; let patterns:[String:JSONValue] }
    struct Upper: Decodable {
        struct Item: Decodable { let id:String; let body:[String:Double]; let overrides:[Edit] }
        struct Failure: Decodable { let id:String; let error:String }
        let cases:[Item]; let nativeReplayFailures:[Failure]
    }
    struct Composition: Decodable {
        struct Item: Decodable { let id:String; let bodyName:String; let overrides:[Edit] }
        let bodies:[String:[String:Double]]; let cases:[Item]
    }
    struct Lower: Decodable {
        struct Item: Decodable { let id:String; let overrides:[Edit] }
        let body:[String:Double]; let cases:[Item]
    }
    struct Baseline: Decodable { let cases:[String:[String:String]] }
    static let fixtureNames=["meta-grid-defaults.json","meta-grid-female.json","upper-placement-oracles.json",
        "native-assembly-levels-oracles.json","composition-rise-oracles.json","lower-branch-oracles.json",
        "native-initialization-three-mode-goldens.json"]
    static let discretePaths:[[String]]=[
        ["collar","f_collar"],["collar","b_collar"],["collar","component","style"],
        ["sleeve","armhole_shape"],["sleeve","cuff","type"],["pants","cuff","type"],
        ["left","collar","f_collar"],["left","collar","b_collar"],
        ["left","sleeve","armhole_shape"],["left","sleeve","cuff","type"],
        ["levels-skirt","base"],["levels-skirt","level"],["godet-skirt","base"],
        ["godet-skirt","num_inserts"],["pencil-skirt","style_side_cut"],
        ["flare-skirt","skirt-many-panels","panel_curve"]]

    static func load(root:URL,catalog:GarmentCodeParameterCatalog)throws->Definitions {
        let fixtures=root.appendingPathComponent("Tests/NativePattern/Fixtures")
        func read<T:Decodable>(_ name:String,_ type:T.Type)throws->T {
            try JSONDecoder().decode(type,from:Data(contentsOf:fixtures.appendingPathComponent(name)))
        }
        let female=try read("meta-grid-female.json",Female.self)
        let profiles=["default":catalog.body,"female":female.body]
        var catalogSelectPaths:Set<String>=[]
        func visit(_ node:GarmentCodeParameterNode,_ path:[String]) {
            if node.type=="select" || node.type=="select_null",path.first != "meta" {
                catalogSelectPaths.insert(path.joined(separator:"."))
            }
            for (key,child) in node.children {visit(child,path+[key])}
        }
        for (key,node) in catalog.design {visit(node,[key])}
        guard catalogSelectPaths==Set(discretePaths.map{$0.joined(separator:".")}) else {
            throw DefinitionError.invalid("Select-path inventory changed; explicitly enable each new component consumer")
        }
        let baseline=try read("native-initialization-three-mode-goldens.json",Baseline.self)
        guard baseline.cases.count==211,SourceMeshCaseDefinitions.cases().count==27 else {
            throw DefinitionError.invalid("The existing 211 / 27 definition inventory changed; review coverage explicitly")
        }
        var cases:[Case]=[]
        func add(_ id:String,_ profile:String,_ edits:[Edit],origin:String,tags:[String]=[],body:[String:Double]?=nil,historical:String?=nil) {
            cases.append(.init(id:id,profile:profile,body:body ?? profiles[profile]!,edits:edits,
                origins:[origin],tags:tags,historicalFailure:historical))
        }
        func selection(_ upper:String?=nil,_ band:String?=nil,_ bottom:String?=nil)->[Edit] {
            [.init(["meta","upper"],upper.map(JSONValue.string) ?? .null),
             .init(["meta","wb"],band.map(JSONValue.string) ?? .null),
             .init(["meta","bottom"],bottom.map(JSONValue.string) ?? .null)]
        }
        let male=try read("meta-grid-defaults.json",[String:JSONValue].self)
        for profile in profiles.keys.sorted() {
            let file=profile=="default" ? "meta-grid-defaults" : "meta-grid-female"
            let patterns=profile=="default" ? male : female.patterns
            guard patterns.count==80 else {throw DefinitionError.invalid(file+" no longer contains 80 original definitions")}
            for key in patterns.keys.sorted() {
                let options=key.components(separatedBy:"|")
                guard options.count==3 else {throw DefinitionError.invalid("Malformed original meta ID "+key)}
                let values=options.map{$0=="None" ? nil : $0}
                add(file+":"+key,profile,selection(values[0],values[1],values[2]),origin:file+".json",tags:["original-meta-grid"])
            }
        }
        let upper=try read("upper-placement-oracles.json",Upper.self)
        for item in upper.cases {
            let profile=item.id.hasPrefix("female-") ? "female" : "default"
            add("upper:"+item.id,profile,item.overrides,origin:"upper-placement-oracles.json",tags:["original-upper"],
                body:item.body,historical:upper.nativeReplayFailures.first{$0.id==item.id}?.error)
        }
        for (file,prefix) in [("native-assembly-levels-oracles.json","levels-rise:"),("composition-rise-oracles.json","composition-rise:")] {
            let fixture=try read(file,Composition.self)
            for item in fixture.cases {
                guard let body=fixture.bodies[item.bodyName],profiles[item.bodyName] != nil else {throw DefinitionError.invalid("Unknown original body "+item.bodyName)}
                add(prefix+item.id,item.bodyName,item.overrides,origin:file,tags:["original-composition-rise"],body:body)
            }
        }
        let lower=try read("lower-branch-oracles.json",Lower.self)
        for profile in profiles.keys.sorted() {
            for item in lower.cases {
                add("lower-branch:"+profile+":"+item.id,profile,selection()+item.overrides,
                    origin:"lower-branch-oracles.json",tags:[profile=="default" ? "original-lower" : "cross-profile-replay"],
                    body:profile=="default" ? lower.body : profiles[profile])
            }
            for item in SourceMeshCaseDefinitions.cases() {
                add("source-mesh:"+profile+":"+item.id,profile,
                    selection(item.upper,item.waistband,item.bottom)+item.changes.map{Edit($0.0,$0.1)},
                    origin:"SourceMeshCaseDefinitions.swift",tags:["original-27","source-mesh-definition-only"])
            }
            for cuff in ["CuffBand","CuffSkirt","CuffBandSkirt"] {
                let id=profile=="default" ? "pants:"+cuff : "pants:female:"+cuff
                add(id,profile,selection(nil,"StraightWB","Pants")+[
                    .init(["pants","cuff","type"],.string(cuff)),.init(["pants","cuff","top_ruffle"],.number(1.2)),
                    .init(["pants","cuff","skirt_ruffle"],.number(1.3))],origin:"NativeAssembly.swift:pants",
                    tags:[profile=="default" ? "original-211-pants" : "cross-profile-replay"])
            }
        }
        func options(_ path:[String])throws->[JSONValue] {
            guard let values=catalog.node(at:path)?.range,!values.isEmpty else {throw DefinitionError.invalid("Missing catalog options "+path.joined(separator:"."))}
            return values
        }
        func label(_ value:JSONValue)throws->String {
            let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
            return String(decoding:try e.encode(value),as:UTF8.self).replacingOccurrences(of:"\"",with:"")
        }
        for profile in profiles.keys.sorted() {
            // The left subtree is a real independent selector catalog. Enable
            // asymmetry so these choices reach the native constructor rather
            // than counting inactive left defaults as component coverage.
            for upperStyle in ["Shirt","FittedShirt"] {
                let asym=selection(upperStyle)+[Edit(["left","enable_asym"],.bool(true))]
                for neck in try options(["left","collar","f_collar"]) {
                    add("discrete:"+profile+":left-neck:"+upperStyle+":"+(try label(neck)),profile,
                        asym+[.init(["left","collar","f_collar"],neck),.init(["left","collar","b_collar"],neck)],
                        origin:"catalog:left-neck",tags:["discrete","asymmetric-left"])
                }
                for armhole in try options(["left","sleeve","armhole_shape"]) {
                    add("discrete:"+profile+":left-armhole:"+upperStyle+":"+(try label(armhole)),profile,
                        asym+[.init(["left","sleeve","sleeveless"],.bool(false)),.init(["left","sleeve","armhole_shape"],armhole)],
                        origin:"catalog:left-armhole",tags:["discrete","asymmetric-left"])
                }
                for cuff in try options(["left","sleeve","cuff","type"]) {
                    add("discrete:"+profile+":left-cuff:"+upperStyle+":"+(try label(cuff)),profile,
                        asym+[.init(["left","sleeve","sleeveless"],.bool(false)),.init(["left","sleeve","length"],.number(0.6)),
                              .init(["left","sleeve","cuff","type"],cuff)],
                        origin:"catalog:left-cuff",tags:["discrete","asymmetric-left"])
                }
                for leftSide in [false,true] {
                    let prefix=leftSide ? ["left"] : []
                    for flip in [false,true] {
                        var edits=selection(upperStyle)
                        if leftSide {edits.append(.init(["left","enable_asym"],.bool(true)))}
                        edits += [.init(prefix+["collar","f_collar"],.string("CurvyNeckHalf")),
                            .init(prefix+["collar","b_collar"],.string("CurvyNeckHalf")),
                            .init(prefix+["collar","f_flip_curve"],.bool(flip)),
                            .init(prefix+["collar","b_flip_curve"],.bool(flip))]
                        add("feature:"+profile+":neck-flip:"+upperStyle+":"+(leftSide ? "left" : "right")+":"+String(flip),
                            profile,edits,origin:"catalog:neck-flip",tags:["boolean-branch","neck-curve"])
                    }
                }
            }
            // This is the full 4 x 3 tier matrix, including catalog combinations
            // formerly excluded by 3D placement tests. A source failure is kept.
            for base in try options(["levels-skirt","base"]) {
                for level in try options(["levels-skirt","level"]) {
                    add("discrete:"+profile+":levels:"+(try label(base))+":"+(try label(level)),profile,
                        selection(nil,nil,"SkirtLevels")+[
                            .init(["levels-skirt","base"],base),.init(["levels-skirt","level"],level),
                            .init(["levels-skirt","num_levels"],.number(3))],origin:"catalog:levels-skirt.base×level",
                        tags:["discrete","tiers-3"])
                }
            }
            for base in try options(["godet-skirt","base"]) {
                for count in try options(["godet-skirt","num_inserts"]) {
                    add("discrete:"+profile+":godet:"+(try label(base))+":"+(try label(count)),profile,
                        selection(nil,nil,"GodetSkirt")+[
                            .init(["godet-skirt","base"],base),.init(["godet-skirt","num_inserts"],count)],
                        origin:"catalog:godet-skirt.base×num_inserts",tags:["discrete","inserts"])
                }
            }
            for curve in try options(["flare-skirt","skirt-many-panels","panel_curve"]) {
                add("discrete:"+profile+":many-curve:"+(try label(curve)),profile,selection(nil,nil,"SkirtManyPanels")+[
                    .init(["flare-skirt","skirt-many-panels","panel_curve"],curve)],origin:"catalog:many-panel-curve",tags:["discrete"])
            }
            for cut in try options(["pencil-skirt","style_side_cut"]) {
                for style in ["PencilSkirt","GodetSkirt","SkirtLevels"] {
                    var edits=selection(nil,nil,style)+[.init(["pencil-skirt","style_side_cut"],cut)]
                    if style=="GodetSkirt" {edits.append(.init(["godet-skirt","base"],.string("PencilSkirt")))}
                    if style=="SkirtLevels" {edits.append(.init(["levels-skirt","base"],.string("PencilSkirt")))}
                    add("discrete:"+profile+":side-cut:"+style+":"+(try label(cut)),profile,edits,
                        origin:"Smoke.swift:side-cut-compositions/catalog",tags:["discrete","side-cut"])
                }
            }
            // One-variable range endpoints, with the consumer enabled. These
            // are selected boundaries, not exhaustive continuous combinations.
            let boundaries:[(String,[String],[Edit])]=[
                ("SkirtCircle",["flare-skirt","suns"],[]),
                ("AsymmSkirtCircle",["flare-skirt","suns"],[]),
                ("SkirtManyPanels",["flare-skirt","skirt-many-panels","n_panels"],[]),
                ("SkirtLevels",["levels-skirt","num_levels"],[]),
                ("SkirtLevels",["levels-skirt","level_ruffle"],[.init(["levels-skirt","num_levels"],.number(3))]),
                ("Skirt2",["skirt","ruffle"],[]),
                ("PencilSkirt",["pencil-skirt","flare"],[]),
                ("Pants",["pants","rise"],[])]
            for (style,path,extra) in boundaries {
                let range=try options(path)
                for (endpoint,value) in [("min",range.first!),("max",range.last!)] {
                    add("boundary:"+profile+":"+path.joined(separator:".")+":"+style+":"+endpoint,
                        profile,selection(nil,nil,style)+extra+[.init(path,value)],origin:"catalog:range-endpoints",tags:["selected-boundary"])
                }
            }
            for style in ["SkirtCircle","AsymmSkirtCircle"] {
                add("feature:"+profile+":"+style+":cut",profile,
                    selection(nil,nil,style)+[.init(["flare-skirt","cut","add"],.bool(true))],
                    origin:"LowerPlacement.swift:circle-cut",tags:["cut-enabled"])
            }
        }
        let ids=cases.map(\.id)
        guard ids.count<=2048,Set(ids).count==ids.count else {throw DefinitionError.invalid("Duplicate IDs or >2048 source definitions")}
        let required=Set(baseline.cases.keys)
        guard required.isSubset(of:Set(ids)) else {throw DefinitionError.invalid("Missing original 211 definitions: "+required.subtracting(ids).sorted().joined(separator:","))}
        return .init(cases:cases.sorted{$0.id<$1.id},baseline211IDs:required,
            sourceMesh27IDs:Set(SourceMeshCaseDefinitions.cases().map(\.id)),profiles:profiles,discretePaths:discretePaths)
    }
}
