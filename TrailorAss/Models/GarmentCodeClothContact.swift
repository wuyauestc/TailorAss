import Foundation

/// Discrete surface contact for the small offline garment solver. This is not
/// continuous collision detection: motion can tunnel between sampled steps.
nonisolated enum GarmentCodeClothContact {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3

    struct Triangle: Sendable {
        let a: Int, b: Int, c: Int
        var vertices: [Int] { [a, b, c] }
        var edges: [(Int, Int)] { [(a,b), (b,c), (c,a)] }
    }

    /// An explicitly sewn point on one actual boundary edge. This is a
    /// separate attachment, not a welded particle or a panel collision mask.
    struct BoundaryPoint: Hashable, Sendable {
        let vertexIDs: [Int]
        let weights: [Double]
    }

    /// Corresponding spans on two boundary edges. A finite sewing tack uses
    /// identical start/end attachments; only an ordinary continuous seam may
    /// supply a nonzero interval. Interior face intersections remain active.
    struct SewnBoundaryContact: Sendable {
        let firstTriangle: Int
        let secondTriangle: Int
        let firstStart: BoundaryPoint
        let firstEnd: BoundaryPoint
        let secondStart: BoundaryPoint
        let secondEnd: BoundaryPoint
    }

    struct Topology: Sendable {
        let vertexCount: Int
        let triangles: [Triangle]
        let neighbors: [Set<Int>]
        private let sewnBoundaries: [UInt64: [SewnBoundaryContact]]
        private let referencePositions: [Vector3]?
        private let sourceRibbonRadiusMeters: Double
        private let proximityRibbons: [UInt64: [ProximityRibbon]]

        /// The two query faces, rather than the original boundary faces,
        /// establish orientation after expanding into adjacent source faces.
        /// These rules affect padding only; they never enter sewnBoundaries.
        private struct ProximityRibbon: Sendable {
            let firstTriangle: Int, secondTriangle: Int
            let boundary: SewnBoundaryContact
            let firstStart: Vector3, firstEnd: Vector3
            let secondStart: Vector3, secondEnd: Vector3
        }
        private struct SpanPair: Hashable {
            let firstStart:BoundaryPoint,firstEnd:BoundaryPoint
            let secondStart:BoundaryPoint,secondEnd:BoundaryPoint
        }
        private struct Expansion: Hashable {
            let firstTriangle:Int,secondTriangle:Int,spanID:Int
        }

        /// Optional references must be the one-to-one flat source positions
        /// for these particle/face indices, before any 3D placement. A nil
        /// reference retains the previous boundary-face-only padding rules.
        /// Source expansion stops at 5.5 mm by default; actual world padding
        /// and matched seam parameters are still checked on every query.
        init(vertexCount: Int, triangleIndices: [UInt32],
             sewnBoundaryContacts: [SewnBoundaryContact] = [],
             referencePositions: [Vector3]? = nil,
             sourceRibbonRadiusMeters: Double = 0.0055,
             maximumSourceRibbonPairs: Int = 250_000,
             isCancelled: @Sendable () -> Bool = { false }) throws {
            guard (3...20_000).contains(vertexCount), !triangleIndices.isEmpty,
                  triangleIndices.count % 3 == 0, triangleIndices.count <= 120_000 else {
                throw ContactError.invalid("布片接触网格超出检查范围。")
            }
            var faces: [Triangle] = []
            var neighbors = Array(repeating: Set<Int>(), count: vertexCount)
            for offset in stride(from: 0, to: triangleIndices.count, by: 3) {
                let a = Int(triangleIndices[offset]), b = Int(triangleIndices[offset+1]), c = Int(triangleIndices[offset+2])
                guard a < vertexCount, b < vertexCount, c < vertexCount,
                      a != b, b != c, c != a else {
                    throw ContactError.invalid("布片接触网格含无效三角面。")
                }
                faces.append(.init(a: a, b: b, c: c))
                for (i,j) in [(a,b),(b,c),(c,a)] {
                    neighbors[i].insert(j); neighbors[j].insert(i)
                }
            }
            self.vertexCount = vertexCount
            self.triangles = faces
            self.neighbors = neighbors
            guard sewnBoundaryContacts.count <= 40_000 else { throw ContactError.budgetExceeded }
            var edgeCounts: [UInt64:Int] = [:]
            if !sewnBoundaryContacts.isEmpty {
                for face in faces { for (a,b) in face.edges { edgeCounts[Self.key(a,b),default:0] += 1 } }
            }
            var boundaryVertices=Set<Int>()
            if !sewnBoundaryContacts.isEmpty {
                for face in faces { for (a,b) in face.edges where edgeCounts[Self.key(a,b)] == 1 {
                    boundaryVertices.insert(a);boundaryVertices.insert(b)
                } }
            }
            func validate(_ start: BoundaryPoint, _ end: BoundaryPoint, face: Triangle) throws {
                for point in [start,end] {
                    guard (1...2).contains(point.vertexIDs.count),
                          point.vertexIDs.count == point.weights.count,
                          Set(point.vertexIDs).count == point.vertexIDs.count,
                          point.vertexIDs.allSatisfy({face.vertices.contains($0)}),
                          point.weights.allSatisfy({$0.isFinite && $0>0 && $0<=1}),
                          abs(point.weights.reduce(0,+)-1) <= 1e-12 else {
                        throw ContactError.invalid("缝合接触附着点必须位于指定三角面的真实边界上。")
                    }
                }
                let ids=Set(start.vertexIDs+end.vertexIDs)
                // Every face incident to a sewn boundary vertex can meet at
                // that point, including fan faces without a boundary edge.
                // This grants a point contact only, never an interior span.
                if start==end,start.vertexIDs.count==1,boundaryVertices.contains(start.vertexIDs[0]) { return }
                guard !ids.isEmpty,ids.count<=2,face.edges.contains(where: { a,b in
                    ids.isSubset(of:Set([a,b])) && edgeCounts[Self.key(a,b)] == 1
                }) else { throw ContactError.invalid("缝合接触区间只能沿一条真实裁片边界，不能屏蔽面内接触。") }
            }
            var contacts: [UInt64:[SewnBoundaryContact]] = [:]
            for contact in sewnBoundaryContacts {
                guard faces.indices.contains(contact.firstTriangle),faces.indices.contains(contact.secondTriangle),
                      contact.firstTriangle != contact.secondTriangle else {
                    throw ContactError.invalid("缝合接触引用了无效的三角面。")
                }
                try validate(contact.firstStart,contact.firstEnd,face:faces[contact.firstTriangle])
                try validate(contact.secondStart,contact.secondEnd,face:faces[contact.secondTriangle])
                contacts[Self.key(contact.firstTriangle,contact.secondTriangle),default:[]].append(contact)
            }
            sewnBoundaries=contacts
            self.referencePositions=referencePositions
            self.sourceRibbonRadiusMeters=sourceRibbonRadiusMeters
            if let referencePositions {
                proximityRibbons=try Self.sourceRibbons(faces:faces,vertexCount:vertexCount,
                    referencePositions:referencePositions,contacts:sewnBoundaryContacts,
                    radius:sourceRibbonRadiusMeters,maximumPairs:maximumSourceRibbonPairs,
                    isCancelled:isCancelled)
            } else {
                // Keep the original contact classification and construction
                // path when a caller has not supplied verified source data.
                proximityRibbons=[:]
            }
        }

        private static func key(_ a:Int,_ b:Int)->UInt64 { (UInt64(min(a,b))<<32)|UInt64(max(a,b)) }

        /// Expand through actual shared source edges only. Spatially adjacent
        /// panels, disconnected slit banks and vertex-only fans do not create
        /// adjacency. Both discovery and the resulting rules have hard budgets.
        private static func sourceRibbons(faces:[Triangle],vertexCount:Int,
            referencePositions:[Vector3],contacts:[SewnBoundaryContact],radius:Double,
            maximumPairs:Int,isCancelled:@Sendable ()->Bool) throws -> [UInt64:[ProximityRibbon]] {
            if isCancelled() { throw CancellationError() }
            guard referencePositions.count==vertexCount,
                  referencePositions.allSatisfy({$0.isFinite && abs($0.x)<1000 && abs($0.y)<1000 && abs($0.z)<=1e-9}),
                  radius.isFinite,(0.0001...0.02).contains(radius),
                  (1...1_000_000).contains(maximumPairs) else {
                throw ContactError.invalid("缝合接触的平面源坐标、有限区域或预算无效。")
            }
            var edgeFaces:[UInt64:[Int]]=[:],used=Set<Int>()
            for (i,face) in faces.enumerated() {
                if i%128==0,isCancelled(){throw CancellationError()}
                let a=referencePositions[face.a],b=referencePositions[face.b],c=referencePositions[face.c]
                guard (b-a).cross(c-a).lengthSquared>1e-24 else {
                    throw ContactError.invalid("缝合接触的源三角面退化，无法回映接触点。")
                }
                for id in face.vertices {used.insert(id)}
                for (a,b) in face.edges {
                    let encoded=key(a,b)
                    edgeFaces[encoded,default:[]].append(i)
                    guard edgeFaces[encoded]!.count<=2 else {
                        throw ContactError.invalid("缝合接触的源网格含非流形边，无法确定同片邻接。")
                    }
                }
            }
            guard used.count==vertexCount else {
                throw ContactError.invalid("缝合接触的源坐标含未被三角面引用的粒子。")
            }
            var adjacent=Array(repeating:[Int](),count:faces.count)
            for incident in edgeFaces.values where incident.count==2 {
                adjacent[incident[0]].append(incident[1]);adjacent[incident[1]].append(incident[0])
            }
            // A fixed neighbour order makes both rules and budget failures
            // independent of the Dictionary's randomized iteration order.
            for i in adjacent.indices {adjacent[i].sort()}
            func point(_ p:BoundaryPoint)->Vector3 {
                zip(p.vertexIDs,p.weights).reduce(.zero){$0+referencePositions[$1.0]*$1.1}
            }
            var faceVisits=0,pairCount=0,result:[UInt64:[ProximityRibbon]]=[:]
            var spanIDs:[SpanPair:Int]=[:],expanded=Set<Expansion>()
            let maximumVisits=max(100_000,maximumPairs*8),epsilon=radius+1e-7
            func near(_ face:Triangle,_ start:Vector3,_ end:Vector3)->Bool {
                let a=referencePositions[face.a],b=referencePositions[face.b],c=referencePositions[face.c]
                guard min(a.x,b.x,c.x)<=max(start.x,end.x)+epsilon,
                      max(a.x,b.x,c.x)>=min(start.x,end.x)-epsilon,
                      min(a.y,b.y,c.y)<=max(start.y,end.y)+epsilon,
                      max(a.y,b.y,c.y)>=min(start.y,end.y)-epsilon else {return false}
                if (onTriangle(start,a,b,c).point-start).length<=epsilon ||
                    (onTriangle(end,a,b,c).point-end).length<=epsilon {return true}
                for (i,j) in face.edges {
                    let points=closestEdges(start,end,referencePositions[i],referencePositions[j])
                    if (points.a-points.b).length<=epsilon {return true}
                }
                return false
            }
            func ribbon(_ seed:Int,_ start:Vector3,_ end:Vector3)throws->[Int] {
                var pending=[seed],visited:Set<Int>=[seed],accepted:[Int]=[],cursor=0
                while cursor<pending.count {
                    let id=pending[cursor];cursor+=1;faceVisits+=1
                    if faceVisits%128==0,isCancelled(){throw CancellationError()}
                    guard faceVisits<=maximumVisits else {throw ContactError.budgetExceeded}
                    guard near(faces[id],start,end) else {continue}
                    accepted.append(id)
                    for next in adjacent[id] where visited.insert(next).inserted {pending.append(next)}
                }
                return accepted
            }
            for (index,contact) in contacts.enumerated() {
                if index%32==0,isCancelled(){throw CancellationError()}
                let a0=point(contact.firstStart),a1=point(contact.firstEnd)
                let b0=point(contact.secondStart),b1=point(contact.secondEnd)
                let spans=SpanPair(firstStart:contact.firstStart,firstEnd:contact.firstEnd,
                    secondStart:contact.secondStart,secondEnd:contact.secondEnd)
                let spanID:Int
                if let existing=spanIDs[spans] {spanID=existing}
                else {spanID=spanIDs.count;spanIDs[spans]=spanID}
                let first=try ribbon(contact.firstTriangle,a0,a1),second=try ribbon(contact.secondTriangle,b0,b1)
                for a in first {for b in second where a != b {
                    // Corner metadata may name every incident fan-face pair.
                    // Their identical source spans must not multiply the same
                    // expanded face rule or exhaust the extra-pair budget.
                    guard expanded.insert(.init(firstTriangle:a,secondTriangle:b,spanID:spanID)).inserted else {continue}
                    guard pairCount<maximumPairs else {throw ContactError.budgetExceeded}
                    pairCount+=1
                    result[key(a,b),default:[]].append(.init(firstTriangle:a,secondTriangle:b,
                        boundary:contact,firstStart:a0,firstEnd:a1,secondStart:b0,secondEnd:b1))
                }}
            }
            if isCancelled(){throw CancellationError()}
            return result
        }

        /// Only matching points on the specified boundary spans may touch.
        /// The 0.1-micrometre tolerance is a numeric classification tolerance;
        /// it is deliberately independent of the 5-mm cloth contact padding.
        func permitsSewnTouch(firstFace:Int,secondFace:Int,firstPoint:Vector3,
                              secondPoint:Vector3,positions:[Vector3])->Bool {
            permitsBoundaryContact(firstFace:firstFace,secondFace:secondFace,firstPoint:firstPoint,
                secondPoint:secondPoint,positions:positions,paddingMeters:0)
        }

        /// Contact padding must taper away at a sewn boundary: a vertex 2 mm
        /// inside a valid stitched strip must not be repelled by a 5 mm cloth
        /// shell across that seam. Only the matched boundary's finite ribbon
        /// (or a finite tack's local neighbourhood) is allowed to approach.
        /// Actual triangle crossings use permitsSewnTouch with zero padding.
        func permitsSewnProximity(firstFace:Int,secondFace:Int,firstPoint:Vector3,
            secondPoint:Vector3,positions:[Vector3],paddingMeters:Double)->Bool {
            guard let referencePositions else {
                return permitsBoundaryContact(firstFace:firstFace,secondFace:secondFace,firstPoint:firstPoint,
                    secondPoint:secondPoint,positions:positions,paddingMeters:paddingMeters)
            }
            guard triangles.indices.contains(firstFace),triangles.indices.contains(secondFace),
                  positions.count==vertexCount,firstPoint.isFinite,secondPoint.isFinite,
                  paddingMeters.isFinite,(0...0.1).contains(paddingMeters),
                  let ribbons=proximityRibbons[Self.key(firstFace,secondFace)] else {return false}
            func source(_ p:Vector3,_ face:Triangle)->Vector3? {
                let a=positions[face.a],b=positions[face.b],c=positions[face.c]
                guard a.isFinite,b.isFinite,c.isFinite,(b-a).cross(c-a).lengthSquared>1e-24 else {return nil}
                let mapped=onTriangle(p,a,b,c)
                // Do not project an arbitrary point onto a different face and
                // thereby manufacture a source-ribbon membership.
                guard (mapped.point-p).length<=1e-7 else {return nil}
                return referencePositions[face.a]*mapped.barycentric[0] +
                    referencePositions[face.b]*mapped.barycentric[1] +
                    referencePositions[face.c]*mapped.barycentric[2]
            }
            guard let sourceA=source(firstPoint,triangles[firstFace]),
                  let sourceB=source(secondPoint,triangles[secondFace]) else {return false}
            func point(_ value:BoundaryPoint)->Vector3 {
                zip(value.vertexIDs,value.weights).reduce(.zero){$0+positions[$1.0]*$1.1}
            }
            func matches(_ p:Vector3,_ q:Vector3,_ a0:Vector3,_ a1:Vector3,
                         _ b0:Vector3,_ b1:Vector3,_ epsilon:Double)->Bool {
                func parameter(_ value:Vector3,_ start:Vector3,_ end:Vector3)->Double? {
                    let d=end-start,length=d.lengthSquared
                    guard length>1e-24 else {return (value-start).length<=epsilon ? 0:nil}
                    let t=max(0,min(1,dot(value-start,d)/length))
                    return (value-start-d*t).length<=epsilon ? t:nil
                }
                guard let ta=parameter(p,a0,a1),let tb=parameter(q,b0,b1) else {return false}
                return abs(ta-tb)*max((a1-a0).length,(b1-b0).length)<=epsilon
            }
            for ribbon in ribbons {
                // Explicitly orient the expanded pair. The original boundary
                // face is generally neither of these interior query faces.
                let forward=ribbon.firstTriangle==firstFace && ribbon.secondTriangle==secondFace
                let reverse=ribbon.secondTriangle==firstFace && ribbon.firstTriangle==secondFace
                guard forward || reverse else {continue}
                let a0=forward ? ribbon.firstStart:ribbon.secondStart,a1=forward ? ribbon.firstEnd:ribbon.secondEnd
                let b0=forward ? ribbon.secondStart:ribbon.firstStart,b1=forward ? ribbon.secondEnd:ribbon.firstEnd
                guard matches(sourceA,sourceB,a0,a1,b0,b1,sourceRibbonRadiusMeters+1e-7) else {continue}
                let contact=ribbon.boundary
                let wa0=point(forward ? contact.firstStart:contact.secondStart)
                let wa1=point(forward ? contact.firstEnd:contact.secondEnd)
                let wb0=point(forward ? contact.secondStart:contact.firstStart)
                let wb1=point(forward ? contact.secondEnd:contact.firstEnd)
                if matches(firstPoint,secondPoint,wa0,wa1,wb0,wb1,paddingMeters+1e-7){return true}
            }
            return false
        }

        private func permitsBoundaryContact(firstFace:Int,secondFace:Int,firstPoint:Vector3,
            secondPoint:Vector3,positions:[Vector3],paddingMeters:Double)->Bool {
            guard let contacts=sewnBoundaries[Self.key(firstFace,secondFace)] else { return false }
            guard paddingMeters.isFinite,(0...0.1).contains(paddingMeters) else { return false }
            let epsilon=1e-7+paddingMeters
            func point(_ value:BoundaryPoint)->Vector3 {
                zip(value.vertexIDs,value.weights).reduce(.zero) { $0+positions[$1.0]*$1.1 }
            }
            func parameter(_ p:Vector3,_ a:Vector3,_ b:Vector3)->Double? {
                let d=b-a,length=d.lengthSquared
                guard length>1e-24 else { return (p-a).length<=epsilon ? 0 : nil }
                let t=max(0,min(1,dot(p-a,d)/length))
                return (p-a-d*t).length<=epsilon ? t : nil
            }
            for contact in contacts {
                let forward=contact.firstTriangle == firstFace
                let a0=point(forward ? contact.firstStart : contact.secondStart)
                let a1=point(forward ? contact.firstEnd : contact.secondEnd)
                let b0=point(forward ? contact.secondStart : contact.firstStart)
                let b1=point(forward ? contact.secondEnd : contact.firstEnd)
                guard let ta=parameter(firstPoint,a0,a1),let tb=parameter(secondPoint,b0,b1) else { continue }
                let scale=max((a1-a0).length,(b1-b0).length)
                if abs(ta-tb)*scale<=epsilon { return true }
            }
            return false
        }

        func excludes(_ vertex: Int, _ face: Triangle) -> Bool {
            face.vertices.contains { $0 == vertex || neighbors[vertex].contains($0) }
        }

        func excludes(_ edge: (Int,Int), _ other: (Int,Int)) -> Bool {
            [edge.0, edge.1].contains { a in
                [other.0, other.1].contains { b in a == b || neighbors[a].contains(b) }
            }
        }
    }

    struct Statistics: Codable, Sendable {
        var candidateTrianglePairs = 0
        var vertexTriangleContacts = 0
        var edgeEdgeContacts = 0
        var crossingRepairs = 0
        var ambiguousNormals = 0
        var maximumCorrectionMeters = 0.0
    }

    struct Quality: Codable, Sendable {
        let candidateTrianglePairs: Int
        let intersectingTrianglePairs: Int
        let closeSurfacePairs: Int
        let degenerateTriangles: Int
        let maximumSurfaceOverlapMeters: Double
    }

    enum ContactError: LocalizedError, Sendable {
        case invalid(String)
        case budgetExceeded
        var errorDescription: String? {
            switch self {
            case let .invalid(message): return message
            case .budgetExceeded: return "布片表面接触超过本轮计算预算，尚未完成穿插检查。请减少圆裙长度或展开量后重试。"
            }
        }
    }

    private struct Bounds {
        let low: Vector3, high: Vector3
        func overlaps(_ other: Self, margin: Double) -> Bool {
            low.x <= other.high.x+margin && high.x+margin >= other.low.x &&
            low.y <= other.high.y+margin && high.y+margin >= other.low.y &&
            low.z <= other.high.z+margin && high.z+margin >= other.low.z
        }
    }
    private struct Cell: Hashable { let x: Int, y: Int, z: Int }
    private struct Pair { let a: Int, b: Int }
    private struct TrianglePoint {
        let point: Vector3
        let barycentric: [Double]
    }
    private struct EdgePoints {
        let a: Vector3, b: Vector3
        let s: Double, t: Double
    }

    private static func dot(_ a: Vector3, _ b: Vector3) -> Double { a.x*b.x+a.y*b.y+a.z*b.z }
    private static func clamp(_ value: Double) -> Double { max(0,min(1,value)) }
    private static func normalized(_ v: Vector3) -> Vector3? {
        let length = v.length
        return length > 1e-12 && length.isFinite ? v/length : nil
    }
    private static func validate(_ positions: [Vector3], topology: Topology, thickness: Double) throws {
        guard positions.count == topology.vertexCount,
              thickness.isFinite, (0.0001...0.1).contains(thickness),
              positions.allSatisfy({ $0.isFinite && abs($0.x) < 1000 && abs($0.y) < 1000 && abs($0.z) < 1000 }) else {
            throw ContactError.invalid("布片表面检查收到无效坐标、数量或厚度。")
        }
    }

    /// Uniform-grid broad phase. Neighboring faces sharing a vertex are not
    /// independent contact surfaces. Candidate and hash-cell budgets fail
    /// explicitly rather than quietly skipping a region of the cloth.
    private static func candidates(positions: [Vector3], topology: Topology,
                                   thickness: Double, maximumCandidatePairs: Int,
                                   isCancelled: @Sendable () -> Bool) throws -> [Pair] {
        guard (1...1_000_000).contains(maximumCandidatePairs) else {
            throw ContactError.invalid("布片接触候选数量预算无效。")
        }
        var samples: [Double] = []
        for face in topology.triangles.prefix(256) {
            samples.append((positions[face.a]-positions[face.b]).length)
            samples.append((positions[face.b]-positions[face.c]).length)
        }
        samples.sort()
        let cellSize = max(thickness*2,min(0.12,max(0.01,samples[samples.count/2])))
        let bounds = topology.triangles.map { face -> Bounds in
            let a=positions[face.a], b=positions[face.b], c=positions[face.c]
            return .init(low:.init(x:min(a.x,b.x,c.x),y:min(a.y,b.y,c.y),z:min(a.z,b.z,c.z)),
                         high:.init(x:max(a.x,b.x,c.x),y:max(a.y,b.y,c.y),z:max(a.z,b.z,c.z)))
        }
        var cells: [Cell:[Int]] = [:], seen = Set<UInt64>(), result: [Pair] = []
        var entries = 0, pairVisits = 0
        for (i,face) in topology.triangles.enumerated() {
            if i % 64 == 0, isCancelled() { throw CancellationError() }
            let box=bounds[i]
            let x0=Int(floor((box.low.x-thickness)/cellSize)), x1=Int(floor((box.high.x+thickness)/cellSize))
            let y0=Int(floor((box.low.y-thickness)/cellSize)), y1=Int(floor((box.high.y+thickness)/cellSize))
            let z0=Int(floor((box.low.z-thickness)/cellSize)), z1=Int(floor((box.high.z+thickness)/cellSize))
            let count=(x1-x0+1)*(y1-y0+1)*(z1-z0+1)
            guard count <= 8192, entries+count <= 500_000 else { throw ContactError.budgetExceeded }
            entries += count
            for x in x0...x1 { for y in y0...y1 { for z in z0...z1 {
                let key=Cell(x:x,y:y,z:z)
                for j in cells[key] ?? [] {
                    pairVisits += 1
                    guard pairVisits <= max(100_000,maximumCandidatePairs*32) else { throw ContactError.budgetExceeded }
                    let other=topology.triangles[j]
                    guard !face.vertices.contains(where: { other.vertices.contains($0) }) else { continue }
                    let encoded=(UInt64(j)<<32)|UInt64(i)
                    guard seen.insert(encoded).inserted else { continue }
                    guard seen.count <= maximumCandidatePairs*8 else { throw ContactError.budgetExceeded }
                    guard bounds[j].overlaps(box,margin:thickness) else { continue }
                    guard result.count < maximumCandidatePairs else { throw ContactError.budgetExceeded }
                    result.append(.init(a:j,b:i))
                }
                cells[key,default:[]].append(i)
            } } }
        }
        return result
    }

    private static func onSegment(_ p: Vector3, _ a: Vector3, _ b: Vector3) -> (Vector3,Double) {
        let direction=b-a, length=direction.lengthSquared
        let t=length > 1e-24 ? clamp(dot(p-a,direction)/length) : 0
        return (a+direction*t,t)
    }

    /// Closest triangle point, with barycentric coordinates. Degenerate faces
    /// fall back to their edges rather than dividing by near-zero area.
    private static func onTriangle(_ p: Vector3, _ a: Vector3, _ b: Vector3, _ c: Vector3) -> TrianglePoint {
        let ab=b-a, ac=c-a
        if ab.cross(ac).lengthSquared < 1e-24 {
            let abPoint=onSegment(p,a,b), bcPoint=onSegment(p,b,c), caPoint=onSegment(p,c,a)
            let options: [TrianglePoint] = [
                .init(point:abPoint.0,barycentric:[1-abPoint.1,abPoint.1,0]),
                .init(point:bcPoint.0,barycentric:[0,1-bcPoint.1,bcPoint.1]),
                .init(point:caPoint.0,barycentric:[caPoint.1,0,1-caPoint.1])]
            return options.min { ($0.point-p).lengthSquared < ($1.point-p).lengthSquared }!
        }
        let ap=p-a, d1=dot(ab,ap), d2=dot(ac,ap)
        if d1 <= 0 && d2 <= 0 { return .init(point:a,barycentric:[1,0,0]) }
        let bp=p-b, d3=dot(ab,bp), d4=dot(ac,bp)
        if d3 >= 0 && d4 <= d3 { return .init(point:b,barycentric:[0,1,0]) }
        let vc=d1*d4-d3*d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v=d1/(d1-d3)
            return .init(point:a+ab*v,barycentric:[1-v,v,0])
        }
        let cp=p-c, d5=dot(ab,cp), d6=dot(ac,cp)
        if d6 >= 0 && d5 <= d6 { return .init(point:c,barycentric:[0,0,1]) }
        let vb=d5*d2-d1*d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w=d2/(d2-d6)
            return .init(point:a+ac*w,barycentric:[1-w,0,w])
        }
        let va=d3*d6-d5*d4
        if va <= 0 && d4-d3 >= 0 && d5-d6 >= 0 {
            let w=(d4-d3)/((d4-d3)+(d5-d6))
            return .init(point:b+(c-b)*w,barycentric:[0,1-w,w])
        }
        let denominator=1/(va+vb+vc), v=vb*denominator, w=vc*denominator
        return .init(point:a+ab*v+ac*w,barycentric:[1-v-w,v,w])
    }

    private static func closestEdges(_ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3) -> EdgePoints {
        let first=b-a, second=d-c, r=a-c
        let aa=dot(first,first), ee=dot(second,second), f=dot(second,r)
        var s=0.0, t=0.0
        if aa <= 1e-24 && ee <= 1e-24 { return .init(a:a,b:c,s:0,t:0) }
        if aa <= 1e-24 { t=clamp(f/ee) }
        else {
            let cc=dot(first,r)
            if ee <= 1e-24 { s=clamp(-cc/aa) }
            else {
                let bb=dot(first,second), denominator=aa*ee-bb*bb
                s=denominator > 1e-24 ? clamp((bb*f-cc*ee)/denominator) : 0
                t=(bb*s+f)/ee
                if t < 0 { t=0; s=clamp(-cc/aa) }
                else if t > 1 { t=1; s=clamp((bb-cc)/aa) }
            }
        }
        return .init(a:a+first*s,b:c+second*t,s:s,t:t)
    }

    private static func perpendicular(_ vector: Vector3) -> Vector3 {
        let axis: Vector3 = abs(vector.x) <= abs(vector.y) && abs(vector.x) <= abs(vector.z)
            ? .init(x:1,y:0,z:0) : (abs(vector.y) <= abs(vector.z) ? .init(x:0,y:1,z:0) : .init(x:0,y:0,z:1))
        return normalized(vector.cross(axis)) ?? .init(x:0,y:1,z:0)
    }

    private static func segmentTriangle(_ p: Vector3, _ q: Vector3, _ a: Vector3, _ b: Vector3, _ c: Vector3) -> (Double,[Double])? {
        let direction=q-p, e1=b-a, e2=c-a, cross=direction.cross(e2), determinant=dot(e1,cross)
        guard abs(determinant) > 1e-12 else { return nil }
        let inverse=1/determinant, offset=p-a
        let u=dot(offset,cross)*inverse
        guard u >= -1e-9, u <= 1+1e-9 else { return nil }
        let other=offset.cross(e1), v=dot(direction,other)*inverse
        guard v >= -1e-9, u+v <= 1+1e-9 else { return nil }
        let t=dot(e2,other)*inverse
        guard t >= -1e-9, t <= 1+1e-9 else { return nil }
        return (clamp(t),[1-u-v,u,v])
    }

    /// Projects one bounded discrete contact sweep. Rebuild candidates each
    /// sweep because corrections may bring new surfaces into contact.
    static func project(positions: inout [Vector3], previousPositions: [Vector3]? = nil,
                        inverseMass: [Double], topology: Topology, thickness: Double,
                        maximumCandidatePairs: Int = 150_000,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Statistics {
        if isCancelled() { throw CancellationError() }
        try validate(positions,topology:topology,thickness:thickness)
        guard inverseMass.count == positions.count,
              inverseMass.allSatisfy({ $0.isFinite && $0 >= 0 }),
              previousPositions == nil || (previousPositions!.count == positions.count && previousPositions!.allSatisfy(\.isFinite)) else {
            throw ContactError.invalid("布片表面接触收到无效质量或历史坐标。")
        }
        let pairs=try candidates(positions:positions,topology:topology,thickness:thickness,
                                 maximumCandidatePairs:maximumCandidatePairs,isCancelled:isCancelled)
        var stats=Statistics(); stats.candidateTrianglePairs=pairs.count
        func move(_ ids: [Int], _ gradients: [Double], normal: Vector3, penetration: Double) {
            let denominator=zip(ids,gradients).reduce(0.0) { $0+inverseMass[$1.0]*$1.1*$1.1 }
            guard denominator > 1e-20, penetration > 0 else { return }
            let amount=min(penetration,4*thickness)/denominator
            for (id,gradient) in zip(ids,gradients) {
                let correction=normal*(amount*inverseMass[id]*gradient)
                positions[id]=positions[id]+correction
                stats.maximumCorrectionMeters=max(stats.maximumCorrectionMeters,correction.length)
            }
        }
        func vertexFace(_ vertex: Int, _ face: Triangle, sourceFaceID:Int, targetFaceID:Int) {
            guard !topology.excludes(vertex,face) else { return }
            let ids=face.vertices, p=positions[vertex], a=positions[face.a], b=positions[face.b], c=positions[face.c]
            let nearest=onTriangle(p,a,b,c), delta=p-nearest.point, distance=delta.length
            guard distance < thickness else { return }
            guard !topology.permitsSewnProximity(firstFace:sourceFaceID,secondFace:targetFaceID,
                firstPoint:p,secondPoint:nearest.point,positions:positions,paddingMeters:thickness) else { return }
            var normal=normalized(delta)
            if normal == nil, let old=previousPositions {
                let oldPoint=onTriangle(old[vertex],old[face.a],old[face.b],old[face.c])
                normal=normalized(old[vertex]-oldPoint.point)
            }
            if normal == nil { normal=normalized((b-a).cross(c-a)) ?? perpendicular(b-a); stats.ambiguousNormals += 1 }
            move([vertex]+ids,[1]+nearest.barycentric.map(-),normal:normal!,penetration:thickness-distance)
            stats.vertexTriangleContacts += 1
        }
        func edgeContact(_ edge: (Int,Int), _ other: (Int,Int), firstFaceID:Int, secondFaceID:Int) {
            guard !topology.excludes(edge,other) else { return }
            let nearest=closestEdges(positions[edge.0],positions[edge.1],positions[other.0],positions[other.1])
            let difference=nearest.a-nearest.b, distance=difference.length
            guard distance < thickness else { return }
            guard !topology.permitsSewnProximity(firstFace:firstFaceID,secondFace:secondFaceID,
                firstPoint:nearest.a,secondPoint:nearest.b,positions:positions,paddingMeters:thickness) else { return }
            var normal=normalized(difference)
            if normal == nil, let old=previousPositions {
                let oldNearest=closestEdges(old[edge.0],old[edge.1],old[other.0],old[other.1])
                normal=normalized(oldNearest.a-oldNearest.b)
            }
            if normal == nil {
                let first=positions[edge.1]-positions[edge.0], second=positions[other.1]-positions[other.0]
                normal=normalized(first.cross(second)) ?? perpendicular(first)
                stats.ambiguousNormals += 1
            }
            move([edge.0,edge.1,other.0,other.1],[1-nearest.s,nearest.s,-(1-nearest.t),-nearest.t],
                 normal:normal!,penetration:thickness-distance)
            stats.edgeEdgeContacts += 1
        }
        // Closest endpoint/edge distances can miss an edge that already passes
        // through a face interior. Separate the two face projection intervals,
        // distributing the correction over each face. A per-endpoint repair
        // can alternate endpoints and leave the crossing in place.
        func crossingPair(_ a: Triangle, _ b: Triangle, firstFaceID:Int, secondFaceID:Int) {
            guard triangleIntersection(a,b,firstFaceID:firstFaceID,secondFaceID:secondFaceID,
                positions:positions,topology:topology) else { return }
            var choices: [(Double,Vector3,[Int],[Double])] = []
            for (reference,subject) in [(a,b),(b,a)] {
                guard let normal=normalized((positions[reference.b]-positions[reference.a]).cross(positions[reference.c]-positions[reference.a])) else { continue }
                let distances=subject.vertices.map { dot(positions[$0]-positions[reference.a],normal) }
                var positive=thickness-distances.min()!, negative=thickness+distances.max()!
                if let old=previousPositions,
                   let oldNormal=normalized((old[reference.b]-old[reference.a]).cross(old[reference.c]-old[reference.a])) {
                    let oldDistances=subject.vertices.map { dot(old[$0]-old[reference.a],oldNormal) }
                    // Preserve a previously separated side. An initially
                    // intersecting pair has no such history; use the shorter
                    // deterministic separating translation instead.
                    if oldDistances.allSatisfy({ $0 > 1e-7 }) { negative = .infinity }
                    if oldDistances.allSatisfy({ $0 < -1e-7 }) { positive = .infinity }
                }
                let sign=positive <= negative ? 1.0 : -1.0
                let amount=min(positive,negative)
                choices.append((amount,normal*sign,subject.vertices+reference.vertices,
                                Array(repeating:1.0/3,count:3)+Array(repeating:-1.0/3,count:3)))
            }
            guard let choice=choices.min(by: { $0.0 < $1.0 }),choice.0 > 0 else { return }
            move(choice.2,choice.3,normal:choice.1,penetration:choice.0)
            stats.crossingRepairs += 1
        }
        for (index,pair) in pairs.enumerated() {
            if index % 128 == 0, isCancelled() { throw CancellationError() }
            let a=topology.triangles[pair.a], b=topology.triangles[pair.b]
            crossingPair(a,b,firstFaceID:pair.a,secondFaceID:pair.b)
            for vertex in a.vertices { vertexFace(vertex,b,sourceFaceID:pair.a,targetFaceID:pair.b) }
            for vertex in b.vertices { vertexFace(vertex,a,sourceFaceID:pair.b,targetFaceID:pair.a) }
            for edge in a.edges { for other in b.edges { edgeContact(edge,other,firstFaceID:pair.a,secondFaceID:pair.b) } }
        }
        guard positions.allSatisfy(\.isFinite) else { throw ContactError.invalid("布片表面接触出现非有限坐标。") }
        return stats
    }

    private static func coplanarIntersection(_ a: [Vector3], _ b: [Vector3]) -> Bool {
        let cross=(a[1]-a[0]).cross(a[2]-a[0])
        guard let normal=normalized(cross),
              abs(dot(b[0]-a[0],normal)) < 1e-8,
              abs(dot(b[1]-a[0],normal)) < 1e-8,
              abs(dot(b[2]-a[0],normal)) < 1e-8 else { return false }
        let axis=abs(normal.x) > abs(normal.y) ? (abs(normal.x) > abs(normal.z) ? 0 : 2) : (abs(normal.y) > abs(normal.z) ? 1 : 2)
        func point(_ p: Vector3) -> (Double,Double) { axis == 0 ? (p.y,p.z) : (axis == 1 ? (p.x,p.z) : (p.x,p.y)) }
        func orientation(_ p: (Double,Double), _ q: (Double,Double), _ r: (Double,Double)) -> Double {
            (q.0-p.0)*(r.1-p.1)-(q.1-p.1)*(r.0-p.0)
        }
        func inside(_ p: (Double,Double), _ face: [(Double,Double)]) -> Bool {
            let values=(0..<3).map { orientation(face[$0],face[($0+1)%3],p) }
            return values.allSatisfy({ $0 > 1e-12 }) || values.allSatisfy({ $0 < -1e-12 })
        }
        let aa=a.map(point), bb=b.map(point)
        let centerA=((aa[0].0+aa[1].0+aa[2].0)/3,(aa[0].1+aa[1].1+aa[2].1)/3)
        let centerB=((bb[0].0+bb[1].0+bb[2].0)/3,(bb[0].1+bb[1].1+bb[2].1)/3)
        if inside(centerA,bb) || inside(centerB,aa) ||
            aa.contains(where: { inside($0,bb) }) || bb.contains(where: { inside($0,aa) }) { return true }
        for i in 0..<3 { for j in 0..<3 {
            let p=aa[i], q=aa[(i+1)%3], r=bb[j], s=bb[(j+1)%3]
            if orientation(p,q,r)*orientation(p,q,s) < -1e-20 && orientation(r,s,p)*orientation(r,s,q) < -1e-20 { return true }
        } }
        return false
    }

    /// A sewn boundary touch may be exempted; an intersection extending into
    /// either face interior, including coplanar overlapping area, may not.
    private static func triangleIntersection(_ a:Triangle,_ b:Triangle,
        firstFaceID:Int,secondFaceID:Int,positions:[Vector3],topology:Topology)->Bool {
        let aa=a.vertices.map { positions[$0] },bb=b.vertices.map { positions[$0] }
        if coplanarIntersection(aa,bb) { return true }
        for edge in a.edges {
            if let hit=segmentTriangle(positions[edge.0],positions[edge.1],bb[0],bb[1],bb[2]) {
                let p=positions[edge.0]+(positions[edge.1]-positions[edge.0])*hit.0
                if !topology.permitsSewnTouch(firstFace:firstFaceID,secondFace:secondFaceID,
                    firstPoint:p,secondPoint:p,positions:positions) { return true }
            }
        }
        for edge in b.edges {
            if let hit=segmentTriangle(positions[edge.0],positions[edge.1],aa[0],aa[1],aa[2]) {
                let p=positions[edge.0]+(positions[edge.1]-positions[edge.0])*hit.0
                if !topology.permitsSewnTouch(firstFace:firstFaceID,secondFace:secondFaceID,
                    firstPoint:p,secondPoint:p,positions:positions) { return true }
            }
        }
        return false
    }

    /// Independent final sampled-surface inspection. Counts intersecting face
    /// pairs; it does not claim to detect swept collisions between time steps.
    static func inspect(positions: [Vector3], topology: Topology, thickness: Double,
                        maximumCandidatePairs: Int = 150_000,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Quality {
        if isCancelled() { throw CancellationError() }
        try validate(positions,topology:topology,thickness:thickness)
        let pairs=try candidates(positions:positions,topology:topology,thickness:thickness,
                                 maximumCandidatePairs:maximumCandidatePairs,isCancelled:isCancelled)
        let degenerate=topology.triangles.filter { (positions[$0.b]-positions[$0.a]).cross(positions[$0.c]-positions[$0.a]).lengthSquared < 1e-20 }.count
        var intersections=0, contacts=0, overlap=0.0
        for (index,pair) in pairs.enumerated() {
            if index % 128 == 0, isCancelled() { throw CancellationError() }
            let a=topology.triangles[pair.a], b=topology.triangles[pair.b]
            let aa=a.vertices.map { positions[$0] }, bb=b.vertices.map { positions[$0] }
            let crossing=triangleIntersection(a,b,firstFaceID:pair.a,secondFaceID:pair.b,
                positions:positions,topology:topology)
            if crossing { intersections += 1 }
            var nearest=Double.infinity
            for vertex in a.vertices where !topology.excludes(vertex,b) {
                let point=onTriangle(positions[vertex],bb[0],bb[1],bb[2]).point
                if !topology.permitsSewnProximity(firstFace:pair.a,secondFace:pair.b,
                    firstPoint:positions[vertex],secondPoint:point,positions:positions,paddingMeters:thickness) {
                    nearest=min(nearest,(positions[vertex]-point).length)
                }
            }
            for vertex in b.vertices where !topology.excludes(vertex,a) {
                let point=onTriangle(positions[vertex],aa[0],aa[1],aa[2]).point
                if !topology.permitsSewnProximity(firstFace:pair.b,secondFace:pair.a,
                    firstPoint:positions[vertex],secondPoint:point,positions:positions,paddingMeters:thickness) {
                    nearest=min(nearest,(positions[vertex]-point).length)
                }
            }
            for edge in a.edges { for other in b.edges where !topology.excludes(edge,other) {
                let points=closestEdges(positions[edge.0],positions[edge.1],positions[other.0],positions[other.1])
                if !topology.permitsSewnProximity(firstFace:pair.a,secondFace:pair.b,
                    firstPoint:points.a,secondPoint:points.b,positions:positions,paddingMeters:thickness) {
                    nearest=min(nearest,(points.a-points.b).length)
                }
            } }
            if nearest < thickness { contacts += 1; overlap=max(overlap,thickness-nearest) }
        }
        return .init(candidateTrianglePairs:pairs.count,intersectingTrianglePairs:intersections,
                     closeSurfacePairs:contacts,degenerateTriangles:degenerate,maximumSurfaceOverlapMeters:overlap)
    }
}
