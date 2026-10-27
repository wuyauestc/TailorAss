import Foundation
import CryptoKit

/// Complete native upper-only construction placement from fixed GarmentCode.
/// Independent paper panels and normals are preserved. No sewing, fitting,
/// collision, mass, support, material or physical acceptance is implied.
@MainActor
enum GarmentCodeUpperPlacement {
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias P=GarmentCodePoint
    typealias G=GarmentCodePanelGeometry
    typealias E=GarmentCodeGeometryEdge
    typealias Transform=GarmentCodePanelPlacement.Transform
    static let upstreamCommit="d449629979028123a5c4dc9e732a2ec19b7fce31"
    enum PlacementError:LocalizedError {
        case invalid(String),unsupported(String)
        var errorDescription:String? {switch self{case let .invalid(s),let .unsupported(s):return s}}
    }
    struct Panel {
        let mesh:GarmentCodePanelMesher.Mesh
        let transform:Transform
        let placed:GarmentCodePanelPlacement.PlacedPanel
    }
    struct Placement {
        let sourceSHA256:String
        let upstreamCommit:String
        let style:String
        let panels:[String:Panel]
        let warnings:[String]
    }
    struct SourcePanel {
        let transform:Transform
        /// One position for every original serialized source vertex. These
        /// are paper vertex IDs, not a triangulated or sewn simulation mesh.
        let sourceVertexPositions:[V]
        let fabricNormal:V
    }
    struct SourceMap {
        let sourceSHA256:String
        let upstreamCommit:String
        let style:String
        let panels:[String:SourcePanel]
    }
    /// Physical construction uses SciPy intrinsic XYZ (Rx*Ry*Rz); serialized
    /// meshgen subsequently uses Rz*Ry*Rx. They differ for the flat lapel back.
    /// anchor is the pre-serialization first source vertex in world cm.
    private struct State {
        var geometry:G
        var anchor:V
        var rx=0.0,ry=0.0,rz=0.0
        func rotate(_ p:V)->V {
            let x=rx * .pi/180,y=ry * .pi/180,z=rz * .pi/180
            let a=V(x:cos(z)*p.x-sin(z)*p.y,y:sin(z)*p.x+cos(z)*p.y,z:p.z)
            let b=V(x:cos(y)*a.x+sin(y)*a.z,y:a.y,z:-sin(y)*a.x+cos(y)*a.z)
            return .init(x:b.x,y:cos(x)*b.y-sin(x)*b.z,z:sin(x)*b.y+cos(x)*b.z)
        }
        func physical(_ p:P)->V {
            let first=geometry.edges[0].start
            return anchor+rotate(.init(x:p.x-first.x,y:p.y-first.y,z:0))
        }
    }
    private struct Box {
        var low:V,high:V
        var center:V{(low+high)/2}
        init(_ points:[V])throws {
            guard let first=points.first,points.allSatisfy(\.isFinite) else {throw PlacementError.invalid("上装组件边界为空或含非有限数值。")}
            low=first;high=first
            for p in points{low.x=min(low.x,p.x);low.y=min(low.y,p.y);low.z=min(low.z,p.z);high.x=max(high.x,p.x);high.y=max(high.y,p.y);high.z=max(high.z,p.z)}
        }
    }
    private struct Context {
        let body:GarmentCodeBodyParameters
        let design:GarmentCodeDesignParameters
        let cancelled:@Sendable()->Bool
        func value(_ key:String)throws->Double {guard let n=body[key],n.isFinite else{throw PlacementError.invalid("缺少上装人体尺寸 \(key)。")};return n}
        func number(_ path:[String])throws->Double {guard let n=design.value(at:path)?.numberValue,n.isFinite else{throw PlacementError.invalid("缺少上装参数 \(path.joined(separator:"."))。")};return n}
        func option(_ path:[String])->String? {if case let .string(s)?=design.value(at:path),!s.isEmpty{return s};return nil}
        func flag(_ path:[String])->Bool {design.value(at:path) == .bool(true)}
    }
    private struct Recipes {
        let sourceSHA256:String,style:String
        let geometry:[String:G],states:[String:State]
        let waist:Double
    }

    /// Source mapping is independent of later triangulation budgets. It never
    /// substitutes paper outlines for a failed cloth mesh: prepare() below
    /// still requires every real source mesh and reports a mesher failure.
    static func sourceMap(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                          design:GarmentCodeDesignParameters,
                          isCancelled:@escaping @Sendable()->Bool={false})throws->SourceMap {
        let r=try recipes(document:document,body:body,design:design,isCancelled:isCancelled)
        var panels:[String:SourcePanel]=[:]
        for id in r.geometry.keys.sorted() {
            if isCancelled(){throw CancellationError()}
            let transform=try transform(r.states[id]!,waist:r.waist)
            let vertices=try document.pattern.panels[id]!.vertices.map{try transform.point(.init(x:$0[0]/100,y:$0[1]/100,z:0))}
            let normal=try transform.direction(.init(x:0,y:0,z:r.geometry[id]!.signedArea<0 ? -1:1))
            panels[id] = .init(transform:transform,sourceVertexPositions:vertices,fabricNormal:normal)
        }
        return .init(sourceSHA256:r.sourceSHA256,upstreamCommit:upstreamCommit,style:r.style,panels:panels)
    }
    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                        design:GarmentCodeDesignParameters,targetEdgeMeters:Double=0.04,
                        isCancelled:@escaping @Sendable()->Bool={false})throws->Placement {
        guard targetEdgeMeters.isFinite,(0.005...0.10).contains(targetEdgeMeters) else {throw PlacementError.invalid("上装源网格目标边长无效。")}
        let r=try recipes(document:document,body:body,design:design,isCancelled:isCancelled)
        var result:[String:Panel]=[:],vertexCount=0
        for id in r.geometry.keys.sorted() {
            if isCancelled(){throw CancellationError()}
            let mesh:GarmentCodePanelMesher.Mesh
            do {mesh=try GarmentCodePanelMesher.prepare(panel:r.geometry[id]!,targetEdgeMeters:targetEdgeMeters,maximumVertices:6000,maximumTriangles:16000,isCancelled:isCancelled)}
            catch is CancellationError {throw CancellationError()}
            catch {throw PlacementError.invalid("上装裁片 \(id) 无法在当前预算内建立源网格：\(error)")}
            vertexCount += mesh.flatPositions.count
            guard vertexCount<=60_000 else {throw PlacementError.invalid("完整上装初始网格超过六万顶点预算。")}
            let transform=try transform(r.states[id]!,waist:r.waist)
            result[id] = .init(mesh:mesh,transform:transform,placed:try GarmentCodePanelPlacement.place(mesh:mesh,transform:transform,isCancelled:isCancelled))
        }
        return .init(sourceSHA256:r.sourceSHA256,upstreamCommit:upstreamCommit,style:r.style,panels:result,
                     warnings:["这是固定上游构造时的独立上装裁片初始摆放，尚未缝合、碰撞求解或验证成衣合体。","完整源裁片、原长和法向保留；上游人体姿态可能与本地人台不同。"])
    }
    private static func transform(_ state:State,waist:Double)throws->Transform {
        try Transform(rotationDegrees:[state.rx,state.ry,state.rz],translation:[state.anchor.x,state.anchor.y,state.anchor.z],unitsInMeter:100,waistLevelCentimeters:waist)
    }
    private static func recipes(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                                design:GarmentCodeDesignParameters,
                                isCancelled:@escaping @Sendable()->Bool)throws->Recipes {
        if isCancelled(){throw CancellationError()}
        guard case let .object(generator)?=document.properties?["tailorass_generator"],
              generator["upstream_commit"] == .string(upstreamCommit),generator["includes_3d_placement"] == .bool(false),
              document.parameters?["design"]==design.jsonValue,
              document.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),
              document.pattern.panels.count<=128,document.pattern.panels.values.reduce(0,{$0+$1.vertices.count})<=20_000 else {
            throw PlacementError.invalid("需要完整原生二维上装及精确人体、设计参数来源。")
        }
        let sourceHash=try hash(document),regenerated=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        guard try hash(regenerated)==sourceHash else {throw PlacementError.invalid("完整原生上装重生成的源 SHA-256 不一致。")}
        let context=Context(body:body,design:design,cancelled:isCancelled)
        guard let style=context.option(["meta","upper"]),["Shirt","FittedShirt"].contains(style),
              context.option(["meta","bottom"])==nil,context.option(["meta","wb"])==nil else {
            throw PlacementError.unsupported("该映射需要完整上装；含腰头或下装的组合须由整套映射处理，不能丢弃组件。")
        }
        let geometry=try document.geometryPanels(),fitted=style=="FittedShirt",asymmetric=context.flag(["left","enable_asym"])
        var states:[String:State]=[:]
        for side in ["right","left"] {
            if isCancelled(){throw CancellationError()}
            let left=side=="left",halfDesign=try halfDesign(design,left:left,asymmetric:asymmetric)
            let half=Context(body:body,design:halfDesign,cancelled:isCancelled)
            let ids=geometry.keys.filter{$0.hasPrefix(side+"_") || $0.hasPrefix("sl_"+side+"_")}
            var local=Dictionary(uniqueKeysWithValues:ids.map{($0,left ? unmirrored(geometry[$0]!):geometry[$0]!)})
            var component=try torso(side:side,geometry:local,fitted:fitted,c:half)
            let strapless=fitted && half.flag(["shirt","strapless"])
            if !strapless && !half.flag(["sleeve","sleeveless"]) {
                let sleeve=try sleeves(side:side,source:document,geometry:local,torso:component,left:left,c:half)
                component.merge(sleeve){_,b in b}
            }
            if !strapless,let collar=half.option(["collar","component","style"]) {
                component.merge(try collars(collar,side:side,geometry:local,c:half)){_,b in b}
            }
            guard Set(component.keys)==Set(ids) else {throw PlacementError.unsupported("上装半身存在未映射的真实领袖或袖口组件，不能省略。")}
            if left {
                for id in component.keys {
                    component[id]!.anchor.x *= -1;component[id]!.ry *= -1;component[id]!.rz *= -1
                    component[id]!.geometry=geometry[id]!
                }
            }
            states.merge(component){_,b in b};local.removeAll(keepingCapacity:false)
        }
        guard Set(states.keys)==Set(geometry.keys) else {throw PlacementError.unsupported("原生上装摆放没有覆盖全部源裁片。")}
        let waist=try context.value("_waist_level")
        return .init(sourceSHA256:sourceHash,style:style,geometry:geometry,states:states,waist:waist)
    }
    private static func hash(_ document:GarmentCodePatternFile)throws->String {
        try document.validateForPreview();let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let bytes=try e.encode(document);guard bytes.count<=32*1024*1024 else{throw PlacementError.invalid("规范化上装超过 32 MiB。")}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    private static func unmirrored(_ geometry:G)->G {
        var result=geometry
        result.edges=geometry.edges.reversed().map{$0.reversed().reflected(acrossLineFrom:.zero,to:.init(x:0,y:1))}
        return result
    }
    private static func halfDesign(_ design:GarmentCodeDesignParameters,left:Bool,asymmetric:Bool)throws->GarmentCodeDesignParameters {
        guard asymmetric else{return design}
        var root=design;_=root.setValue(.bool(false),at:["left","enable_asym"]);_=root.setValue(.null,at:["collar","component","style"])
        guard left else{return root}
        guard let parameters=design.design["left"],var shirt=parameters.children["shirt"],var collar=parameters.children["collar"],let sleeve=parameters.children["sleeve"],let rightShirt=design.design["shirt"],let rightCollar=design.design["collar"] else {throw PlacementError.invalid("左右不对称上装参数不完整。")}
        shirt.children["length"]=rightShirt.children["length"]
        collar.children["fc_depth"]=rightCollar.children["fc_depth"];collar.children["bc_depth"]=rightCollar.children["bc_depth"]
        collar.children["component"]=root.design["collar"]?.children["component"]
        root.design["shirt"]=shirt;root.design["collar"]=collar;root.design["sleeve"]=sleeve
        return root
    }
    private static func torso(side:String,geometry:[String:G],fitted:Bool,c:Context)throws->[String:State] {
        let h=try c.value("height")-c.value("head_l"),t=try tan(c.value("_shoulder_incl") * .pi/180)
        let f=try (c.value("bust")-c.value("back_width"))/2,b=try c.value("back_width")/2,s=try c.value("shoulder_w")/2
        let length=try c.number(["shirt","length"]),width=try c.number(["shirt","width"])
        var result:[String:State]=[:]
        for front in [true,false] {
            let id=side+(front ? "_ftorso":"_btorso")
            guard let g=geometry[id] else{throw PlacementError.invalid("缺少真实衣身 \(id)。")}
            let y:Double
            if fitted {
                let lf=try c.value("waist_over_bust_line")-t*(f-s),lb=try c.value("waist_line")-t*(b-s)
                y=front ? h-lf-t*f:h-lb-t*b+t*b/4
            } else {
                let lb=try length*c.value("waist_line"),lf=lb-t*(f-b)
                y=front ? h-lf-t*width*f:h-lb-t*width*b
            }
            result[id] = .init(geometry:g,anchor:.init(x:0,y:y,z:front ? 30:-25))
        }
        return result
    }
    private static func sleeves(side:String,source:GarmentCodePatternFile,geometry:[String:G],torso:[String:State],left:Bool,c:Context)throws->[String:State] {
        let h=try c.value("height")-c.value("head_l"),shoulder=try c.value("shoulder_w")/2
        var result:[String:State]=[:]
        let sleeveIDs=Set([side+"_sleeve_f",side+"_sleeve_b"]),torsoIDs=Set(torso.keys)
        for front in [true,false] {
            let id=side+(front ? "_sleeve_f":"_sleeve_b")
            guard let g=geometry[id],g.edges.count>=4 else {throw PlacementError.invalid("缺少真实袖片 \(id)。")}
            let closing=front ? g.edges.last!.start:g.edges.first!.end
            result[id] = .init(geometry:g,anchor:.init(x:-shoulder-Double(Int(closing.x)),y:h-Double(Int(closing.y)),z:front ? 15:-15))
        }
        if let cuff=c.option(["sleeve","cuff","type"]) {
            guard ["CuffBand","CuffSkirt","CuffBandSkirt"].contains(cuff) else {throw PlacementError.unsupported("未知真实袖口组件。")}
            var bands:[String:State]=[:],skirts:[String:State]=[:]
            for front in [true,false] {for (kind,enabled) in [("cuff",cuff != "CuffSkirt"),("cuff_skirt",cuff != "CuffBand")] where enabled {
                let id="sl_"+side+"_"+kind+(front ? "_f":"_b")
                guard let g=geometry[id] else {throw PlacementError.invalid("缺少真实袖口 \(id)。")}
                let xs=g.edges.map{$0.start.x},ys=g.edges.map{$0.start.y}
                let state=State(geometry:g,anchor:.init(x:-(xs.max()!-xs.min()!)/2,y:-Double(Int(ys.max()!-ys.min()!)),z:front ? 15:-15))
                if kind=="cuff"{bands[id]=state}else{skirts[id]=state}
            }}
            if cuff=="CuffBandSkirt" {try below(&skirts,other:bands,gap:2)}
            var component=bands.merging(skirts){_,b in b}
            let top=try topEdges(bands.isEmpty ? skirts:bands)
            try rotateZ(&component,degrees:-90)
            let out=[side+"_sleeve_f":[0],side+"_sleeve_b":[result[side+"_sleeve_b"]!.geometry.edges.count-1]]
            try place(&component,own:top,outStates:result,out:out,gap:2,alignmentTop:true)
            result.merge(component){_,b in b}
        }
        try rotateZ(&result,degrees:c.value("arm_pose_angle"))
        var own:[String:Set<Int>]=[:],out:[String:Set<Int>]=[:]
        for stitch in source.pattern.stitches {
            let a=stitch.sides[0],b=stitch.sides[1]
            let sleeve:GarmentCodeStitchSide,bodice:GarmentCodeStitchSide
            if sleeveIDs.contains(a.panel) && torsoIDs.contains(b.panel){sleeve=a;bodice=b}
            else if sleeveIDs.contains(b.panel) && torsoIDs.contains(a.panel){sleeve=b;bodice=a}
            else{continue}
            let si=left ? geometry[sleeve.panel]!.edges.count-1-sleeve.edge:sleeve.edge
            let bi=left ? geometry[bodice.panel]!.edges.count-1-bodice.edge:bodice.edge
            own[sleeve.panel,default:[]].insert(si);out[bodice.panel,default:[]].insert(bi)
        }
        guard Set(own.keys)==sleeveIDs,Set(out.keys)==torsoIDs else {throw PlacementError.invalid("袖片与衣身的真实源接口不完整。")}
        let gap=try -1-c.value("arm_pose_angle")/10
        try place(&result,own:own.mapValues{$0.sorted()},outStates:torso,out:out.mapValues{$0.sorted()},gap:gap,alignmentTop:true)
        return result
    }
    private static func collars(_ type:String,side:String,geometry:[String:G],c:Context)throws->[String:State] {
        let h=try c.value("height")-c.value("head_l"),depth=try c.number(["collar","component","depth"])
        var result:[String:State]=[:]
        if type=="Hood2Panels" {
            let id=side+"_hood"
            guard let g=geometry[id],let f=geometry[side+"_ftorso"]?.edges.first(where:{$0.label?.hasSuffix("_collar")==true}),let b=geometry[side+"_btorso"]?.edges.first(where:{$0.label?.hasSuffix("_collar")==true}) else {throw PlacementError.invalid("风帽及真实领口投影缺失。")}
            let half=abs(f.end.x-f.start.x),backDepth=abs(b.end.y-b.start.y)
            result[id] = .init(geometry:g,anchor:.init(x:-half,y:h+10-backDepth,z:-half),ry:-90)
            return result
        }
        guard ["Turtle","SimpleLapel"].contains(type) else{throw PlacementError.unsupported("未知真实领片组件。")}
        for front in [true,false] {
            let id=side+(front ? "_collar_front":"_collar_back")
            guard let g=geometry[id] else{throw PlacementError.invalid("真实领片缺失。")}
            let xs=g.edges.map{$0.start.x},width=xs.max()!-xs.min()!
            if type=="Turtle" {result[id] = .init(geometry:g,anchor:.init(x:-width,y:h+depth-Double(Int(depth)),z:front ? 10:-10))}
            else if front {result[id] = .init(geometry:g,anchor:.init(x:-2*depth,y:h+2*depth,z:35))}
            else if c.flag(["collar","component","lapel_standing"]) {result[id] = .init(geometry:g,anchor:.init(x:-width,y:h+2*depth-Double(Int(depth)),z:-10))}
            else {
                guard let top=g.edges.first,top.curvature?.type=="circle",let radius=top.curvature?.circle?.radius else{throw PlacementError.invalid("翻领后片的真实圆弧缺失。")}
                let length=top.length(tolerance:1e-10),p0=V(x:-abs(top.end.x-top.start.x)/2,y:0,z:0)
                guard radius>0 else {throw PlacementError.invalid("翻领后片圆弧半径无效。")}
                var state=State(geometry:g,anchor:.zero,rx:90,ry:45)
                state.anchor=V(x:-length,y:h+2*depth,z:-10)+state.rotate(p0);result[id]=state
            }
        }
        return result
    }
    private static func samples(_ edge:E)->[P] {
        guard edge.curvature != nil else{return [edge.start,edge.end]}
        if edge.curvature?.type=="circle"{return (0...10).map{edge.point(at:Double($0)/10)}}
        let length=edge.length(tolerance:1e-10)
        return (0...10).map{i in
            if i==0{return edge.start};if i==10{return edge.end}
            var lo=0.0,hi=1.0
            for _ in 0..<38{let mid=(lo+hi)/2;if edge.split(at:mid).0.length(tolerance:1e-10)<length*Double(i)/10{lo=mid}else{hi=mid}}
            return edge.point(at:(lo+hi)/2)
        }
    }
    private static func box(_ states:[String:State],edges:[String:[Int]]?=nil)throws->Box {
        var points:[V]=[]
        for id in states.keys.sorted(){let state=states[id]!,indices=edges?[id] ?? (edges==nil ? Array(state.geometry.edges.indices):[])
            for i in indices{guard state.geometry.edges.indices.contains(i) else{throw PlacementError.invalid("上装接口边索引无效。")};points += samples(state.geometry.edges[i]).map{state.physical($0)}}
        }
        return try Box(points)
    }
    private static func place(_ states:inout[String:State],own:[String:[Int]],outStates:[String:State],out:[String:[Int]],gap:Double,alignmentTop:Bool)throws {
        let a=try box(states,edges:own),b=try box(outStates,edges:out),full=try box(states)
        var pa=a.center,pb=b.center
        if alignmentTop{pa.y=a.high.y;pb.y=b.high.y}
        let direction=a.center-full.center
        guard direction.length>1e-10 else{throw PlacementError.invalid("上装组件无法确定原始接口间隔方向。")}
        let delta=pb-pa-direction*(gap/direction.length)
        for id in states.keys{states[id]!.anchor=states[id]!.anchor+delta}
    }
    private static func rotateZ(_ states:inout[String:State],degrees:Double)throws {
        let b=try box(states),pivot=V(x:b.center.x,y:b.high.y,z:b.center.z),a=degrees * .pi/180
        for id in states.keys {
            guard states[id]!.rx==0,states[id]!.ry==0 else{throw PlacementError.invalid("袖口组件含未经证明的复合旋转。")}
            let d=states[id]!.anchor-pivot
            states[id]!.anchor=pivot+V(x:cos(a)*d.x-sin(a)*d.y,y:sin(a)*d.x+cos(a)*d.y,z:d.z)
            states[id]!.rz += degrees
        }
    }
    private static func below(_ own:inout[String:State],other:[String:State],gap:Double)throws {
        let d=try box(other).low.y-box(own).high.y-gap
        for id in own.keys{own[id]!.anchor.y += d}
    }
    private static func topEdges(_ states:[String:State])throws->[String:[Int]] {
        var result:[String:[Int]]=[:]
        for (id,state) in states {
            let top=state.geometry.edges.map{$0.start.y}.max()!
            let edges=state.geometry.edges.indices.filter{abs(state.geometry.edges[$0].start.y-top)<1e-7 && abs(state.geometry.edges[$0].end.y-top)<1e-7}
            guard !edges.isEmpty else{throw PlacementError.invalid("袖口真实上缘缺失。")};result[id]=edges
        }
        return result
    }
}
