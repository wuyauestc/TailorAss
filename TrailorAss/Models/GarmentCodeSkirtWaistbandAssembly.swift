import Foundation

/// Four real paper panels, connected by the source waistband/skirt stitches.
/// Component previews are layout seeds only; the final plan and validation
/// always refer to the complete, unchanged composed document.
@MainActor
enum GarmentCodeSkirtWaistbandAssembly {
    typealias Kernel = GarmentCodeCircleDrape
    typealias Sewing = GarmentCodeSewing
    typealias Sewn = GarmentCodeSewnDrape
    typealias Builder = GarmentCodeAssemblyBuilder
    typealias Vector3 = Kernel.Vector3
    typealias Mesh = GarmentCodePanelMesher.Mesh

    nonisolated enum InitialPlacement:String,Codable,Sendable {
        /// Initially align the complete source waist onto the band lower edge.
        case connectedCone
        /// Keep each circular panel's original angular metric, translate the
        /// component below the real band and let sewing close the initial gap.
        case componentMetricSeed
    }

    private struct Arc {
        let center: Vector3
        let radius: Double
        let start: Double
        let delta: Double
        func coordinates(_ p: Vector3) -> (Double,Double) {
            let q=p-center
            var theta=atan2(q.y,q.x)
            let middle=start+delta/2
            while theta-middle>Double.pi { theta -= 2*Double.pi }
            while theta-middle < -Double.pi { theta += 2*Double.pi }
            return ((theta-start)/delta,hypot(q.x,q.y)-radius)
        }
    }

    private struct Seed {
        let mesh: Mesh
        let positions: [Vector3]
        /// Evaluate the component's piecewise affine initial placement. A new
        /// analytic boundary point may lie up to the old flattening error
        /// outside that old polygon, so only that bounded margin is accepted.
        func sample(_ p: Vector3) throws -> Vector3 {
            var bestDistance=Double.infinity,best:Vector3?
            for t in stride(from:0,to:mesh.triangleIndices.count,by:3) {
                let ids=(0..<3).map {Int(mesh.triangleIndices[t+$0])}
                let a=mesh.flatPositions[ids[0]],b=mesh.flatPositions[ids[1]],c=mesh.flatPositions[ids[2]]
                let u=b-a,v=c-a,q=p-a,det=u.x*v.y-u.y*v.x
                guard abs(det)>1e-18 else {continue}
                let beta=(q.x*v.y-q.y*v.x)/det,gamma=(u.x*q.y-u.y*q.x)/det
                var weights=[1-beta-gamma,beta,gamma]
                if weights.allSatisfy({$0>=(-1e-10)}) {
                    return (0..<3).reduce(.zero) {$0+positions[ids[$1]]*weights[$1]}
                }
                weights=weights.map {max(0,$0)}
                let sum=weights.reduce(0,+);weights=weights.map {$0/sum}
                let source=(0..<3).reduce(Vector3.zero) {$0+mesh.flatPositions[ids[$1]]*weights[$1]}
                let distance=(source-p).length
                if distance<bestDistance {
                    bestDistance=distance
                    best=(0..<3).reduce(.zero) {$0+positions[ids[$1]]*weights[$1]}
                }
            }
            guard let best,bestDistance<=max(1e-8,mesh.maximumBoundaryDeviationMeters*2+1e-9) else {
                throw Kernel.DrapeError.invalid("局部细分点不能对应原始组件的完整源网格。")
            }
            return best
        }
    }

    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                        settings:Kernel.Settings,
                        initialPlacement:InitialPlacement = .connectedCone,
                        isCancelled:@Sendable()->Bool={false}) throws -> Sewn.PreparedInput {
        if isCancelled() {throw CancellationError()}
        let sourceHash=try Sewn.canonicalSourceSHA256(document:document)
        let geometry=try document.geometryPanels()
        let bandNames=["wb_front","wb_back"],skirtNames=["skirt_front","skirt_back"]
        guard Set(geometry.keys)==Set(bandNames+skirtNames),document.pattern.stitches.count==6 else {
            throw Kernel.DrapeError.unsupported("腰头与圆裙装配需要完整的四片源纸样和六组接缝，不能省略其他组件。")
        }
        let straight=bandNames.allSatisfy {name in geometry[name]!.edges.allSatisfy {$0.curvature==nil}}
        let bandTop=straight ? [2,1] : [3,0],bandBottom=straight ? [0,3] : [1,2]
        let bandSides=straight ? [[3,0],[1,2]] : [[0,3],[2,1]]
        let skirtTop=[3,0],skirtHem=[1,2]
        func edgeKey(_ panel:String,_ edge:Int)->Sewing.EdgeKey {.init(panelID:panel,edgeIndex:edge)}
        func pair(_ a:Sewing.EdgeKey,_ b:Sewing.EdgeKey)->String {
            ["\(a.panelID):\(a.edgeIndex)","\(b.panelID):\(b.edgeIndex)"].sorted().joined(separator:"|")
        }
        var expected=Set<String>()
        for sides in bandSides {expected.insert(pair(edgeKey(bandNames[0],sides[0]),edgeKey(bandNames[1],sides[1])))}
        for sides in [[0,3],[2,1]] {expected.insert(pair(edgeKey(skirtNames[0],sides[0]),edgeKey(skirtNames[1],sides[1])))}
        for i in 0..<2 {expected.insert(pair(edgeKey(bandNames[i],bandBottom[i]),edgeKey(skirtNames[i],skirtTop[i])))}
        var actual=Set<String>()
        for stitch in document.pattern.stitches {
            guard stitch.sides.count==2,!stitch.rightWrong else {
                throw Kernel.DrapeError.unsupported("腰头与圆裙当前需要明确的普通正反面配对，不能猜测扭转或反缝。")
            }
            let key=pair(edgeKey(stitch.sides[0].panel,stitch.sides[0].edge),edgeKey(stitch.sides[1].panel,stitch.sides[1].edge))
            guard actual.insert(key).inserted else {throw Kernel.DrapeError.invalid("组合源接缝被重复使用。")}
        }
        guard actual==expected else {throw Kernel.DrapeError.unsupported("组合源接缝不是已知的完整腰头侧缝、圆裙侧缝和对应腰口连接。")}

        func component(_ names:[String]) -> GarmentCodePatternFile {
            let selected=Set(names)
            return .init(pattern:.init(panels:document.pattern.panels.filter {selected.contains($0.key)},
                stitches:document.pattern.stitches.filter {$0.sides.allSatisfy {selected.contains($0.panel)}},
                panelOrder:names),parameters:document.parameters,parameterOrder:document.parameterOrder,properties:document.properties)
        }
        // The component hashes never leave these layout seeds. No component
        // plan is reused as proof of the original four-panel source document.
        let band=try GarmentCodeWaistbandAssembly.prepare(document:component(bandNames),body:body,settings:settings,isCancelled:isCancelled)
        let skirt=try GarmentCodeCircleAssembly.prepare(document:component(skirtNames),body:body,settings:settings,isCancelled:isCancelled)
        guard let standard=band.cloth.standardBody else {throw Kernel.DrapeError.invalid("组合缺少同源标准人体。")}
        var seeds:[String:Seed]=[:]
        for prepared in [band,skirt] {
            for binding in prepared.panelBindings {
                seeds[binding.mesh.panelID] = .init(mesh:binding.mesh,positions:binding.vertexIDs.map {prepared.cloth.positions[$0]})
            }
        }
        let knownNative=try isKnownNative(document:document,body:body,hash:sourceHash)
        var hints:[Sewing.StitchHint]=[],hasEase=false
        for (index,stitch) in document.pattern.stitches.enumerated() {
            let a=edgeKey(stitch.sides[0].panel,stitch.sides[0].edge),b=edgeKey(stitch.sides[1].panel,stitch.sides[1].edge)
            let lengthA=geometry[a.panelID]!.edges[a.edgeIndex].length()/100
            let lengthB=geometry[b.panelID]!.edges[b.edgeIndex].length()/100
            let connector=bandNames.contains(a.panelID) != bandNames.contains(b.panelID)
            let intent:Sewing.Intent
            if abs(lengthA-lengthB)<=1e-5 {intent = .ordinary}
            else {
                guard connector,knownNative else {
                    throw Kernel.DrapeError.unsupported("不等长腰口需要可复核的原生款式接口吃势意图；不能对未知导入纸样按长度猜测或缩短源边。")
                }
                hasEase=true
                intent = .eased(longerSide:lengthA>lengthB ? .a : .b,maximumLengthRatio:max(lengthA,lengthB)/min(lengthA,lengthB)+1e-8)
            }
            hints.append(.init(stitchIndex:index,seamID:"circle-waistband-\(index)",a:a,b:b,
                aDirection:.forward,bDirection:.reverse,rightWrong:stitch.rightWrong,intent:intent,
                maximumTackSpacingMeters:0.06,minimumFreeBoundaryNodes:1))
        }
        let arcs=try skirtNames.enumerated().map {i,name in try arc(geometry[name]!.edges[skirtTop[i]])}
        let depths=try skirtNames.enumerated().map {i,name in try arc(geometry[name]!.edges[skirtHem[i]]).radius-arcs[i].radius}
        let slope=arcs.reduce(0.0) {$0+abs($1.delta)}/(2*Double.pi)
        guard (0.1-1e-7...1+1e-7).contains(slope),depths.allSatisfy({$0>=0.05-1e-9 && $0<=1.5+1e-9}) else {
            throw Kernel.DrapeError.unsupported("组合圆裙原始展开量或径向裙长超出可验证范围。")
        }
        var overrides:[String:[Int:Double]]=[:]
        for attempt in 0..<5 {
            if isCancelled() {throw CancellationError()}
            var panels:[Builder.Panel]=[]
            for (i,name) in bandNames.enumerated() {
                let seed=seeds[name]!
                let mesh=try remesh(name,geometry:geometry,seeds:seeds,overrides:overrides,settings:settings,isCancelled:isCancelled)
                let fixed=Set(mesh.boundaries[bandTop[i]].vertexIDs)
                let placed=try mesh.flatPositions.enumerated().map {local,p -> Vector3 in
                    let world=try seed.sample(p)
                    return fixed.contains(local) ? world : standard.project(world,thickness:0.0025)
                }
                panels.append(.init(mesh:mesh,positions:placed,fixedVertexIDs:fixed))
            }
            for (i,name) in skirtNames.enumerated() {
                let mesh=try remesh(name,geometry:geometry,seeds:seeds,overrides:overrides,settings:settings,isCancelled:isCancelled)
                let bandSeed=seeds[bandNames[i]]!,edge=geometry[bandNames[i]]!.edges[bandBottom[i]]
                let placed=try mesh.flatPositions.map {p -> Vector3 in
                    if initialPlacement == .componentMetricSeed {
                        let component=try seeds[name]!.sample(p)
                        let translated=component+Vector3(x:0,y:-band.cloth.radialLengthMeters,z:0)
                        return standard.project(translated,thickness:0.0025)
                    }
                    let (u0,s0)=arcs[i].coordinates(p),margin=mesh.maximumBoundaryDeviationMeters+1e-8
                    guard u0>=(-1e-7),u0<=1+1e-7,s0>=(-margin),s0<=depths[i]+margin else {
                        throw Kernel.DrapeError.invalid("组合圆裙网格偏离原环扇形。")
                    }
                    let u=max(0,min(1,u0)),s=max(0,min(depths[i],s0))
                    let q=edge.point(at:1-u),anchor=try bandSeed.sample(.init(x:q.x/100,y:q.y/100,z:0))
                    let radial=Vector3(x:anchor.x,y:0,z:anchor.z),unit=radial/max(1e-12,radial.length)
                    // The source radial distance is retained. The initial
                    // cone starts at the actual band lower boundary; no skirt
                    // vertex is pinned, including its joined upper boundary.
                    let world=anchor+unit*(s*slope)+Vector3(x:0,y:-s*sqrt(max(0,1-slope*slope)),z:0)
                    return standard.project(world,thickness:0.0025)
                }
                panels.append(.init(mesh:mesh,positions:placed))
            }
            var metrics=Builder.Metrics(garmentStyle:"SkirtCircle+\(straight ? "StraightWB" : "FittedWB")",
                lengthLabel:"径向裙长",sourceWaistMeters:skirt.cloth.waistCircumferenceMeters,
                sourceHemMeters:skirt.cloth.hemCircumferenceMeters,sourceLengthMeters:depths[0])
            metrics.warnings=["四片源纸样保留独立顶点、原边长和质量；只固定腰头上缘，裙腰通过源接缝与腰头下缘连接并自由受力。"]
            if initialPlacement == .componentMetricSeed {
                metrics.warnings.append("初始布局保留圆裙组件的原始角份额，整体移至腰头下方；真实初始接缝间距由缝合逐步闭合，不通过扭转整片去预先贴齐不等长接口。")
            }
            if hasEase {metrics.warnings.append("不等长腰口来自完整原生款式重生成一致的已知接口，采用明确吃势和有限缝合点，保留未附着的原长折叠节点；不是实测弹性或完整连续缝线模型。")}
            do {
                return try Builder.prepare(document:document,body:body,settings:settings,panels:panels,hints:hints,metrics:metrics,isCancelled:isCancelled)
            } catch Sewing.SewingError.refinementNeeded(let requests) {
                guard attempt<4,!requests.isEmpty else {throw Sewing.SewingError.refinementNeeded(requests)}
                for request in requests {
                    let spacing=request.requiredMaximumBoundarySpacingMeters
                    guard spacing.isFinite,spacing>=0.0005 else {throw Sewing.SewingError.refinementNeeded(requests)}
                    let previous=overrides[request.edge.panelID]?[request.edge.edgeIndex] ?? .infinity
                    overrides[request.edge.panelID,default:[:]][request.edge.edgeIndex]=min(previous,spacing)
                }
            }
        }
        throw Kernel.DrapeError.invalid("组合接缝的局部细分没有在预算内完成。")
    }

    private static func remesh(_ name:String,geometry:[String:GarmentCodePanelGeometry],seeds:[String:Seed],
                               overrides:[String:[Int:Double]],settings:Kernel.Settings,
                               isCancelled:@Sendable()->Bool) throws -> Mesh {
        guard let spacing=overrides[name],!spacing.isEmpty else {return seeds[name]!.mesh}
        return try GarmentCodePanelMesher.prepare(panel:geometry[name]!,targetEdgeMeters:settings.targetEdgeMeters,
            maximumVertices:8000,maximumTriangles:24000,maximumBoundarySpacingMeters:spacing,isCancelled:isCancelled)
    }

    private static func isKnownNative(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,hash:String) throws -> Bool {
        guard case let .object(values)?=document.parameters?["design"] else {return false}
        let encoder=JSONEncoder(),decoder=JSONDecoder()
        let nodes=try decoder.decode([String:GarmentCodeParameterNode].self,from:encoder.encode(JSONValue.object(values)))
        let catalog=GarmentCodeParameterCatalog(design:nodes,body:body.values,bodyDerivedFormulas:nil)
        let design=GarmentCodeDesignParameters(catalog:catalog)
        // ParameterNode's Decodable deliberately represents a JSON-null v as
        // nil while retaining hasValueKey, so both express the empty upper.
        let upper=design.value(at:["meta","upper"])
        guard upper==nil || upper == .null,
              design.value(at:["meta","bottom"]) == .string("SkirtCircle"),
              design.value(at:["meta","wb"]) == .string("StraightWB") || design.value(at:["meta","wb"]) == .string("FittedWB") else {return false}
        let regenerated=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        return try Sewn.canonicalSourceSHA256(document:regenerated)==hash
    }

    private static func arc(_ edge:GarmentCodeGeometryEdge) throws -> Arc {
        guard let spec=edge.curvature?.circle else {throw Kernel.DrapeError.unsupported("组合圆裙需要真实圆弧，不能替换为直边模板。")}
        let a=Vector3(x:edge.start.x/100,y:edge.start.y/100,z:0),b=Vector3(x:edge.end.x/100,y:edge.end.y/100,z:0)
        let chord=b-a,d=chord.length,r=spec.radius/100
        guard d>1e-10,r.isFinite,r>=d/2-1e-10 else {throw Kernel.DrapeError.invalid("组合圆裙源圆弧无效。")}
        let height=sqrt(max(0,r*r-d*d/4)),sign=spec.largeArc == spec.right ? -1.0 : 1.0
        let center=(a+b)/2+Vector3(x:-chord.y/d,y:chord.x/d,z:0)*(height*sign)
        let first=atan2(a.y-center.y,a.x-center.x),last=atan2(b.y-center.y,b.x-center.x)
        var delta=last-first
        if spec.right {while delta<0 {delta += 2*Double.pi};while delta>=2*Double.pi {delta -= 2*Double.pi}}
        else {while delta>0 {delta -= 2*Double.pi};while delta <= -2*Double.pi {delta += 2*Double.pi}}
        if abs(delta) != Double.pi && (abs(delta)>Double.pi) != spec.largeArc {delta += spec.right ? -2*Double.pi : 2*Double.pi}
        return .init(center:center,radius:r,start:first,delta:delta)
    }
}
