import Foundation
import CryptoKit

/// Discrete contact with the same closed triangle surface that is displayed.
/// This complements the SDF's vertex projection; it is not swept collision.
nonisolated enum GarmentCodeBodySurfaceContact {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3
    typealias Topology = GarmentCodeClothContact.Topology
    /// Sub-micrometre tolerance for distinguishing a proper crossing from
    /// rounded waist-contour samples or a tangent contact.
    static let intersectionToleranceMeters = 1e-7

    /// Geometry/provenance receipt, not an arbitrary `isValidated` flag. Its
    /// private construction is used by the heavy factory only after Rig's
    /// private ValidatedBody and independent exact-query SHA have succeeded.
    struct FixedSurfaceReceipt:Sendable {
        let mesh:BodyMesh
        let geometrySHA256:String,sourceGeometrySHA256:String,rigResourceSHA256:String
        let requestedAlphaDegrees:Double
        fileprivate init(mesh:BodyMesh,geometrySHA256:String,sourceGeometrySHA256:String,
                         rigResourceSHA256:String,requestedAlphaDegrees:Double) {
            self.mesh=mesh;self.geometrySHA256=geometrySHA256;self.sourceGeometrySHA256=sourceGeometrySHA256
            self.rigResourceSHA256=rigResourceSHA256;self.requestedAlphaDegrees=requestedAlphaDegrees
        }
        func verify(positions:[Vector3],triangleIndices:[UInt32])throws {
            guard positions==mesh.positions,triangleIndices==mesh.triangleIndices,
                  geometrySHA256==GarmentCodeBodySurfaceContact.geometrySHA256(positions,triangleIndices),
                  rigResourceSHA256=="91e06b16078cb136678580fed690a0a4cd08f8284fca6c721e670aacfd7472ff",
                  requestedAlphaDegrees.isFinite,(0...90).contains(requestedAlphaDegrees) else {
                throw ContactError.invalid("固定姿态人体的表面、SHA 或原 Rig 来源不一致。")
            }
        }
    }
    static func captureFixedSurface(positions:[Vector3],triangleIndices:[UInt32],expectedGeometrySHA256:String,
        sourcePositions:[Vector3],sourceTriangleIndices:[UInt32],rigResourceSHA256:String,requestedAlphaDegrees:Double,
        templateData:Data,rigData:Data,bodyValues:[String:Double],
        isCancelled:@Sendable()->Bool={false})throws->FixedSurfaceReceipt {
        if isCancelled(){throw CancellationError()}
        guard triangleIndices==sourceTriangleIndices,positions.count==sourcePositions.count else {throw ContactError.invalid("摆臂不能更换原人体顶点或三角面编号。")}
        try replayFixedPose(positions:positions,indices:triangleIndices,sourcePositions:sourcePositions,
            templateData:templateData,rigData:rigData,bodyValues:bodyValues,alpha:requestedAlphaDegrees,
            rigSHA:rigResourceSHA256,isCancelled:isCancelled)
        let mesh=try BodyMesh(positions:positions,triangleIndices:triangleIndices)
        let sha=geometrySHA256(mesh.positions,mesh.triangleIndices)
        guard sha==expectedGeometrySHA256 else {throw ContactError.invalid("固定姿态的实际表面SHA不符。")}
        let result=FixedSurfaceReceipt(mesh:mesh,geometrySHA256:sha,
            sourceGeometrySHA256:geometrySHA256(sourcePositions,sourceTriangleIndices),
            rigResourceSHA256:rigResourceSHA256,requestedAlphaDegrees:requestedAlphaDegrees)
        try result.verify(positions:positions,triangleIndices:triangleIndices)
        if isCancelled(){throw CancellationError()}
        return result
    }
    // A cross-file caller cannot substitute arbitrary vertices by supplying a
    // plausible SHA. Replay the pinned source transform and all skin weights;
    // no Rig/Q type dependency is introduced into legacy kernel compilation.
    private struct PoseTemplate:Decodable {
        let baseline:[String:Double],positions:[[Double]],triangleIndices:[UInt32]
    }
    private struct PoseRig:Decodable {
        struct Point:Decodable {let templatePositionMeters:[Double]}
        struct Joint:Decodable {let sourceVertexTableIndices:[Int]}
        struct Bone:Decodable {let name:String,parent:Int?,head:Int,tail:Int}
        struct Weights:Decodable {let vertexOffsets:[Int],boneIndices:[Int],normalizedValues:[Double]}
        let templateResourceSHA256:String,jointSourceVertexTable:[Point],joints:[Joint],bones:[Bone],boneEvaluationOrder:[Int],weights:Weights
    }
    private static func replayFixedPose(positions:[Vector3],indices:[UInt32],sourcePositions:[Vector3],
        templateData:Data,rigData:Data,bodyValues:[String:Double],alpha:Double,rigSHA:String,
        isCancelled:@Sendable()->Bool)throws {
        func dataSHA(_ d:Data)->String{SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
        guard templateData.count<=8_000_000,rigData.count<=8_000_000,
              rigSHA=="91e06b16078cb136678580fed690a0a4cd08f8284fca6c721e670aacfd7472ff",dataSHA(rigData)==rigSHA,
              alpha.isFinite,(0...90).contains(alpha),bodyValues["arm_pose_angle"]==alpha else {throw ContactError.invalid("摆姿源资源或请求角不匹配。")}
        let r=try JSONDecoder().decode(PoseRig.self,from:rigData)
        guard dataSHA(templateData)==r.templateResourceSHA256 else {throw ContactError.invalid("摆姿模板不是Rig绑定的CC0表面。")}
        let t=try JSONDecoder().decode(PoseTemplate.self,from:templateData),base=t.baseline
        guard t.positions.count==13380,positions.count==13380,t.triangleIndices==indices,
              let height=bodyValues["height"],let waist=bodyValues["waist"],let hips=bodyValues["hips"],
              let hipLine=bodyValues["hips_line"],let waistLevel=bodyValues["_waist_level"],
              let bh=base["height"],let bw=base["waist"],let bp=base["hips"],let bl=base["hipLine"],let blevel=base["waistLevel"] else {throw ContactError.invalid("摆姿原始人体尺度缺失。")}
        let ws=waist/100/bw,hs=hips/100/bp,hy=hipLine/100/bl,
            ly=(waistLevel-hipLine)/100/(blevel-bl),uy=(height-waistLevel)/100/(bh-blevel)
        guard [ws,hs,hy,ly,uy].allSatisfy({$0.isFinite && (0.5...1.8).contains($0)}) else {throw ContactError.invalid("摆姿原始人体尺度无效。")}
        func warp(_ a:[Double])->Vector3 {
            let y=a[1],q=max(0,min(1,(y+bl)/bl)),blend=q*q*(3-2*q),h=hs+(ws-hs)*blend
            let yy=y>=0 ? y*uy:(y>=(-bl) ? y*hy:-bl*hy+(y+bl)*ly)
            return .init(x:a[0]*h,y:yy,z:a[2]*h)
        }
        func same(_ a:Vector3,_ b:Vector3)->Bool{a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern}
        for i in positions.indices {
            if i%128==0,isCancelled(){throw CancellationError()}
            guard same(sourcePositions[i],warp(t.positions[i])) else {throw ContactError.invalid("摆姿的原始人体不是同一五尺度CC0表面。")}
        }
        let helper=r.jointSourceVertexTable.map{warp($0.templatePositionMeters)}
        let joints=r.joints.map {j->Vector3 in
            let sum=j.sourceVertexTableIndices.map{helper[$0]}.reduce(Vector3.zero,+),n=Double(j.sourceVertexTableIndices.count)
            return .init(x:sum.x/n,y:sum.y/n,z:sum.z/n)
        }
        var radians=Array(repeating:0.0,count:r.bones.count),pivots=Array(repeating:Vector3.zero,count:r.bones.count)
        for side in ["L","R"] {
            let root=r.bones.firstIndex{$0.name=="upperarm01."+side}!,elbow=r.bones.firstIndex{$0.name=="upperarm02."+side}!
            let pivot=joints[r.bones[root].head],axis=joints[r.bones[elbow].tail]-pivot
            let rest=atan2(-axis.y,abs(axis.x)),delta=(rest-alpha*Double.pi/180)*(side=="L" ? 1:-1)
            var affected=Set<Int>()
            for id in r.boneEvaluationOrder {let b=r.bones[id];if id==root || (b.parent != nil && affected.contains(b.parent!)) {affected.insert(id);radians[id]=delta;pivots[id]=pivot}}
        }
        for i in positions.indices {
            if i%128==0,isCancelled(){throw CancellationError()}
            let p=sourcePositions[i];var delta=Vector3.zero
            for j in r.weights.vertexOffsets[i]..<r.weights.vertexOffsets[i+1] {
                let bone=r.weights.boneIndices[j],rad=radians[bone]
                if rad==0{continue}
                let q=p-pivots[bone],c=cos(rad)-1,s=sin(rad)
                delta=delta+Vector3(x:c*q.x-s*q.y,y:s*q.x+c*q.y,z:0)*r.weights.normalizedValues[j]
            }
            let expected=(delta.x != 0 || delta.y != 0 || delta.z != 0) ? p+delta:p
            guard same(positions[i],expected) else {throw ContactError.invalid("摆姿顶点与固定源Rig全部权重重放不符。")}
        }
        // The receipt has its own actual geometric gates as well as replay;
        // a direct caller cannot bypass the heavy Rig's fold/crossing rejection.
        for k in stride(from:0,to:indices.count,by:3) {
            if k%384==0,isCancelled(){throw CancellationError()}
            let a=Int(indices[k]),b=Int(indices[k+1]),c=Int(indices[k+2])
            let n=(positions[b]-positions[a]).cross(positions[c]-positions[a]),old=(sourcePositions[b]-sourcePositions[a]).cross(sourcePositions[c]-sourcePositions[a])
            guard n.lengthSquared>1e-22,n.x*old.x+n.y*old.y+n.z*old.z>0 else {throw ContactError.invalid("摆姿重放含退化或相对反转三角面。")}
        }
        let topology=try GarmentCodeClothContact.Topology(vertexCount:positions.count,triangleIndices:indices,isCancelled:isCancelled)
        let inspection=try GarmentCodeClothContact.inspect(positions:positions,topology:topology,thickness:0.0001,maximumCandidatePairs:300_000,isCancelled:isCancelled)
        guard inspection.intersectingTrianglePairs==0,inspection.degenerateTriangles==0 else {throw ContactError.invalid("摆姿重放存在非邻面交叉。")}
    }

    private static func geometrySHA256(_ positions:[Vector3],_ indices:[UInt32])->String {
        var d=Data("rigid-clearance-visible-body-v1\0".utf8)
        func add<T:FixedWidthInteger>(_ x:T){var y=x.littleEndian;withUnsafeBytes(of:&y){d.append(contentsOf:$0)}}
        add(UInt64(positions.count));add(UInt64(indices.count))
        for p in positions {add(p.x.bitPattern);add(p.y.bitPattern);add(p.z.bitPattern)}
        for i in indices {add(i)}
        return SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()
    }

    enum ContactError: LocalizedError, Sendable {
        case invalid(String)
        case budgetExceeded
        var errorDescription: String? {
            switch self {
            case let .invalid(message): return message
            case .budgetExceeded: return "人体表面碰撞超出本轮检查预算，不能确认布片与人体已分离。"
            }
        }
    }

    struct Statistics: Codable, Sendable {
        var candidateTrianglePairs = 0
        var clothVertexTriangleContacts = 0
        var bodyVertexTriangleContacts = 0
        var edgeEdgeContacts = 0
        var edgeCrossingContacts = 0
        var crossingRepairs = 0
        var unresolvedPinnedContacts = 0
        var maximumCorrectionMeters = 0.0
    }

    struct Quality: Codable, Sendable {
        let candidateTrianglePairs: Int
        let intersectingTrianglePairs: Int
        let degenerateClothTriangles: Int
        /// A local tangent-plane overlap, not a signed volumetric depth.
        let maximumPlaneOverlapMeters: Double
    }

    fileprivate struct Bounds: Sendable {
        let low: Vector3, high: Vector3
        init(_ a: Vector3, _ b: Vector3, _ c: Vector3) {
            low = .init(x: min(a.x,b.x,c.x), y: min(a.y,b.y,c.y), z: min(a.z,b.z,c.z))
            high = .init(x: max(a.x,b.x,c.x), y: max(a.y,b.y,c.y), z: max(a.z,b.z,c.z))
        }
        init(low: Vector3, high: Vector3) { self.low=low; self.high=high }
        func union(_ b: Self) -> Self {
            .init(low: .init(x:min(low.x,b.low.x),y:min(low.y,b.low.y),z:min(low.z,b.low.z)),
                  high: .init(x:max(high.x,b.high.x),y:max(high.y,b.high.y),z:max(high.z,b.high.z)))
        }
        func overlaps(_ b: Self, margin: Double) -> Bool {
            low.x <= b.high.x+margin && high.x+margin >= b.low.x &&
            low.y <= b.high.y+margin && high.y+margin >= b.low.y &&
            low.z <= b.high.z+margin && high.z+margin >= b.low.z
        }
    }
    fileprivate struct Face: Sendable {
        let a: Int, b: Int, c: Int
        let normal: Vector3
        let bounds: Bounds
        var vertices: [Int] { [a,b,c] }
    }
    fileprivate struct Node: Sendable {
        let bounds: Bounds
        let left: Int, right: Int, start: Int, count: Int
    }

    struct BodyMesh: Sendable {
        let positions: [Vector3]
        let triangleIndices: [UInt32]
        fileprivate let faces: [Face]
        fileprivate let vertexNormals: [Vector3]
        fileprivate let nodes: [Node]
        fileprivate let faceOrder: [Int]

        /// Each component must be a consistently wound closed two-manifold.
        /// Signed volume canonicalizes reversed components independently.
        /// The optional SDF checks orientation, but never replaces the mesh.
        init(positions: [Vector3], triangleIndices: [UInt32],
             signedDistance: (@Sendable (Vector3) -> Double?)? = nil) throws {
            guard (4...100_000).contains(positions.count),
                  !triangleIndices.isEmpty, triangleIndices.count % 3 == 0,
                  triangleIndices.count <= 600_000,
                  positions.allSatisfy({ $0.isFinite && $0.length < 100 }) else {
                throw ContactError.invalid("人体表面网格坐标或数量无效。")
            }
            struct EdgeUse { var count: Int; var direction: Int }
            var edges: [UInt64:EdgeUse] = [:]
            var parent=Array(positions.indices)
            func find(_ i: Int) -> Int { var p=i; while parent[p] != p { p=parent[p] }; return p }
            var raw: [(Int,Int,Int,Vector3)] = []
            for t in stride(from:0,to:triangleIndices.count,by:3) {
                let a=Int(triangleIndices[t]),b=Int(triangleIndices[t+1]),c=Int(triangleIndices[t+2])
                guard a<positions.count,b<positions.count,c<positions.count,a != b,b != c,c != a else {
                    throw ContactError.invalid("人体表面网格含无效三角面。")
                }
                let cross=(positions[b]-positions[a]).cross(positions[c]-positions[a])
                guard cross.lengthSquared>1e-22 else { throw ContactError.invalid("人体表面含退化三角面。") }
                raw.append((a,b,c,cross))
                parent[find(b)]=find(a); parent[find(c)]=find(a)
                for (i,j) in [(a,b),(b,c),(c,a)] {
                    let key=(UInt64(min(i,j))<<32)|UInt64(max(i,j))
                    var value=edges[key] ?? .init(count:0,direction:0)
                    value.count += 1; value.direction += i<j ? 1 : -1; edges[key]=value
                }
            }
            guard edges.values.allSatisfy({ $0.count==2 && $0.direction==0 }) else {
                throw ContactError.invalid("人体表面必须闭合且三角面方向一致，不能跳过开放或翻转的面。")
            }
            var volumes: [Int:Double] = [:]
            for (a,b,c,_) in raw {
                volumes[find(a),default:0] += dot(positions[a],positions[b].cross(positions[c]))/6
            }
            guard volumes.values.allSatisfy({ $0.isFinite && abs($0)>1e-12 }) else {
                throw ContactError.invalid("人体表面组件没有可靠的内外体积方向。")
            }
            var faces: [Face] = [], normals=Array(repeating:Vector3.zero,count:positions.count)
            for (a,b,c,cross) in raw {
                let oriented=cross*((volumes[find(a)]! > 0) ? 1 : -1)
                let normal=oriented/oriented.length
                faces.append(.init(a:a,b:b,c:c,normal:normal,bounds:.init(positions[a],positions[b],positions[c])))
                normals[a]=normals[a]+oriented; normals[b]=normals[b]+oriented; normals[c]=normals[c]+oriented
            }
            normals=normals.map { unit($0) ?? .zero }
            if let signedDistance {
                var agreed=0, opposed=0
                for i in stride(from:0,to:faces.count,by:max(1,faces.count/256)) {
                    let face=faces[i], center=(positions[face.a]+positions[face.b]+positions[face.c])/3
                    if let outside=signedDistance(center+face.normal*0.004),
                       let inside=signedDistance(center-face.normal*0.004),abs(outside-inside)>1e-6 {
                        if outside>inside { agreed += 1 } else { opposed += 1 }
                    }
                }
                guard opposed<8 || opposed<3*agreed else {
                    throw ContactError.invalid("人体碰撞场的内外方向与显示三角面不一致。")
                }
            }
            var nodes: [Node] = [], order: [Int] = []
            func build(_ ids: [Int]) -> Int {
                let box=ids.dropFirst().reduce(faces[ids[0]].bounds) { $0.union(faces[$1].bounds) }
                let index=nodes.count
                nodes.append(.init(bounds:box,left:-1,right:-1,start:0,count:0))
                if ids.count<=8 {
                    let start=order.count; order += ids
                    nodes[index] = .init(bounds:box,left:-1,right:-1,start:start,count:ids.count)
                } else {
                    let size=box.high-box.low
                    let axis = size.x>=size.y && size.x>=size.z ? 0 : (size.y>=size.z ? 1 : 2)
                    func center(_ i: Int) -> Double {
                        let b=faces[i].bounds
                        return axis==0 ? b.low.x+b.high.x : (axis==1 ? b.low.y+b.high.y : b.low.z+b.high.z)
                    }
                    let sorted=ids.sorted { center($0)==center($1) ? $0<$1 : center($0)<center($1) }, mid=ids.count/2
                    let left=build(Array(sorted[..<mid])),right=build(Array(sorted[mid...]))
                    nodes[index] = .init(bounds:box,left:left,right:right,start:0,count:0)
                }
                return index
            }
            _ = build(Array(faces.indices))
            self.positions=positions; self.triangleIndices=triangleIndices
            self.faces=faces; self.vertexNormals=normals; self.nodes=nodes; self.faceOrder=order
        }
    }

    private struct Pair { let cloth: Int, body: Int }
    private struct Closest { let point: Vector3; let barycentric: [Double] }
    private struct SegmentClosest { let a: Vector3, b: Vector3; let s: Double, t: Double }
    private static func dot(_ a:Vector3,_ b:Vector3)->Double { a.x*b.x+a.y*b.y+a.z*b.z }
    private static func unit(_ v:Vector3)->Vector3? { v.length>1e-12 ? v/v.length : nil }
    private static func clamp(_ v:Double)->Double { max(0,min(1,v)) }

    private static func validate(_ positions:[Vector3],topology:Topology,thickness:Double) throws {
        guard positions.count==topology.vertexCount,positions.allSatisfy({$0.isFinite && $0.length<100}),
              thickness.isFinite,(0.0001...0.02).contains(thickness) else {
            throw ContactError.invalid("人体表面接触收到无效布片坐标、数量或厚度。")
        }
    }

    private static func candidates(positions:[Vector3],topology:Topology,body:BodyMesh,
                                   thickness:Double,maximumCandidatePairs:Int,
                                   isCancelled:@Sendable()->Bool) throws -> [Pair] {
        guard (1...1_000_000).contains(maximumCandidatePairs) else {
            throw ContactError.invalid("人体表面接触候选预算无效。")
        }
        var result:[Pair]=[], visits=0
        for (i,face) in topology.triangles.enumerated() {
            if i%64==0 && isCancelled() { throw CancellationError() }
            let box=Bounds(positions[face.a],positions[face.b],positions[face.c])
            var stack=[0]
            while let index=stack.popLast() {
                visits += 1
                guard visits<=max(1_000_000,maximumCandidatePairs*64) else { throw ContactError.budgetExceeded }
                let node=body.nodes[index]
                guard box.overlaps(node.bounds,margin:thickness) else { continue }
                if node.count>0 {
                    for j in node.start..<(node.start+node.count) {
                        let bodyID=body.faceOrder[j]
                        if box.overlaps(body.faces[bodyID].bounds,margin:thickness) {
                            guard result.count<maximumCandidatePairs else { throw ContactError.budgetExceeded }
                            result.append(.init(cloth:i,body:bodyID))
                        }
                    }
                } else { stack.append(node.right); stack.append(node.left) }
            }
        }
        return result
    }

    private static func onSegment(_ p:Vector3,_ a:Vector3,_ b:Vector3)->(Vector3,Double) {
        let e=b-a,t=e.lengthSquared>1e-24 ? clamp(dot(p-a,e)/e.lengthSquared) : 0
        return (a+e*t,t)
    }
    private static func onTriangle(_ p:Vector3,_ a:Vector3,_ b:Vector3,_ c:Vector3)->Closest {
        let ab=b-a,ac=c-a
        if ab.cross(ac).lengthSquared<1e-24 {
            let x=onSegment(p,a,b),y=onSegment(p,b,c),z=onSegment(p,c,a)
            return [Closest(point:x.0,barycentric:[1-x.1,x.1,0]),
                    Closest(point:y.0,barycentric:[0,1-y.1,y.1]),
                    Closest(point:z.0,barycentric:[z.1,0,1-z.1])].min { ($0.point-p).lengthSquared<($1.point-p).lengthSquared }!
        }
        let ap=p-a,d1=dot(ab,ap),d2=dot(ac,ap)
        if d1<=0 && d2<=0 { return .init(point:a,barycentric:[1,0,0]) }
        let bp=p-b,d3=dot(ab,bp),d4=dot(ac,bp)
        if d3>=0 && d4<=d3 { return .init(point:b,barycentric:[0,1,0]) }
        let vc=d1*d4-d3*d2
        if vc<=0 && d1>=0 && d3<=0 { let v=d1/(d1-d3);return .init(point:a+ab*v,barycentric:[1-v,v,0]) }
        let cp=p-c,d5=dot(ab,cp),d6=dot(ac,cp)
        if d6>=0 && d5<=d6 { return .init(point:c,barycentric:[0,0,1]) }
        let vb=d5*d2-d1*d6
        if vb<=0 && d2>=0 && d6<=0 { let w=d2/(d2-d6);return .init(point:a+ac*w,barycentric:[1-w,0,w]) }
        let va=d3*d6-d5*d4
        if va<=0 && d4-d3>=0 && d5-d6>=0 { let w=(d4-d3)/((d4-d3)+(d5-d6));return .init(point:b+(c-b)*w,barycentric:[0,1-w,w]) }
        let inverse=1/(va+vb+vc),v=vb*inverse,w=vc*inverse
        return .init(point:a+ab*v+ac*w,barycentric:[1-v-w,v,w])
    }
    private static func closestEdges(_ a:Vector3,_ b:Vector3,_ c:Vector3,_ d:Vector3)->SegmentClosest {
        let u=b-a,v=d-c,w=a-c,aa=dot(u,u),bb=dot(u,v),cc=dot(v,v),dd=dot(u,w),ee=dot(v,w)
        if aa<1e-24 {let q=onSegment(a,c,d);return .init(a:a,b:q.0,s:0,t:q.1)}
        if cc<1e-24 {let q=onSegment(c,a,b);return .init(a:q.0,b:c,s:q.1,t:0)}
        let denominator=aa*cc-bb*bb
        var s=denominator>1e-24 ? clamp((bb*ee-cc*dd)/denominator) : 0
        var t=(bb*s+ee)/cc
        if t<0 {t=0;s=clamp(-dd/aa)}
        else if t>1 {t=1;s=clamp((bb-dd)/aa)}
        return .init(a:a+u*s,b:c+v*t,s:s,t:t)
    }

    /// A proper crossing has a positive-length overlap of the two plane-cut
    /// segments. Isolated touches, coplanar faces and rounded boundary samples
    /// are contacts, not face interiors cutting through each other.
    private static func crossingPoint(_ a:[Vector3],_ b:[Vector3])->Vector3? {
        guard let na=unit((a[1]-a[0]).cross(a[2]-a[0])),
              let nb=unit((b[1]-b[0]).cross(b[2]-b[0])),
              let line=unit(na.cross(nb)) else {return nil}
        let da=a.map {dot($0-b[0],nb)},db=b.map {dot($0-a[0],na)},epsilon=intersectionToleranceMeters
        guard da.min()! < -epsilon,da.max()! > epsilon,db.min()! < -epsilon,db.max()! > epsilon else {return nil}
        func interval(_ p:[Vector3],_ distances:[Double])->(Double,Double,Vector3)? {
            var points:[Vector3]=[]
            for i in 0..<3 {
                let j=(i+1)%3,di=distances[i],dj=distances[j]
                if abs(di)<=epsilon {points.append(p[i])}
                if di*dj<0 {points.append(p[i]+(p[j]-p[i])*(di/(di-dj)))}
            }
            let values=points.map {dot($0,line)}
            guard let low=values.min(),let high=values.max() else {return nil}
            return (low,high,points[0])
        }
        guard let x=interval(a,da),let y=interval(b,db) else {return nil}
        let low=max(x.0,y.0),high=min(x.1,y.1)
        guard high-low>epsilon else {return nil}
        return x.2+line*((low+high)/2-dot(x.2,line))
    }
    private static func crosses(_ a:[Vector3],_ b:[Vector3])->Bool {
        crossingPoint(a,b) != nil
    }

    static func project(positions:inout[Vector3],inverseMass:[Double],topology:Topology,
                        body:BodyMesh,thickness:Double,previousPositions:[Vector3]?=nil,
                        maximumCandidatePairs:Int=200_000,
                        isCancelled:@Sendable()->Bool={false}) throws -> Statistics {
        if isCancelled() {throw CancellationError()}
        try validate(positions,topology:topology,thickness:thickness)
        guard inverseMass.count==positions.count,inverseMass.allSatisfy({$0.isFinite && $0>=0}),
              previousPositions == nil || (previousPositions!.count==positions.count && previousPositions!.allSatisfy(\.isFinite)) else {
            throw ContactError.invalid("人体表面接触收到无效质量或历史坐标。")
        }
        let pairs=try candidates(positions:positions,topology:topology,body:body,thickness:thickness,
                                 maximumCandidatePairs:maximumCandidatePairs,isCancelled:isCancelled)
        var stats=Statistics();stats.candidateTrianglePairs=pairs.count
        func move(_ ids:[Int],_ gradients:[Double],normal:Vector3,depth:Double) {
            guard depth>1e-10 else {return}
            let denominator=zip(ids,gradients).reduce(0.0) {$0+inverseMass[$1.0]*$1.1*$1.1}
            guard denominator>1e-20 else {stats.unresolvedPinnedContacts += 1;return}
            // A contact carried mostly by a pinned face corner can have a
            // tiny free barycentric weight. Bound actual vertex motion, not
            // just constraint depth, without changing the mass ratios.
            let largestWeight=zip(ids,gradients).map {abs(inverseMass[$0.0]*$0.1)}.max() ?? 0
            let amount=min(depth/denominator,0.02/max(1e-20,largestWeight))
            for (i,g) in zip(ids,gradients) {
                let correction=normal*(amount*inverseMass[i]*g)
                positions[i]=positions[i]+correction
                stats.maximumCorrectionMeters=max(stats.maximumCorrectionMeters,correction.length)
            }
        }
        for (index,pair) in pairs.enumerated() {
            if index%128==0 && isCancelled() {throw CancellationError()}
            let cloth=topology.triangles[pair.cloth],face=body.faces[pair.body]
            let ids=cloth.vertices,bb=face.vertices.map {body.positions[$0]}
            var aa=ids.map {positions[$0]}
            // AABB overlap is necessary but not sufficient. If the complete
            // cloth triangle is farther than the shell on either side of
            // this body face's plane, its vertices and edges cannot be within
            // the shell of that finite face, nor can its interior cross it.
            // This rejects empty work before all nine edge-distance solves.
            let planeDistances=aa.map {dot($0-bb[0],face.normal)}
            if planeDistances.min()!>thickness || planeDistances.max()! < -thickness {continue}
            let crossing=crossingPoint(aa,bb)
            if let point=crossing {
                // Only the actual clipped intersection carries this contact.
                // Projecting every cloth corner outside an infinite local
                // body-face plane overconstrains a sheet wrapping curved skin.
                let barycentric=onTriangle(point,aa[0],aa[1],aa[2]).barycentric
                move(ids,barycentric,normal:face.normal,depth:thickness)
                stats.crossingRepairs += 1;stats.edgeCrossingContacts += 1
                aa=ids.map {positions[$0]}
            }
            for id in ids {
                let p=positions[id],q=onTriangle(p,bb[0],bb[1],bb[2]),delta=p-q.point
                let distance=delta.length,signed=dot(delta,face.normal)
                let insideFacet=q.barycentric.allSatisfy {$0>1e-7}
                if (distance<thickness && signed > -thickness) || (crossing != nil && signed<0 && insideFacet) {
                    move([id],[1],normal:face.normal,depth:thickness-signed)
                    stats.clothVertexTriangleContacts += 1
                }
            }
            for id in face.vertices {
                aa=ids.map {positions[$0]}
                let p=body.positions[id],q=onTriangle(p,aa[0],aa[1],aa[2]),delta=q.point-p
                let normal=body.vertexNormals[id]
                let gap=dot(delta,normal),insideFace=q.barycentric.allSatisfy {$0>1e-7}
                if normal.lengthSquared>0.5 && (delta.length<thickness || (crossing != nil && gap<0 && insideFace)) {
                    move(ids,q.barycentric,normal:normal,depth:thickness-gap)
                    stats.bodyVertexTriangleContacts += 1
                }
            }
            // Edge proximity prevents a body edge entering between the cloth
            // vertices while both endpoint-to-face distances remain clear.
            for (i,j) in [(0,1),(1,2),(2,0)] {
                for (k,l) in [(0,1),(1,2),(2,0)] {
                    let p=closestEdges(positions[ids[i]],positions[ids[j]],bb[k],bb[l])
                    let delta=p.a-p.b
                    if delta.length<thickness {
                        let na=body.vertexNormals[face.vertices[k]],nb=body.vertexNormals[face.vertices[l]]
                        let normal=unit(na*(1-p.t)+nb*p.t) ?? face.normal
                        move([ids[i],ids[j]],[1-p.s,p.s],normal:normal,depth:thickness-dot(delta,normal))
                        stats.edgeEdgeContacts += 1
                    }
                }
            }
        }
        guard positions.allSatisfy(\.isFinite) else {throw ContactError.invalid("人体表面碰撞产生非有限坐标。")}
        return stats
    }

    static func inspect(positions:[Vector3],topology:Topology,body:BodyMesh,thickness:Double=0.0025,
                        maximumCandidatePairs:Int=200_000,
                        isCancelled:@Sendable()->Bool={false}) throws -> Quality {
        if isCancelled() {throw CancellationError()}
        try validate(positions,topology:topology,thickness:thickness)
        let pairs=try candidates(positions:positions,topology:topology,body:body,thickness:thickness,
                                 maximumCandidatePairs:maximumCandidatePairs,isCancelled:isCancelled)
        var intersections=0,overlap=0.0
        for (i,pair) in pairs.enumerated() {
            if i%128==0 && isCancelled() {throw CancellationError()}
            let cloth=topology.triangles[pair.cloth],face=body.faces[pair.body]
            let aa=cloth.vertices.map {positions[$0]},bb=face.vertices.map {body.positions[$0]}
            if crosses(aa,bb) {
                intersections += 1
                overlap=max(overlap,max(0,-aa.map {dot($0-bb[0],face.normal)}.min()!))
            }
        }
        let degenerate=topology.triangles.filter {
            (positions[$0.b]-positions[$0.a]).cross(positions[$0.c]-positions[$0.a]).lengthSquared<1e-20
        }.count
        return .init(candidateTrianglePairs:pairs.count,intersectingTrianglePairs:intersections,
                     degenerateClothTriangles:degenerate,maximumPlaneOverlapMeters:overlap)
    }
}
