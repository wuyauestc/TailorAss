import Foundation

/// Pattern-driven adapters for the supported skirt families. Simulation stays
/// in the existing numerical kernel so circle-skirt baselines are untouched.
enum GarmentCodeSkirtDrape {
    typealias Kernel = GarmentCodeCircleDrape
    typealias Vector3 = Kernel.Vector3

    static func prepare(document: GarmentCodePatternFile,
                        body: GarmentCodeBodyParameters,
                        settings: Kernel.Settings = .init()) throws -> Kernel.Input {
        let panels = try document.geometryPanels()
        if panels.values.contains(where: { $0.edges.contains(where: { $0.curvature?.circle != nil }) }) {
            return try Kernel.prepare(document: document, body: body, settings: settings)
        }
        return try twoPanel(document: document, body: body, settings: settings)
    }

    private static func twoPanel(document: GarmentCodePatternFile,
                                 body: GarmentCodeBodyParameters,
                                 settings: Kernel.Settings) throws -> Kernel.Input {
        try document.validateForPreview()
        let geometry = try document.geometryPanels()
        func reject(_ message: String) -> Kernel.DrapeError { .unsupported(message) }
        guard Set(geometry.keys) == Set(["skirt_front", "skirt_back"]), document.pattern.stitches.count == 2 else {
            throw reject("当前裙装 3D 支持无腰头、无切口的圆裙或双片裙；不能省略其他组件后生成。")
        }
        guard settings.targetEdgeMeters.isFinite, (0.025...0.06).contains(settings.targetEdgeMeters),
              (60...2400).contains(settings.maximumSteps), (4...32).contains(settings.solverIterations) else {
            throw Kernel.DrapeError.invalid("3D 网格或求解预算超出实验范围。")
        }
        guard body.values.values.allSatisfy(\.isFinite),
              let waistCM = body["waist"], let backWaistCM = body["waist_back_width"],
              let hipsCM = body["hips"], let hipLineCM = body["hips_line"], let heightCM = body["height"],
              (30...200).contains(waistCM), (40...220).contains(hipsCM), hipsCM >= waistCM,
              (5...45).contains(hipLineCM), (100...240).contains(heightCM),
              backWaistCM > 0, backWaistCM < waistCM else {
            throw Kernel.DrapeError.invalid("双片裙 3D 需要有效的腰围、后腰围、臀围、腰臀高与身高。")
        }
        struct Panel {
            let name: String
            let source: GarmentCodePanelGeometry
            let top: GarmentCodeGeometryEdge
            let hem: GarmentCodeGeometryEdge
            let height: Double
            let topWidth: Double
            let hemWidth: Double
        }
        func panel(_ name: String) throws -> Panel {
            guard let p = geometry[name], p.edges.count == 4,
                  p.edges.allSatisfy({ $0.curvature == nil }) else {
                throw reject("双片裙 3D 暂不支持开衩、切口、省道或曲线裁片。")
            }
            let horizontal = p.edges.filter { abs($0.start.y-$0.end.y) < 1e-6 }
            guard horizontal.count == 2 else { throw reject("双片裙 3D 需要水平腰口和下摆的直线梯形裁片。") }
            let ordered = horizontal.sorted { $0.start.y > $1.start.y }
            func ascending(_ e: GarmentCodeGeometryEdge) -> GarmentCodeGeometryEdge {
                e.start.x <= e.end.x ? e : e.reversed()
            }
            let top = ascending(ordered[0]), hem = ascending(ordered[1])
            let height = top.start.y-hem.start.y
            let flare = (hem.length()-top.length())/2
            guard (5...150).contains(height), top.length() > 1,
                  flare >= -1e-6, flare <= 20.000001,
                  abs((top.start.x+top.end.x)-(hem.start.x+hem.end.x)) < 1e-5 else {
                throw reject("当前双片裙需要 5～150 cm 的垂直裙长、0～20 cm 的对称裙摆增量。")
            }
            let allowed = [top.start, top.end, hem.start, hem.end]
            guard p.edges.allSatisfy({ edge in allowed.contains(edge.start) && allowed.contains(edge.end) }) else {
                throw reject("双片裙轮廓不能映射为完整的四边裁片。")
            }
            return .init(name: name, source: p, top: top, hem: hem,
                         height: height/100, topWidth: top.length()/100, hemWidth: hem.length()/100)
        }
        let panels = try [panel("skirt_front"), panel("skirt_back")]
        guard abs(panels[0].height-panels[1].height) < 1e-6,
              abs((panels[0].hemWidth-panels[0].topWidth)-(panels[1].hemWidth-panels[1].topWidth)) < 1e-6 else {
            throw reject("双片裙前后片需要相同垂直长度和侧缝增量。")
        }
        let bodyWaist = waistCM/100, bodyHips = hipsCM/100, hipLine = hipLineCM/100
        let sourceWaist = panels.reduce(0) { $0+$1.topWidth }
        let sourceHem = panels.reduce(0) { $0+$1.hemWidth }
        let ratio = sourceWaist/bodyWaist
        let frontRatio = panels[0].topWidth/((waistCM-backWaistCM)/100)
        let backRatio = panels[1].topWidth/(backWaistCM/100)
        guard ratio >= 1-1e-6, ratio <= 1.5+1e-6, abs(frontRatio-backRatio) < 1e-5 else {
            throw reject("双片裙 3D 暂支持自然腰位和 1～1.5 倍统一腰口抽褶；请核对腰位、后腰围及抽褶倍率。")
        }
        if case let .object(design)? = document.parameters?["design"],
           case let .object(skirt)? = design["skirt"],
           case let .object(rise)? = skirt["rise"],
           let value = rise["v"]?.numberValue, abs(value-1) > 1e-6 {
            throw reject("双片裙 3D 当前仅支持自然腰位，请将双片裙腰位比例设为 1。")
        }
        let n = min(96, max(24, Int(ceil(panels.map(\.hemWidth).max()!/settings.targetEdgeMeters))))
        let rows = min(45, max(6, Int(ceil(panels[0].height/settings.targetEdgeMeters))))
        guard 2*(n+1)*(rows+1) <= 8000 else { throw Kernel.DrapeError.invalid("双片裙网格超过本轮离线预算。") }
        let stride = (n+1)*(rows+1)
        var flat: [Vector3] = [], sourceTriangles: [UInt32] = []
        var records: [(Int,Int,Double,Bool)] = [], bendRecords: [(Int,Int,Double,Bool)] = []
        var edgeVertices: [String:[Int]] = [:]
        for (p, panel) in panels.enumerated() {
            func index(_ r: Int, _ c: Int) -> Int { p*stride+r*(n+1)+c }
            for r in 0...rows {
                let v = Double(r)/Double(rows)
                for c in 0...n {
                    let u = Double(c)/Double(n)
                    let point = panel.top.point(at: u)*(1-v)+panel.hem.point(at: u)*v
                    flat.append(.init(x: point.x/100, y: point.y/100, z: 0))
                }
            }
            for r in 0..<rows {
                for c in 0..<n {
                    let a=index(r,c), b=index(r,c+1), cc=index(r+1,c), d=index(r+1,c+1)
                    sourceTriangles += [UInt32(a),UInt32(b),UInt32(cc),UInt32(b),UInt32(d),UInt32(cc)]
                }
            }
            for r in 0...rows {
                for c in 0...n {
                    let a=index(r,c)
                    // Use the actual triangle edges. Adding the unused other
                    // diagonal fixes all six quad distances and blocks bending
                    // along the mesh's b–c hinge.
                    for (rr,cc) in [(r+1,c),(r,c+1),(r+1,c-1)] where rr <= rows && cc >= 0 && cc <= n {
                        let b=index(rr,cc)
                        records.append((a,b,(flat[a]-flat[b]).length,rr != r && cc != c))
                    }
                    for (rr,cc) in [(r+2,c),(r,c+2)] where rr <= rows && cc <= n {
                        let b=index(rr,cc)
                        bendRecords.append((a,b,(flat[a]-flat[b]).length,false))
                    }
                }
            }
            let boundaries = [(0...n).map { index(0,$0) },(0...n).map { index(rows,$0) },
                              (0...rows).map { index($0,0) },(0...rows).map { index($0,n) }]
            for e in panel.source.edges.indices {
                let edge=panel.source.edges[e]
                let start=Vector3(x:edge.start.x/100,y:edge.start.y/100,z:0)
                let end=Vector3(x:edge.end.x/100,y:edge.end.y/100,z:0)
                guard let path=boundaries.first(where: { path in
                    let a=flat[path[0]], b=flat[path[path.count-1]]
                    return ((a-start).length<1e-7 && (b-end).length<1e-7) || ((a-end).length<1e-7 && (b-start).length<1e-7)
                }) else {throw Kernel.DrapeError.invalid("双片裙边界到网格的映射失败。")}
                edgeVertices["\(panel.name):\(e)"] = (flat[path[0]]-start).length<1e-7 ? path : Array(path.reversed())
            }
        }
        var parent=Array(flat.indices)
        func find(_ i:Int)->Int {var j=i;while parent[j] != j {j=parent[j]};return j}
        var sourceSeams:[[Int]]=[], sourcePairs:[(Int,Int)]=[], used=Set<String>()
        for stitch in document.pattern.stitches {
            guard stitch.sides.count==2,!stitch.rightWrong else {throw reject("双片裙只支持普通双边侧缝。")}
            let keys=stitch.sides.map {"\($0.panel):\($0.edge)"}
            guard keys[0] != keys[1],keys.allSatisfy({used.insert($0).inserted}),
                  stitch.sides[0].panel != stitch.sides[1].panel,
                  let a=edgeVertices[keys[0]], let other=edgeVertices[keys[1]], a.count==rows+1,other.count==a.count else {
                throw reject("双片裙接缝必须完整连接两片的侧边，不能交叉缝合腰口或下摆。")
            }
            let b=Array(other.reversed())
            for (i,j) in zip(a,b) {parent[find(j)]=find(i);sourcePairs.append((i,j))}
            sourceSeams.append(a)
        }
        var roots:[Int:Int]=[:], mapping:[Int]=[]
        for i in flat.indices {let root=find(i);if roots[root]==nil {roots[root]=roots.count};mapping.append(roots[root]!)}
        guard roots.count==2*n*(rows+1) else {throw reject("双片裙没有形成完整环状拓扑。")}
        // Ordinary Skirt2 connects left to left and right to right. A different
        // imported relationship needs a distinct assembly, not a silent twist.
        for r in 0...rows {
            guard mapping[r*(n+1)]==mapping[stride+r*(n+1)],
                  mapping[r*(n+1)+n]==mapping[stride+r*(n+1)+n] else {
                throw reject("双片裙侧缝方向与普通前后片装配不一致。")
            }
        }
        func springs(_ raw:[(Int,Int,Double,Bool)])throws->[Kernel.Spring] {
            var result:[String:Kernel.Spring]=[:]
            for (i,j,length,shear) in raw {
                let a=min(mapping[i],mapping[j]),b=max(mapping[i],mapping[j]),key="\(a):\(b)"
                guard a != b,length.isFinite,length>1e-9 else {throw Kernel.DrapeError.invalid("双片裙存在退化参考约束。")}
                if let old=result[key],abs(old.length-length)>0.00002 {throw reject("双片裙侧缝不等长，当前不支持侧缝吃势。")}
                result[key] = .init(a:a,b:b,length:length,isShear:shear)
            }
            return result.values.sorted {$0.a == $1.a ? $0.b<$1.b : $0.a<$1.a}
        }
        let standard=settings.bodyMode == .standardMannequin ? try GarmentCodeStandardBody.load(body:body,resourceDirectory:settings.bodyResourceDirectory) : nil
        let proxy=Kernel.ProxyBody(levels:[0.30,0.14,0,-hipLine,-hipLine-0.14,-hipLine-0.80],
            circumferences:[max(bodyWaist*1.15,(body["bust"] ?? waistCM*1.2)/100),bodyWaist*1.08,bodyWaist,bodyHips,bodyHips*0.83,bodyHips*0.48])
        let radius=bodyWaist/(2*Double.pi)
        let clearanceContour:[Vector3]?
        if let standard, settings.useBodySurfaceCollision {
            // SDF gradients are piecewise smooth. Cache a closed continuous
            // contour before chord marching instead of projecting each trial
            // point independently inside the root finder.
            clearanceContour=(0..<512).map {
                standard.project(standard.waistPoint(arcFraction:Double($0)/512),thickness:0.005)
            }
        } else {clearanceContour=nil}
        func base(_ fraction:Double)->Vector3 {
            if let contour=clearanceContour {
                let f=(fraction-floor(fraction))*Double(contour.count),i=Int(floor(f)),t=f-Double(i)
                return contour[i]*(1-t)+contour[(i+1)%contour.count]*t
            }
            if let standard {
                return standard.waistPoint(arcFraction:fraction)
            }
            return .init(x:radius*cos(2*Double.pi*fraction),y:0,z:radius*sin(2*Double.pi*fraction))
        }
        let targetLengths=Array(repeating:panels[0].topWidth/Double(n),count:n)+Array(repeating:panels[1].topWidth/Double(n),count:n)
        let indexedSupport=sourceHem>sourceWaist+1e-8 || settings.useBodySurfaceCollision
        let ring=try supportRing(base:base,restLengths:targetLengths,seamPeaks:indexedSupport)
        var rowRings=[ring]
        // An actual section hull can shrink in front of the thighs. Keeping
        // the waist radius here creates an artificial pouch whose perimeter
        // may exceed the available cloth and send the initializer into a leg.
        for r in 1...rows {
            let v=Double(r)/Double(rows), y = -panels[0].height*v
            let front=panels[0].topWidth*(1-v)+panels[0].hemWidth*v
            let back=panels[1].topWidth*(1-v)+panels[1].hemWidth*v
            let circumference=front+back
            let hull:[Vector3]
            if let standard {
                hull=try sectionHull(standard,y:y)
            } else {
                let axes=proxy.axes(at:y) ?? Kernel.ProxyBody.axes(circumference:bodyWaist)
                hull=(0..<128).map {i in let t=2*Double.pi*Double(i)/128
                    return Vector3(x:(axes.0+0.0025)*cos(t),y:y,z:(axes.1+0.0025)*sin(t))}
            }
            let perimeter=zip(hull,hull.dropFirst()+[hull[0]]).reduce(0.0) {$0+($1.0-$1.1).length}
            guard perimeter<circumference+0.00001 else {
                throw reject("裁片在距腰口 \(Int((-y*100).rounded())) cm 处的围度不足以包住标准人台；请增加抽褶倍率或裙摆增量。")
            }
            // Flared rows start farther from the body, rather than putting
            // the complete increase into a deep artificial corrugation.
            let growth=min((sourceHem-sourceWaist)*v/(2*Double.pi),max(0,circumference-perimeter)*0.8/(2*Double.pi))
            func rowBase(_ fraction:Double)->Vector3 {
                let directionPoint=base(fraction),direction=Vector3(x:directionPoint.x,y:0,z:directionPoint.z)
                let unit=direction/direction.length
                return hullPoint(hull,direction:unit,y:y)+unit*growth
            }
            let lengths=Array(repeating:front/Double(n),count:n)+Array(repeating:back/Double(n),count:n)
            rowRings.append(try supportRing(base:rowBase,restLengths:lengths,seamPeaks:indexedSupport))
        }
        var positions=Array(repeating:Vector3.zero,count:roots.count),pinned=Array(repeating:false,count:roots.count)
        for p in 0..<2 {
            for r in 0...rows {
                for c in 0...n {
                    let ringIndex=p==0 ? c : 2*n-c
                    var point=rowRings[r].points[ringIndex%(2*n)]
                    if r>0 {point=standard?.project(point,thickness:0.0025) ?? proxy.project(point,thickness:0.0025)}
                    let id=mapping[p*stride+r*(n+1)+c]
                    positions[id]=point
                    if r==0 {pinned[id]=true}
                }
            }
        }
        var triangles:[UInt32]=[]
        for offset in Swift.stride(from:0,to:sourceTriangles.count,by:3) {
            var ids=(0..<3).map {UInt32(mapping[Int(sourceTriangles[offset+$0])])}
            if Int(sourceTriangles[offset])/stride==1 {ids.swapAt(1,2)}
            triangles += ids
        }
        var area=0.0
        for offset in Swift.stride(from:0,to:sourceTriangles.count,by:3) {
            let a=flat[Int(sourceTriangles[offset])],b=flat[Int(sourceTriangles[offset+1])],c=flat[Int(sourceTriangles[offset+2])]
            area += (b-a).cross(c-a).length/2
        }
        let mesh=standard.map {($0.positions,$0.triangleIndices)} ?? proxyMesh(proxy)
        var input=Kernel.Input(positions:positions,triangleIndices:triangles,referencePositions:flat,
            referenceTriangles:sourceTriangles,referenceToSimulation:mapping,panelColumns:n,radialSegments:rows,
            seamPaths:sourceSeams.map {$0.map {mapping[$0]}},seamVertexPairs:sourcePairs.map {.init(a:mapping[$0.0],b:mapping[$0.1])},
            pinned:pinned,springs:try springs(records),bendingSprings:try springs(bendRecords),body:proxy,
            mannequinPositions:mesh.0,mannequinTriangleIndices:mesh.1,waistCircumferenceMeters:sourceWaist,
            hemCircumferenceMeters:sourceHem,radialLengthMeters:panels[0].height,referenceAreaSquareMeters:area,settings:settings)
        input.standardBody=standard
        input.garmentStyle="Skirt2";input.patternLengthLabel="垂直裙长";input.waistGatherRatio=ratio
        input.preparationWarnings=["双片裙腰口采用按原裁片边长构造的外向褶皱支撑环；它是抽褶装配实验，不代表已缝制真实腰头。"]
        if settings.useSurfaceCollision {input.surfaceTopology=try GarmentCodeClothContact.Topology(vertexCount:positions.count,triangleIndices:triangles)}
        if let preset=settings.material {
            let material=preset.parameters;try material.validate()
            let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:flat.map {SIMD3<Double>($0.x,$0.y,$0.z)},
                triangleIndices:sourceTriangles,referenceToSimulation:mapping,simulationVertexCount:positions.count,
                arealDensity:material.arealDensityKgPerSquareMeter)
            input.inverseMasses=masses.normalizedInverseMasses.enumerated().map {pinned[$0.offset] ? 0 : $0.element}
            input.meanParticleMassKg=masses.meanMassKg;input.totalFabricMassKg=masses.totalMassKg
        }
        try Kernel.attachBodySurfaceContact(to: &input)
        return input
    }

    /// Convex envelope of the actual torso or two leg slice loops. Arms and
    /// hands form separate distant loops and are not part of a skirt envelope.
    private static func sectionHull(_ body:GarmentCodeStandardBody.Snapshot,y:Double)throws->[Vector3] {
        struct Key:Hashable {let x:Int;let z:Int}
        var points:[Vector3]=[],links:[Set<Int>]=[],lookup:[Key:Int]=[:]
        func id(_ p:Vector3)->Int {
            let key=Key(x:Int((p.x*1e7).rounded()),z:Int((p.z*1e7).rounded()))
            if let i=lookup[key] {return i}
            let i=points.count;lookup[key]=i;points.append(p);links.append([]);return i
        }
        for t in Swift.stride(from:0,to:body.triangleIndices.count,by:3) {
            let triangle=(0..<3).map {body.positions[Int(body.triangleIndices[t+$0])]}
            var hits:[Vector3]=[]
            for j in 0..<3 {
                let a=triangle[j],b=triangle[(j+1)%3],da=a.y-y,db=b.y-y
                if abs(da)<1e-9 {hits.append(.init(x:a.x,y:y,z:a.z))}
                if da*db < 0 {hits.append(a+(b-a)*(-da/(db-da)))}
            }
            var ids:[Int]=[]
            for hit in hits {let i=id(hit);if !ids.contains(i) {ids.append(i)}}
            if ids.count>=2 {for j in 1..<ids.count {links[ids[0]].insert(ids[j]);links[ids[j]].insert(ids[0])}}
        }
        guard !points.isEmpty else {
            throw Kernel.DrapeError.unsupported("当前裙长超出标准人台可建立截面支撑的范围。")
        }
        var pending=Set(points.indices),components:[[Int]]=[]
        while let first=pending.first {
            var stack=[first],component:[Int]=[]
            while let i=stack.popLast() {if pending.remove(i) != nil {component.append(i);stack += links[i]}}
            if component.count>=3 {components.append(component)}
        }
        func center(_ component:[Int])->Vector3 {component.reduce(.zero) {$0+points[$1]}/Double(component.count)}
        let spanning=components.filter {c in c.map {points[$0].x}.min()! < -0.005 && c.map {points[$0].x}.max()! > 0.005}
        let selected:[[Int]]
        if let torso=spanning.min(by:{center($0).length<center($1).length}) {selected=[torso]}
        else {
            let left=components.filter {center($0).x<0}.min {center($0).length<center($1).length}
            let right=components.filter {center($0).x>=0}.min {center($0).length<center($1).length}
            selected=[left,right].compactMap {$0}
        }
        let selectedIndices:[Int]=selected.flatMap {$0}
        let selectedPoints:[Vector3]=selectedIndices.map {points[$0]}
        let sorted=selectedPoints.sorted {a,b in a.x == b.x ? a.z<b.z : a.x<b.x}
        guard sorted.count>=3 else {throw Kernel.DrapeError.invalid("标准人台截面无法组成闭合裙装包络。")}
        func cross(_ a:Vector3,_ b:Vector3,_ c:Vector3)->Double {(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)}
        var lower:[Vector3]=[],upper:[Vector3]=[]
        for p in sorted {while lower.count>=2 && cross(lower[lower.count-2],lower.last!,p)<=1e-12 {lower.removeLast()};lower.append(p)}
        for p in sorted.reversed() {while upper.count>=2 && cross(upper[upper.count-2],upper.last!,p)<=1e-12 {upper.removeLast()};upper.append(p)}
        let hull=Array(lower.dropLast())+Array(upper.dropLast())
        guard hull.count>=3 else {throw Kernel.DrapeError.invalid("标准人台截面退化。")}
        return hull.indices.map {i in
            let previous=hull[(i+hull.count-1)%hull.count],p=hull[i],next=hull[(i+1)%hull.count]
            let e1=p-previous,e2=next-p
            let n1=Vector3(x:e1.z,y:0,z:-e1.x)/e1.length,n2=Vector3(x:e2.z,y:0,z:-e2.x)/e2.length
            let sum=n1+n2,normal=sum/sum.length
            let dot=normal.x*n1.x+normal.z*n1.z
            return p+normal*min(0.0075,0.0025/max(0.1,dot))
        }
    }

    private static func hullPoint(_ hull:[Vector3],direction:Vector3,y:Double)->Vector3 {
        var radius=0.0
        for i in hull.indices {
            let a=hull[i],e=hull[(i+1)%hull.count]-a
            let denominator=direction.x*e.z-direction.z*e.x
            if abs(denominator)<1e-12 {continue}
            let r=(a.x*e.z-a.z*e.x)/denominator
            let u=(a.x*direction.z-a.z*direction.x)/denominator
            if r>=0 && u>=(-1e-8) && u<=1+1e-8 {radius=max(radius,r)}
        }
        return direction*radius+Vector3(x:0,y:y,z:0)
    }

    /// A closed, outward-only corrugated contour. March by each SOURCE chord
    /// length, then bisect amplitude until the last chord closes the loop.
    /// This does not compress a gathered flat waist onto the body's perimeter.
    private static func supportRing(base:(Double)->Vector3,restLengths:[Double],seamPeaks:Bool=false)throws->(points:[Vector3],fractions:[Double]) {
        let waves=6.0
        // A flared flat panel has an obtuse corner at each waist endpoint.
        // Both sides of the sewn corner need the descending seam to lean
        // outward. Prescribed source-index peaks put BOTH seams at convex
        // support corners, despite unequal front/back source widths.
        let offsets=(0...restLengths.count).map { (1+cos(2*Double.pi*waves*Double($0)/Double(restLengths.count)))/2 }
        func curve(_ f:Double,_ amplitude:Double,_ index:Int)->Vector3 {
            let p=base(f),radial=Vector3(x:p.x,y:0,z:p.z)
            let normal=radial.length>1e-9 ? radial/radial.length : Vector3(x:1,y:0,z:0)
            let weight=seamPeaks ? offsets[index] : (1-cos(2*Double.pi*waves*f))/2
            return p+normal*(amplitude*weight)
        }
        func march(_ amplitude:Double)throws->(points:[Vector3],fractions:[Double]) {
            var points=[curve(0,amplitude,0)],fractions=[0.0]
            for (index,length) in restLengths.enumerated() {
                let start=fractions.last!,p=points.last!
                guard (curve(start,amplitude,index+1)-p).length<length else {
                    throw Kernel.DrapeError.invalid("抽褶支撑的相邻径向差超过原裁片边长。")
                }
                var high=start+0.0005
                while (curve(high,amplitude,index+1)-p).length<length && high<start+0.10 {high += 0.0005}
                guard high<start+0.101 else {throw Kernel.DrapeError.invalid("腰口抽褶支撑曲线无法按原始边长离散。")}
                var low=start
                for _ in 0..<35 {
                    let mid=(low+high)/2
                    if (curve(mid,amplitude,index+1)-p).length<length {low=mid}else{high=mid}
                }
                let next=(low+high)/2
                fractions.append(next);points.append(curve(next,amplitude,index+1))
            }
            return (points,fractions)
        }
        let feasible=restLengths.indices.map {i in restLengths[i]*0.95/max(1e-9,abs(offsets[i+1]-offsets[i]))}.min()!
        var low=0.0,high=seamPeaks ? min(0.08,feasible) : 0.08
        let plain=try march(0)
        if abs(plain.fractions.last!-1)<0.00001 {return plain}
        guard plain.fractions.last!>=1,try march(high).fractions.last!<1 else {
            throw Kernel.DrapeError.invalid("原始腰口尺寸不能组成当前抽褶支撑环。")
        }
        for _ in 0..<45 {
            let mid=(low+high)/2
            if try march(mid).fractions.last!>1 {low=mid}else{high=mid}
        }
        var result=try march((low+high)/2)
        guard (result.points.last!-result.points[0]).length<1e-5 else {throw Kernel.DrapeError.invalid("抽褶支撑环没有可靠闭合。")}
        result.points[result.points.count-1]=result.points[0]
        result.fractions[result.fractions.count-1]=1
        let relative=zip(zip(result.points,result.points.dropFirst()),restLengths).map {abs(($0.0.0-$0.0.1).length/$0.1-1)}.max() ?? 0
        guard relative<0.001 else {throw Kernel.DrapeError.invalid("抽褶支撑的局部边长偏差过大。")}
        return result
    }

    private static func proxyMesh(_ body:Kernel.ProxyBody)->([Vector3],[UInt32]) {
        let columns=64,rows=48
        var positions:[Vector3]=[],triangles:[UInt32]=[]
        for r in 0...rows {
            let y=body.levels[0]+(body.levels.last!-body.levels[0])*Double(r)/Double(rows)
            let (a,b)=body.axes(at:y) ?? Kernel.ProxyBody.axes(circumference:body.circumferences.last!)
            for c in 0..<columns {let t=2*Double.pi*Double(c)/Double(columns);positions.append(.init(x:a*cos(t),y:y,z:b*sin(t)))}
        }
        for r in 0..<rows {for c in 0..<columns {let a=UInt32(r*columns+c),b=UInt32(r*columns+(c+1)%columns),cc=a+UInt32(columns),d=b+UInt32(columns);triangles += [a,b,cc,b,d,cc]}}
        return (positions,triangles)
    }
}
