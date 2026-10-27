import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Distances and even-odd containment against the exact immutable visible mesh.
/// This is a bounded binary64 geometric query, not the coarse inverse-warp SDF,
/// a cloth projector, a continuous collision test, or a personal body fit.
nonisolated enum GarmentCodeBodyMeshQueries {
    typealias V = GarmentCodeCircleDrape.Vector3
    typealias BodyMesh = GarmentCodeBodySurfaceContact.BodyMesh

    struct Limits: Sendable {
        var maximumVertices = 100_000
        var maximumTriangles = 200_000
        var maximumBVHNodes = 100_000
    }
    struct Options: Sendable {
        /// A declared numerical surface band, not a physical garment thickness.
        var surfaceToleranceMeters = 1e-8
        var barycentricTolerance = 1e-10
        var angularTolerance = 1e-12
        var requiredAgreeingDirections = 3
        var maximumRayDirections = 12
        var maximumClosestNodeVisits = 200_000
        var maximumClosestTriangleTests = 200_000
        var maximumRayNodeVisits = 1_000_000
        var maximumRayTriangleTests = 1_000_000
    }
    enum Classification: String, Codable, Sendable {
        case inside, outside, onSurface, uncertain
    }
    enum Issue: String, Codable, Sendable {
        case invalidQuery, cancelled, nearestBudgetExceeded, parityBudgetExceeded
        case insufficientUnambiguousDirections, directionDisagreement, numericalIndeterminate, unsupportedRounding
    }
    enum RayIssue: String, Codable, Sendable {
        case nearParallel, sourceFeature, nearOrigin, arithmeticUnresolved
    }
    struct RayRecord: Codable, Sendable {
        let directionIndex: Int
        let direction: V
        let completed: Bool
        let crossings: Int
        let ambiguousTriangleID: Int?
        let issue: RayIssue?
        var isInside: Bool? { completed ? crossings % 2 == 1 : nil }
    }
    struct Statistics: Codable, Sendable {
        var closestNodeVisits = 0
        var closestTriangleTests = 0
        var rayNodeVisits = 0
        var rayTriangleTests = 0
        var acceptedDirections = 0
        var attemptedDirections = 0
        var rays: [RayRecord] = []
    }
    struct Result: Codable, Sendable {
        /// Nil if the nearest search itself was invalid, cancelled or incomplete.
        let unsignedDistanceMeters: Double?
        let closestPoint: V?
        let closestTriangleID: Int?
        let classification: Classification
        let issue: Issue?
        let surfaceToleranceMeters: Double
        let statistics: Statistics
        /// No sign is fabricated after an unresolved or partial parity query.
        /// onSurface is the explicitly reported tolerance band and returns zero.
        var signedDistanceMeters: Double? {
            guard let d = unsignedDistanceMeters else { return nil }
            switch classification {
            case .inside: return -d
            case .outside: return d
            case .onSurface: return 0
            case .uncertain: return nil
            }
        }
    }
    enum PreparationError: LocalizedError, Sendable {
        case invalid(String), budgetExceeded, unsupportedRounding
        var errorDescription: String? {
            switch self {
            case let .invalid(s): return "可见人体距离查询无效：" + s
            case .budgetExceeded: return "可见人体距离索引超出准备预算。"
            case .unsupportedRounding: return "当前浮点环境不支持可见人体距离查询。"
            }
        }
    }

    /// Elementary outward-rounded intervals. Source/query Doubles are exact
    /// inputs. These enclose the ray predicates; an unresolved interval never
    /// becomes a crossing. Nearest points remain numerical binary64 estimates.
    private struct I: Sendable {
        let lo: Double, hi: Double
        init(_ x: Double) { lo = x; hi = x }
        init(_ lo: Double, _ hi: Double) { self.lo = lo; self.hi = hi }
        var finite: Bool { lo.isFinite && hi.isFinite && lo <= hi }
        static func + (a: Self, b: Self) -> Self { .init((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp) }
        static func - (a: Self, b: Self) -> Self { .init((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp) }
        static func * (a: Self, b: Self) -> Self {
            let p=a.lo*b.lo,q=a.lo*b.hi,r=a.hi*b.lo,s=a.hi*b.hi
            return .init(min(min(p,q),min(r,s)).nextDown,max(max(p,q),max(r,s)).nextUp)
        }
        static func / (a: Self, b: Self) -> Self? {
            guard b.lo > 0 || b.hi < 0 else { return nil }
            return a * .init((1/b.hi).nextDown,(1/b.lo).nextUp)
        }
    }
    private struct IV: Sendable {
        let x: I, y: I, z: I
        init(_ p: V) { x=I(p.x);y=I(p.y);z=I(p.z) }
        init(_ x: I, _ y: I, _ z: I) {self.x=x;self.y=y;self.z=z}
        static func + (a: Self,b: Self)->Self { .init(a.x+b.x,a.y+b.y,a.z+b.z) }
        static func - (a: Self,b: Self)->Self { .init(a.x-b.x,a.y-b.y,a.z-b.z) }
        static func * (a: Self,b: I)->Self { .init(a.x*b,a.y*b,a.z*b) }
        func dot(_ b: Self)->I {x*b.x+y*b.y+z*b.z}
        func cross(_ b: Self)->Self { .init(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
    }
    private struct Box: Sendable {
        let lo: V, hi: V
        init(_ a: V,_ b: V,_ c: V) {
            lo = .init(x:min(a.x,b.x,c.x).nextDown,y:min(a.y,b.y,c.y).nextDown,z:min(a.z,b.z,c.z).nextDown)
            hi = .init(x:max(a.x,b.x,c.x).nextUp,y:max(a.y,b.y,c.y).nextUp,z:max(a.z,b.z,c.z).nextUp)
        }
        init(lo: V,hi: V) { self.lo=lo;self.hi=hi }
        func union(_ b: Self)->Self {
            .init(lo:.init(x:min(lo.x,b.lo.x),y:min(lo.y,b.lo.y),z:min(lo.z,b.lo.z)),
                  hi:.init(x:max(hi.x,b.hi.x),y:max(hi.y,b.hi.y),z:max(hi.z,b.hi.z)))
        }
        func lowerDistanceSquared(_ p: V)->Double {
            func delta(_ a: Double,_ b: Double,_ x: Double)->Double {
                if x<a { return max(0,(a-x).nextDown) }
                if x>b { return max(0,(x-b).nextDown) }
                return 0
            }
            let x=delta(lo.x,hi.x,p.x),y=delta(lo.y,hi.y,p.y),z=delta(lo.z,hi.z,p.z)
            return max(0,((x*x).nextDown+(y*y).nextDown).nextDown+(z*z).nextDown).nextDown
        }
        func intersectsRay(_ p: V,_ d: V)->Bool {
            var enter=0.0,exit=Double.infinity
            for (low,high,x,v) in [(lo.x,hi.x,p.x,d.x),(lo.y,hi.y,p.y,d.y),(lo.z,hi.z,p.z,d.z)] {
                if v==0 { if x<low || x>high { return false };continue }
                guard let t = (I(low,high)-I(x))/I(v),t.finite else { return true }
                enter=max(enter,t.lo);exit=min(exit,t.hi)
                if enter>exit { return false }
            }
            return exit>=0
        }
    }
    private struct Face: Sendable {
        let a: Int,b: Int,c: Int
        let box: Box
    }
    private struct Node: Sendable {
        let box: Box
        let left: Int,right: Int,start: Int,count: Int
    }
    private struct Closest {
        let point: V
        let distanceSquared: Double
        /// Upper bound to a real feasible point on this source triangle. Used
        /// for BVH pruning so a rounded nearest-point estimate cannot cull it.
        let upperDistanceSquared: Double
    }
    private enum Hit {
        case miss, crossing, ambiguous(RayIssue)
    }

    struct Prepared: Sendable {
        let positions: [V]
        let triangleIndices: [UInt32]
        let geometrySHA256: String
        let bvhNodeCount: Int
        private let faces: [Face]
        private let nodes: [Node]
        private let order: [Int]

        init(positions: [V],triangleIndices: [UInt32],limits: Limits = .init(),
             isCancelled: @Sendable ()->Bool = {false}) throws {
            if isCancelled() { throw CancellationError() }
            guard Self.nearestRounding() else { throw PreparationError.unsupportedRounding }
            try Self.validateLimits(limits,vertices:positions.count,triangles:triangleIndices.count/3)
            let body = try BodyMesh(positions:positions,triangleIndices:triangleIndices)
            try self.init(body:body,limits:limits,isCancelled:isCancelled)
        }
        init(body: BodyMesh,limits: Limits = .init(),
             isCancelled: @Sendable ()->Bool = {false}) throws {
            if isCancelled() { throw CancellationError() }
            guard Self.nearestRounding() else { throw PreparationError.unsupportedRounding }
            try Self.validateLimits(limits,vertices:body.positions.count,triangles:body.triangleIndices.count/3)
            let p=body.positions,ids=body.triangleIndices
            var f: [Face]=[]
            var incident=Array(repeating:[Int](),count:p.count)
            for offset in stride(from:0,to:ids.count,by:3) {
                if offset % 768 == 0 && isCancelled() { throw CancellationError() }
                let a=Int(ids[offset]),b=Int(ids[offset+1]),c=Int(ids[offset+2]),i=f.count
                f.append(.init(a:a,b:b,c:c,box:.init(p[a],p[b],p[c])))
                incident[a].append(i);incident[b].append(i);incident[c].append(i)
            }
            // Edge closure alone permits two fans joined only at a vertex.
            // Reject that non-manifold ambiguity and unused source vertices.
            for (vertex,fan) in incident.enumerated() {
                if vertex % 128 == 0 && isCancelled() { throw CancellationError() }
                guard !fan.isEmpty else { throw PreparationError.invalid("人体含未引用的孤立顶点。") }
                var byNeighbor: [Int:[Int]] = [:]
                for face in fan {
                    let t=f[face]
                    for v in [t.a,t.b,t.c] where v != vertex { byNeighbor[v,default:[]].append(face) }
                }
                guard byNeighbor.values.allSatisfy({$0.count==2}) else {
                    throw PreparationError.invalid("人体顶点邻域不是闭合流形。")
                }
                var seen=Set<Int>(),stack=[fan[0]]
                while let face=stack.popLast() {
                    if !seen.insert(face).inserted { continue }
                    let t=f[face]
                    for v in [t.a,t.b,t.c] where v != vertex { stack += byNeighbor[v]! }
                }
                guard seen.count==fan.count else { throw PreparationError.invalid("人体顶点含分离的面扇。") }
            }
            var built: [Node]=[],sortedFaces: [Int]=[]
            func build(_ facesToBuild: [Int]) throws -> Int {
                if isCancelled() { throw CancellationError() }
                guard built.count<limits.maximumBVHNodes else { throw PreparationError.budgetExceeded }
                let box=facesToBuild.dropFirst().reduce(f[facesToBuild[0]].box){$0.union(f[$1].box)}
                let index=built.count
                built.append(.init(box:box,left:-1,right:-1,start:0,count:0))
                if facesToBuild.count<=8 {
                    let start=sortedFaces.count;sortedFaces += facesToBuild
                    built[index] = .init(box:box,left:-1,right:-1,start:start,count:facesToBuild.count)
                } else {
                    let s=box.hi-box.lo,axis=s.x>=s.y && s.x>=s.z ? 0 : (s.y>=s.z ? 1:2)
                    func center(_ id: Int)->Double {
                        let b=f[id].box
                        return axis==0 ? b.lo.x+b.hi.x : (axis==1 ? b.lo.y+b.hi.y:b.lo.z+b.hi.z)
                    }
                    let x=facesToBuild.sorted{center($0)==center($1) ? $0<$1:center($0)<center($1)},mid=x.count/2
                    let left=try build(Array(x[..<mid])),right=try build(Array(x[mid...]))
                    built[index] = .init(box:box,left:left,right:right,start:0,count:0)
                }
                return index
            }
            _ = try build(Array(f.indices))
            if isCancelled() { throw CancellationError() }
            positions=p;triangleIndices=ids;faces=f;nodes=built;order=sortedFaces
            bvhNodeCount=built.count
            geometrySHA256=Self.geometryHash(positions:p,indices:ids)
        }
        private static func validateLimits(_ limits: Limits,vertices: Int,triangles: Int) throws {
            guard (4...100_000).contains(limits.maximumVertices),(4...200_000).contains(limits.maximumTriangles),
                  (1...100_000).contains(limits.maximumBVHNodes) else { throw PreparationError.invalid("索引数量预算无效。") }
            guard vertices>=4,triangles>=4,vertices<=limits.maximumVertices,triangles<=limits.maximumTriangles else {
                throw PreparationError.budgetExceeded
            }
        }
        private static func geometryHash(positions: [V],indices: [UInt32])->String {
            // Identical to the existing visible-body binding, not a new shape.
            var data=Data("rigid-clearance-visible-body-v1\0".utf8)
            func append<T:FixedWidthInteger>(_ x: T) {
                var y=x.littleEndian;withUnsafeBytes(of:&y){data.append(contentsOf:$0)}
            }
            append(UInt64(positions.count));append(UInt64(indices.count))
            for p in positions {append(p.x.bitPattern);append(p.y.bitPattern);append(p.z.bitPattern)}
            for i in indices {append(i)}
            return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        }

        func query(_ point: V,options: Options = .init(),
                   isCancelled: @Sendable ()->Bool = {false})->Result {
            var statistics=Statistics()
            var closest: Closest?,closestID: Int?
            func result(_ classification: Classification,_ issue: Issue? = nil,nearestComplete: Bool = true)->Result {
                .init(unsignedDistanceMeters:nearestComplete ? closest.map{sqrt(max(0,$0.distanceSquared))}:nil,
                      closestPoint:nearestComplete ? closest?.point:nil,closestTriangleID:nearestComplete ? closestID:nil,
                      classification:classification,issue:issue,surfaceToleranceMeters:options.surfaceToleranceMeters,statistics:statistics)
            }
            guard Self.valid(options),point.isFinite,point.length<1_000 else {
                return result(.uncertain,.invalidQuery,nearestComplete:false)
            }
            if isCancelled() { return result(.uncertain,.cancelled,nearestComplete:false) }
            guard Self.nearestRounding() else { return result(.uncertain,.unsupportedRounding,nearestComplete:false) }
            var stack=[0]
            while let i=stack.popLast() {
                if statistics.closestNodeVisits % 64 == 0 && isCancelled() { return result(.uncertain,.cancelled,nearestComplete:false) }
                guard statistics.closestNodeVisits<options.maximumClosestNodeVisits else {
                    return result(.uncertain,.nearestBudgetExceeded,nearestComplete:false)
                }
                statistics.closestNodeVisits += 1
                let node=nodes[i]
                if let best=closest,node.box.lowerDistanceSquared(point)>best.upperDistanceSquared {continue}
                if node.count>0 {
                    for j in node.start..<(node.start+node.count) {
                        guard statistics.closestTriangleTests<options.maximumClosestTriangleTests else {
                            return result(.uncertain,.nearestBudgetExceeded,nearestComplete:false)
                        }
                        if statistics.closestTriangleTests % 64 == 0 && isCancelled() { return result(.uncertain,.cancelled,nearestComplete:false) }
                        statistics.closestTriangleTests += 1
                        let id=order[j],f=faces[id],q=Self.closest(point,positions[f.a],positions[f.b],positions[f.c])
                        guard q.distanceSquared.isFinite,q.upperDistanceSquared.isFinite else {
                            return result(.uncertain,.numericalIndeterminate,nearestComplete:false)
                        }
                        if closest == nil || q.distanceSquared<closest!.distanceSquared ||
                            (q.distanceSquared==closest!.distanceSquared && id<closestID!) { closest=q;closestID=id }
                    }
                } else {
                    let l=nodes[node.left].box.lowerDistanceSquared(point),r=nodes[node.right].box.lowerDistanceSquared(point)
                    if l<=r {stack.append(node.right);stack.append(node.left)}
                    else {stack.append(node.left);stack.append(node.right)}
                }
            }
            guard let closest else { return result(.uncertain,.numericalIndeterminate,nearestComplete:false) }
            if sqrt(max(0,closest.distanceSquared))<=options.surfaceToleranceMeters { return result(.onSurface) }
            var agreed: Bool?
            for (index,direction) in Self.directions.prefix(options.maximumRayDirections).enumerated() {
                if isCancelled() { return result(.uncertain,.cancelled) }
                statistics.attemptedDirections += 1
                var count=0,rayStack=[0],ambiguousID: Int?,rayIssue: RayIssue?
                ray: while let i=rayStack.popLast() {
                    if statistics.rayNodeVisits % 64 == 0 && isCancelled() { return result(.uncertain,.cancelled) }
                    guard statistics.rayNodeVisits<options.maximumRayNodeVisits else { return result(.uncertain,.parityBudgetExceeded) }
                    statistics.rayNodeVisits += 1
                    let node=nodes[i]
                    if !node.box.intersectsRay(point,direction) {continue}
                    if node.count>0 {
                        for j in node.start..<(node.start+node.count) {
                            let id=order[j],f=faces[id]
                            if !f.box.intersectsRay(point,direction) {continue}
                            guard statistics.rayTriangleTests<options.maximumRayTriangleTests else { return result(.uncertain,.parityBudgetExceeded) }
                            if statistics.rayTriangleTests % 32 == 0 && isCancelled() { return result(.uncertain,.cancelled) }
                            statistics.rayTriangleTests += 1
                            switch Self.hit(point,direction,positions[f.a],positions[f.b],positions[f.c],options) {
                            case .miss:break
                            case .crossing:count += 1
                            case let .ambiguous(issue):ambiguousID=id;rayIssue=issue;break ray
                            }
                        }
                    } else {rayStack.append(node.right);rayStack.append(node.left)}
                }
                let complete=rayIssue==nil
                statistics.rays.append(.init(directionIndex:index,direction:direction,completed:complete,crossings:count,
                                            ambiguousTriangleID:ambiguousID,issue:rayIssue))
                if !complete { continue }
                statistics.acceptedDirections += 1
                let inside=count%2==1
                if let expected=agreed,expected != inside { return result(.uncertain,.directionDisagreement) }
                agreed=inside
                if statistics.acceptedDirections>=options.requiredAgreeingDirections { return result(inside ? .inside:.outside) }
            }
            return result(.uncertain,.insufficientUnambiguousDirections)
        }
        private static func valid(_ o: Options)->Bool {
            o.surfaceToleranceMeters.isFinite && (1e-12...1e-5).contains(o.surfaceToleranceMeters) &&
            o.barycentricTolerance.isFinite && (1e-14...1e-5).contains(o.barycentricTolerance) &&
            o.angularTolerance.isFinite && (1e-15...1e-5).contains(o.angularTolerance) &&
            (2...12).contains(o.requiredAgreeingDirections) && (1...12).contains(o.maximumRayDirections) &&
            (0...2_000_000).contains(o.maximumClosestNodeVisits) && (0...2_000_000).contains(o.maximumClosestTriangleTests) &&
            (0...12_000_000).contains(o.maximumRayNodeVisits) && (0...12_000_000).contains(o.maximumRayTriangleTests)
        }
        private static func nearestRounding()->Bool {
            #if os(macOS)
            return fegetround()==FE_TONEAREST
            #elseif canImport(NativeClothCollision)
            return FloatingPointEnvironment.isNearestRounding
            #else
            return false
            #endif
        }
        private static let directions: [V] = [
            V(x:1,y:0,z:0),V(x:0,y:1,z:0),V(x:0,y:0,z:1),
            V(x:1,y:0.327197,z:0.719231),V(x:-0.419273,y:1,z:0.137519),
            V(x:0.237913,y:-0.539117,z:1),V(x:-1,y:0.613279,z:0.283417),
            V(x:0.718327,y:1,z:-0.413971),V(x:-0.319937,y:0.813719,z:1),
            V(x:1,y:-0.271931,z:-0.617923),V(x:0.139813,y:-1,z:0.731927),
            V(x:-0.713921,y:-0.319127,z:-1)
        ].map{$0/$0.length}
        private static func dot(_ a: V,_ b: V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
        private static func closest(_ p: V,_ a: V,_ b: V,_ c: V)->Closest {
            func candidate(_ beta: Double,_ gamma: Double)->Closest {
                let q=a+(b-a)*beta+(c-a)*gamma
                let exact=IV(a)+(IV(b)-IV(a))*I(beta)+(IV(c)-IV(a))*I(gamma)
                let diff=IV(p)-exact,bound=diff.dot(diff)
                return .init(point:q,distanceSquared:(p-q).lengthSquared,upperDistanceSquared:max(0,bound.hi))
            }
            func edge(_ x: V,_ y: V)->Closest {
                let v=y-x,t=max(0,min(1,dot(p-x,v)/v.lengthSquared))
                let q=t==0 ? x:(t==1 ? y:x+v*t)
                // Use the one real edge coefficient directly. Rounded
                // (1-t,t) can sum above one and is not a feasible-point bound.
                let exact=IV(x)+(IV(y)-IV(x))*I(t),diff=IV(p)-exact
                return .init(point:q,distanceSquared:(p-q).lengthSquared,
                             upperDistanceSquared:max(0,diff.dot(diff).hi))
            }
            var best=edge(a,b)
            for q in [edge(b,c),edge(c,a)] where q.distanceSquared<best.distanceSquared {best=q}
            let u=b-a,v=c-a,n=u.cross(v),nn=n.lengthSquared
            let q=p-n*(dot(p-a,n)/nn),w=q-a
            let beta=dot(w.cross(v),n)/nn,gamma=dot(u.cross(w),n)/nn
            if beta>=0,gamma>=0,(I(beta)+I(gamma)).hi<=1 {
                let face=candidate(beta,gamma)
                if face.distanceSquared<best.distanceSquared {best=face}
            }
            return best
        }
        private static func hit(_ p: V,_ d: V,_ a: V,_ b: V,_ c: V,_ o: Options)->Hit {
            let e1=IV(b)-IV(a),e2=IV(c)-IV(a),dv=IV(d),pv=dv.cross(e2),det=e1.dot(pv)
            let normal=(b-a).cross(c-a),angular=normal.length*o.angularTolerance
            guard det.finite else { return .ambiguous(.arithmeticUnresolved) }
            if det.lo<=angular && det.hi >= -angular {return .ambiguous(.nearParallel)}
            let tv=IV(p)-IV(a),qv=tv.cross(e1)
            guard let u=tv.dot(pv)/det,let v=dv.dot(qv)/det,let t=e2.dot(qv)/det,
                  u.finite,v.finite,t.finite else {return .ambiguous(.arithmeticUnresolved)}
            let sum=u+v
            if t.hi<0 || u.hi<0 || v.hi<0 || sum.lo>1 {return .miss}
            if t.lo<=o.surfaceToleranceMeters {return .ambiguous(.nearOrigin)}
            let tol=o.barycentricTolerance
            if u.lo<=tol || v.lo<=tol || sum.hi>=1-tol {return .ambiguous(.sourceFeature)}
            return .crossing
        }
    }
}

