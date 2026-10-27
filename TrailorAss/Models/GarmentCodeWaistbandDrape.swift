import Foundation

/// Independent, source-metric-preserving waistbands. Lower garments are not
/// implicitly removed or gathered onto these panels by this adapter.
enum GarmentCodeWaistbandDrape {
    typealias Kernel = GarmentCodeCircleDrape
    typealias Vector3 = Kernel.Vector3

    /// Separate source-panel data survives admissible side-seam welding. A
    /// later sewing assembler can restore independent paper DOFs using the
    /// input's referenceToSimulation map instead of inventing new rest edges.
    nonisolated struct SourcePanelBinding: Sendable {
        let panelID: String
        let mesh: GarmentCodePanelMesher.Mesh
        let referenceVertexOffset: Int
        /// Offset in the UInt32 index arrays, not a face number. Reference and
        /// simulation triangle arrays retain the same panel/face order.
        let triangleIndexOffset: Int
        let topEdgeIndex: Int
        let bottomEdgeIndex: Int
        let sideEdgeIndices: [Int]
        let depthMeters: Double
    }

    nonisolated struct Prepared: Sendable {
        let input: Kernel.Input
        let sourcePanelBindings: [SourcePanelBinding]
    }

    private struct Arc {
        let center: Vector3
        let radius: Double
        let startAngle: Double
        let delta: Double
    }
    private struct Panel {
        let name: String
        let source: GarmentCodePanelGeometry
        let mesh: GarmentCodePanelMesher.Mesh
        let top: Int
        let bottom: Int
        let sides: [Int]
        let depth: Double
        let topLength: Double
        let bottomLength: Double
        let arc: Arc?

        func coordinates(_ p:Vector3)throws->(u:Double,v:Double) {
            let rawU:Double,rawV:Double
            if let arc {
                let relative=p-arc.center
                var angle=atan2(relative.y,relative.x)
                let middle=arc.startAngle+arc.delta/2
                while angle-middle>Double.pi {angle -= 2*Double.pi}
                while angle-middle < -Double.pi {angle += 2*Double.pi}
                rawU=(angle-arc.startAngle)/arc.delta
                rawV=(hypot(relative.x,relative.y)-arc.radius)/depth
            } else {
                let edge=source.edges[top],a=point(edge.start),b=point(edge.end),direction=b-a
                rawU=dot(p-a,direction)/direction.lengthSquared
                rawV=(a.y-p.y)/depth
            }
            // The polygonal inner-arc approximation can differ from its
            // analytic radius by at most the declared flattening error.
            let margin=mesh.maximumBoundaryDeviationMeters/depth+1e-7
            guard rawU>=(-1e-7),rawU<=1+1e-7,rawV>=(-margin),rawV<=1+margin else {
                throw Kernel.DrapeError.unsupported("腰头网格不能映射到原始矩形或环扇形纸样。")
            }
            return (max(0,min(1,rawU)),max(0,min(1,rawV)))
        }
    }
    private struct Contour {
        let points: [Vector3]
        let lengths: [Double]
        let frontMidplaneFraction: Double
        init(_ input:[Vector3])throws {
            guard input.count>=3,input.allSatisfy(\.isFinite) else {throw Kernel.DrapeError.invalid("人体截面支撑无效。")}
            var points:[Vector3]=[]
            for p in input where points.last.map({($0-p).length>1e-10}) ?? true {points.append(p)}
            if points.count>3,(points.last!-points[0]).length<1e-10 {points.removeLast()}
            guard points.count>=3 else {throw Kernel.DrapeError.invalid("人体截面支撑退化。")}
            let area=points.indices.reduce(0.0) {sum,i in let a=points[i],b=points[(i+1)%points.count];return sum+a.x*b.z-a.z*b.x}
            if area<0 {points=[points[0]]+Array(points.dropFirst().reversed())}
            var lengths=[0.0]
            for i in points.indices {lengths.append(lengths.last!+(points[(i+1)%points.count]-points[i]).length)}
            guard lengths.last!>0.1 else {throw Kernel.DrapeError.invalid("人体腰部截面过小。")}
            // Front and back source panels are centered on the body's
            // sagittal plane. A max-X start would place only one side seam
            // behind that plane when the source front/back widths differ.
            var front:(z:Double,fraction:Double)?
            for i in points.indices {
                let a=points[i],b=points[(i+1)%points.count],t:Double
                if abs(a.x)<1e-12 {t=0}
                else if a.x*b.x<0 {t = -a.x/(b.x-a.x)}
                else {continue}
                let z=a.z+(b.z-a.z)*t
                if front == nil || z>front!.z {
                    front=(z,(lengths[i]+(b-a).length*t)/lengths.last!)
                }
            }
            guard let front,front.z>0 else {throw Kernel.DrapeError.invalid("人体截面不能可靠定位前中线。")}
            self.points=points;self.lengths=lengths;frontMidplaneFraction=front.fraction
        }
        func point(_ fraction:Double)->Vector3 {
            let f=fraction-floor(fraction),target=f*lengths.last!
            var low=0,high=points.count
            while high-low>1 {let m=(low+high)/2;if lengths[m]<target {low=m}else{high=m}}
            let t=(target-lengths[low])/max(1e-20,lengths[low+1]-lengths[low])
            return points[low]*(1-t)+points[(low+1)%points.count]*t
        }
    }

    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                        settings:Kernel.Settings,
                        isCancelled:@Sendable()->Bool={false})throws->Kernel.Input {
        try prepareAssembly(document:document,body:body,settings:settings,isCancelled:isCancelled).input
    }

    static func prepareAssembly(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                                settings:Kernel.Settings,
                                isCancelled:@Sendable()->Bool={false})throws->Prepared {
        if isCancelled() {throw CancellationError()}
        try document.validateForPreview()
        let geometry=try document.geometryPanels()
        guard Set(geometry.keys)==Set(["wb_front","wb_back"]),document.pattern.stitches.count==2 else {
            throw Kernel.DrapeError.unsupported("当前腰头 3D 需要独立的普通腰头或贴体腰头两片纸样；不能省略上衣、裙身或裤身后生成。")
        }
        guard settings.bodyMode == .standardMannequin else {
            throw Kernel.DrapeError.unsupported("腰头 3D 当前使用标准人体，请选择标准人体模式。")
        }
        guard settings.targetEdgeMeters.isFinite,(0.025...0.06).contains(settings.targetEdgeMeters),
              (60...2400).contains(settings.maximumSteps),(4...32).contains(settings.solverIterations),
              body.values.values.allSatisfy(\.isFinite),let waistCM=body["waist"],let hipsCM=body["hips"],
              let hiplineCM=body["hips_line"],waistCM>0,hipsCM>=waistCM,hiplineCM>0 else {
            throw Kernel.DrapeError.invalid("腰头 3D 的人体尺寸或网格配置无效。")
        }
        let allStraight=geometry.values.allSatisfy {$0.edges.count==4 && $0.edges.allSatisfy {$0.curvature==nil}}
        let style=allStraight ? "StraightWB" : "FittedWB"
        let topRoles=allStraight ? [2,1] : [3,0],bottomRoles=allStraight ? [0,3] : [1,2]
        let sideRoles=allStraight ? [[3,1],[0,2]] : [[0,2],[3,1]]
        let names=["wb_front","wb_back"]
        var panels:[Panel]=[]
        for i in 0..<2 {
            let source=geometry[names[i]]!
            guard source.edges.count==4 else {throw Kernel.DrapeError.unsupported("腰头 3D 暂不支持开口、装饰切口或附加裁片。")}
            let top=source.edges[topRoles[i]],bottom=source.edges[bottomRoles[i]]
            let depth:Double,arc:Arc?
            if allStraight {
                guard abs(top.start.y-top.end.y)<1e-6,abs(bottom.start.y-bottom.end.y)<1e-6,
                      abs(top.length()-bottom.length())<1e-6,top.start.y>bottom.start.y,
                      sideRoles[i].allSatisfy({abs(source.edges[$0].start.x-source.edges[$0].end.x)<1e-6}) else {
                    throw Kernel.DrapeError.unsupported("普通腰头需要完整矩形纸样，不能替代斜边或曲线腰头。")
                }
                depth=(top.start.y-bottom.start.y)/100;arc=nil
            } else {
                guard top.curvature?.type=="circle",bottom.curvature?.type=="circle",
                      sideRoles[i].allSatisfy({source.edges[$0].curvature==nil}) else {
                    throw Kernel.DrapeError.unsupported("贴体腰头需要两条同心圆弧和两条径向直边。")
                }
                let inner=try circle(top),outer=try circle(bottom)
                guard (inner.center-outer.center).length<1e-7,
                      abs(abs(inner.delta)-abs(outer.delta))<1e-7,
                      outer.radius>inner.radius,abs(inner.delta)<Double.pi else {
                    throw Kernel.DrapeError.unsupported("贴体腰头不是可对应的同心环扇形。")
                }
                depth=outer.radius-inner.radius;arc=inner
            }
            guard (0.01...0.30).contains(depth),sideRoles[i].allSatisfy({abs(source.edges[$0].length()/100-depth)<1e-7}) else {
                throw Kernel.DrapeError.unsupported("腰头纸样宽度需为 1～30 cm，侧边必须保持完整且等长。")
            }
            let mesh=try GarmentCodePanelMesher.prepare(panel:source,targetEdgeMeters:settings.targetEdgeMeters,
                maximumVertices:4000,maximumTriangles:12000,isCancelled:isCancelled)
            panels.append(.init(name:names[i],source:source,mesh:mesh,top:topRoles[i],bottom:bottomRoles[i],sides:sideRoles[i],
                                depth:depth,topLength:top.length()/100,bottomLength:bottom.length()/100,arc:arc))
        }
        guard abs(panels[0].depth-panels[1].depth)<1e-7 else {throw Kernel.DrapeError.unsupported("腰头前后片的纸样宽度不同，当前不能可靠装配。")}
        let standard=try GarmentCodeStandardBody.load(body:body,resourceDirectory:settings.bodyResourceDirectory)
        let depth=panels[0].depth,sourceTop=panels.reduce(0){$0+$1.topLength},sourceBottom=panels.reduce(0){$0+$1.bottomLength}
        var contours:[Contour]=[]
        let levelCount=max(8,min(32,Int(ceil(depth/settings.targetEdgeMeters))*4))
        for r in 0...levelCount {
            if isCancelled() {throw CancellationError()}
            let v=Double(r)/Double(levelCount),clearance=0.005*(1-v)+0.0025*v
            let contour:[Vector3]
            if r==0 {contour=(0..<1024).map {standard.waistPoint(arcFraction:Double($0)/1024)}}
            else {contour=try torsoSection(standard,y:-depth*v)}
            contours.append(try Contour(contour.map {standard.project($0,thickness:clearance)}))
        }
        func placed(_ panel:Int,_ p:Vector3)throws->Vector3 {
            let uv=try panels[panel].coordinates(p),v=uv.v
            let front=panels[0].topLength*(1-v)+panels[0].bottomLength*v
            let back=panels[1].topLength*(1-v)+panels[1].bottomLength*v
            let split=front/(front+back),f=panel==0 ? uv.u*split : split+uv.u*(1-split)
            let row=v*Double(levelCount),low=min(levelCount-1,Int(floor(row))),t=row-Double(low)
            let a=contours[low],b=contours[low+1]
            return a.point(f+a.frontMidplaneFraction-split/2)*(1-t)
                + b.point(f+b.frontMidplaneFraction-split/2)*t
        }
        var flat:[Vector3]=[],initial:[Vector3]=[],referenceTriangles:[UInt32]=[],offsets:[Int]=[],triangleOffsets:[Int]=[]
        var paths:[String:[Int]]=[:],topOriginal=Set<Int>()
        for i in 0..<2 {
            let offset=flat.count;offsets.append(offset)
            triangleOffsets.append(referenceTriangles.count)
            flat += panels[i].mesh.flatPositions
            initial += try panels[i].mesh.flatPositions.map {try placed(i,$0)}
            referenceTriangles += panels[i].mesh.triangleIndices.map {$0+UInt32(offset)}
            for boundary in panels[i].mesh.boundaries {
                let ids=boundary.vertexIDs.map {$0+offset};paths["\(names[i]):\(boundary.edgeIndex)"]=ids
                if boundary.edgeIndex==panels[i].top {topOriginal.formUnion(ids)}
            }
        }
        guard flat.count<=8000 else {throw Kernel.DrapeError.invalid("腰头网格超过本轮顶点预算。")}
        var parent=Array(flat.indices)
        func find(_ i:Int)->Int {var j=i;while parent[j] != j {j=parent[j]};return j}
        var originalPairs:[(Int,Int)]=[],originalSeams:[[Int]]=[],used=Set<String>()
        for stitch in document.pattern.stitches {
            guard stitch.sides.count==2,!stitch.rightWrong,stitch.sides[0].panel != stitch.sides[1].panel else {
                throw Kernel.DrapeError.unsupported("腰头只支持前后片的普通双边侧缝。")
            }
            let sides=stitch.sides,keys=sides.map {"\($0.panel):\($0.edge)"}
            for side in sides {
                guard let i=names.firstIndex(of:side.panel),panels[i].sides.contains(side.edge) else {
                    throw Kernel.DrapeError.unsupported("腰头接缝不能缝合上缘或下缘，也不能忽略附加接口。")
                }
            }
            guard keys.allSatisfy({used.insert($0).inserted}),let a=paths[keys[0]],let rawB=paths[keys[1]],a.count==rawB.count else {
                throw Kernel.DrapeError.unsupported("腰头两侧缝的离散采样不同，不能强行合并。")
            }
            let b=Array(rawB.reversed())
            let sourceA=geometry[sides[0].panel]!.edges[sides[0].edge],sourceB=geometry[sides[1].panel]!.edges[sides[1].edge]
            guard abs(sourceA.length()-sourceB.length())<1e-6 else {throw Kernel.DrapeError.unsupported("腰头侧缝不等长，不能通过修改原始尺寸强行焊接。")}
            for k in a.indices {
                if k>0,abs((flat[a[k]]-flat[a[k-1]]).length-(flat[b[k]]-flat[b[k-1]]).length)>1e-8 {
                    throw Kernel.DrapeError.unsupported("腰头侧缝的原始分段长度不一致。")
                }
                guard (initial[a[k]]-initial[b[k]]).length<1e-6 else {throw Kernel.DrapeError.unsupported("腰头侧缝方向与原始版型装配不一致。")}
                parent[find(b[k])]=find(a[k]);originalPairs.append((a[k],b[k]))
            }
            originalSeams.append(a)
        }
        var roots:[Int:Int]=[:],mapping:[Int]=[]
        for i in flat.indices {let root=find(i);if roots[root]==nil {roots[root]=roots.count};mapping.append(roots[root]!)}
        var positions=Array(repeating:Vector3.zero,count:roots.count),pinned=Array(repeating:false,count:roots.count)
        for i in flat.indices {positions[mapping[i]]=initial[i];if topOriginal.contains(i){pinned[mapping[i]]=true}}
        var triangles:[UInt32]=[]
        for i in 0..<2 {
            let ids=panels[i].mesh.triangleIndices
            for t in stride(from:0,to:ids.count,by:3) {
                var face=(0..<3).map {UInt32(mapping[offsets[i]+Int(ids[t+$0])])}
                // Mesh normalizes source XY to CCW; the back source panel's
                // original winding is opposite to the front's outward side.
                if panels[i].mesh.sourceClockwise {face.swapAt(1,2)}
                triangles += face
            }
        }
        var springMap:[UInt64:Kernel.Spring]=[:],bendMap:[UInt64:Kernel.Spring]=[:]
        for i in 0..<2 {
            let ids=panels[i].mesh.triangleIndices,offset=offsets[i]
            var adjacency:[UInt64:[Int]]=[:]
            for t in stride(from:0,to:ids.count,by:3) {
                let a=offset+Int(ids[t]),b=offset+Int(ids[t+1]),c=offset+Int(ids[t+2])
                for (u,v,opposite) in [(a,b,c),(b,c,a),(c,a,b)] {
                    adjacency[key(u,v),default:[]].append(opposite)
                    let x=min(mapping[u],mapping[v]),y=max(mapping[u],mapping[v]),length=(flat[u]-flat[v]).length,k=key(x,y)
                    guard x != y,length>1e-10 else {throw Kernel.DrapeError.invalid("腰头结构边在装配后退化。")}
                    if let old=springMap[k],abs(old.length-length)>1e-8 {throw Kernel.DrapeError.unsupported("焊接会改变一侧腰头的原始结构长度。")}
                    springMap[k] = .init(a:x,b:y,length:length)
                }
            }
            for opposite in adjacency.values where opposite.count==2 {
                let u=opposite[0],v=opposite[1],a=min(mapping[u],mapping[v]),b=max(mapping[u],mapping[v])
                guard a != b else {continue}
                let spring=Kernel.Spring(a:a,b:b,length:(flat[u]-flat[v]).length)
                if spring.length>1e-10 {bendMap[key(a,b)]=spring}
            }
        }
        let springs=springMap.values.sorted {$0.a == $1.a ? $0.b<$1.b : $0.a<$1.a}
        let bends=bendMap.values.sorted {$0.a == $1.a ? $0.b<$1.b : $0.a<$1.a}
        let maximumPinnedStrain=springs.filter {pinned[$0.a] && pinned[$0.b]}.map {abs((positions[$0.a]-positions[$0.b]).length/$0.length-1)}.max() ?? 0
        guard maximumPinnedStrain<0.08 else {throw Kernel.DrapeError.unsupported("腰头上缘与当前标准人体的围度不匹配，辅助支撑会超过原始纸样的应变门槛。")}
        var area=0.0
        for t in stride(from:0,to:referenceTriangles.count,by:3) {
            let a=flat[Int(referenceTriangles[t])],b=flat[Int(referenceTriangles[t+1])],c=flat[Int(referenceTriangles[t+2])]
            area += (b-a).cross(c-a).length/2
        }
        let waist=waistCM/100,hips=hipsCM/100,hipline=hiplineCM/100
        let proxy=Kernel.ProxyBody(levels:[0.3,0.14,0,-hipline,-hipline-0.14,-hipline-0.8],
            circumferences:[max(waist*1.15,(body["bust"] ?? waistCM*1.2)/100),waist*1.08,waist,hips,hips*0.83,hips*0.48])
        var solverSettings=settings
        solverSettings.sourceStrainLimit=0.05
        var input=Kernel.Input(positions:positions,triangleIndices:triangles,referencePositions:flat,
            referenceTriangles:referenceTriangles,referenceToSimulation:mapping,panelColumns:0,radialSegments:0,
            seamPaths:originalSeams.map {$0.map {mapping[$0]}},seamVertexPairs:originalPairs.map {.init(a:mapping[$0.0],b:mapping[$0.1])},
            pinned:pinned,springs:springs,bendingSprings:bends,body:proxy,mannequinPositions:standard.positions,
            mannequinTriangleIndices:standard.triangleIndices,waistCircumferenceMeters:sourceTop,
            hemCircumferenceMeters:sourceBottom,radialLengthMeters:depth,referenceAreaSquareMeters:area,settings:solverSettings)
        input.standardBody=standard;input.garmentStyle=style;input.patternLengthLabel="腰头纸样宽度"
        input.preparationWarnings=["当前为独立腰头预览，上缘使用距标准人体约 5 mm 的辅助固定支撑；侧缝按等长原始边合并，未包含裙身或完整成衣缝合过程。"]
        if settings.useSurfaceCollision {input.surfaceTopology=try GarmentCodeClothContact.Topology(vertexCount:positions.count,triangleIndices:triangles)}
        if let preset=settings.material {
            let material=preset.parameters;try material.validate()
            let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:flat.map {SIMD3<Double>($0.x,$0.y,$0.z)},
                triangleIndices:referenceTriangles,referenceToSimulation:mapping,simulationVertexCount:positions.count,
                arealDensity:material.arealDensityKgPerSquareMeter)
            input.inverseMasses=masses.normalizedInverseMasses.enumerated().map {pinned[$0.offset] ? 0 : $0.element}
            input.meanParticleMassKg=masses.meanMassKg;input.totalFabricMassKg=masses.totalMassKg
        }
        try Kernel.attachBodySurfaceContact(to:&input)
        let bindings=panels.indices.map {i in
            SourcePanelBinding(panelID:panels[i].name,mesh:panels[i].mesh,
                referenceVertexOffset:offsets[i],triangleIndexOffset:triangleOffsets[i],
                topEdgeIndex:panels[i].top,bottomEdgeIndex:panels[i].bottom,
                sideEdgeIndices:panels[i].sides,depthMeters:panels[i].depth)
        }
        return Prepared(input:input,sourcePanelBindings:bindings)
    }

    private static func point(_ p:GarmentCodePoint)->Vector3 {.init(x:p.x/100,y:p.y/100,z:0)}
    private static func dot(_ a:Vector3,_ b:Vector3)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func key(_ a:Int,_ b:Int)->UInt64 {(UInt64(min(a,b))<<32)|UInt64(max(a,b))}
    private static func circle(_ edge:GarmentCodeGeometryEdge)throws->Arc {
        guard let circle=edge.curvature?.circle else {throw Kernel.DrapeError.unsupported("腰头缺少圆弧参数。")}
        let a=point(edge.start),b=point(edge.end),chord=b-a,d=chord.length
        guard d>1e-10 else {throw Kernel.DrapeError.unsupported("腰头圆弧端点重合。")}
        let radius=max(circle.radius/100,d/2),height=sqrt(max(0,radius*radius-d*d/4))
        let center=(a+b)/2+Vector3(x:-chord.y/d,y:chord.x/d,z:0)*(height*(circle.largeArc == circle.right ? -1 : 1))
        let theta=atan2(a.y-center.y,a.x-center.x),last=atan2(b.y-center.y,b.x-center.x)
        var delta=last-theta
        if circle.right {while delta<0 {delta += 2*Double.pi};while delta>=2*Double.pi {delta -= 2*Double.pi}}
        else {while delta>0 {delta -= 2*Double.pi};while delta <= -2*Double.pi {delta += 2*Double.pi}}
        if abs(delta) != Double.pi && (abs(delta)>Double.pi) != circle.largeArc {delta += circle.right ? -2*Double.pi : 2*Double.pi}
        return .init(center:center,radius:radius,startAngle:theta,delta:delta)
    }

    /// The central closed torso component, not the disconnected arm/hand loops
    /// that can intersect the same horizontal level.
    private static func torsoSection(_ body:GarmentCodeStandardBody.Snapshot,y:Double)throws->[Vector3] {
        struct Key:Hashable {let x:Int;let z:Int}
        var points:[Vector3]=[],links:[Set<Int>]=[],lookup:[Key:Int]=[:]
        func id(_ p:Vector3)->Int {
            let key=Key(x:Int((p.x*1e8).rounded()),z:Int((p.z*1e8).rounded()))
            if let i=lookup[key] {return i}
            let i=points.count;points.append(p);links.append([]);lookup[key]=i;return i
        }
        for t in stride(from:0,to:body.triangleIndices.count,by:3) {
            let p=(0..<3).map {body.positions[Int(body.triangleIndices[t+$0])]}
            var hits:[Int]=[]
            for i in 0..<3 {
                let a=p[i],b=p[(i+1)%3],da=a.y-y,db=b.y-y
                if abs(da)<1e-10 {let v=id(.init(x:a.x,y:y,z:a.z));if !hits.contains(v){hits.append(v)}}
                if da*db<0 {let v=id(a+(b-a)*(-da/(db-da)));if !hits.contains(v){hits.append(v)}}
            }
            if hits.count>=2 {for j in 1..<hits.count {links[hits[0]].insert(hits[j]);links[hits[j]].insert(hits[0])}}
        }
        var pending=Set(points.indices),components:[[Int]]=[]
        while let first=pending.first {
            var stack=[first],component:[Int]=[]
            while let i=stack.popLast() {if pending.remove(i) != nil {component.append(i);stack += links[i]}}
            if component.count>=3,component.contains(where:{points[$0].x < -0.005}),component.contains(where:{points[$0].x>0.005}) {components.append(component)}
        }
        guard let selected=components.min(by:{a,b in
            let ca=a.reduce(Vector3.zero){$0+points[$1]}/Double(a.count),cb=b.reduce(Vector3.zero){$0+points[$1]}/Double(b.count)
            return ca.lengthSquared<cb.lengthSquared
        }),selected.allSatisfy({links[$0].count==2}) else {throw Kernel.DrapeError.unsupported("当前腰头深度没有可可靠定位的闭合躯干截面。")}
        let start=selected.max {a,b in points[a].x==points[b].x ? points[a].z<points[b].z : points[a].x<points[b].x}!
        var result:[Vector3]=[],previous = -1,current=start
        repeat {
            result.append(points[current])
            guard let next=links[current].sorted().first(where:{$0 != previous}) else {throw Kernel.DrapeError.invalid("人体躯干截面未闭合。")}
            previous=current;current=next
            guard result.count<=selected.count else {throw Kernel.DrapeError.invalid("人体截面包含重复回路。")}
        } while current != start
        guard result.count==selected.count else {throw Kernel.DrapeError.invalid("人体截面没有覆盖完整躯干。")}
        return result
    }
}
