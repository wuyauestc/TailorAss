import Foundation
import CryptoKit

/// Native lower-garment construction placement from GarmentCode d4496299.
/// These are the upstream separated sheets, not a sewn or fitted garment.
/// Every source panel is retained. No particles, masses or supports are added.
@MainActor
enum GarmentCodeLowerPlacement {
    typealias K = GarmentCodeCircleDrape
    typealias V = K.Vector3
    typealias P = GarmentCodePoint
    typealias G = GarmentCodePanelGeometry
    typealias E = GarmentCodeGeometryEdge
    typealias Transform = GarmentCodePanelPlacement.Transform
    static let upstreamCommit = "d449629979028123a5c4dc9e732a2ec19b7fce31"
    enum PlacementError: LocalizedError {
        case invalid(String), unsupported(String)
        var errorDescription: String? {
            switch self {case let .invalid(s),let .unsupported(s):return s}
        }
    }
    struct Panel {
        let mesh: GarmentCodePanelMesher.Mesh
        let transform: Transform
        let placed: GarmentCodePanelPlacement.PlacedPanel
    }
    struct Placement {
        let sourceSHA256: String
        let upstreamCommit: String
        let style: String
        let panels: [String: Panel]
        let warnings: [String]
    }
    /// One native lower component before MetaGarment stacking. Unlike prepare,
    /// this read-only construction map does not triangulate or claim physics.
    struct ComponentMap {
        let document:GarmentCodePatternFile
        let sourceSHA256:String
        let style:String
        let transforms:[String:Transform]
        /// Non-nil only for explicit fitted-outfit construction; the source
        /// document is not claimed to be a default prepare() lower pattern.
        let constructionRiseOverride:Double?
    }
    static func componentMap(body:GarmentCodeBodyParameters,design:GarmentCodeDesignParameters,
        requestedRise:Double?=nil,isCancelled:@escaping @Sendable()->Bool={false})throws->ComponentMap {
        if isCancelled(){throw CancellationError()}
        let c=Context(body:body,design:design,cancelled:isCancelled)
        guard c.option(["meta","upper"])==nil,c.option(["meta","wb"])==nil,
              let style=c.option(["meta","bottom"]),
              ["Pants","Skirt2","PencilSkirt","SkirtCircle","AsymmSkirtCircle","SkirtManyPanels","GodetSkirt","SkirtLevels"].contains(style),
              requestedRise == nil || (style=="SkirtLevels" && requestedRise!.isFinite && (0...1).contains(requestedRise!)) else {
            throw PlacementError.invalid("只读构造映射需要完整独立下装；requestedRise 仅供层裙原生组合请求。")
        }
        let document:GarmentCodePatternFile
        if let requestedRise {
            let raw=try GarmentCodePrograms.skirtLevels(body:body,design:design,requestedRise:requestedRise)
            document = .init(pattern:raw.pattern,parameters:GarmentCodeNativeGenerator.provenance(body:body,design:design),
                parameterOrder:["design","body"],properties:raw.properties)
        }else{document=try GarmentCodeNativeGenerator.generate(body:body,design:design)}
        let source=try document.geometryPanels(),states=try lower(style,c,requestedRise:requestedRise)
        guard Set(source.keys)==Set(states.keys),source.count<=128,
              document.pattern.panels.values.reduce(0,{$0+$1.vertices.count})<=20_000 else {
            throw PlacementError.invalid("下装构造映射必须覆盖所有原始裁片并符合源预算。")
        }
        let waist=try c.value("_waist_level")
        var transforms:[String:Transform]=[:]
        for id in source.keys.sorted(){
            if isCancelled(){throw CancellationError()}
            let state=states[id]!
            guard state.geometry.edges[0].start.distance(to:source[id]!.edges[0].start)<1e-7 else {
                throw PlacementError.invalid("原生下装构造源首点不同，不能重新拟合。")
            }
            transforms[id]=try Transform(rotationDegrees:[0,state.ry,state.rz],
                translation:[state.anchor.x,state.anchor.y,state.anchor.z],unitsInMeter:100,waistLevelCentimeters:waist)
        }
        return .init(document:document,sourceSHA256:try canonicalHash(document),style:style,transforms:transforms,constructionRiseOverride:requestedRise)
    }
    /// anchor is the upstream pre-serialization first vertex in world cm.
    /// source XY already contains int(p0) subtraction. Subtract its fractional
    /// first vertex only for pre-assembly bbox/interface operations; the final
    /// meshgen transform deliberately retains upstream's fractional convention.
    private struct State {
        var geometry: G
        var anchor: V
        var ry = 0.0
        var rz = 0.0
        func rotate(_ p: V) -> V {
            let y=ry  * .pi/180,z=rz  * .pi/180
            let a=V(x:cos(y)*p.x+sin(y)*p.z,y:p.y,z:-sin(y)*p.x+cos(y)*p.z)
            return V(x:cos(z)*a.x-sin(z)*a.y,y:sin(z)*a.x+cos(z)*a.y,z:a.z)
        }
        func physical(_ p: P) -> V {
            let first=geometry.edges[0].start
            return anchor+rotate(.init(x:p.x-first.x,y:p.y-first.y,z:0))
        }
    }
    private struct Box {
        var min: V, max: V
        var center: V {(min+max)/2}
        init(_ points: [V]) throws {
            guard let first=points.first,points.allSatisfy(\.isFinite) else {throw PlacementError.invalid("初始摆放边界为空或含非有限数值。")}
            min=first;max=first
            for p in points {min.x=Swift.min(min.x,p.x);min.y=Swift.min(min.y,p.y);min.z=Swift.min(min.z,p.z);max.x=Swift.max(max.x,p.x);max.y=Swift.max(max.y,p.y);max.z=Swift.max(max.z,p.z)}
        }
    }
    private struct Context {
        let body: GarmentCodeBodyParameters
        let design: GarmentCodeDesignParameters
        let cancelled: @Sendable () -> Bool
        func value(_ key: String) throws -> Double {
            guard let n=body[key],n.isFinite else {throw PlacementError.invalid("缺少人体尺寸 \(key)。")};return n
        }
        func number(_ path: [String]) throws -> Double {
            guard let n=design.value(at:path)?.numberValue,n.isFinite else {throw PlacementError.invalid("缺少下装参数 \(path.joined(separator:".") )。")} ;return n
        }
        func option(_ path: [String]) -> String? {if case let .string(s)?=design.value(at:path),!s.isEmpty{return s};return nil}
    }

    static func prepare(document: GarmentCodePatternFile, body: GarmentCodeBodyParameters,
                        design: GarmentCodeDesignParameters, targetEdgeMeters: Double = 0.04,
                        isCancelled: @escaping @Sendable () -> Bool = {false}) throws -> Placement {
        if isCancelled() {throw CancellationError()}
        guard case let .object(generator)?=document.properties?["tailorass_generator"],
              generator["upstream_commit"] == .string(upstreamCommit),
              generator["includes_3d_placement"] == .bool(false),
              document.parameters?["design"] == design.jsonValue,
              document.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),
              targetEdgeMeters.isFinite,(0.005...0.10).contains(targetEdgeMeters) else {
            throw PlacementError.invalid("需要完整原生二维纸样及其精确人体、设计参数来源。")
        }
        guard document.pattern.panels.count<=128,document.pattern.panels.values.reduce(0,{$0+$1.vertices.count})<=20_000 else {throw PlacementError.invalid("下装源纸样超过摆放预算。")}
        let hash=try canonicalHash(document),regenerated=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        guard try canonicalHash(regenerated)==hash else {throw PlacementError.invalid("原生参数重生成的完整纸样与当前源 SHA-256 不同。")}
        let context=Context(body:body,design:design,cancelled:isCancelled)
        guard context.option(["meta","upper"])==nil,let style=context.option(["meta","bottom"]),
              ["Pants","Skirt2","PencilSkirt","SkirtCircle","AsymmSkirtCircle","SkirtManyPanels","GodetSkirt","SkirtLevels"].contains(style) else {
            throw PlacementError.unsupported("该映射需要完整下装及可选腰头；含上装的组合须由整套服装映射处理，不能丢弃上装。")
        }
        var states=try lower(style,context)
        if let waistband=context.option(["meta","wb"]) {
            let rise=try lowerRise(style,context)
            let wb=try band(waistband,rise:rise,context:context)
            let lowerIDs=Set(states.keys),wbIDs=Set(wb.keys)
            // Interfaces before MetaGarment appends its final stitching rule.
            let topStyle = style=="SkirtLevels" ? context.option(["levels-skirt","base"])! : style=="GodetSkirt" ? context.option(["godet-skirt","base"])! : style
            let top=try topEdges(states:states,style:topStyle)
            let bottom=try bandBottom(wb)
            try place(&states,own:top,outStates:wb,out:bottom,gap:5)
            guard lowerIDs.isDisjoint(with:wbIDs) else {throw PlacementError.invalid("下装与腰头裁片名重复。")}
            states.merge(wb){_,b in b}
        }
        let source=try document.geometryPanels()
        guard Set(states.keys)==Set(source.keys) else {throw PlacementError.unsupported("下装摆放必须覆盖完整源裁片集合，不能省略裤口、层裙或插片。")}
        let waist=try context.value("_waist_level")
        var result:[String:Panel]=[:],vertices=0
        for id in source.keys.sorted() {
            if isCancelled(){throw CancellationError()}
            let state=states[id]!,geometry=source[id]!
            guard state.geometry.edges[0].start.distance(to:geometry.edges[0].start)<1e-7 else {throw PlacementError.unsupported("裁片 \(id) 的序列化首点与已证明的组件来源不同。")}
            let transform=try Transform(rotationDegrees:[0,state.ry,state.rz],translation:[state.anchor.x,state.anchor.y,state.anchor.z],unitsInMeter:100,waistLevelCentimeters:waist)
            let mesh=try GarmentCodePanelMesher.prepare(panel:geometry,targetEdgeMeters:targetEdgeMeters,maximumVertices:6000,maximumTriangles:16000,isCancelled:isCancelled)
            vertices += mesh.flatPositions.count
            guard vertices<=60_000 else {throw PlacementError.invalid("完整下装初始网格超过六万顶点预算。")}
            result[id] = .init(mesh:mesh,transform:transform,placed:try GarmentCodePanelPlacement.place(mesh:mesh,transform:transform,isCancelled:isCancelled))
        }
        return .init(sourceSHA256:hash,upstreamCommit:upstreamCommit,style:style,panels:result,
                     warnings:["这是固定上游构造时的独立裁片初始摆放，尚未缝合、碰撞求解或验证成衣合体。","完整源裁片、原长和法向保留；上游初始人台姿态可能与本地标准人台不同。"])
    }

    private static func canonicalHash(_ document: GarmentCodePatternFile) throws -> String {
        try document.validateForPreview();let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let bytes=try e.encode(document);guard bytes.count<=32*1024*1024 else {throw PlacementError.invalid("规范化纸样超过 32 MiB。")}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    private static func bare(_ style:String,_ c:Context,length:Double?=nil,tag:String="",topRuffles:Bool=true,rise:Double?=nil) throws -> [String:G] {
        var d=c.design;_=d.setValue(.string(style),at:["meta","bottom"])
        if let rise {let section=style=="PencilSkirt" ? "pencil-skirt":style=="Skirt2" ? "skirt":"flare-skirt";_=d.setValue(.number(rise),at:[section,"rise"])}
        let file:GarmentCodePatternFile
        switch style {
        case "Pants":file=try GarmentCodePrograms.pants(body:c.body,design:d)
        case "PencilSkirt":file=try GarmentCodePrograms.pencilSkirt(body:c.body,design:d,requestedTotalLength:length)
        case "Skirt2":file=try GarmentCodePrograms.twoPanelSkirt(body:c.body,design:d,lengthOverride:length,tag:tag,topRuffles:topRuffles)
        case "SkirtCircle":file=try GarmentCodePrograms.circleSkirt(body:c.body,design:d,requestedLength:length)
        case "AsymmSkirtCircle":file=try GarmentCodePrograms.asymmetricCircleSkirt(body:c.body,design:d,requestedLength:length)
        case "SkirtManyPanels":file=try GarmentCodePrograms.manyPanelSkirt(body:c.body,design:d)
        default:throw PlacementError.unsupported("没有已验证的下装组件 \(style)。")
        }
        var geometry=try file.geometryPanels()
        if !tag.isEmpty && style != "Skirt2" {
            geometry=Dictionary(uniqueKeysWithValues:geometry.map{key,value in var g=value;g.id=key+tag;return(key+tag,g)})
        }
        return geometry
    }
    private static func lower(_ style:String,_ c:Context,requestedRise:Double?=nil) throws -> [String:State] {
        if c.cancelled(){throw CancellationError()}
        if style=="GodetSkirt" {return try godet(c)}
        if style=="SkirtLevels" {return try levels(c,requestedRise:requestedRise)}
        let geometry=try bare(style,c)
        if style=="Pants" {return try pants(geometry,c)}
        if style=="SkirtManyPanels" {return try many(geometry,c)}
        return try skirt(style,geometry,c)
    }
    private static func skirt(_ style:String,_ geometry:[String:G],_ c:Context,length:Double?=nil,rise:Double?=nil) throws -> [String:State] {
        let waist=try c.value("_waist_level")
        var result:[String:State]=[:]
        for (id,g) in geometry {
            let front=id.hasPrefix("skirt_front"),z=style.contains("Circle") ? (front ? 15.0:-15.0):(front ? 25.0:-20.0)
            let anchor:V
            if style.contains("Circle") {
                let e=try circleTop(g,front:front)
                anchor = .init(x:-abs(e.end.x-e.start.x)/2,y:waist,z:z)
            } else if style=="Skirt2" {
                let xs=g.edges.map{$0.start.x},ys=g.edges.map{$0.start.y}
                anchor = .init(x:-Double(Int((xs.max()!-xs.min()!)/2)),y:waist-Double(Int(ys.max()!-ys.min()!)),z:z)
            } else {
                let r=try rise ?? c.number(["pencil-skirt","rise"]),depth=r * (try c.value("hips_line")) * (front ? 1:1.05)
                let hips=try (front ? c.value("hips")-c.value("hip_back_width"):c.value("hip_back_width"))/2
                let low=try c.value("hips")*(c.number(["pencil-skirt","flare"])-1)/4+hips
                let angle=try tan(c.number(["pencil-skirt","low_angle"]) * .pi/180)*low
                let l=try length.map{$0-r*(try c.value("hips_line"))} ?? c.number(["pencil-skirt","length"])*c.value("_leg_length")
                anchor = .init(x:hips-low-Double(Int(hips)),y:waist+angle-Double(Int(max(l+depth,abs(angle)))),z:z)
            }
            result[id] = .init(geometry:g,anchor:anchor)
        }
        return result
    }
    private static func pants(_ geometry:[String:G],_ c:Context) throws -> [String:State] {
        let rise=try c.number(["pants","rise"]),hipDepth=rise*(try c.value("hips_line")),waist=try c.value("_waist_level")
        let cuff=c.option(["pants","cuff","type"]),requested=try c.number(["pants","length"])
        let minimum=c.design.design["pants"]?.children["length"]?.range?.compactMap(\.numberValue).min() ?? 0.2
        let cuffRatio=try cuff==nil ? 0:min(c.number(["pants","cuff","cuff_len"]),requested-minimum)
        let length=try (requested-cuffRatio)*c.value("_leg_length"),difference=try c.value("crotch_hip_diff")
        let frontHip=try (c.value("hips")-c.value("hip_back_width"))/2
        let frontExtension=frontHip/4,total=try (c.value("leg_circ")-c.value("hips")/2+5)*c.number(["pants","width"])
        let flare=try c.value("leg_circ")*(c.number(["pants","flare"])-1)/4
        var right:[String:State]=[:]
        for front in [true,false] {
            let id=front ? "pant_f_r":"pant_b_r",hips=try front ? frontHip:c.value("hip_back_width")/2
            let ext=front ? frontExtension:total-frontExtension,depth=hipDepth*(front ? 1:1.1)
            guard let g=geometry[id] else {throw PlacementError.invalid("缺少真实裤片 \(id)。")}
            right[id] = .init(geometry:g,anchor:.init(x:-0.5-flare-Double(Int(hips+ext)),y:waist-depth-difference-Double(Int(length-difference)),z:front ? 25:-20))
        }
        if let cuff {
            var bands:[String:State]=[:],skirts:[String:State]=[:]
            for front in [true,false] {
                let ending=front ? "f":"b"
                for (kind,enabled) in [("cuff",cuff != "CuffSkirt"),("cuff_skirt",cuff != "CuffBand")] where enabled {
                    let id="pant_r_\(kind)_\(ending)";guard let g=geometry[id] else {throw PlacementError.invalid("缺少真实裤口组件 \(id)。")}
                    let xs=g.edges.map{$0.start.x},ys=g.edges.map{$0.start.y}
                    let state=State(geometry:g,anchor:.init(x:-(xs.max()!-xs.min()!)/2,y:-Double(Int(ys.max()!-ys.min()!)),z:front ? 15:-15))
                    if kind=="cuff" {bands[id]=state}else{skirts[id]=state}
                }
            }
            if cuff=="CuffBandSkirt" {try below(&skirts,bands,gap:2)}
            var component=bands.merging(skirts){_,b in b}
            let own=try horizontalEdges(bands.isEmpty ? skirts:bands,top:true),out=try hemEdges(right)
            try place(&component,own:own,outStates:right,out:out,gap:5,alignLeft:true)
            right.merge(component){_,b in b}
        }
        var result=right
        for (id,state) in right {
            let left=id.replacingOccurrences(of:"_r",with:"_l")
            guard let g=geometry[left] else {throw PlacementError.invalid("缺少对应左裤片 \(left)。")}
            result[left] = .init(geometry:g,anchor:.init(x:-state.anchor.x,y:state.anchor.y,z:state.anchor.z))
        }
        return result
    }
    private static func many(_ geometry:[String:G],_ c:Context) throws -> [String:State] {
        let n=Int(try c.number(["flare-skirt","skirt-many-panels","n_panels"]))
        let r=try c.number(["flare-skirt","rise"]),waist=try c.value("hips")*(1-r)+c.value("waist")*r
        let length=try max(r*c.value("hips_line")+c.number(["flare-skirt","length"])*c.value("_leg_length"),5)
        let top=waist/Double(n),bottom=try top*(1+c.number(["flare-skirt","suns"])*length*2 * .pi/waist),flare=(bottom-top)/2
        guard let first=geometry["skirt_panel_0"] else {throw PlacementError.invalid("多片裙缺少首裁片。")}
        let distance=first.edges[0].length(tolerance:1e-10)/(2*tan(.pi/Double(n))),angle = -90+atan2(top/2,distance)*180 / .pi
        let natural=try c.value("_waist_level"),p0=V(x:-Double(Int(flare)),y:-Double(Int(length)),z:0)
        var result:[String:State]=[:]
        for i in 0..<n {
            let id="skirt_panel_\(i)";guard let g=geometry[id] else {throw PlacementError.invalid("多片裙裁片缺失。")}
            let theta=Double(i)*360/Double(n),t=theta * .pi/180
            let base=V(x:-distance*cos(t),y:natural,z:distance*sin(t))
            var state=State(geometry:g,anchor:.zero,ry:angle+theta)
            state.anchor=base+state.rotate(p0);result[id]=state
        }
        return result
    }

    // Component placement helpers intentionally reproduce upstream bbox
    // sampling (nine internal curve vertices; Bezier samples by arc length).
    private static func samples(_ edge:E) -> [P] {
        guard edge.curvature != nil else {return [edge.start,edge.end]}
        if edge.curvature?.type=="circle" {return (0...10).map{edge.point(at:Double($0)/10)}}
        let length=edge.length(tolerance:1e-10)
        return (0...10).map {i in
            if i==0{return edge.start};if i==10{return edge.end}
            var lo=0.0,hi=1.0
            for _ in 0..<38 {let mid=(lo+hi)/2;if edge.split(at:mid).0.length(tolerance:1e-10)<length*Double(i)/10 {lo=mid}else{hi=mid}}
            return edge.point(at:(lo+hi)/2)
        }
    }
    private static func box(_ states:[String:State],edges:[String:[Int]]?=nil) throws -> Box {
        var points:[V]=[]
        for id in states.keys.sorted() {
            let s=states[id]!,indices=edges?[id] ?? (edges==nil ? Array(s.geometry.edges.indices):[])
            for index in indices {guard s.geometry.edges.indices.contains(index) else {throw PlacementError.invalid("摆放接口引用无效。")};points += samples(s.geometry.edges[index]).map{s.physical($0)}}
        }
        return try Box(points)
    }
    private static func place(_ own:inout[String:State],own ownEdges:[String:[Int]],outStates:[String:State],out:[String:[Int]],gap:Double,alignLeft:Bool=false) throws {
        let a=try box(own,edges:ownEdges),b=try box(outStates,edges:out),full=try box(own)
        var pa=a.center,pb=b.center
        if alignLeft {pa.x=a.max.x;pb.x=b.max.x}
        let direction=a.center-full.center
        guard direction.length>1e-10 else {throw PlacementError.invalid("组件接口无法确定上游间隔方向。")}
        let delta=pb-pa-direction*(gap/direction.length)
        for id in own.keys {own[id]!.anchor=own[id]!.anchor+delta}
    }
    private static func below(_ own:inout[String:State],_ other:[String:State],gap:Double) throws {
        let shift=try box(other).min.y-box(own).max.y-gap
        for id in own.keys {own[id]!.anchor.y += shift}
    }
    private static func horizontalEdges(_ states:[String:State],top:Bool) throws -> [String:[Int]] {
        var result:[String:[Int]]=[:]
        for (id,s) in states {
            let y=(top ? s.geometry.edges.map{$0.start.y}.max():s.geometry.edges.map{$0.start.y}.min())!
            let indices=s.geometry.edges.indices.filter{abs(s.geometry.edges[$0].start.y-y)<1e-7 && abs(s.geometry.edges[$0].end.y-y)<1e-7}
            if !indices.isEmpty {result[id]=indices}
        }
        guard !result.isEmpty else {throw PlacementError.invalid("没有真实水平组件接口。")};return result
    }
    private static func hemEdges(_ states:[String:State]) throws -> [String:[Int]] {
        var result:[String:[Int]]=[:]
        for (id,s) in states {
            guard let edge=s.geometry.edges.indices.min(by:{s.geometry.edges[$0].start.y+s.geometry.edges[$0].end.y < s.geometry.edges[$1].start.y+s.geometry.edges[$1].end.y}) else {throw PlacementError.invalid("没有真实下摆接口。")}
            result[id]=[edge]
        }
        return result
    }
    private static func circleTop(_ g:G,front:Bool) throws -> E {
        let edge=front ? g.edges.last!:g.edges.first!
        guard edge.curvature?.type=="circle" else {throw PlacementError.invalid("圆裙真实腰口弧未找到。")};return edge
    }
    private static func topEdges(states:[String:State],style:String,rootOnly:Bool=true) throws -> [String:[Int]] {
        let base=rootOnly ? states.filter{!$0.key.hasPrefix("ins_") && !$0.key.contains("_cuff") && !$0.key.hasSuffix("_0") && !$0.key.hasSuffix("_1") && !$0.key.hasSuffix("_2") && !$0.key.hasSuffix("_3") && !$0.key.hasSuffix("_4")}:states
        if style=="SkirtManyPanels" {return Dictionary(uniqueKeysWithValues:states.keys.map{($0,[2])})}
        if style.contains("Circle") {return Dictionary(uniqueKeysWithValues:base.map{($0.key,[$0.key.contains("front") ? $0.value.geometry.edges.count-1:0])})}
        return try horizontalEdges(base,top:true)
    }
    private static func lowerRise(_ style:String,_ c:Context) throws -> Double {
        let section=style=="Pants" ? "pants":style=="PencilSkirt" ? "pencil-skirt":style=="SkirtLevels" ? "levels-skirt":style=="GodetSkirt" ? (c.option(["godet-skirt","base"])=="PencilSkirt" ? "pencil-skirt":"skirt"):style=="Skirt2" ? "skirt":"flare-skirt"
        return try c.number([section,"rise"])
    }
    private static func band(_ style:String,rise:Double,context c:Context) throws -> [String:State] {
        guard ["StraightWB","FittedWB"].contains(style) else {throw PlacementError.unsupported("未知腰头组件。")}
        let geometry=try GarmentCodePrograms.waistband(body:c.body,design:c.design,rise:rise).geometryPanels(),natural=try c.value("_waist_level")
        var result:[String:State]=[:]
        for (id,g) in geometry {
            let front=id=="wb_front",anchor:V
            if style=="FittedWB" {let e=try circleTop(g,front:front);anchor = .init(x:-abs(e.end.x-e.start.x)/2,y:natural,z:front ? 20:-15)}
            else {let xs=g.edges.map{$0.start.x},ys=g.edges.map{$0.start.y};anchor = .init(x:-(xs.max()!-xs.min()!)/2,y:natural-Double(Int(ys.max()!-ys.min()!)),z:front ? 20:-15)}
            result[id] = .init(geometry:g,anchor:anchor)
        }
        return result
    }
    private static func bandBottom(_ states:[String:State]) throws -> [String:[Int]] {
        var result:[String:[Int]]=[:]
        for (id,s) in states {let curved=s.geometry.edges.contains{$0.curvature?.type=="circle"};result[id]=[curved ? (id=="wb_front" ? 1:2):(id=="wb_front" ? 0:s.geometry.edges.count-1)]}
        return result
    }
    private static func godet(_ c:Context) throws -> [String:State] {
        guard let style=c.option(["godet-skirt","base"]),["Skirt2","PencilSkirt"].contains(style) else {throw PlacementError.unsupported("未知 GodetSkirt 底裙组件。")}
        // Upstream suppresses base slits. Check the actual geometry instead of
        // permanently forbidding the parameter: once that 2D branch is fixed,
        // the same complete source provenance will pass without a special case.
        let complete=try GarmentCodePrograms.godetSkirt(body:c.body,design:c.design)
        if style=="PencilSkirt" {
            var suppressed=c.design
            for key in ["front_slit","back_slit","left_slit","right_slit"] {_=suppressed.setValue(.number(0),at:["pencil-skirt",key])}
            let expected=try GarmentCodePrograms.godetSkirt(body:c.body,design:suppressed)
            guard try canonicalHash(complete)==canonicalHash(expected) else {
                throw PlacementError.unsupported("GodetSkirt 上游会关闭底裙开衩；当前原生底裙几何尚未遵守该分支。")
            }
        }
        var baseDesign=c.design;_=baseDesign.setValue(.string(style),at:["meta","bottom"])
        _=baseDesign.setValue(.number(0),at:["skirt","bottom_cut"])
        let baseContext=Context(body:c.body,design:baseDesign,cancelled:c.cancelled)
        for key in ["front_slit","back_slit","left_slit","right_slit"] {_=baseDesign.setValue(.number(0),at:["pencil-skirt",key])}
        let suppressedContext=Context(body:c.body,design:baseDesign,cancelled:c.cancelled)
        let seed=try bare(style,suppressedContext),full=try complete.geometryPanels()
        var result=try skirt(style,seed,baseContext)
        let width=try c.number(["godet-skirt","insert_w"]),depth=try c.number(["godet-skirt","insert_depth"]),n=Int(try c.number(["godet-skirt","num_inserts"]))/2
        for name in ["skirt_front","skirt_back"] {
            guard let state=result[name],let actual=full[name] else {throw PlacementError.invalid("GodetSkirt 缺少完整底裙。")}
            let b=try box([name:state]),z=state.anchor.z+(state.anchor.z<0 ? -5:5)
            result[name]!.geometry=actual
            for i in 0..<n {
                let id="ins_\(name)_\(i)";guard let g=full[id] else {throw PlacementError.invalid("GodetSkirt 真实插片缺失。")}
                result[id] = .init(geometry:g,anchor:.init(x:b.center.x-Double(n)*width/2+Double(i)*width,y:b.min.y+depth-Double(Int(depth)),z:z))
            }
        }
        guard Set(result.keys)==Set(full.keys) else {throw PlacementError.invalid("GodetSkirt 组件不能被丢弃。")}
        return result
    }
    private static func levels(_ c:Context,requestedRise:Double?=nil) throws -> [String:State] {
        guard let baseStyle=c.option(["levels-skirt","base"]),let tierStyle=c.option(["levels-skirt","level"]) else {throw PlacementError.invalid("层裙缺少真实组件类型。")}
        let total=try c.number(["levels-skirt","length"])*c.value("_leg_length"),fraction=try c.number(["levels-skirt","base_length_frac"])
        let designRise=try c.number(["levels-skirt","rise"]),rise=requestedRise ?? designRise
        let baseLength=try total*fraction+c.value("hips_line")*designRise
        let count=Int(try c.number(["levels-skirt","num_levels"])),tierLength=total*(1-fraction)/Double(count),ruffle=try c.number(["levels-skirt","level_ruffle"])
        var baseDesign=c.design
        _=baseDesign.setValue(.number(0),at:["skirt","bottom_cut"]);_=baseDesign.setValue(.bool(false),at:["flare-skirt","cut","add"])
        for key in ["front_slit","back_slit","left_slit","right_slit"] {_=baseDesign.setValue(.number(0),at:["pencil-skirt",key])}
        let baseContext=Context(body:c.body,design:baseDesign,cancelled:c.cancelled)
        let baseGeometry=try bare(baseStyle,baseContext,length:baseLength,rise:rise)
        var result=try skirt(baseStyle,baseGeometry,baseContext,length:baseLength,rise:rise)
        var previous=result,previousStyle=baseStyle,levelBody=c.body
        let angle=try baseStyle=="PencilSkirt" ? c.number(["pencil-skirt","low_angle"]):0
        for i in 0..<count {
            if c.cancelled(){throw CancellationError()}
            let bottom=try skirtBottom(previous,style:previousStyle)
            var frontLength=0.0,backLength=0.0
            for (name,indices) in bottom {
                let sum=indices.reduce(0){$0+previous[name]!.geometry.edges[$1].length(tolerance:1e-10)}
                if name.hasPrefix("skirt_front") {frontLength += sum}else{backLength += sum}
            }
            levelBody.set(ruffle*(frontLength+backLength),for:"waist");levelBody.set(ruffle*backLength,for:"waist_back_width")
            let levelContext=Context(body:levelBody,design:baseDesign,cancelled:c.cancelled)
            let geometry=try bare(tierStyle,levelContext,length:tierLength,tag:"_\(i)",topRuffles:false)
            var tier=try skirt(tierStyle,geometry,levelContext,length:tierLength)
            if angle != 0 {
                let b=try box(tier),pivot=V(x:b.center.x,y:b.max.y,z:b.center.z),a = -angle  * .pi/180
                for id in tier.keys {
                    let delta=tier[id]!.anchor-pivot
                    tier[id]!.anchor=pivot+V(x:cos(a)*delta.x-sin(a)*delta.y,y:sin(a)*delta.x+cos(a)*delta.y,z:delta.z)
                    tier[id]!.rz = -angle
                }
            }
            try place(&tier,own:topEdges(states:tier,style:tierStyle,rootOnly:false),outStates:previous,out:bottom,gap:5)
            result.merge(tier){_,b in b};previous=tier;previousStyle=tierStyle
        }
        return result
    }
    private static func skirtBottom(_ states:[String:State],style:String) throws -> [String:[Int]] {
        var result:[String:[Int]]=[:]
        for (id,s) in states {
            let front=id.hasPrefix("skirt_front")
            result[id]=[style.contains("Circle") ? (front ? 1:2):(front ? 0:s.geometry.edges.count-1)]
        }
        return result
    }
}
