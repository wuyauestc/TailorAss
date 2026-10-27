import Foundation

/// Immutable line/surface queries for garment initialization. The input is the
/// exact visible body's triangle mesh, not a reconstructed or replacement body.
/// A ray hit is a local boundary observation, not a smooth fitted envelope.
nonisolated enum GarmentCodeBodyEnvelope {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3
    enum Axis:Int,Codable,Sendable {case x=0,y=1,z=2}
    enum Direction:Int,Codable,Sendable {case positive=1,negative = -1}
    enum HitKind:String,Codable,Sendable {case crossing,tangent,ambiguous}
    enum Ambiguity:String,Codable,Sendable {
        case mixedNormalsAtFeature,coincidentIndependentSurfaces,nearParallel
    }
    struct Limits:Sendable {
        var binSizeMeters=0.025
        var pointToleranceMeters=1e-8
        var angularTolerance=1e-10
        var maximumVertices=100_000
        var maximumTriangles=200_000
        var maximumBinReferences=4_000_000
        var maximumCells=200_000
        var maximumQueryCells=4096
        var maximumCandidateTriangles=50_000
        var maximumHits=4096
    }
    enum SurfaceError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded(String)
        var errorDescription:String? {
            switch self {
            case let .invalid(reason):return "人体表面查询无效：\(reason)"
            case let .budgetExceeded(reason):return "人体表面查询超出预算：\(reason)"
            }
        }
    }
    struct Bounds:Sendable {
        let minimum:Vector3
        let maximum:Vector3
    }
    struct Component:Codable,Sendable {
        let triangleCount:Int
        let isClosed:Bool
        /// Source winding is retained. A negative closed component is reported
        /// honestly; outward query normals reverse its source normals only.
        let signedVolumeCubicMeters:Double?
    }
    struct Hit:Codable,Sendable {
        let point:Vector3
        let normal:Vector3
        let normalIsOutward:Bool
        let triangleID:Int
        let incidentTriangleIDs:[Int]
        let barycentric:Vector3
        let kind:HitKind
        let ambiguity:[Ambiguity]
        let isOnSourceFeature:Bool
    }
    struct LineQuery:Codable,Sendable {
        let axis:Axis
        let hits:[Hit]
        /// These axis-parallel triangles have a continuous/coplanar contact
        /// with the query line. No single hit is fabricated for that interval.
        let coplanarTriangleIDs:[Int]
        let candidateTriangleCount:Int
        var isUnambiguous:Bool {coplanarTriangleIDs.isEmpty && hits.allSatisfy{$0.kind == .crossing}}
    }
    struct Envelope:Sendable {let back:Hit;let front:Hit}
    struct FrontBackQuery:Sendable {let line:LineQuery;let envelope:Envelope?}

    private struct Edge:Hashable,Sendable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int){self.a=min(a,b);self.b=max(a,b)}
    }
    private struct Use:Sendable {let triangle:Int;let direction:Int;var count:Int}
    private struct Cell:Hashable,Sendable {let u:Int,v:Int}
    private struct Triangle:Sendable {let a:Int,b:Int,c:Int;let sourceNormal:Vector3}
    private struct RawHit:Sendable {
        let point:Vector3,normal:Vector3,barycentric:Vector3
        let triangle:Int,component:Int,feature:Set<Int>
        let boundary:Bool,outward:Bool,nearParallel:Bool
    }

    struct PreparedSurface:Sendable {
        let positions:[Vector3]
        let triangleIndices:[UInt32]
        let bounds:Bounds
        let components:[Component]
        var isClosed:Bool {components.allSatisfy(\.isClosed)}
        let binReferenceCount:Int
        let cellCount:Int
        private let limits:Limits
        private let triangles:[Triangle]
        private let triangleComponents:[Int]
        private let bins:[[Cell:[Int]]]

        init(positions:[Vector3],triangleIndices:[UInt32],limits:Limits = .init(),
             isCancelled:@Sendable()->Bool={false}) throws {
            if isCancelled(){throw CancellationError()}
            guard limits.binSizeMeters.isFinite,(0.002...0.25).contains(limits.binSizeMeters),
                  limits.pointToleranceMeters.isFinite,(1e-12...1e-5).contains(limits.pointToleranceMeters),
                  limits.angularTolerance.isFinite,(1e-14...1e-4).contains(limits.angularTolerance),
                  (3...1_000_000).contains(limits.maximumVertices),(1...1_000_000).contains(limits.maximumTriangles),
                  (1...20_000_000).contains(limits.maximumBinReferences),(1...1_000_000).contains(limits.maximumCells),
                  (1...1_000_000).contains(limits.maximumQueryCells),(1...1_000_000).contains(limits.maximumCandidateTriangles),
                  (1...100_000).contains(limits.maximumHits) else {throw SurfaceError.invalid("索引或容差配置无效。")}
            guard positions.count>=3,positions.count<=limits.maximumVertices,
                  !triangleIndices.isEmpty,triangleIndices.count%3==0,
                  triangleIndices.count/3<=limits.maximumTriangles else {throw SurfaceError.budgetExceeded("顶点或三角面数量无效。")}
            guard positions.allSatisfy({$0.isFinite && max(abs($0.x),abs($0.y),abs($0.z))<=100}),
                  triangleIndices.allSatisfy({Int($0)<positions.count}) else {throw SurfaceError.invalid("人体顶点或三角面引用无效。")}
            var prepared:[Triangle]=[],edges:[Edge:Use]=[:],neighbors=Array(repeating:[Int](),count:triangleIndices.count/3)
            var incident=Array(repeating:[Int](),count:positions.count)
            var usedVertices=Set<Int>()
            for offset in stride(from:0,to:triangleIndices.count,by:3) {
                if offset%384==0 && isCancelled(){throw CancellationError()}
                let ids=(0..<3).map{Int(triangleIndices[offset+$0])},face=offset/3
                guard Set(ids).count==3 else {throw SurfaceError.invalid("人体三角面含重复顶点。")}
                let cross=(positions[ids[1]]-positions[ids[0]]).cross(positions[ids[2]]-positions[ids[0]])
                guard cross.length.isFinite,cross.length>1e-16 else {throw SurfaceError.invalid("人体三角面退化。")}
                prepared.append(.init(a:ids[0],b:ids[1],c:ids[2],sourceNormal:cross/cross.length));usedVertices.formUnion(ids)
                for vertex in ids {incident[vertex].append(face)}
                for (a,b) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                    let key=Edge(a,b),direction=a<b ? 1 : -1
                    if var prior=edges[key] {
                        guard prior.count==1,prior.direction == -direction else {throw SurfaceError.invalid("人体边非流形或相邻三角面方向不一致。")}
                        neighbors[face].append(prior.triangle);neighbors[prior.triangle].append(face)
                        prior.count=2;edges[key]=prior
                    } else {edges[key] = .init(triangle:face,direction:direction,count:1)}
                }
            }
            guard usedVertices.count==positions.count else {throw SurfaceError.invalid("人体包含未被任何三角面引用的顶点。")}
            for (vertex,faces) in incident.enumerated() {
                if vertex%128==0 && isCancelled(){throw CancellationError()}
                let allowed=Set(faces)
                var stack=[faces[0]],seen=Set<Int>()
                while let face=stack.popLast() {
                    if seen.insert(face).inserted {stack += neighbors[face].filter{allowed.contains($0) && !seen.contains($0)}}
                }
                guard seen.count==faces.count else {throw SurfaceError.invalid("人体顶点连接了不连续的三角面扇区。")}
            }
            var summaries:[Component]=[],componentIDs=Array(repeating:-1,count:prepared.count)
            for first in prepared.indices where componentIDs[first]<0 {
                if isCancelled(){throw CancellationError()}
                let component=summaries.count,origin=positions[prepared[first].a]
                var stack=[first],count=0,closed=true,volume=0.0
                while let face=stack.popLast() {
                    if componentIDs[face]>=0{continue}
                    componentIDs[face]=component;count += 1
                    if count%128==0 && isCancelled(){throw CancellationError()}
                    let t=prepared[face],a=positions[t.a]-origin,b=positions[t.b]-origin,c=positions[t.c]-origin
                    volume += dot(a,b.cross(c))/6
                    for edge in [Edge(t.a,t.b),Edge(t.b,t.c),Edge(t.c,t.a)] {if edges[edge]!.count != 2{closed=false}}
                    stack += neighbors[face].filter{componentIDs[$0]<0}
                }
                guard !closed || (volume.isFinite && abs(volume)>1e-18) else {throw SurfaceError.invalid("闭合人体分量没有可分辨的有向体积。")}
                summaries.append(.init(triangleCount:count,isClosed:closed,signedVolumeCubicMeters:closed ? volume : nil))
            }
            let minimum=positions.reduce(positions[0]){.init(x:min($0.x,$1.x),y:min($0.y,$1.y),z:min($0.z,$1.z))}
            let maximum=positions.reduce(positions[0]){.init(x:max($0.x,$1.x),y:max($0.y,$1.y),z:max($0.z,$1.z))}
            var indices=Array(repeating:[Cell:[Int]](),count:3),references=0,occupied=0
            let epsilon=limits.pointToleranceMeters,spacing=limits.binSizeMeters
            for (id,t) in prepared.enumerated() {
                if id%64==0 && isCancelled(){throw CancellationError()}
                let p=[positions[t.a],positions[t.b],positions[t.c]]
                for axis in Axis.all {
                    let u=(axis.rawValue+1)%3,v=(axis.rawValue+2)%3
                    let loU=Int(floor((p.map{coordinate($0,u)}.min()!-epsilon)/spacing)),hiU=Int(floor((p.map{coordinate($0,u)}.max()!+epsilon)/spacing))
                    let loV=Int(floor((p.map{coordinate($0,v)}.min()!-epsilon)/spacing)),hiV=Int(floor((p.map{coordinate($0,v)}.max()!+epsilon)/spacing))
                    let amount=(hiU-loU+1)*(hiV-loV+1)
                    guard amount<=limits.maximumBinReferences-references else {throw SurfaceError.budgetExceeded("人体二维索引引用过多。")}
                    for i in loU...hiU {for j in loV...hiV {
                        if references%256==0 && isCancelled(){throw CancellationError()}
                        let key=Cell(u:i,v:j)
                        if indices[axis.rawValue][key]==nil {occupied += 1}
                        guard occupied<=limits.maximumCells else {throw SurfaceError.budgetExceeded("人体二维索引单元过多。")}
                        indices[axis.rawValue][key,default:[]].append(id);references += 1
                    }}
                }
            }
            self.positions=positions;self.triangleIndices=triangleIndices;self.bounds = .init(minimum:minimum,maximum:maximum)
            self.components=summaries;self.limits=limits;self.triangles=prepared;self.triangleComponents=componentIDs
            self.bins=indices;self.binReferenceCount=references;self.cellCount=occupied
        }

        /// Fixed coordinates are cyclic: X uses (Y,Z), Y uses (Z,X), Z uses
        /// (X,Y). Results retain every crossing, not only the outermost pair.
        func query(axis:Axis,first:Double,second:Double,isCancelled:@Sendable()->Bool={false}) throws -> LineQuery {
            if isCancelled(){throw CancellationError()}
            guard first.isFinite,second.isFinite else {throw SurfaceError.invalid("人体查询坐标必须有限。")}
            let candidates=try candidateTriangles(axis:axis,first:first...first,second:second...second,isCancelled:isCancelled)
            let u=(axis.rawValue+1)%3,v=(axis.rawValue+2)%3,epsilon=limits.pointToleranceMeters
            var raw:[RawHit]=[],coplanar:[Int]=[]
            for (index,id) in candidates.enumerated() {
                if index%64==0 && isCancelled(){throw CancellationError()}
                let t=triangles[id],ids=[t.a,t.b,t.c],p=ids.map{positions[$0]}
                let au=coordinate(p[0],u),av=coordinate(p[0],v),bu=coordinate(p[1],u),bv=coordinate(p[1],v),cu=coordinate(p[2],u),cv=coordinate(p[2],v)
                let e1u=bu-au,e1v=bv-av,e2u=cu-au,e2v=cv-av,det=e1u*e2v-e1v*e2u
                let projectedScale=max(hypot(e1u,e1v),hypot(e2u,e2v),hypot(cu-bu,cv-bv))
                if abs(det)<=max(1e-24,epsilon*projectedScale*1e-6) {
                    let q=[first,second],projected=[[au,av],[bu,bv],[cu,cv]]
                    if (0..<3).contains(where:{distance2D(q,projected[$0],projected[($0+1)%3])<=epsilon}) {coplanar.append(id)}
                    continue
                }
                let du=first-au,dv=second-av,beta=(du*e2v-dv*e2u)/det,gamma=(e1u*dv-e1v*du)/det
                var weights=[1-beta-gamma,beta,gamma]
                let worldScale=max((p[1]-p[0]).length,(p[2]-p[0]).length,(p[2]-p[1]).length)
                let insideTolerance=min(1e-9,epsilon/max(worldScale,epsilon))
                let tolerance=max(insideTolerance,epsilon*max(projectedScale,epsilon)/abs(det))
                // A projected epsilon must not turn a nearly parallel miss
                // into a point far outside the actual triangle in 3D.
                guard weights.allSatisfy({$0>=(-insideTolerance) && $0<=1+insideTolerance}) else {continue}
                weights=weights.map{max(0,min(1,$0))}
                let sum=weights.reduce(0,+);weights=weights.map{$0/sum}
                let point=p[0]*weights[0]+p[1]*weights[1]+p[2]*weights[2]
                let component=triangleComponents[id],summary=components[component]
                let normal=t.sourceNormal*((summary.signedVolumeCubicMeters ?? 1)<0 ? -1 : 1)
                let boundary=weights.contains{$0<=tolerance}
                let feature=Set(zip(ids,weights).filter{$0.1>tolerance}.map(\.0))
                raw.append(.init(point:point,normal:normal,barycentric:.init(x:weights[0],y:weights[1],z:weights[2]),
                    triangle:id,component:component,feature:feature,boundary:boundary,outward:summary.isClosed,
                    nearParallel:abs(coordinate(normal,axis.rawValue))<=limits.angularTolerance))
                guard raw.count<=limits.maximumHits*16 else {throw SurfaceError.budgetExceeded("人体射线原始命中过多。")}
            }
            raw.sort {a,b in let x=coordinate(a.point,axis.rawValue),y=coordinate(b.point,axis.rawValue);return x==y ? a.triangle<b.triangle : x<y}
            var groups:[[RawHit]]=[]
            for hit in raw {
                if let previous=groups.last?.first,abs(coordinate(hit.point,axis.rawValue)-coordinate(previous.point,axis.rawValue))<=epsilon*4 {
                    groups[groups.count-1].append(hit)
                }else{groups.append([hit])}
            }
            guard groups.count<=limits.maximumHits else {throw SurfaceError.budgetExceeded("人体射线命中过多。")}
            let hits=groups.map {group -> Hit in
                let representative=group.min{$0.triangle<$1.triangle}!
                var ambiguity:[Ambiguity]=[]
                if group.count>1 {
                    let shared=group.dropFirst().reduce(group[0].feature){$0.intersection($1.feature)}
                    if !group.allSatisfy(\.boundary) || shared.isEmpty || Set(group.map(\.component)).count>1 {ambiguity.append(.coincidentIndependentSurfaces)}
                }
                let signs=Set(group.filter{!$0.nearParallel}.map{coordinate($0.normal,axis.rawValue)>0 ? 1 : -1})
                if signs.count>1 {ambiguity.append(.mixedNormalsAtFeature)}
                if group.contains(where:{$0.nearParallel}) {ambiguity.append(.nearParallel)}
                let kind:HitKind=ambiguity.isEmpty ? .crossing : (group.allSatisfy(\.nearParallel) ? .tangent : .ambiguous)
                return .init(point:representative.point,normal:representative.normal,normalIsOutward:representative.outward,
                    triangleID:representative.triangle,incidentTriangleIDs:group.map(\.triangle).sorted(),
                    barycentric:representative.barycentric,kind:kind,ambiguity:ambiguity,isOnSourceFeature:representative.boundary)
            }
            return .init(axis:axis,hits:hits,coplanarTriangleIDs:coplanar.sorted(),candidateTriangleCount:candidates.count)
        }

        func frontBackAt(x:Double,y:Double,isCancelled:@Sendable()->Bool={false}) throws -> FrontBackQuery {
            let line=try query(axis:.z,first:x,second:y,isCancelled:isCancelled)
            let envelope:Envelope?
            if isClosed,line.isUnambiguous,line.hits.count>=2,line.hits.count%2==0 {envelope = .init(back:line.hits.first!,front:line.hits.last!)}else{envelope=nil}
            return .init(line:line,envelope:envelope)
        }

        /// Ray hits are ordered by travel from the supplied origin. This does
        /// not infer a continuous surface where neighbouring lines lose hits.
        func ray(from origin:Vector3,axis:Axis,direction:Direction,maximumDistanceMeters:Double=100,
                 isCancelled:@Sendable()->Bool={false}) throws -> LineQuery {
            guard origin.isFinite,maximumDistanceMeters.isFinite,(0...1000).contains(maximumDistanceMeters) else {throw SurfaceError.invalid("人体射线起点或长度无效。")}
            let line=try query(axis:axis,first:coordinate(origin,(axis.rawValue+1)%3),second:coordinate(origin,(axis.rawValue+2)%3),isCancelled:isCancelled)
            let start=coordinate(origin,axis.rawValue),sign=Double(direction.rawValue),tolerance=limits.pointToleranceMeters
            var hits=line.hits.filter{let distance=(coordinate($0.point,axis.rawValue)-start)*sign;return distance>=(-tolerance) && distance<=maximumDistanceMeters+tolerance}
            if direction == .negative {hits.reverse()}
            let end=start+sign*maximumDistanceMeters,low=min(start,end),high=max(start,end)
            let coplanar=line.coplanarTriangleIDs.filter{id in let t=triangles[id],p=[positions[t.a],positions[t.b],positions[t.c]].map{coordinate($0,axis.rawValue)};return p.max()!>=low-tolerance && p.min()!<=high+tolerance}
            return .init(axis:axis,hits:hits,coplanarTriangleIDs:coplanar,candidateTriangleCount:line.candidateTriangleCount)
        }

        /// Local layout algorithms may request bounded candidate boxes to
        /// construct their own continuous envelope extensions near silhouettes.
        func candidateTriangles(axis:Axis,first:ClosedRange<Double>,second:ClosedRange<Double>,
                                isCancelled:@Sendable()->Bool={false}) throws -> [Int] {
            if isCancelled(){throw CancellationError()}
            guard [first.lowerBound,first.upperBound,second.lowerBound,second.upperBound].allSatisfy(\.isFinite) else {throw SurfaceError.invalid("人体索引范围必须有限。")}
            let u=(axis.rawValue+1)%3,v=(axis.rawValue+2)%3,e=limits.pointToleranceMeters
            let loU=max(first.lowerBound,coordinate(bounds.minimum,u)-e),hiU=min(first.upperBound,coordinate(bounds.maximum,u)+e)
            let loV=max(second.lowerBound,coordinate(bounds.minimum,v)-e),hiV=min(second.upperBound,coordinate(bounds.maximum,v)+e)
            if loU>hiU || loV>hiV{return []}
            let a=Int(floor(loU/limits.binSizeMeters)),b=Int(floor(hiU/limits.binSizeMeters))
            let c=Int(floor(loV/limits.binSizeMeters)),d=Int(floor(hiV/limits.binSizeMeters))
            guard (b-a+1)*(d-c+1)<=limits.maximumQueryCells else {throw SurfaceError.budgetExceeded("人体局部查询覆盖索引单元过多。")}
            var ids=Set<Int>(),visited=0
            for i in a...b {for j in c...d {
                if visited%64==0 && isCancelled(){throw CancellationError()};visited += 1
                ids.formUnion(bins[axis.rawValue][.init(u:i,v:j)] ?? [])
                guard ids.count<=limits.maximumCandidateTriangles else {throw SurfaceError.budgetExceeded("人体局部查询候选面过多。")}
            }}
            return ids.sorted()
        }

        func triangleBounds(at id:Int) throws -> Bounds {
            guard triangles.indices.contains(id) else {throw SurfaceError.invalid("人体三角面 ID 越界。")}
            let t=triangles[id],p=[positions[t.a],positions[t.b],positions[t.c]]
            return .init(minimum:p.reduce(p[0]){.init(x:min($0.x,$1.x),y:min($0.y,$1.y),z:min($0.z,$1.z))},
                         maximum:p.reduce(p[0]){.init(x:max($0.x,$1.x),y:max($0.y,$1.y),z:max($0.z,$1.z))})
        }
    }

    private static func coordinate(_ p:Vector3,_ axis:Int)->Double {axis==0 ? p.x : (axis==1 ? p.y : p.z)}
    private static func dot(_ a:Vector3,_ b:Vector3)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func distance2D(_ p:[Double],_ a:[Double],_ b:[Double])->Double {
        let x=b[0]-a[0],y=b[1]-a[1],square=x*x+y*y
        let t=square>0 ? max(0,min(1,((p[0]-a[0])*x+(p[1]-a[1])*y)/square)) : 0
        return hypot(p[0]-a[0]-x*t,p[1]-a[1]-y*t)
    }
}

private extension GarmentCodeBodyEnvelope.Axis {
    nonisolated static var all:[Self] {[.x,.y,.z]}
}
