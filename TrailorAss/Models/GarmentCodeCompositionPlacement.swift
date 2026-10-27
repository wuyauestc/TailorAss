import Foundation
import CryptoKit

/// Compose already established native component placements using the complete
/// paper's real connecting interfaces. This produces separated construction
/// sheets; it does not sew, fit, support or simulate the garment.
enum GarmentCodeCompositionPlacement {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias Transform=GarmentCodePanelPlacement.Transform
    typealias Geometry=GarmentCodePanelGeometry
    typealias Edge=GarmentCodeGeometryEdge

    nonisolated enum Kind:String,Codable,Sendable,CaseIterable {
        case upper,waistband,lower
    }
    nonisolated struct Component:Sendable {
        let kind:Kind
        /// These are the component's own construction transforms, before the
        /// MetaGarment adds its inter-component translation.
        let transforms:[String:Transform]
    }
    nonisolated struct Bounds:Codable,Sendable {
        let minimum:V,maximum:V
        var center:V {(minimum+maximum)/2}
        init(points:[V])throws {
            guard let first=points.first,points.allSatisfy({$0.isFinite && $0.length<100}) else {
                throw PlacementError.invalid("组件边界为空、超出范围或含非有限坐标。")
            }
            var lo=first,hi=first
            for p in points {
                lo.x=min(lo.x,p.x);lo.y=min(lo.y,p.y);lo.z=min(lo.z,p.z)
                hi.x=max(hi.x,p.x);hi.y=max(hi.y,p.y);hi.z=max(hi.z,p.z)
            }
            minimum=lo;maximum=hi
        }
    }
    nonisolated struct EdgeReference:Codable,Hashable,Sendable {
        let panelID:String,edgeIndex:Int
    }
    nonisolated struct Step:Codable,Sendable {
        let movingComponent:Kind,targetComponent:Kind
        let movingInterface:[EdgeReference],targetInterface:[EdgeReference]
        let movingBounds:Bounds,movingInterfaceBounds:Bounds,targetInterfaceBounds:Bounds
        let translationMeters:V
    }
    nonisolated struct Placement:Sendable {
        let sourceSHA256:String
        let transforms:[String:Transform]
        let steps:[Step]
        let warnings:[String]
    }
    nonisolated enum PlacementError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded(String)
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "成衣初始组合无效：\(s)"
            case let .budgetExceeded(s):return "成衣初始组合超过预算：\(s)"
            }
        }
    }

    /// Native source identity is checked for the entire outfit, including
    /// components whose interfaces were split during pattern generation.
    @MainActor static func prepare(document:GarmentCodePatternFile,
        body:GarmentCodeBodyParameters,design:GarmentCodeDesignParameters,
        components:[Component],gapMeters:Double=0.05,
        isCancelled:@Sendable()->Bool={false})throws->Placement {
        if isCancelled(){throw CancellationError()}
        guard document.parameters?["design"]==design.jsonValue,
              document.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),
              case let .object(provenance)?=document.properties?["tailorass_generator"],
              provenance["upstream_commit"] == .string("d449629979028123a5c4dc9e732a2ec19b7fce31"),
              provenance["includes_3d_placement"] == .bool(false),
              let waist=body["_waist_level"],waist.isFinite,
              gapMeters.isFinite,abs(gapMeters)<=1 else {
            throw PlacementError.invalid("需要完整原生纸样及其精确人体、设计与有限构造间隔。")
        }
        let sourceHash=try hash(document)
        let regenerated=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        guard try hash(regenerated)==sourceHash else {
            throw PlacementError.invalid("完整参数重生成纸样与源 SHA-256 不符。")
        }
        var expected:[Kind]=[]
        for (kind,key) in [(Kind.upper,"upper"),(.waistband,"wb"),(.lower,"bottom")] {
            if case let .string(value)?=design.value(at:["meta",key]),!value.isEmpty {expected.append(kind)}
        }
        guard !expected.isEmpty,components.map(\.kind)==expected else {
            throw PlacementError.invalid("组件必须完整并按上衣、腰头、下装顺序提供，不能省略或重复。")
        }
        let geometry=try document.geometryPanels()
        let construction=try constructionGeometry(body:body,design:design,components:components)
        guard geometry.count<=128,document.pattern.stitches.count<=4096 else {
            throw PlacementError.budgetExceeded("源裁片或真实接缝数量过多。")
        }
        var transforms:[String:Transform]=[:],membership:[String:Int]=[:]
        for (i,component) in components.enumerated() {
            guard !component.transforms.isEmpty else {throw PlacementError.invalid("组件没有源裁片。")}
            for id in component.transforms.keys.sorted() {
                guard geometry[id] != nil,membership[id]==nil,
                      component.transforms[id]!.translationMeters.length<100,
                      abs(component.transforms[id]!.waistLevelMeters-waist/100)<1e-12 else {
                    throw PlacementError.invalid("裁片归属重复、源片缺失或坐标腰位不一致。")
                }
                membership[id]=i;transforms[id]=component.transforms[id]!
            }
        }
        guard Set(transforms.keys)==Set(geometry.keys) else {
            throw PlacementError.invalid("组合没有覆盖每一片原始裁片。")
        }
        var own=Array(repeating:Set<EdgeReference>(),count:components.count)
        var target=Array(repeating:Set<EdgeReference>(),count:components.count)
        for (ordinal,stitch) in document.pattern.stitches.enumerated() {
            if ordinal%64==0,isCancelled(){throw CancellationError()}
            guard stitch.sides.count==2,let a=membership[stitch.sides[0].panel],
                  let b=membership[stitch.sides[1].panel] else {throw PlacementError.invalid("真实接缝引用无效。")}
            if a==b {continue}
            guard abs(a-b)==1 else {throw PlacementError.invalid("源接缝跨越了非相邻组件，不能推测构造接口。")}
            let moving=max(a,b),movingSide=a==moving ? stitch.sides[0]:stitch.sides[1]
            let targetSide=a==moving ? stitch.sides[1]:stitch.sides[0]
            own[moving].insert(.init(panelID:movingSide.panel,edgeIndex:movingSide.edge))
            target[moving].insert(.init(panelID:targetSide.panel,edgeIndex:targetSide.edge))
        }
        func sorted(_ refs:Set<EdgeReference>)->[EdgeReference] {
            refs.sorted {$0.panelID==$1.panelID ? $0.edgeIndex<$1.edgeIndex:$0.panelID<$1.panelID}
        }
        var steps:[Step]=[]
        for i in components.indices.dropFirst() {
            if isCancelled(){throw CancellationError()}
            guard !own[i].isEmpty,!target[i].isEmpty else {throw PlacementError.invalid("相邻组件缺少真实连接接口。")}
            let all=components[i].transforms.keys.sorted().flatMap {id in
                construction[id]!.edges.indices.map{EdgeReference(panelID:id,edgeIndex:$0)}
            }
            let ownRefs=sorted(own[i]),targetRefs=sorted(target[i])
            // Upstream stacks the original component interfaces before the
            // connector subdivides them. Sampling the later cut arcs changes
            // their bbox and therefore their translation, especially when a
            // curved waistband is joined to many skirt panels.
            let ownConstruction=try constructionInterface(ownRefs,full:geometry,original:construction,isCancelled:isCancelled)
            let targetConstruction=try constructionInterface(targetRefs,full:geometry,original:construction,isCancelled:isCancelled)
            let full=try bounds(all,geometry:construction,transforms:transforms,isCancelled:isCancelled)
            let a=try bounds(ownConstruction,geometry:construction,transforms:transforms,isCancelled:isCancelled)
            let b=try bounds(targetConstruction,geometry:construction,transforms:transforms,isCancelled:isCancelled)
            let direction=a.center-full.center
            guard direction.length>1e-12 else {throw PlacementError.invalid("真实接口不能确定组件外侧方向。")}
            // Exact upstream center alignment and normalized gap direction,
            // including nonzero X/Z offsets of asymmetric components.
            let delta=b.center-a.center-direction*(gapMeters/direction.length)
            for id in components[i].transforms.keys.sorted() {
                let t=transforms[id]!,p=t.translationMeters+delta
                transforms[id]=try Transform(rotationDegrees:t.rotationDegrees,
                    translation:[p.x,p.y,p.z],unitsInMeter:1,waistLevelCentimeters:waist)
            }
            steps.append(.init(movingComponent:components[i].kind,targetComponent:components[i-1].kind,
                movingInterface:ownRefs,targetInterface:targetRefs,movingBounds:full,
                movingInterfaceBounds:a,targetInterfaceBounds:b,translationMeters:delta))
        }
        if isCancelled(){throw CancellationError()}
        return .init(sourceSHA256:sourceHash,transforms:transforms,steps:steps,
            warnings:["组合保留完整原始裁片，按真实接口移动独立组件；尚未缝合或进行人体受力仿真。"])
    }

    @MainActor private static func hash(_ document:GarmentCodePatternFile)throws->String {
        try document.validateForPreview()
        let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let data=try e.encode(document)
        guard data.count<=32*1024*1024 else {throw PlacementError.budgetExceeded("完整源纸样超过 32 MiB。")}
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    @MainActor private static func constructionGeometry(body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,components:[Component])throws->[String:Geometry] {
        var result:[String:Geometry]=[:]
        let fitted=design.value(at:["meta","upper"]) == .string("FittedShirt")
        var lowerDesign=design
        _=lowerDesign.setValue(.null,at:["meta","upper"])
        _=lowerDesign.setValue(.null,at:["meta","wb"])
        let lowerName=design.value(at:["meta","bottom"])
        let section:String
        switch lowerName {
        case .string("Pants"):section="pants"
        case .string("PencilSkirt"):section="pencil-skirt"
        case .string("Skirt2"):section="skirt"
        case .string("SkirtLevels"):section="levels-skirt"
        case .string("GodetSkirt"):
            section=design.value(at:["godet-skirt","base"]) == .string("PencilSkirt") ? "pencil-skirt":"skirt"
        default:section="flare-skirt"
        }
        if fitted {_=lowerDesign.setValue(.number(1),at:[section,"rise"])}
        let hasLower=components.contains{$0.kind == .lower}
        for component in components {
            let source:GarmentCodePatternFile
            switch component.kind {
            case .upper:
                var d=design;_=d.setValue(.null,at:["meta","wb"]);_=d.setValue(.null,at:["meta","bottom"])
                source=try GarmentCodeNativeGenerator.generate(body:body,design:d)
            case .lower:
                if fitted,lowerName == .string("SkirtLevels") {
                    // The requested base rise changes while the original
                    // design rise still participates in base-length math.
                    source=try GarmentCodePrograms.skirtLevels(body:body,design:design,requestedRise:1)
                } else {
                    source=try GarmentCodeNativeGenerator.generate(body:body,design:lowerDesign)
                }
            case .waistband:
                let rise=hasLower ? lowerDesign.value(at:[section,"rise"])?.numberValue:1
                source=try GarmentCodePrograms.waistband(body:body,design:design,rise:rise)
            }
            let panels=try source.geometryPanels()
            guard Set(panels.keys)==Set(component.transforms.keys) else {
                throw PlacementError.invalid("原始构造组件与完整源裁片归属不符。")
            }
            for (id,panel) in panels {guard result[id]==nil else {throw PlacementError.invalid("构造源裁片重复。")};result[id]=panel}
        }
        return result
    }
    @MainActor private static func constructionInterface(_ refs:[EdgeReference],full:[String:Geometry],
        original:[String:Geometry],isCancelled:@Sendable()->Bool)throws->[EdgeReference] {
        var selected:[EdgeReference]=[]
        // This tolerance only identifies which unchanged original edge was
        // subdivided. No point, control, source length or bbox is adjusted.
        let identificationToleranceCentimeters=0.0001
        for id in Set(refs.map(\.panelID)).sorted() {
            guard let g=original[id],let f=full[id],let first=g.edges.first?.start,
                  let fullFirst=f.edges.first?.start else {throw PlacementError.invalid("接口缺少完整构造源。")}
            let portions=try refs.filter{$0.panelID==id}.map{ref -> Edge in
                guard f.edges.indices.contains(ref.edgeIndex) else {throw PlacementError.invalid("接口源边越界。")}
                return f.edges[ref.edgeIndex]
            }
            var indices:[Int]=[]
            for index in g.edges.indices {
                if isCancelled(){throw CancellationError()}
                let edge=g.edges[index]
                let probes=[0.0,0.25,0.5,0.75,1.0].map {t -> GarmentCodePoint in
                    let p=edge.point(at:t)
                    return .init(x:p.x-first.x+fullFirst.x,y:p.y-first.y+fullFirst.y)
                }
                if probes.allSatisfy({p in portions.contains{distance(p,to:$0)<identificationToleranceCentimeters}}) {
                    indices.append(index);selected.append(.init(panelID:id,edgeIndex:index))
                }
            }
            guard !indices.isEmpty else {throw PlacementError.invalid("真实分段接口没有匹配的原始完整边。")}
            for portion in portions {
                let p=portion.point(at:0.5)
                let originalPoint=GarmentCodePoint(x:p.x-fullFirst.x+first.x,y:p.y-fullFirst.y+first.y)
                guard indices.contains(where:{distance(originalPoint,to:g.edges[$0])<identificationToleranceCentimeters}) else {
                    throw PlacementError.invalid("连接接口只覆盖原边的一部分，不能猜测原始构造范围。")
                }
            }
        }
        return selected
    }
    @MainActor private static func distance(_ p:GarmentCodePoint,to edge:Edge)->Double {
        if edge.curvature==nil {
            let dx=edge.end.x-edge.start.x,dy=edge.end.y-edge.start.y,l=dx*dx+dy*dy
            let t=l>0 ? max(0,min(1,((p.x-edge.start.x)*dx+(p.y-edge.start.y)*dy)/l)):0
            return hypot(p.x-edge.start.x-t*dx,p.y-edge.start.y-t*dy)
        }
        func squared(_ t:Double)->Double {let q=edge.point(at:t);return (p.x-q.x)*(p.x-q.x)+(p.y-q.y)*(p.y-q.y)}
        var best=0
        for i in 1...64 {if squared(Double(i)/64)<squared(Double(best)/64) {best=i}}
        var lo=Double(max(0,best-1))/64,hi=Double(min(64,best+1))/64
        for _ in 0..<50 {
            let a=lo+(hi-lo)/3,b=hi-(hi-lo)/3
            if squared(a)<squared(b) {hi=b}else{lo=a}
        }
        return sqrt(min(squared((lo+hi)/2),squared(0),squared(1)))
    }
    @MainActor private static func bounds(_ refs:[EdgeReference],geometry:[String:Geometry],
        transforms:[String:Transform],isCancelled:@Sendable()->Bool)throws->Bounds {
        guard !refs.isEmpty,refs.count<=65_536 else {throw PlacementError.budgetExceeded("接口边数量无效。")}
        var points:[V]=[]
        for (i,ref) in refs.enumerated() {
            if i%16==0,isCancelled(){throw CancellationError()}
            guard let g=geometry[ref.panelID],g.edges.indices.contains(ref.edgeIndex),
                  let t=transforms[ref.panelID],let first=g.edges.first?.start else {
                throw PlacementError.invalid("接口没有对应真实源边。")
            }
            // Upstream component bounds precede serialization's fractional
            // p0 offset. Meshgen later retains that offset in the paper.
            for q in try samples(g.edges[ref.edgeIndex],isCancelled:isCancelled) {
                points.append(try t.point(.init(x:(q.x-first.x)/100,y:(q.y-first.y)/100,z:0)))
            }
            guard points.count<=100_000 else {throw PlacementError.budgetExceeded("组件边界采样点过多。")}
        }
        return try Bounds(points:points)
    }
    @MainActor private static func samples(_ edge:Edge,isCancelled:@Sendable()->Bool)throws->[GarmentCodePoint] {
        guard edge.curvature != nil else {return [edge.start,edge.end]}
        if edge.curvature?.type=="circle" {return (0...10).map{edge.point(at:Double($0)/10)}}
        let length=edge.length(tolerance:1e-10)
        guard length.isFinite,length>0 else {throw PlacementError.invalid("构造接口曲线长度无效。")}
        return try (0...10).map {i in
            if i==0{return edge.start};if i==10{return edge.end}
            var lo=0.0,hi=1.0
            for iteration in 0..<38 {
                if iteration%8==0,isCancelled(){throw CancellationError()}
                let mid=(lo+hi)/2
                if edge.split(at:mid).0.length(tolerance:1e-10)<length*Double(i)/10 {lo=mid}else{hi=mid}
            }
            return edge.point(at:(lo+hi)/2)
        }
    }
}
