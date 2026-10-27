import Foundation

/// Redundant source-geodesic upper bounds, not template positions or new pins.
/// If every original mesh edge is within the existing 8% acceptance bound and
/// each actual sewn attachment pair is within 0.5 mm, triangle inequality makes
/// all these bounds redundant. Fold nodes retain their original long paths.
/// The default mode runs only after the actual sewing ramp ends. An explicit
/// ramp-following mode uses that same ramp's true initial seam gaps to retain
/// a valid upper bound throughout assembly; it does not alter sewing targets.
nonisolated enum GarmentCodeSourceTethers {
    typealias K = GarmentCodeCircleDrape
    typealias S = GarmentCodeSewing
    typealias V = K.Vector3
    static let sourceEdgeStretchFactor = 1.08
    static let seamGapUpperBoundMeters = 0.0005

    enum TetherError: LocalizedError, Sendable {
        case invalid(String), budgetExceeded(String)
        var errorDescription: String? {
            switch self { case let .invalid(s), let .budgetExceeded(s): return s }
        }
    }
    struct Limits: Sendable {
        var maximumVertices = 20_000
        var maximumSourceEdges = 120_000
        var maximumSewingConstraints = 4_096
        var maximumGraphNodes = 30_000
        var maximumGraphEdges = 160_000
        var maximumDijkstraVisits = 1_000_000
    }
    enum Provenance: Equatable, Sendable {
        case verifiedSourceSHA256(String)
        /// Numeric graph validation only; no external paper/source validation.
        case rawGraphOnly
    }
    enum Mode: Sendable {
        case completedOnly
        case followSewingRamp
    }
    struct Tether: Sendable {
        let vertexID: Int
        let pinID: Int
        let pathUpperBoundMeters: Double
        /// Sum on the selected fixed source path, not all document seams.
        let initialSewingGapSumMeters: Double
        func upperBoundMeters(seamRampFraction: Double) -> Double {
            pathUpperBoundMeters+(1-seamRampFraction)*initialSewingGapSumMeters
        }
    }
    struct Plan: Sendable {
        let tethers: [Tether]
        let unreachableVertexIDs: [Int]
        let unreachableComponentCount: Int
        let provenance: Provenance
        let graphNodeCount: Int
        let graphEdgeCount: Int
        let virtualAttachmentCount: Int
        fileprivate let pinned: [Bool]
        fileprivate let inverseMasses: [Double]
        fileprivate init(tethers: [Tether], unreachableVertexIDs: [Int], unreachableComponentCount: Int,
                         provenance: Provenance, graphNodeCount: Int, graphEdgeCount: Int,
                         virtualAttachmentCount: Int, pinned: [Bool], inverseMasses: [Double]) {
            self.tethers=tethers;self.unreachableVertexIDs=unreachableVertexIDs
            self.unreachableComponentCount=unreachableComponentCount;self.provenance=provenance
            self.graphNodeCount=graphNodeCount;self.graphEdgeCount=graphEdgeCount
            self.virtualAttachmentCount=virtualAttachmentCount;self.pinned=pinned;self.inverseMasses=inverseMasses
        }
    }
    struct ProjectionStatistics: Sendable {
        var examinedVertices = 0
        var projectedVertices = 0
        var cappedCorrections = 0
        var unreachableVertices = 0
        var maximumViolationBeforeMeters = 0.0
        var maximumViolationAfterMeters = 0.0
        var maximumSingleVertexCorrectionMeters = 0.0
        var totalCorrectionTravelMeters = 0.0
    }
    private struct Edge: Hashable {
        let a: Int, b: Int
        init(_ a: Int, _ b: Int) { self.a=min(a,b);self.b=max(a,b) }
    }
    private struct EdgeBound {let length: Double;let initialGap: Double}
    private struct Arc { let node: Int; let length: Double;let initialGap: Double }
    private struct Visit {
        let distance: Double, pin: Int, node: Int
        static func precedes(_ a: Visit, _ b: Visit) -> Bool {
            if a.distance != b.distance { return a.distance < b.distance }
            if a.pin != b.pin { return a.pin < b.pin }
            return a.node < b.node
        }
    }
    private struct Heap {
        var values: [Visit] = []
        mutating func push(_ value: Visit) {
            values.append(value);var i=values.count-1
            while i>0 {let p=(i-1)/2;if !Visit.precedes(values[i],values[p]) {break};values.swapAt(i,p);i=p}
        }
        mutating func pop() -> Visit? {
            guard !values.isEmpty else {return nil}
            if values.count==1 {return values.removeLast()}
            let result=values[0];values[0]=values.removeLast();var i=0
            while i*2+1<values.count {
                let l=i*2+1,r=l+1,j=r<values.count && Visit.precedes(values[r],values[l]) ? r:l
                if !Visit.precedes(values[j],values[i]) {break};values.swapAt(i,j);i=j
            }
            return result
        }
    }

    static func prepare(input: GarmentCodeSewnDrape.PreparedInput, limits: Limits = .init(),
                        isCancelled: @Sendable () -> Bool = {false}) throws -> Plan {
        try build(referencePositions:input.cloth.referencePositions,sourceEdges:input.cloth.springs,
                  pinned:input.cloth.pinned,inverseMasses:input.cloth.inverseMasses,
                  constraints:input.plan.constraints,provenance:.verifiedSourceSHA256(input.sourceSHA256),
                  limits:limits,isCancelled:isCancelled)
    }

    /// Strict analytic graph entry point. It does not validate a paper document,
    /// its complete topology, sewing intent, area/masses or source provenance.
    static func prepareRawGraph(referencePositions: [V], sourceEdges: [K.Spring], pinned: [Bool],
                                inverseMasses: [Double], constraints: [S.Constraint],
                                limits: Limits = .init(),
                                isCancelled: @Sendable () -> Bool = {false}) throws -> Plan {
        try build(referencePositions:referencePositions,sourceEdges:sourceEdges,pinned:pinned,
                  inverseMasses:inverseMasses,constraints:constraints,provenance:.rawGraphOnly,
                  limits:limits,isCancelled:isCancelled)
    }

    private static func build(referencePositions: [V], sourceEdges: [K.Spring], pinned: [Bool],
                              inverseMasses: [Double], constraints: [S.Constraint], provenance: Provenance,
                              limits: Limits, isCancelled: @Sendable () -> Bool) throws -> Plan {
        if isCancelled() {throw CancellationError()}
        guard (1...20_000).contains(limits.maximumVertices),
              (1...120_000).contains(limits.maximumSourceEdges),
              (0...4_096).contains(limits.maximumSewingConstraints),
              (1...30_000).contains(limits.maximumGraphNodes),
              (1...160_000).contains(limits.maximumGraphEdges),
              (1...1_000_000).contains(limits.maximumDijkstraVisits) else {
            throw TetherError.budgetExceeded("无效的源路径图预算。")
        }
        let n=referencePositions.count
        guard n>0,n<=limits.maximumVertices,n<=limits.maximumGraphNodes,
              sourceEdges.count<=limits.maximumSourceEdges,constraints.count<=limits.maximumSewingConstraints else {
            throw TetherError.budgetExceeded("源路径图的输入超过预算。")
        }
        guard pinned.count==n,inverseMasses.count==n,
              referencePositions.allSatisfy({$0.isFinite && $0.length<100}),
              inverseMasses.enumerated().allSatisfy({$0.element.isFinite && (pinned[$0.offset] ? $0.element==0:$0.element>0)}) else {
            throw TetherError.invalid("源路径顶点、固定点或原质量无效。")
        }
        var graph=Array(repeating:[Arc](),count:n),edges:[Edge:EdgeBound]=[:],sourceLengths:[Edge:Double]=[:]
        func appendEdge(_ a: Int, _ b: Int, _ length: Double, initialGap: Double = 0) throws {
            if a==b {return}
            let key=Edge(a,b)
            if let old=edges[key] {
                if length<old.length || (length==old.length && initialGap<old.initialGap) {
                    edges[key] = .init(length:length,initialGap:initialGap)
                }
            }
            else {
                guard edges.count<limits.maximumGraphEdges else {throw TetherError.budgetExceeded("源路径图边数超过预算。")}
                edges[key] = .init(length:length,initialGap:initialGap)
            }
        }
        for (index,e) in sourceEdges.enumerated() {
            if index%128==0 && isCancelled() {throw CancellationError()}
            guard (0..<n).contains(e.a),(0..<n).contains(e.b),e.a != e.b,
                  e.length.isFinite,e.length>1e-10,e.length<200 else {throw TetherError.invalid("源结构边无效。")}
            let actual=(referencePositions[e.a]-referencePositions[e.b]).length,key=Edge(e.a,e.b)
            guard sourceLengths[key]==nil,abs(actual-e.length)<=max(1e-12,e.length*1e-10) else {
                throw TetherError.invalid("源结构边重复，或静止长度偏离原参考坐标。")
            }
            sourceLengths[key]=e.length
            try appendEdge(e.a,e.b,e.length*sourceEdgeStretchFactor)
        }
        var virtual: [S.Attachment:Int]=[:]
        func node(for attachment: S.Attachment) throws -> Int {
            guard (1...2).contains(attachment.vertexIDs.count),attachment.vertexIDs.count==attachment.weights.count,
                  attachment.vertexIDs.allSatisfy({(0..<n).contains($0)}),
                  attachment.weights.allSatisfy({$0.isFinite && $0>0 && $0<=1}),
                  abs(attachment.weights.reduce(0,+)-1)<1e-12 else {throw TetherError.invalid("源路径附着点无效。")}
            if attachment.vertexIDs.count==1 {return attachment.vertexIDs[0]}
            guard attachment.vertexIDs[0]<attachment.vertexIDs[1],
                  let length=sourceLengths[Edge(attachment.vertexIDs[0],attachment.vertexIDs[1])] else {
                throw TetherError.invalid("双节点附着点必须使用一条真实源结构边。")
            }
            if let existing=virtual[attachment] {return existing}
            guard graph.count<limits.maximumGraphNodes else {throw TetherError.budgetExceeded("源路径虚拟节点超过预算。")}
            let id=graph.count;graph.append([]);virtual[attachment]=id
            try appendEdge(id,attachment.vertexIDs[0],attachment.weights[1]*length*sourceEdgeStretchFactor)
            try appendEdge(id,attachment.vertexIDs[1],attachment.weights[0]*length*sourceEdgeStretchFactor)
            return id
        }
        for (index,c) in constraints.enumerated() {
            if index%128==0 && isCancelled() {throw CancellationError()}
            guard c.finalGapMeters==0,c.initialGapMeters.isFinite,c.initialGapMeters>=0 else {
                throw TetherError.invalid("源路径缝合约束无效。")
            }
            let a=try node(for:c.a),b=try node(for:c.b)
            try appendEdge(a,b,seamGapUpperBoundMeters,initialGap:c.initialGapMeters)
        }
        for (edge,bound) in edges {
            graph[edge.a].append(.init(node:edge.b,length:bound.length,initialGap:bound.initialGap))
            graph[edge.b].append(.init(node:edge.a,length:bound.length,initialGap:bound.initialGap))
        }
        for i in graph.indices {graph[i].sort{$0.node<$1.node}}
        var distances=Array(repeating:Double.infinity,count:graph.count),owners=Array(repeating:Int.max,count:graph.count),heap=Heap()
        var initialGapSums=Array(repeating:0.0,count:graph.count)
        for pin in pinned.indices where pinned[pin] {distances[pin]=0;owners[pin]=pin;heap.push(.init(distance:0,pin:pin,node:pin))}
        var visits=0
        while let visit=heap.pop() {
            visits += 1
            guard visits<=limits.maximumDijkstraVisits else {throw TetherError.budgetExceeded("源路径搜索超过预算。")}
            if visits%128==0 && isCancelled() {throw CancellationError()}
            if visit.distance != distances[visit.node] || visit.pin != owners[visit.node] {continue}
            for arc in graph[visit.node] {
                let d=visit.distance+arc.length
                if d<distances[arc.node] || (d==distances[arc.node] && visit.pin<owners[arc.node]) {
                    distances[arc.node]=d;owners[arc.node]=visit.pin;heap.push(.init(distance:d,pin:visit.pin,node:arc.node))
                    initialGapSums[arc.node]=initialGapSums[visit.node]+arc.initialGap
                }
            }
        }
        var tethers:[Tether]=[],unreachable:[Int]=[]
        for i in 0..<n where !pinned[i] {
            if distances[i].isFinite {
                tethers.append(.init(vertexID:i,pinID:owners[i],pathUpperBoundMeters:distances[i],
                                     initialSewingGapSumMeters:initialGapSums[i]))
            }
            else {unreachable.append(i)}
        }
        var visited=Set<Int>(),componentCount=0
        for root in unreachable where !visited.contains(root) {
            componentCount += 1;var stack=[root];visited.insert(root)
            while let node=stack.popLast() {
                for arc in graph[node] where !distances[arc.node].isFinite && visited.insert(arc.node).inserted {stack.append(arc.node)}
            }
        }
        if isCancelled() {throw CancellationError()}
        return .init(tethers:tethers,unreachableVertexIDs:unreachable,unreachableComponentCount:componentCount,
                     provenance:provenance,graphNodeCount:graph.count,graphEdgeCount:edges.count,
                     virtualAttachmentCount:virtual.count,pinned:pinned,inverseMasses:inverseMasses)
    }

    /// Caller must pass the actual sewing ramp fraction, not elapsed gravity
    /// time. In followSewingRamp mode each true seam path edge contributes
    /// initialGap*(1-ramp)+0.5mm; a fixed full-ramp shortest path remains a valid
    /// triangle-inequality bound at every ramp value without recomputing paths.
    /// No position is changed on errors/cancellation. A pin remains an
    /// actual existing fixed DOF; each free node retains all directions inside
    /// its source-path sphere. This is not a calibrated physical constraint.
    static func project(positions: inout [V], plan: Plan, seamRampFraction: Double,
                        mode: Mode = .completedOnly,
                        maximumSingleVertexCorrectionMeters: Double = 0.02,
                        isCancelled: @Sendable () -> Bool = {false}) throws -> ProjectionStatistics {
        if isCancelled() {throw CancellationError()}
        guard seamRampFraction.isFinite,(0...1).contains(seamRampFraction) else {
            throw TetherError.invalid("源路径上界需要 0 至 1 的真实缝合渐进比例。")
        }
        if case .completedOnly=mode, seamRampFraction != 1 {
            throw TetherError.invalid("默认源路径上界只能在真实缝合渐进阶段结束后启用。")
        }
        guard maximumSingleVertexCorrectionMeters.isFinite,
              (0.000001...0.02).contains(maximumSingleVertexCorrectionMeters) else {
            throw TetherError.budgetExceeded("源路径单次顶点修正必须在 1 微米至 20 毫米之间。")
        }
        guard positions.count==plan.pinned.count,positions.allSatisfy({$0.isFinite && $0.length<100}) else {
            throw TetherError.invalid("源路径投影坐标无效。")
        }
        var next=positions,stats=ProjectionStatistics();stats.unreachableVertices=plan.unreachableVertexIDs.count
        for (index,tether) in plan.tethers.enumerated() {
            if index%128==0 && isCancelled() {throw CancellationError()}
            stats.examinedVertices += 1
            let delta=next[tether.vertexID]-next[tether.pinID],distance=delta.length
            let bound=tether.upperBoundMeters(seamRampFraction:seamRampFraction)
            let violation=max(0,distance-bound)
            stats.maximumViolationBeforeMeters=max(stats.maximumViolationBeforeMeters,violation)
            if violation<=max(1e-12,bound*1e-12) {continue}
            let correction=min(violation,maximumSingleVertexCorrectionMeters)
            next[tether.vertexID]=next[tether.vertexID]-delta*(correction/distance)
            stats.projectedVertices += 1
            if violation>maximumSingleVertexCorrectionMeters {stats.cappedCorrections += 1}
            stats.maximumSingleVertexCorrectionMeters=max(stats.maximumSingleVertexCorrectionMeters,correction)
            stats.totalCorrectionTravelMeters += correction
            stats.maximumViolationAfterMeters=max(stats.maximumViolationAfterMeters,violation-correction)
        }
        if isCancelled() {throw CancellationError()}
        positions=next;return stats
    }
}
