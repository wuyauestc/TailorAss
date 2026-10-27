import Foundation

/// Experimental generic-mesh circle-skirt assembly. The legacy structured,
/// welded skirt remains an independent control and supplies no final geometry.
@MainActor
enum GarmentCodeCircleAssembly {
    typealias Kernel=GarmentCodeCircleDrape
    typealias Vector3=Kernel.Vector3
    typealias Sewing=GarmentCodeSewing
    typealias Sewn=GarmentCodeSewnDrape

    private struct Edge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int) {self.a=min(a,b);self.b=max(a,b)}
    }
    private struct Arc {
        let center:Vector3
        let radius:Double
        let startAngle:Double
        let delta:Double
    }
    private struct Sector {
        let name:String
        let mesh:GarmentCodePanelMesher.Mesh
        let top:Arc
        let topIndex:Int
        let hemIndex:Int
        let depth:Double
        let topLength:Double
        let hemLength:Double
        func polar(_ p:Vector3)throws->(fraction:Double,radial:Double) {
            let relative=p-top.center
            var angle=atan2(relative.y,relative.x)
            let middle=top.startAngle+top.delta/2
            while angle-middle>Double.pi {angle -= 2*Double.pi}
            while angle-middle < -Double.pi {angle += 2*Double.pi}
            let u=(angle-top.startAngle)/top.delta,s=hypot(relative.x,relative.y)-top.radius
            let tolerance=mesh.maximumBoundaryDeviationMeters+1e-8
            guard u>=(-1e-7),u<=1+1e-7,s>=(-tolerance),s<=depth+tolerance else {
                throw Kernel.DrapeError.invalid("通用圆裙网格超出其原始环扇形范围。")
            }
            return (max(0,min(1,u)),max(0,min(depth,s)))
        }
    }
    private struct Support {
        let points:[Vector3]
        let lengths:[Double]
        let frontMidplaneFraction:Double
        init(body:GarmentCodeStandardBody.Snapshot)throws {
            var points=(0..<1024).map {body.project(body.waistPoint(arcFraction:Double($0)/1024),thickness:0.005)}
            let area=points.indices.reduce(0.0) {sum,i in
                let a=points[i],b=points[(i+1)%points.count]
                return sum+a.x*b.z-a.z*b.x
            }
            if area<0 {points=[points[0]]+Array(points.dropFirst().reversed())}
            var lengths=[0.0]
            for i in points.indices {lengths.append(lengths.last!+(points[(i+1)%points.count]-points[i]).length)}
            guard lengths.last!.isFinite,lengths.last!>0.1 else {throw Kernel.DrapeError.invalid("圆裙人体腰线支撑退化。")}
            var front:(z:Double,fraction:Double)?
            for i in points.indices {
                let a=points[i],b=points[(i+1)%points.count],t:Double
                if abs(a.x)<1e-12 {t=0}
                else if a.x*b.x<0 {t = -a.x/(b.x-a.x)}
                else {continue}
                let z=a.z+(b.z-a.z)*t
                if front==nil || z>front!.z {front=(z,(lengths[i]+(b-a).length*t)/lengths.last!)}
            }
            guard let front,front.z>0 else {throw Kernel.DrapeError.invalid("圆裙支撑不能定位人体前中线。")}
            self.points=points;self.lengths=lengths;frontMidplaneFraction=front.fraction
        }
        func point(_ fraction:Double)->Vector3 {
            let target=(fraction-floor(fraction))*lengths.last!
            var low=0,high=points.count
            while high-low>1 {let m=(low+high)/2;if lengths[m]<target {low=m}else{high=m}}
            let t=(target-lengths[low])/max(1e-20,lengths[low+1]-lengths[low])
            return points[low]*(1-t)+points[(low+1)%points.count]*t
        }
    }

    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                        settings:Kernel.Settings,
                        isCancelled:@Sendable()->Bool={false})throws->Sewn.PreparedInput {
        if isCancelled() {throw CancellationError()}
        guard settings.bodyMode == .standardMannequin,settings.useSurfaceCollision,
              settings.useBodySurfaceCollision,let material=settings.material else {
            throw Kernel.DrapeError.unsupported("通用圆裙缝合需要标准人体、实验面料和完整表面接触设置。")
        }
        try material.parameters.validate()
        let sourceHash=try Sewn.canonicalSourceSHA256(document:document)
        let geometry=try document.geometryPanels(),names=["skirt_front","skirt_back"]
        guard Set(geometry.keys)==Set(names),document.pattern.stitches.count==2 else {
            throw Kernel.DrapeError.unsupported("通用圆裙当前只支持独立、无开衩、自然腰位的对称双片圆裙，不能省略其他裁片。")
        }
        // Keep the old experiment's measurement/range validation and exact
        // collision body. None of its structured vertices or springs is used.
        let legacy=try Kernel.prepare(document:document,body:body,settings:settings)
        guard let standard=legacy.standardBody,legacy.bodySurfaceMesh != nil,
              let waistCM=body["waist"],abs(legacy.waistCircumferenceMeters-waistCM/100)<1e-7 else {
            throw Kernel.DrapeError.unsupported("通用圆裙仅支持当前人体的自然腰围，不能自动改动腰位或增加抽褶。")
        }
        var sectors:[Sector]=[]
        for (index,name) in names.enumerated() {
            if isCancelled() {throw CancellationError()}
            let panel=geometry[name]!,topIndex=index==0 ? 3 : 0,hemIndex=index==0 ? 1 : 2
            let sides=index==0 ? [0,2] : [3,1]
            guard panel.edges.count==4,panel.edges[topIndex].curvature?.type=="circle",
                  panel.edges[hemIndex].curvature?.type=="circle",
                  sides.allSatisfy({panel.edges[$0].curvature==nil}) else {
                throw Kernel.DrapeError.unsupported("通用圆裙需要原始两条同心圆弧和两条完整径向侧边。")
            }
            let top=try circle(panel.edges[topIndex]),hem=try circle(panel.edges[hemIndex]),depth=hem.radius-top.radius
            guard depth>=0.05-1e-9,depth<=1.5+1e-9,abs(top.delta)>=0.1*Double.pi-1e-7,
                  abs(top.delta)<=Double.pi+1e-7,top.delta*hem.delta<0,
                  (top.center-hem.center).length<1e-7,abs(abs(top.delta)-abs(hem.delta))<1e-7,
                  sides.allSatisfy({abs(panel.edges[$0].length()/100-depth)<1e-7}) else {
                throw Kernel.DrapeError.unsupported("圆裙原始环扇形或范围不受支持；不能平均半径或替换裁片。")
            }
            for t in [0.0,0.25,0.5,0.75,1.0] {
                let a=panel.edges[topIndex].point(at:t),b=panel.edges[hemIndex].point(at:1-t)
                guard abs(a.distance(to:b)/100-depth)<1e-7 else {throw Kernel.DrapeError.unsupported("圆裙内外弧没有一致的径向对应。")}
            }
            let mesh=try GarmentCodePanelMesher.prepare(panel:panel,targetEdgeMeters:settings.targetEdgeMeters,
                maximumVertices:4000,maximumTriangles:12000,isCancelled:isCancelled)
            sectors.append(.init(name:name,mesh:mesh,top:top,topIndex:topIndex,hemIndex:hemIndex,
                depth:depth,topLength:panel.edges[topIndex].length()/100,hemLength:panel.edges[hemIndex].length()/100))
        }
        guard abs(sectors[0].depth-sectors[1].depth)<1e-7,
              abs(sectors[0].top.radius-sectors[1].top.radius)<1e-7,
              abs(abs(sectors[0].top.delta)-abs(sectors[1].top.delta))<1e-7 else {
            throw Kernel.DrapeError.unsupported("通用圆裙暂不支持前后不对称的原始环扇形。")
        }
        let totalAngle=sectors.reduce(0.0){$0+abs($1.top.delta)},slope=totalAngle/(2*Double.pi)
        guard slope>=0.1-1e-7,slope<=1+1e-7 else {throw Kernel.DrapeError.unsupported("通用圆裙当前支持 0.1～1 整圆范围。")}
        let support=try Support(body:standard),frontShare=abs(sectors[0].top.delta)/totalAngle
        let phase=support.frontMidplaneFraction-frontShare/2,vertical=sqrt(max(0,1-slope*slope))
        var flat:[Vector3]=[],positions:[Vector3]=[],pinned:[Bool]=[],referenceTriangles:[UInt32]=[],triangles:[UInt32]=[]
        var bindings:[Sewing.PanelBinding]=[],paths:[Sewing.EdgeKey:[Int]]=[:]
        var structural:[Edge:Kernel.Spring]=[:],bendCandidates=Set<Edge>()
        for (index,sector) in sectors.enumerated() {
            if isCancelled() {throw CancellationError()}
            let mesh=sector.mesh,offset=flat.count
            guard offset+mesh.flatPositions.count<=8000 else {throw Sewing.SewingError.budgetExceeded("通用圆裙源网格超过 8000 个独立顶点。")}
            bindings.append(try .init(mesh:mesh,vertexOffset:offset,triangleOffset:triangles.count/3))
            let topNodes=Set(mesh.boundaries[sector.topIndex].vertexIDs)
            for (local,p) in mesh.flatPositions.enumerated() {
                if local%128==0 && isCancelled() {throw CancellationError()}
                let polar=try sector.polar(p),fraction=index==0 ? polar.fraction*frontShare : frontShare+polar.fraction*(1-frontShare)
                let theta=2*Double.pi*fraction,s=polar.radial,anchor=support.point(fraction+phase)
                var initial=anchor+Vector3(x:cos(theta),y:0,z:sin(theta))*(s*slope)
                    + Vector3(x:0,y:-s*vertical+s*0.012*sin(8*theta),z:0)
                let pin=topNodes.contains(local)
                if !pin {initial=standard.project(initial,thickness:0.0025)}
                flat.append(p);positions.append(initial);pinned.append(pin)
            }
            var adjacent:[Edge:[Int]]=[:]
            for t in stride(from:0,to:mesh.triangleIndices.count,by:3) {
                let face=(0..<3).map {offset+Int(mesh.triangleIndices[t+$0])}
                referenceTriangles += face.map(UInt32.init)
                var sourceFacing=face;if mesh.sourceClockwise {sourceFacing.swapAt(1,2)}
                triangles += sourceFacing.map(UInt32.init)
                for (a,b,c) in [(face[0],face[1],face[2]),(face[1],face[2],face[0]),(face[2],face[0],face[1])] {
                    let key=Edge(a,b),length=(flat[a]-flat[b]).length
                    guard length.isFinite,length>1e-10 else {throw Kernel.DrapeError.invalid("通用圆裙原始结构边退化。")}
                    structural[key] = .init(a:key.a,b:key.b,length:length);adjacent[key,default:[]].append(c)
                }
            }
            for opposite in adjacent.values where opposite.count==2 {bendCandidates.insert(.init(opposite[0],opposite[1]))}
            for boundary in mesh.boundaries {paths[.init(panelID:sector.name,edgeIndex:boundary.edgeIndex)]=boundary.vertexIDs.map {offset+$0}}
        }
        func order(_ a:Kernel.Spring,_ b:Kernel.Spring)->Bool {a.a==b.a ? a.b<b.b : a.a<b.a}
        let springs=structural.values.sorted(by:order)
        let bends=bendCandidates.filter {$0.a != $0.b && structural[$0]==nil}.map {
            Kernel.Spring(a:$0.a,b:$0.b,length:(flat[$0.a]-flat[$0.b]).length)
        }.sorted(by:order)
        let pinnedStrain=springs.filter {pinned[$0.a] && pinned[$0.b]}.map {abs((positions[$0.a]-positions[$0.b]).length/$0.length-1)}.max() ?? 0
        guard pinnedStrain<0.08 else {throw Kernel.DrapeError.unsupported("通用圆裙腰口支撑超过原始纸样的应变门槛。")}
        var sourceStitches:[Sewing.SourceStitch]=[],hints:[Sewing.StitchHint]=[],seamPaths:[[Int]]=[],used=Set<Int>()
        let expected=[0:3,2:1]
        for (index,stitch) in document.pattern.stitches.enumerated() {
            guard stitch.sides.count==2,!stitch.rightWrong,
                  let front=stitch.sides.first(where:{$0.panel=="skirt_front"}),
                  let back=stitch.sides.first(where:{$0.panel=="skirt_back"}),
                  expected[front.edge]==back.edge,used.insert(front.edge).inserted else {
                throw Kernel.DrapeError.unsupported("通用圆裙仅支持原始双侧普通等长接缝，不能猜测扭转、反缝或抽褶。")
            }
            let a=Sewing.EdgeKey(panelID:stitch.sides[0].panel,edgeIndex:stitch.sides[0].edge),b=Sewing.EdgeKey(panelID:stitch.sides[1].panel,edgeIndex:stitch.sides[1].edge)
            guard let ap=paths[a],let bp=paths[b] else {throw Kernel.DrapeError.invalid("通用圆裙缺少源侧缝路径。")}
            sourceStitches.append(.init(a:a,b:b,rightWrong:stitch.rightWrong))
            hints.append(.init(stitchIndex:index,seamID:"circle-side-\(index)",a:a,b:b,aDirection:.forward,bDirection:.reverse,rightWrong:stitch.rightWrong,intent:.ordinary))
            seamPaths += [ap,bp]
        }
        let plan=try Sewing.build(bindings:bindings,positions:positions,sourceStitches:sourceStitches,
            actualSourceSHA256:sourceHash,assembly:.init(sourceSHA256:sourceHash,hints:hints),isCancelled:isCancelled)
        let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:flat.map {SIMD3<Double>($0.x,$0.y,$0.z)},
            triangleIndices:referenceTriangles,arealDensity:material.parameters.arealDensityKgPerSquareMeter)
        var input=Kernel.Input(positions:positions,triangleIndices:triangles,referencePositions:flat,
            referenceTriangles:referenceTriangles,referenceToSimulation:Array(flat.indices),panelColumns:0,radialSegments:0,
            seamPaths:seamPaths,seamVertexPairs:[],pinned:pinned,springs:springs,bendingSprings:bends,body:legacy.body,
            mannequinPositions:legacy.mannequinPositions,mannequinTriangleIndices:legacy.mannequinTriangleIndices,
            waistCircumferenceMeters:sectors.reduce(0){$0+$1.topLength},hemCircumferenceMeters:sectors.reduce(0){$0+$1.hemLength},
            radialLengthMeters:sectors[0].depth,referenceAreaSquareMeters:masses.totalAreaSquareMeters,settings:settings)
        input.standardBody=standard;input.bodySurfaceMesh=legacy.bodySurfaceMesh
        input.inverseMasses=masses.normalizedInverseMasses.enumerated().map {pinned[$0.offset] ? 0 : $0.element}
        input.meanParticleMassKg=masses.meanMassKg;input.totalFabricMassKg=masses.totalMassKg
        input.garmentStyle="SkirtCircle";input.patternLengthLabel="径向裙长"
        input.preparationWarnings=["当前为通用网格双片圆裙缝合实验：保留独立裁片，腰口使用距标准人体约 5 mm 的辅助支撑；尚未与真实腰头缝合。"]
        input.surfaceTopology=try Sewn.contactTopology(vertexCount:flat.count,triangleIndices:triangles,plan:plan,isCancelled:isCancelled)
        return try Sewn.prepare(input:input,plan:plan,document:document,bindings:bindings,isCancelled:isCancelled)
    }

    private static func point(_ p:GarmentCodePoint)->Vector3 {.init(x:p.x/100,y:p.y/100,z:0)}
    private static func circle(_ edge:GarmentCodeGeometryEdge)throws->Arc {
        guard let circle=edge.curvature?.circle else {throw Kernel.DrapeError.invalid("圆裙缺少源圆弧参数。")}
        let a=point(edge.start),b=point(edge.end),chord=b-a,d=chord.length,r=circle.radius/100
        guard d>1e-10,r.isFinite,r>0,r>=d/2-1e-10 else {throw Kernel.DrapeError.invalid("圆裙源半径与弦长不一致。")}
        let height=sqrt(max(0,r*r-d*d/4))
        let center=(a+b)/2+Vector3(x:-chord.y/d,y:chord.x/d,z:0)*(height*(circle.largeArc == circle.right ? -1 : 1))
        let start=atan2(a.y-center.y,a.x-center.x),last=atan2(b.y-center.y,b.x-center.x)
        var delta=last-start
        if circle.right {while delta<0 {delta += 2*Double.pi};while delta>=2*Double.pi {delta -= 2*Double.pi}}
        else {while delta>0 {delta -= 2*Double.pi};while delta <= -2*Double.pi {delta += 2*Double.pi}}
        if abs(delta) != Double.pi && (abs(delta)>Double.pi) != circle.largeArc {delta += circle.right ? -2*Double.pi : 2*Double.pi}
        return .init(center:center,radius:r,startAngle:start,delta:delta)
    }
}
