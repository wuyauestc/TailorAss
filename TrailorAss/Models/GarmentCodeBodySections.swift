import Foundation
import CryptoKit

/// Plane intersections of the exact visible triangle mesh, in metres. Every
/// connected contour is retained. No hull, anatomical selection, tape bridge,
/// automatic plane offset or body/SDF deformation is performed here.
nonisolated enum GarmentCodeBodySections {
    typealias V=GarmentCodeCircleDrape.Vector3
    struct Limits:Sendable {
        var maximumVertices=100_000
        var maximumTriangles=200_000
        var maximumSegments=20_000
        var maximumLoops=128
        var maximumContourPairTests=2_000_000
    }
    struct Plane:Codable,Sendable {
        let origin:V
        let unitNormal:V
        init(origin:V,normal:V)throws {
            guard origin.isFinite,origin.length<100,normal.isFinite,normal.length.isFinite,
                  normal.length>1e-12 else {throw SectionError.invalid("截面平面坐标或法向无效。")}
            self.origin=origin;self.unitNormal=normal/normal.length
        }
    }
    enum SectionError:LocalizedError,Sendable {
        case invalid(String),budget(String)
        var errorDescription:String?{switch self{case let .invalid(s):return "人体截面无效："+s;case let .budget(s):return "人体截面超出预算："+s}}
    }
    enum Status:String,Codable,Sendable {case complete,indeterminate}
    enum Issue:Codable,Sendable {
        case sourceFeature(vertexIDs:[Int],coplanarTriangleIDs:[Int])
        case numericalIntersection(triangleID:Int)
        case ambiguousContour
    }
    struct SourceEdge:Codable,Hashable,Sendable {
        let a:Int,b:Int
        fileprivate init(_ i:Int,_ j:Int){a=min(i,j);b=max(i,j)}
        fileprivate var key:UInt64{UInt64(a)<<32|UInt64(b)}
    }
    struct Vertex:Codable,Sendable {
        let position:V
        /// Interpolation parameter from the smaller source vertex ID to larger.
        let sourceEdge:SourceEdge
        let edgeParameter:Double
    }
    struct Segment:Codable,Sendable {
        let sourceTriangleID:Int
        let fromVertex:Int,toVertex:Int
    }
    struct Loop:Codable,Sendable {
        /// No repeated last point. Boundary includes the final-to-first segment.
        let vertices:[Vertex]
        let boundary:[Segment]
        let perimeterMeters:Double
        let areaSquareMeters:Double
        let minimum:V,maximum:V
    }
    struct Section:Codable,Sendable {
        let bodyGeometrySHA256:String
        let sourceVertexCount:Int,sourceTriangleCount:Int
        let plane:Plane
        let numericalPlaneToleranceMeters:Double
        let status:Status
        let issue:Issue?
        /// Independent loops, not a union area or a selected body measurement.
        let loops:[Loop]
        let sourceSegmentCount:Int
        let maximumPlaneResidualMeters:Double
    }
    private struct Use {var faces:[Int]=[];var direction=0}
    private struct Face {let ids:[Int]}
    private struct Crossing {let a:UInt64,b:UInt64,face:Int}

    static func slice(positions:[V],triangleIndices:[UInt32],plane:Plane,
        numericalPlaneToleranceMeters tolerance:Double=1e-11,limits:Limits = .init(),
        isCancelled:@Sendable()->Bool={false})throws->Section {
        func cancel()throws{if isCancelled(){throw CancellationError()}}
        try cancel()
        guard (4...100_000).contains(limits.maximumVertices),(4...200_000).contains(limits.maximumTriangles),
              (3...20_000).contains(limits.maximumSegments),(1...128).contains(limits.maximumLoops),
              (1...20_000_000).contains(limits.maximumContourPairTests),
              tolerance.isFinite,(0...1e-6).contains(tolerance),plane.origin.isFinite,plane.origin.length<100,
              plane.unitNormal.isFinite,abs(plane.unitNormal.length-1)<1e-12 else {throw SectionError.invalid("平面、误差声明或预算无效。")}
        guard positions.count<=limits.maximumVertices,triangleIndices.count/3<=limits.maximumTriangles else {throw SectionError.budget("源顶点或三角面数量。")}
        guard positions.count>=4,!triangleIndices.isEmpty,triangleIndices.count%3==0,
              positions.allSatisfy({$0.isFinite && $0.length<100}) else {throw SectionError.invalid("源网格必须有界且坐标有限。")}
        var uses:[UInt64:Use]=[:],faces:[Face]=[],incident=Array(repeating:[Int](),count:positions.count),unique=Set<[Int]>()
        var parent=Array(positions.indices)
        func find(_ i:Int)->Int{var p=i;while parent[p] != p{p=parent[p]};return p}
        for t in stride(from:0,to:triangleIndices.count,by:3){
            if t%384==0{try cancel()}
            let ids=(0..<3).map{Int(triangleIndices[t+$0])},f=t/3
            guard ids.allSatisfy({positions.indices.contains($0)}),Set(ids).count==3,
                  unique.insert(ids.sorted()).inserted else {throw SectionError.invalid("三角面引用越界、重复或退化。")}
            let a=positions[ids[0]],b=positions[ids[1]],c=positions[ids[2]]
            guard (b-a).cross(c-a).lengthSquared>1e-22 else {throw SectionError.invalid("源三角面几何退化。")}
            faces.append(.init(ids:ids));for id in ids{incident[id].append(f)}
            parent[find(ids[1])]=find(ids[0]);parent[find(ids[2])]=find(ids[0])
            for (i,j) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])]{
                let key=SourceEdge(i,j).key;var use=uses[key] ?? Use();use.faces.append(f);use.direction += i<j ? 1:-1;uses[key]=use
            }
        }
        guard uses.values.allSatisfy({$0.faces.count==2 && $0.direction==0}),incident.allSatisfy({!$0.isEmpty}) else {throw SectionError.invalid("源表面必须闭合、方向一致且没有未使用顶点。")}
        // Edge incidence alone misses two closed shells pinched at one vertex.
        // The link of each source vertex must have a single connected fan.
        for v in positions.indices{
            if v%128==0{try cancel()}
            var visited=Set<Int>(),stack=[incident[v][0]]
            while let f=stack.popLast(){
                if !visited.insert(f).inserted{continue}
                if visited.count%128==0{try cancel()}
                for other in faces[f].ids where other != v {
                    stack += uses[SourceEdge(v,other).key]!.faces.filter{!visited.contains($0)}
                }
            }
            guard visited.count==incident[v].count else {throw SectionError.invalid("源顶点的邻域不是单一闭合流形扇。")}
        }
        var volumes:[Int:Double]=[:]
        for (f,face) in faces.enumerated(){
            if f%256==0{try cancel()}
            let a=positions[face.ids[0]],b=positions[face.ids[1]],c=positions[face.ids[2]],cross=b.cross(c)
            volumes[find(face.ids[0]),default:0] += (a.x*cross.x+a.y*cross.y+a.z*cross.z)/6
        }
        guard volumes.values.allSatisfy({$0.isFinite && abs($0)>1e-12}) else {throw SectionError.invalid("封闭源组件的体积退化。")}
        let hash=try geometryHash(positions,triangleIndices,isCancelled:isCancelled)
        func result(_ loops:[Loop],_ count:Int,_ residual:Double,_ issue:Issue?=nil)->Section {
            .init(bodyGeometrySHA256:hash,sourceVertexCount:positions.count,sourceTriangleCount:faces.count,
                plane:plane,numericalPlaneToleranceMeters:tolerance,status:issue==nil ? .complete:.indeterminate,
                issue:issue,loops:loops,sourceSegmentCount:count,maximumPlaneResidualMeters:residual)
        }
        func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
        var distances:[Double]=[],on=Set<Int>()
        for (i,p) in positions.enumerated(){
            if i%256==0{try cancel()}
            let q=p-plane.origin,n=plane.unitNormal,d=dot(q,n)
            let rounding=32*Double.ulpOfOne*(abs(q.x*n.x)+abs(q.y*n.y)+abs(q.z*n.z)+1)
            distances.append(d);if abs(d)<=max(tolerance,rounding){on.insert(i)}
        }
        if !on.isEmpty{
            let coplanar=faces.indices.filter{faces[$0].ids.allSatisfy{on.contains($0)}}
            return result([],0,0,.sourceFeature(vertexIDs:on.sorted(),coplanarTriangleIDs:coplanar))
        }
        var points:[UInt64:Vertex]=[:],crossings:[Crossing]=[],adjacency:[UInt64:[Int]]=[:],residual=0.0
        for (f,face) in faces.enumerated(){
            if f%128==0{try cancel()}
            var keys:[UInt64]=[]
            for (i,j) in [(face.ids[0],face.ids[1]),(face.ids[1],face.ids[2]),(face.ids[2],face.ids[0])]{
                guard (distances[i]<0) != (distances[j]<0) else {continue}
                let edge=SourceEdge(i,j),key=edge.key;keys.append(key)
                if points[key]==nil{
                    let a=distances[edge.a],b=distances[edge.b],t=a/(a-b)
                    let p=positions[edge.a]+(positions[edge.b]-positions[edge.a])*t
                    guard t.isFinite,t>0,t<1,p.isFinite else {return result([],crossings.count,residual,.numericalIntersection(triangleID:f))}
                    residual=max(residual,abs(dot(p-plane.origin,plane.unitNormal)))
                    points[key] = .init(position:p,sourceEdge:edge,edgeParameter:t)
                }
            }
            if keys.isEmpty{continue}
            guard keys.count==2,keys[0] != keys[1] else {return result([],crossings.count,residual,.numericalIntersection(triangleID:f))}
            guard crossings.count<limits.maximumSegments else {throw SectionError.budget("截面交线段数量。")}
            let id=crossings.count;crossings.append(.init(a:keys[0],b:keys[1],face:f));for k in keys{adjacency[k,default:[]].append(id)}
        }
        guard adjacency.values.allSatisfy({$0.count==2}) else {return result([],crossings.count,residual,.ambiguousContour)}
        var consumed=Set<Int>(),loops:[Loop]=[]
        for start in points.keys.sorted(){
            guard adjacency[start]!.contains(where:{!consumed.contains($0)}) else {continue}
            try cancel();guard loops.count<limits.maximumLoops else {throw SectionError.budget("独立截面环数量。")}
            var nodes:[UInt64]=[],segments:[Int]=[],current=start
            repeat{
                nodes.append(current)
                guard let segment=adjacency[current]!.sorted().first(where:{!consumed.contains($0)}),consumed.insert(segment).inserted else {return result([],crossings.count,residual,.ambiguousContour)}
                let s=crossings[segment];segments.append(s.face);current=s.a==current ? s.b:s.a
                guard nodes.count<=points.count else {return result([],crossings.count,residual,.ambiguousContour)}
            }while current != start
            guard nodes.count>=3 else {return result([],crossings.count,residual,.ambiguousContour)}
            let origin=points[start]!.position
            var signedArea=0.0,perimeter=0.0
            for i in nodes.indices{
                let a=points[nodes[i]]!.position,b=points[nodes[(i+1)%nodes.count]]!.position
                signedArea += dot((a-origin).cross(b-origin),plane.unitNormal)/2;perimeter += (b-a).length
            }
            guard signedArea.isFinite,abs(signedArea)>1e-16,perimeter.isFinite,perimeter>0 else {return result([],crossings.count,residual,.ambiguousContour)}
            if signedArea<0{nodes=[nodes[0]]+nodes.dropFirst().reversed();segments.reverse()}
            let vertices=nodes.map{points[$0]!},p=vertices.map(\.position)
            loops.append(.init(vertices:vertices,boundary:segments.enumerated().map{.init(sourceTriangleID:$0.element,fromVertex:$0.offset,toVertex:($0.offset+1)%nodes.count)},
                perimeterMeters:perimeter,areaSquareMeters:abs(signedArea),
                minimum:.init(x:p.map(\.x).min()!,y:p.map(\.y).min()!,z:p.map(\.z).min()!),
                maximum:.init(x:p.map(\.x).max()!,y:p.map(\.y).max()!,z:p.map(\.z).max()!)))
        }
        guard consumed.count==crossings.count else {return result([],crossings.count,residual,.ambiguousContour)}
        // A closed graph can still be a geometric bow tie. Refuse ambiguous
        // or touching contours; never repair them with a convex envelope.
        let n=plane.unitNormal,seed:V=abs(n.x)<0.8 ? .init(x:1,y:0,z:0):.init(x:0,y:1,z:0)
        let raw=n.cross(seed),u=raw/raw.length,v=n.cross(u)
        struct E {let a:(Double,Double),b:(Double,Double),loop:Int,index:Int,count:Int}
        let edges=loops.enumerated().flatMap{l,loop in loop.vertices.indices.map{i -> E in
            func xy(_ p:V)->(Double,Double){let q=p-plane.origin;return(dot(q,u),dot(q,v))}
            return .init(a:xy(loop.vertices[i].position),b:xy(loop.vertices[(i+1)%loop.vertices.count].position),loop:l,index:i,count:loop.vertices.count)
        }}
        func orient(_ a:(Double,Double),_ b:(Double,Double),_ c:(Double,Double))->Double{(b.0-a.0)*(c.1-a.1)-(b.1-a.1)*(c.0-a.0)}
        var tests=0
        for i in edges.indices{for j in edges.indices where j>i{
            let a=edges[i],b=edges[j]
            if a.loop==b.loop && (abs(a.index-b.index)==1 || abs(a.index-b.index)==a.count-1){continue}
            tests += 1;if tests%256==0{try cancel()};guard tests<=limits.maximumContourPairTests else {throw SectionError.budget("截面交叉检查次数。")}
            let eps=max(tolerance,1e-12)
            if max(a.a.0,a.b.0)+eps<min(b.a.0,b.b.0) || max(b.a.0,b.b.0)+eps<min(a.a.0,a.b.0) || max(a.a.1,a.b.1)+eps<min(b.a.1,b.b.1) || max(b.a.1,b.b.1)+eps<min(a.a.1,a.b.1){continue}
            let p=orient(a.a,a.b,b.a),q=orient(a.a,a.b,b.b),r=orient(b.a,b.b,a.a),s=orient(b.a,b.b,a.b)
            let scale=max(1,hypot(a.b.0-a.a.0,a.b.1-a.a.1),hypot(b.b.0-b.a.0,b.b.1-b.a.1)),bound=eps*scale
            if (min(p,q)<=bound && max(p,q)>=(-bound)) && (min(r,s)<=bound && max(r,s)>=(-bound)){return result([],crossings.count,residual,.ambiguousContour)}
        }}
        try cancel();return result(loops,crossings.count,residual)
    }
    /// Same exact byte convention as rigid-clearance visible-body provenance.
    private static func geometryHash(_ positions:[V],_ indices:[UInt32],isCancelled:@Sendable()->Bool)throws->String {
        var bytes=Data("rigid-clearance-visible-body-v1\0".utf8)
        func append<T:FixedWidthInteger>(_ value:T){var v=value.littleEndian;withUnsafeBytes(of:&v){bytes.append(contentsOf:$0)}}
        append(UInt64(positions.count));append(UInt64(indices.count))
        for (i,p) in positions.enumerated(){if i%256==0 && isCancelled(){throw CancellationError()};append(p.x.bitPattern);append(p.y.bitPattern);append(p.z.bitPattern)}
        for (i,id) in indices.enumerated(){if i%768==0 && isCancelled(){throw CancellationError()};append(id)}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
}
