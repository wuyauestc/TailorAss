import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Final, independent visible-mesh checks. This never moves cloth or claims
/// temporal stability, personal fit, or a collision-free motion trajectory.
nonisolated enum GarmentCodeVisibleBodyInspection {
    typealias V = GarmentCodeCircleDrape.Vector3
    typealias Q = GarmentCodeBodyMeshQueries
    typealias B = GarmentCodeBodySurfaceContact
    typealias C = GarmentCodeClothContact

    struct Limits: Sendable {
        var maximumSamples = 140_000
        var maximumSurfaceCandidatePairs = 200_000
        var maximumTotalNodeVisits = 50_000_000
        var maximumTotalTriangleTests = 50_000_000
        var query = Q.Options()
    }
    enum InspectionError: LocalizedError, Sendable {
        case invalid(String), budgetExceeded
        var errorDescription: String? {
            switch self {
            case let .invalid(s): return "最终人体表面验收无效：" + s
            case .budgetExceeded: return "最终人体表面验收超出准备预算。"
            }
        }
    }
    enum SampleKind: String, Codable, Sendable { case vertex, edgeMidpoint, triangleCentroid }
    enum StopReason: String, Codable, Sendable { case sampleBudget, totalWorkBudget, unresolvedQuery, surfaceContactOrIndeterminate, surfaceSeparationBudget }
    enum SeparationStatus: String, Codable, Sendable { case clear, contactOrIndeterminate, budgetExceeded, notExamined }
    struct SurfaceSeparation: Codable, Sendable {
        let status: SeparationStatus
        let candidateTrianglePairs: Int
        let nodeVisits: Int
        let triangleTests: Int
        let witnessClothTriangleID: Int?
        let witnessBodyTriangleID: Int?
    }
    struct Witness: Codable, Sendable {
        let kind: SampleKind
        let vertexIDs: [Int]
        let position: V
        let classification: Q.Classification
        let unsignedDistanceMeters: Double?
        let issue: Q.Issue?
    }
    struct Report: Codable, Sendable {
        let sourceSHA256: String
        let bodyGeometrySHA256: String
        let clothStateSHA256: String
        let expectedSamples: Int
        let examinedSamples: Int
        let vertexSamples: Int
        let edgeMidpointSamples: Int
        let triangleCentroidSamples: Int
        let outsideSamples: Int
        let insideSamples: Int
        let onSurfaceSamples: Int
        let uncertainSamples: Int
        let totalNodeVisits: Int
        let totalTriangleTests: Int
        let maximumKnownPenetrationMeters: Double
        /// Sampled maximum only. Nil if a query/sample or complete surface
        /// separation is unresolved, including contact not seen by samples.
        let maximumPenetrationMeters: Double?
        let minimumKnownUnsignedDistanceMeters: Double?
        let surface: B.Quality
        /// A strict separating-axis certificate covers feature-aligned and
        /// coplanar cases that the legacy proper-crossing count cannot detect.
        let surfaceSeparation: SurfaceSeparation
        let completedAllSamples: Bool
        let stopReason: StopReason?
        /// Bounded diagnostic witnesses; counts above cover the whole run.
        let witnesses: [Witness]
        let computationSeconds: Double
        var allSamplesStrictlyOutside: Bool {
            completedAllSamples && outsideSamples == expectedSamples
        }
        var meetsFinalBodyGate: Bool {
            allSamplesStrictlyOutside && surface.intersectingTrianglePairs == 0 &&
            surface.degenerateClothTriangles == 0 &&
            surfaceSeparation.status == .clear &&
            maximumPenetrationMeters.map { $0 < 0.003 } == true
        }
    }
    private struct Edge: Sendable { let a: Int, b: Int }
    /// Independent triangle separation uses outward-rounded SAT projections.
    /// Any certified axis proves disjointness. With no such axis, contact or
    /// arithmetic ambiguity blocks the final gate; it never becomes a miss.
    private struct Interval: Sendable {
        let low: Double, high: Double
        init(_ x: Double) {low=x;high=x}
        init(_ low: Double,_ high: Double) {self.low=low;self.high=high}
        static func + (a: Self,b: Self)->Self {.init((a.low+b.low).nextDown,(a.high+b.high).nextUp)}
        static func - (a: Self,b: Self)->Self {.init((a.low-b.high).nextDown,(a.high-b.low).nextUp)}
        static func * (a: Self,b: Self)->Self {
            let p=a.low*b.low,q=a.low*b.high,r=a.high*b.low,s=a.high*b.high
            return .init(min(min(p,q),min(r,s)).nextDown,max(max(p,q),max(r,s)).nextUp)
        }
        var finite: Bool {low.isFinite && high.isFinite && low<=high}
    }
    private struct IntervalVector: Sendable {
        let x: Interval,y: Interval,z: Interval
        init(_ p: V) {x=Interval(p.x);y=Interval(p.y);z=Interval(p.z)}
        init(_ x: Interval,_ y: Interval,_ z: Interval) {self.x=x;self.y=y;self.z=z}
        static func - (a: Self,b: Self)->Self {.init(a.x-b.x,a.y-b.y,a.z-b.z)}
        func cross(_ b: Self)->Self {.init(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x)}
        func dot(_ b: Self)->Interval {x*b.x+y*b.y+z*b.z}
    }
    private struct SurfaceBounds: Sendable {
        let low: V,high: V
        init(_ p: [V]) {
            low = .init(x:p.map(\.x).min()!.nextDown,y:p.map(\.y).min()!.nextDown,z:p.map(\.z).min()!.nextDown)
            high = .init(x:p.map(\.x).max()!.nextUp,y:p.map(\.y).max()!.nextUp,z:p.map(\.z).max()!.nextUp)
        }
        init(low: V,high: V) {self.low=low;self.high=high}
        func union(_ b: Self)->Self {
            .init(low:.init(x:min(low.x,b.low.x),y:min(low.y,b.low.y),z:min(low.z,b.low.z)),
                  high:.init(x:max(high.x,b.high.x),y:max(high.y,b.high.y),z:max(high.z,b.high.z)))
        }
        func overlaps(_ b: Self)->Bool {
            low.x<=b.high.x && b.low.x<=high.x && low.y<=b.high.y && b.low.y<=high.y && low.z<=b.high.z && b.low.z<=high.z
        }
    }
    private struct SurfaceSeparationIndex: Sendable {
        private struct Face: Sendable {let vertexIDs:[Int],bounds:SurfaceBounds}
        private struct Node: Sendable {let bounds:SurfaceBounds,left:Int,right:Int,start:Int,count:Int}
        let positions: [V]
        private let faces: [Face],nodes: [Node],order: [Int]
        init(body: Q.Prepared,isCancelled:@Sendable()->Bool)throws {
            var f:[Face]=[]
            for i in stride(from:0,to:body.triangleIndices.count,by:3) {
                if i%768==0 && isCancelled(){throw CancellationError()}
                let ids=(0..<3).map{Int(body.triangleIndices[i+$0])}
                f.append(.init(vertexIDs:ids,bounds:.init(ids.map{body.positions[$0]})))
            }
            var n:[Node]=[],o:[Int]=[]
            func build(_ ids:[Int])throws->Int {
                if isCancelled(){throw CancellationError()}
                // Q already bounds the source at 200k triangles. A leaf of
                // eight needs fewer than 100k nodes; keep that bound explicit.
                guard n.count<100_000 else {throw InspectionError.budgetExceeded}
                let box=ids.dropFirst().reduce(f[ids[0]].bounds){$0.union(f[$1].bounds)},index=n.count
                n.append(.init(bounds:box,left:-1,right:-1,start:0,count:0))
                if ids.count<=8 {
                    let start=o.count;o += ids;n[index] = .init(bounds:box,left:-1,right:-1,start:start,count:ids.count)
                } else {
                    let size=box.high-box.low,axis=size.x>=size.y && size.x>=size.z ? 0:(size.y>=size.z ? 1:2)
                    func center(_ id:Int)->Double {
                        let b=f[id].bounds
                        return axis==0 ? b.low.x+b.high.x:(axis==1 ? b.low.y+b.high.y:b.low.z+b.high.z)
                    }
                    let sorted=ids.sorted{center($0)==center($1) ? $0<$1:center($0)<center($1)},mid=sorted.count/2
                    let left=try build(Array(sorted[..<mid])),right=try build(Array(sorted[mid...]))
                    n[index] = .init(bounds:box,left:left,right:right,start:0,count:0)
                }
                return index
            }
            _ = try build(Array(f.indices))
            positions=body.positions;faces=f;nodes=n;order=o
        }
        func inspect(cloth:[V],triangles:[UInt32],maximumPairs:Int,maximumNodeVisits:Int,maximumTriangleTests:Int,
                     isCancelled:@Sendable()->Bool)throws->SurfaceSeparation {
            var pairs=0,visits=0,tests=0
            func report(_ status:SeparationStatus,_ clothID:Int?=nil,_ bodyID:Int?=nil)->SurfaceSeparation {
                .init(status:status,candidateTrianglePairs:pairs,nodeVisits:visits,triangleTests:tests,
                      witnessClothTriangleID:clothID,witnessBodyTriangleID:bodyID)
            }
            for offset in stride(from:0,to:triangles.count,by:3) {
                if isCancelled(){throw CancellationError()}
                let a=(0..<3).map{cloth[Int(triangles[offset+$0])]},box=SurfaceBounds(a),id=offset/3
                var stack=[0]
                while let i=stack.popLast() {
                    if visits%64==0 && isCancelled(){throw CancellationError()}
                    guard visits<maximumNodeVisits else{return report(.budgetExceeded,id)}
                    visits += 1
                    let node=nodes[i]
                    if !box.overlaps(node.bounds){continue}
                    if node.count>0 {
                        for j in node.start..<(node.start+node.count) {
                            let other=order[j],f=faces[other]
                            if !box.overlaps(f.bounds){continue}
                            guard pairs<maximumPairs,tests<maximumTriangleTests else{return report(.budgetExceeded,id,other)}
                            if tests%32==0 && isCancelled(){throw CancellationError()}
                            pairs += 1;tests += 1
                            if !Self.certifiedSeparate(a,f.vertexIDs.map{positions[$0]}) {
                                return report(.contactOrIndeterminate,id,other)
                            }
                        }
                    } else {stack.append(node.right);stack.append(node.left)}
                }
            }
            if isCancelled(){throw CancellationError()}
            return report(.clear)
        }
        private static func certifiedSeparate(_ a:[V],_ b:[V])->Bool {
            let av=a.map(IntervalVector.init),bv=b.map(IntervalVector.init)
            let ae=[av[1]-av[0],av[2]-av[1],av[0]-av[2]],be=[bv[1]-bv[0],bv[2]-bv[1],bv[0]-bv[2]]
            let an=ae[0].cross(av[2]-av[0]),bn=be[0].cross(bv[2]-bv[0])
            var axes=[an,bn]
            for x in ae {for y in be {axes.append(x.cross(y))}}
            // Face normals / edge-edge axes alone are incomplete when the
            // triangles are coplanar. Include each in-plane edge normal.
            for e in ae {axes.append(an.cross(e))}
            for e in be {axes.append(bn.cross(e))}
            for axis in axes {
                let x=av.map{axis.dot($0)},y=bv.map{axis.dot($0)}
                guard x.allSatisfy(\.finite),y.allSatisfy(\.finite) else {continue}
                let xHigh=x.map(\.high).max()!,xLow=x.map(\.low).min()!
                let yHigh=y.map(\.high).max()!,yLow=y.map(\.low).min()!
                if xHigh<yLow || yHigh<xLow {return true}
            }
            return false
        }
    }

    struct Prepared: Sendable {
        let sourceSHA256: String
        let body: Q.Prepared
        let vertexCount: Int
        let triangleIndices: [UInt32]
        let expectedSamples: Int
        private let bodyMesh: B.BodyMesh
        private let topology: C.Topology
        private let edges: [Edge]
        private let limits: Limits
        private let separator: SurfaceSeparationIndex

        init(sourceSHA256: String, vertexCount: Int, triangleIndices: [UInt32], body: Q.Prepared,
             limits: Limits = .init(), isCancelled: @Sendable () -> Bool = { false }) throws {
            if isCancelled() { throw CancellationError() }
            guard sourceSHA256.count == 64, sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  (3...20_000).contains(vertexCount), !triangleIndices.isEmpty, triangleIndices.count % 3 == 0,
                  triangleIndices.count / 3 <= 40_000,
                  (1...140_000).contains(limits.maximumSamples),
                  (1...200_000).contains(limits.maximumSurfaceCandidatePairs),
                  (1...100_000_000).contains(limits.maximumTotalNodeVisits),
                  (1...100_000_000).contains(limits.maximumTotalTriangleTests),
                  limits.query.surfaceToleranceMeters == 1e-8,
                  limits.query.barycentricTolerance == 1e-10, limits.query.angularTolerance == 1e-12,
                  limits.query.requiredAgreeingDirections == 3, limits.query.maximumRayDirections == 12 else {
                throw InspectionError.invalid("需要完整源身份、原拓扑及固定的三方向体内判定。")
            }
            let t = try C.Topology(vertexCount: vertexCount, triangleIndices: triangleIndices, isCancelled: isCancelled)
            var keys = Set<UInt64>()
            for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                if i % 768 == 0 && isCancelled() { throw CancellationError() }
                let ids = (0..<3).map { Int(triangleIndices[i+$0]) }
                for j in 0..<3 {
                    let a = min(ids[j], ids[(j+1)%3]), b = max(ids[j], ids[(j+1)%3])
                    keys.insert((UInt64(a)<<32) | UInt64(b))
                }
            }
            let e = keys.sorted().map { Edge(a: Int($0>>32), b: Int($0 & 0xffff_ffff)) }
            self.sourceSHA256 = sourceSHA256; self.vertexCount = vertexCount
            self.triangleIndices = triangleIndices; self.body = body
            bodyMesh = try B.BodyMesh(positions: body.positions, triangleIndices: body.triangleIndices)
            topology = t; edges = e; self.limits = limits
            separator = try SurfaceSeparationIndex(body: body, isCancelled: isCancelled)
            expectedSamples = vertexCount + e.count + triangleIndices.count/3
            if isCancelled() { throw CancellationError() }
        }

        func inspect(positions x: [V], isCancelled: @Sendable () -> Bool = { false }) throws -> Report {
            if isCancelled() { throw CancellationError() }
            guard x.count == vertexCount, x.allSatisfy({ $0.isFinite && $0.length < 100 }) else {
                throw InspectionError.invalid("需要同一完整拓扑的有限候选位置。")
            }
            guard Self.nearestRounding() else { throw InspectionError.invalid("浮点环境必须保持 nearest rounding。") }
            let start = Date()
            // Full triangle checks complement the independent volume samples.
            // A whole panel enclosed by the body has zero crossing triangles.
            let surface = try B.inspect(positions: x, topology: topology, body: bodyMesh, thickness: 0.0005,
                maximumCandidatePairs: limits.maximumSurfaceCandidatePairs, isCancelled: isCancelled)
            var examined = 0, vertices = 0, midpoints = 0, centers = 0
            var outside = 0, inside = 0, onSurface = 0, uncertain = 0
            var nodes = 0, triangles = 0, penetration = 0.0, distance: Double?
            var witnesses: [Witness] = [], stop: StopReason?
            func sample(_ p: V, _ kind: SampleKind, _ ids: [Int]) throws -> Bool {
                if isCancelled() { throw CancellationError() }
                guard examined < limits.maximumSamples else { stop = .sampleBudget; return false }
                guard nodes < limits.maximumTotalNodeVisits, triangles < limits.maximumTotalTriangleTests else {
                    stop = .totalWorkBudget; return false
                }
                var options = limits.query
                let nodeBudget = limits.maximumTotalNodeVisits - nodes, triangleBudget = limits.maximumTotalTriangleTests - triangles
                // Nearest and parity stages share the remaining whole-run cap.
                // Reserve half for each; exhausted work is an unknown result.
                options.maximumClosestNodeVisits = min(options.maximumClosestNodeVisits, nodeBudget/2)
                options.maximumRayNodeVisits = min(options.maximumRayNodeVisits, nodeBudget-nodeBudget/2)
                options.maximumClosestTriangleTests = min(options.maximumClosestTriangleTests, triangleBudget/2)
                options.maximumRayTriangleTests = min(options.maximumRayTriangleTests, triangleBudget-triangleBudget/2)
                let r = body.query(p, options: options, isCancelled: isCancelled)
                if r.issue == .cancelled || isCancelled() { throw CancellationError() }
                examined += 1
                switch kind { case .vertex: vertices += 1; case .edgeMidpoint: midpoints += 1; case .triangleCentroid: centers += 1 }
                nodes += r.statistics.closestNodeVisits + r.statistics.rayNodeVisits
                triangles += r.statistics.closestTriangleTests + r.statistics.rayTriangleTests
                if let d = r.unsignedDistanceMeters { distance = min(distance ?? d, d) }
                switch r.classification {
                case .outside: outside += 1
                case .inside: inside += 1; penetration = max(penetration, r.unsignedDistanceMeters ?? 0)
                case .onSurface: onSurface += 1
                case .uncertain: uncertain += 1
                }
                if r.classification != .outside && witnesses.count < 16 {
                    witnesses.append(.init(kind: kind, vertexIDs: ids, position: p, classification: r.classification,
                        unsignedDistanceMeters: r.unsignedDistanceMeters, issue: r.issue))
                }
                if r.classification == .uncertain || r.issue != nil { stop = .unresolvedQuery; return false }
                return true
            }
            loop: do {
                for i in x.indices { if try !sample(x[i], .vertex, [i]) { break loop } }
                for e in edges { if try !sample((x[e.a]+x[e.b])*0.5, .edgeMidpoint, [e.a,e.b]) { break loop } }
                for i in stride(from: 0, to: triangleIndices.count, by: 3) {
                    let ids = (0..<3).map { Int(triangleIndices[i+$0]) }
                    if try !sample((x[ids[0]]+x[ids[1]]+x[ids[2]])/3, .triangleCentroid, ids) { break loop }
                }
            }
            if isCancelled() { throw CancellationError() }
            let complete = stop == nil && examined == expectedSamples && uncertain == 0
            let separation: SurfaceSeparation
            if complete {
                separation = try separator.inspect(cloth: x, triangles: triangleIndices,
                    maximumPairs: limits.maximumSurfaceCandidatePairs - surface.candidateTrianglePairs,
                    maximumNodeVisits: limits.maximumTotalNodeVisits - nodes,
                    maximumTriangleTests: limits.maximumTotalTriangleTests - triangles, isCancelled: isCancelled)
                nodes += separation.nodeVisits; triangles += separation.triangleTests
                if separation.status == .contactOrIndeterminate { stop = .surfaceContactOrIndeterminate }
                if separation.status == .budgetExceeded { stop = .surfaceSeparationBudget }
            } else {
                separation = .init(status: .notExamined, candidateTrianglePairs: 0, nodeVisits: 0, triangleTests: 0,
                    witnessClothTriangleID: nil, witnessBodyTriangleID: nil)
            }
            if isCancelled() { throw CancellationError() }
            return .init(sourceSHA256: sourceSHA256, bodyGeometrySHA256: body.geometrySHA256,
                clothStateSHA256: Self.stateHash(x, triangleIndices), expectedSamples: expectedSamples, examinedSamples: examined,
                vertexSamples: vertices, edgeMidpointSamples: midpoints, triangleCentroidSamples: centers,
                outsideSamples: outside, insideSamples: inside, onSurfaceSamples: onSurface, uncertainSamples: uncertain,
                totalNodeVisits: nodes, totalTriangleTests: triangles, maximumKnownPenetrationMeters: penetration,
                maximumPenetrationMeters: complete && separation.status == .clear ? penetration : nil, minimumKnownUnsignedDistanceMeters: distance,
                surface: surface, surfaceSeparation: separation, completedAllSamples: complete, stopReason: stop, witnesses: witnesses,
                computationSeconds: Date().timeIntervalSince(start))
        }
        private static func nearestRounding() -> Bool {
            #if os(macOS)
            return fegetround() == FE_TONEAREST
            #elseif canImport(NativeClothCollision)
            return FloatingPointEnvironment.isNearestRounding
            #else
            return false
            #endif
        }
        private static func stateHash(_ x: [V], _ ids: [UInt32]) -> String {
            var data = Data("visible-body-cloth-state-v1\0".utf8)
            func append<T: FixedWidthInteger>(_ x: T) { var y = x.littleEndian; withUnsafeBytes(of: &y) { data.append(contentsOf: $0) } }
            append(UInt64(x.count)); append(UInt64(ids.count))
            for p in x { append(p.x.bitPattern); append(p.y.bitPattern); append(p.z.bitPattern) }
            for i in ids { append(i) }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}
