import Foundation
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Runtime sewing between immutable panel meshes. Sewing anchors are not welds:
/// every panel keeps its own vertices, rest lengths, reference area and mass.
/// All coordinates and clearances in this file use metres.
nonisolated enum GarmentCodeSewing {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3

    struct EdgeKey: Codable, Hashable, Sendable {
        let panelID: String
        let edgeIndex: Int
    }
    enum Side: String, Codable, Hashable, Sendable { case a, b }
    enum Direction: String, Codable, Hashable, Sendable { case forward, reverse }
    enum Intent: Codable, Hashable, Sendable {
        case ordinary
        case eased(longerSide: Side, maximumLengthRatio: Double)
        case gathered(longerSide: Side, maximumLengthRatio: Double)
    }

    struct RefinementRequest: Codable, Equatable, Sendable {
        let edge: EdgeKey
        let edgeID: String
        /// Original, unreversed source arc fractions, not a world-space span.
        let sourceArcRange: ClosedRange<Double>
        let existingFreeBoundaryNodes: Int
        let minimumFreeBoundaryNodes: Int
        let requiredMaximumBoundarySpacingMeters: Double
        let reason: String
    }
    enum SewingError: LocalizedError, Sendable {
        case invalid(String)
        case budgetExceeded(String)
        case refinementNeeded([RefinementRequest])
        case precisionUnresolved
        var errorDescription: String? {
            switch self {
            case let .invalid(reason): return "缝合设置无效：\(reason)"
            case let .budgetExceeded(reason): return "缝合超出本轮预算：\(reason)"
            case .precisionUnresolved:return "完整接缝边界的数值范围或浮点环境无法确认。"
            case let .refinementNeeded(requests):
                return "\(requests.count) 处接缝边界需要局部细分，才能在缝合点之间保留可折叠节点；没有缩短或压缩原纸样。"
            }
        }
    }

    /// A canonical vertex or edge point. Repeated IDs are combined, zero
    /// weights removed, and the remaining positive weights sum exactly to one.
    struct Attachment: Codable, Hashable, Sendable {
        let vertexIDs: [Int]
        let weights: [Double]

        init(vertexIDs: [Int], weights: [Double]) throws {
            guard !vertexIDs.isEmpty, vertexIDs.count <= 16, vertexIDs.count == weights.count,
                  vertexIDs.allSatisfy({ $0 >= 0 }),
                  weights.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw SewingError.invalid("缝合附着点的顶点或权重无效。")
            }
            let sum=weights.reduce(0,+)
            guard sum.isFinite, abs(sum-1)<=1e-10 else {
                throw SewingError.invalid("附着点权重之和必须为 1。")
            }
            var combined: [Int:Double]=[:]
            for (id,weight) in zip(vertexIDs,weights) where weight>0 {
                combined[id,default:0] += weight
            }
            let ids=combined.keys.sorted()
            guard (1...2).contains(ids.count) else {
                throw SewingError.invalid("当前缝合附着点必须位于一个顶点或一条边上。")
            }
            var normalized=ids.map {combined[$0]!/sum}
            normalized[normalized.count-1]=1-normalized.dropLast().reduce(0,+)
            guard normalized.allSatisfy({$0.isFinite && $0>0 && $0<=1}) else {
                throw SewingError.invalid("附着点权重无法可靠归一化。")
            }
            self.vertexIDs=ids;self.weights=normalized
        }
        init(vertexID: Int) throws {try self.init(vertexIDs:[vertexID],weights:[1])}
        private enum CodingKeys: String, CodingKey {case vertexIDs,weights}
        init(from decoder: Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            try self.init(vertexIDs:c.decode([Int].self,forKey:.vertexIDs),
                          weights:c.decode([Double].self,forKey:.weights))
        }
        func point(in positions: [Vector3]) throws -> Vector3 {
            guard vertexIDs.allSatisfy({positions.indices.contains($0)}) else {
                throw SewingError.invalid("缝合附着点引用了不存在的顶点。")
            }
            let value=zip(vertexIDs,weights).reduce(Vector3.zero) {$0+positions[$1.0]*$1.1}
            guard value.isFinite else {throw SewingError.invalid("缝合附着点不是有限坐标。")}
            return value
        }
    }

    struct BoundarySegment: Codable, Hashable, Sendable {
        let edge: EdgeKey
        let edgeID: String
        let segmentIndex: Int
        let vertexIDs: [Int]
        let adjacentTriangleID: Int
        let sourceArcRange: ClosedRange<Double>
    }
    struct Location: Codable, Hashable, Sendable {
        let edge: EdgeKey
        let edgeID: String
        let sourceArcFraction: Double
        let sourceLengthMeters: Double
        /// Exact source parameter bounds of the supporting mesh segment(s).
        /// No claim is made that linear chord interpolation is exact curve t.
        let sourceParameterRange: ClosedRange<Double>
        let attachment: Attachment
        let boundarySegments: [BoundarySegment]
    }
    struct Origin: Codable, Hashable, Sendable {
        let seamID: String
        let stitchIndex: Int
        let a: Location
        let b: Location
        let aDirection: Direction
        let bDirection: Direction
        let intent: Intent
        let rightWrong: Bool
        /// Corner deduplication can share a constraint whose a/b order is the
        /// reverse of this original source stitch's a/b order.
        let reversedRelativeToConstraint: Bool
    }
    struct Constraint: Codable, Sendable {
        let a: Attachment
        let b: Attachment
        let initialGapMeters: Double
        let finalGapMeters: Double
        let initialDirection: Vector3
        fileprivate(set) var origins: [Origin]

        init(a: Attachment,b: Attachment,initialGapMeters: Double,
             initialDirection: Vector3 = .zero,origins: [Origin] = []) throws {
            guard initialGapMeters.isFinite,(0...100).contains(initialGapMeters),
                  initialDirection.isFinite,initialDirection.length<100,
                  a != b || initialGapMeters<=1e-12 else {
                throw SewingError.invalid("缝合初始间距或方向无效。")
            }
            self.a=a;self.b=b;self.initialGapMeters=initialGapMeters;self.finalGapMeters=0
            self.initialDirection=initialDirection.length>1e-12 ? initialDirection/initialDirection.length : .zero
            self.origins=origins
        }
        private enum CodingKeys: String,CodingKey {case a,b,initialGapMeters,finalGapMeters,initialDirection,origins}
        init(from decoder: Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            guard try c.decode(Double.self,forKey:.finalGapMeters)==0 else {
                throw SewingError.invalid("当前缝合终态间距必须为 0。")
            }
            try self.init(a:c.decode(Attachment.self,forKey:.a),b:c.decode(Attachment.self,forKey:.b),
                          initialGapMeters:c.decode(Double.self,forKey:.initialGapMeters),
                          initialDirection:c.decode(Vector3.self,forKey:.initialDirection),
                          origins:c.decode([Origin].self,forKey:.origins))
        }
    }

    /// A fresh state is needed when the constraint plan or vertex numbering
    /// changes. resetForFrame() resets XPBD lambdas and motion budgets; keep the
    /// same ramp fraction for all iterations within that frame.
    struct State: Sendable {
        fileprivate(set) var lambdas: [Double]
        fileprivate(set) var directions: [Vector3]
        fileprivate(set) var accumulatedCorrectionsMeters: [Double]
        fileprivate(set) var rampFraction: Double?
        init(constraintCount: Int,vertexCount: Int) throws {
            guard (0...20_000).contains(constraintCount),(1...200_000).contains(vertexCount) else {
                throw SewingError.budgetExceeded("状态数组的约束或顶点数量无效。")
            }
            lambdas=Array(repeating:0,count:constraintCount)
            directions=Array(repeating:.zero,count:constraintCount)
            accumulatedCorrectionsMeters=Array(repeating:0,count:vertexCount)
            rampFraction=nil
        }
        mutating func resetForFrame() {
            lambdas=Array(repeating:0,count:lambdas.count)
            accumulatedCorrectionsMeters=Array(repeating:0,count:accumulatedCorrectionsMeters.count)
            rampFraction=nil
        }
    }
    struct ProjectionStatistics: Codable,Sendable {
        var processedConstraints=0
        var unresolvedPinnedConstraints=0
        var unresolvedDirectionConstraints=0
        var cappedConstraints=0
        var maximumSingleCorrectionMeters=0.0
        var maximumAccumulatedCorrectionMeters=0.0
    }
    struct Quality: Codable,Sendable {
        let anchorConstraintCount: Int
        let maximumGapMeters: Double
        let rmsGapMeters: Double
        let maximumTargetResidualMeters: Double
        let rmsTargetResidualMeters: Double
        let rampFraction: Double
        /// Finite tacks do not certify that every point of a continuous seam
        /// is closed. This distinction is particularly important for gathers.
        let measuresOnlyAnchorGaps: Bool
        /// Nil in legacy constraints-only inspections/JSON. Never interpret a
        /// missing or gathered-excluding report as all-seam closure evidence.
        var continuousBoundary:ContinuousBoundaryQuality?=nil
        var maximumMeasuredGapMeters:Double {max(maximumGapMeters,continuousBoundary?.maximumGapUpperBoundMeters ?? maximumGapMeters)}
        var hasCompleteBoundaryClosureEvidence:Bool {continuousBoundary?.allSourceSeamsCovered == true}
    }
    struct ContinuousSeamQuality:Codable,Sendable {
        let seamID:String,stitchIndex:Int,evaluatedSourceKnots:Int
        /// Conservative binary64 upper bound over the COMPLETE actual paired
        /// polylines, not just the finite constraints or a fixed sample set.
        let maximumGapUpperBoundMeters:Double
    }
    struct ContinuousBoundaryQuality:Codable,Sendable {
        let sourceSHA256:String,declaredSeams:Int,measuredContinuousSeams:Int,gatheredSeamsUnproven:Int
        let evaluatedSourceKnots:Int,evaluatedSegmentEnclosures:Int,completedAllContinuousSeams:Bool
        let maximumGapUpperBoundMeters:Double?
        let seams:[ContinuousSeamQuality]
        var allSourceSeamsCovered:Bool {completedAllContinuousSeams && gatheredSeamsUnproven==0 && measuredContinuousSeams==declaredSeams}
    }
    struct InspectionLimits:Sendable {
        var maximumSeams=4096
        var maximumBoundaryKnots=100_000
        var maximumEvaluatedSourceKnots=100_000
        var maximumSegmentEnclosures=400_000
        var maximumEstimatedWorkingBytes=32*1024*1024
    }

    private static func validatePositions(_ positions:[Vector3]) throws {
        guard (1...200_000).contains(positions.count),positions.allSatisfy({$0.isFinite && $0.length<100}) else {
            throw SewingError.invalid("缝合坐标必须有限、使用米且位于本轮有效范围。")
        }
    }
    private static func validateRamp(_ ramp:Double) throws {
        guard ramp.isFinite,(0...1).contains(ramp) else {throw SewingError.invalid("缝合收拢比例必须为 0～1。")}
    }

    /// One XPBD projection pass. normalizedInverseMass is the same area/mass
    /// normalized inverse mass used by the cloth kernel; pinned particles are
    /// represented by zero. physicalCompliance*m_mean/dt² therefore has the
    /// same normalized units as those inverse masses. No mass is renormalized.
    /// The frame budget measures accumulated numerical travel, not net motion.
    /// A separate single-correction cap prevents a larger iteration budget from
    /// allowing one large jump. Both caps use one common constraint scale so
    /// the inverse-mass correction ratios remain unchanged.
    ///
    /// Cancellation throws; like the existing contact primitives, an in-flight
    /// pass may already have changed its inout frame. The caller discards it.
    static func project(positions:inout[Vector3],constraints:[Constraint],
                        normalizedInverseMass:[Double],state:inout State,
                        timeStep:Double,physicalCompliance:Double,
                        meanParticleMassKg:Double,rampFraction:Double,
                        maximumVertexCorrectionPerFrameMeters:Double=0.02,
                        maximumSingleVertexCorrectionMeters:Double=0.02,
                        isCancelled:@Sendable()->Bool={false}) throws -> ProjectionStatistics {
        if isCancelled() {throw CancellationError()}
        try validatePositions(positions);try validateRamp(rampFraction)
        guard constraints.count<=20_000,normalizedInverseMass.count==positions.count,
              normalizedInverseMass.allSatisfy({$0.isFinite && $0>=0}),
              state.lambdas.count==constraints.count,state.directions.count==constraints.count,
              state.accumulatedCorrectionsMeters.count==positions.count,
              timeStep.isFinite,(0.00001...1).contains(timeStep),
              physicalCompliance.isFinite,(0...10_000).contains(physicalCompliance),
              meanParticleMassKg.isFinite,meanParticleMassKg>0,meanParticleMassKg<=100,
              maximumVertexCorrectionPerFrameMeters.isFinite,
              (0.000001...0.5).contains(maximumVertexCorrectionPerFrameMeters),
              maximumSingleVertexCorrectionMeters.isFinite,
              (0.000001...0.1).contains(maximumSingleVertexCorrectionMeters) else {
            throw SewingError.invalid("缝合质量、时间步、柔顺度或状态数组无效。")
        }
        if let prior=state.rampFraction,abs(prior-rampFraction)>1e-12 {
            throw SewingError.invalid("收拢目标变化后必须先 resetForFrame()，不能复用上一时间步的乘子。")
        }
        state.rampFraction=rampFraction
        let alpha=physicalCompliance*meanParticleMassKg/(timeStep*timeStep)
        guard alpha.isFinite else {throw SewingError.invalid("缝合柔顺度换算溢出。")}
        var stats=ProjectionStatistics()
        for (index,c) in constraints.enumerated() {
            if index%64==0 && isCancelled() {throw CancellationError()}
            let a=try c.a.point(in:positions),b=try c.b.point(in:positions),delta=a-b
            let distance=delta.length,target=c.initialGapMeters*(1-rampFraction)
            let residual=distance-target
            var coefficients:[Int:Double]=[:]
            for (id,w) in zip(c.a.vertexIDs,c.a.weights) {coefficients[id,default:0] += w}
            for (id,w) in zip(c.b.vertexIDs,c.b.weights) {coefficients[id,default:0] -= w}
            let ids=coefficients.keys.sorted()
            let denominator=ids.reduce(0.0) {$0+normalizedInverseMass[$1]*pow(coefficients[$1]!,2)}
            guard denominator.isFinite else {throw SewingError.invalid("缝合逆质量换算溢出。")}
            stats.processedConstraints += 1
            if denominator<=1e-24 {
                if abs(residual)>1e-9 {stats.unresolvedPinnedConstraints += 1}
                continue
            }
            let direction:Vector3
            if distance>1e-12 {direction=delta/distance;state.directions[index]=direction}
            else if state.directions[index].length>0.5 {direction=state.directions[index]}
            else if c.initialDirection.length>0.5 {direction=c.initialDirection;state.directions[index]=direction}
            else {
                if abs(residual)>1e-9 {stats.unresolvedDirectionConstraints += 1}
                continue
            }
            let change = -(residual+alpha*state.lambdas[index])/(denominator+alpha)
            guard change.isFinite else {throw SewingError.invalid("缝合乘子产生非有限值。")}
            var scale=1.0
            for id in ids {
                let proposed=abs(change*normalizedInverseMass[id]*coefficients[id]!)
                if proposed>0 {
                    let remaining=max(0,maximumVertexCorrectionPerFrameMeters-state.accumulatedCorrectionsMeters[id])
                    scale=min(scale,remaining/proposed)
                    scale=min(scale,maximumSingleVertexCorrectionMeters/proposed)
                }
            }
            scale=max(0,min(1,scale))
            if scale<1-1e-12 {stats.cappedConstraints += 1}
            let applied=change*scale
            state.lambdas[index] += applied
            for id in ids {
                let correction=direction*(applied*normalizedInverseMass[id]*coefficients[id]!)
                positions[id]=positions[id]+correction
                state.accumulatedCorrectionsMeters[id] += correction.length
                stats.maximumSingleCorrectionMeters=max(stats.maximumSingleCorrectionMeters,correction.length)
            }
        }
        guard positions.allSatisfy(\.isFinite),state.lambdas.allSatisfy(\.isFinite) else {
            throw SewingError.invalid("缝合产生了非有限结果。")
        }
        stats.maximumAccumulatedCorrectionMeters=state.accumulatedCorrectionsMeters.max() ?? 0
        return stats
    }

    static func inspect(positions:[Vector3],constraints:[Constraint],rampFraction:Double=1,
                        isCancelled:@Sendable()->Bool={false}) throws -> Quality {
        if isCancelled() {throw CancellationError()}
        try validatePositions(positions);try validateRamp(rampFraction)
        guard constraints.count<=20_000 else {throw SewingError.budgetExceeded("检查的缝合约束过多。")}
        var maximum=0.0,squared=0.0,maxResidual=0.0,squaredResidual=0.0
        for (i,c) in constraints.enumerated() {
            if i%64==0 && isCancelled() {throw CancellationError()}
            let gap=(try c.a.point(in:positions)-c.b.point(in:positions)).length
            let residual=abs(gap-c.initialGapMeters*(1-rampFraction))
            maximum=max(maximum,gap);squared += gap*gap
            maxResidual=max(maxResidual,residual);squaredResidual += residual*residual
        }
        let count=Double(max(1,constraints.count))
        return .init(anchorConstraintCount:constraints.count,maximumGapMeters:maximum,
                     rmsGapMeters:sqrt(squared/count),maximumTargetResidualMeters:maxResidual,
                     rmsTargetResidualMeters:sqrt(squaredResidual/count),rampFraction:rampFraction,
                     measuresOnlyAnchorGaps:true)
    }

    struct SourceStitch: Codable,Sendable {
        let a: EdgeKey
        let b: EdgeKey
        let rightWrong: Bool
    }
    /// Physical intent and both arc directions must be supplied by a known
    /// runtime program/placement plan. A length ratio alone cannot distinguish
    /// elastic ease, gathered fabric, a wrong edge, or an invalid import.
    struct StitchHint: Codable,Sendable {
        let stitchIndex: Int
        let seamID: String
        let a: EdgeKey
        let b: EdgeKey
        let aDirection: Direction
        let bDirection: Direction
        let rightWrong: Bool
        let intent: Intent
        let maximumTackSpacingMeters: Double
        let minimumFreeBoundaryNodes: Int
        let ordinaryLengthToleranceMeters: Double
        init(stitchIndex:Int,seamID:String,a:EdgeKey,b:EdgeKey,
             aDirection:Direction,bDirection:Direction,rightWrong:Bool,intent:Intent,
             maximumTackSpacingMeters:Double=0.06,minimumFreeBoundaryNodes:Int=1,
             ordinaryLengthToleranceMeters:Double=0.00001) {
            self.stitchIndex=stitchIndex;self.seamID=seamID;self.a=a;self.b=b
            self.aDirection=aDirection;self.bDirection=bDirection;self.rightWrong=rightWrong;self.intent=intent
            self.maximumTackSpacingMeters=maximumTackSpacingMeters
            self.minimumFreeBoundaryNodes=minimumFreeBoundaryNodes
            self.ordinaryLengthToleranceMeters=ordinaryLengthToleranceMeters
        }
    }
    struct RuntimeAssembly: Codable,Sendable {
        let sourceSHA256: String
        let hints: [StitchHint]
    }
    /// Vertex and triangle IDs refer to the caller's concatenated simulation
    /// arrays. Panels remain separate; supplying pre-welded panel vertices is
    /// rejected rather than silently accepting lost source degrees of freedom.
    struct PanelBinding: Sendable {
        let mesh: GarmentCodePanelMesher.Mesh
        let vertexIDs: [Int]
        let triangleIDs: [Int]
        init(mesh:GarmentCodePanelMesher.Mesh,vertexIDs:[Int],triangleIDs:[Int]) {
            self.mesh=mesh;self.vertexIDs=vertexIDs;self.triangleIDs=triangleIDs
        }
        init(mesh:GarmentCodePanelMesher.Mesh,vertexOffset:Int,triangleOffset:Int) throws {
            let vertices=mesh.flatPositions.count,triangles=mesh.triangleIndices.count/3
            guard vertexOffset>=0,triangleOffset>=0,
                  vertexOffset<=Int.max-vertices,triangleOffset<=Int.max-triangles else {
                throw SewingError.invalid("裁片顶点或三角面偏移溢出。")
            }
            self.init(mesh:mesh,vertexIDs:(0..<vertices).map {vertexOffset+$0},
                      triangleIDs:(0..<triangles).map {triangleOffset+$0})
        }
    }
    struct BoundaryPath: Codable,Sendable {
        let edge: EdgeKey
        let edgeID: String
        let vertexIDs: [Int]
        let sourceParameters: [Double]
        let sourceArcFractions: [Double]
        let sourceLengthMeters: Double
        let segments: [BoundarySegment]
    }
    struct Anchor: Codable,Sendable {
        let seamID: String
        let stitchIndex: Int
        let normalizedSeamFraction: Double
        let a: Location
        let b: Location
        /// nil means both locations already refer to the very same topological
        /// particle. Its source correspondence is still retained here.
        let constraintIndex: Int?
    }
    struct TrianglePair: Codable,Hashable,Sendable {
        /// Source-side order: a belongs to Location.a, b to Location.b.
        /// It must not be replaced by a numerical min/max ordering.
        let a: Int
        let b: Int
    }
    /// Metadata for attachment-local contact treatment only. These are the
    /// boundary segments and their immediate adjacent faces at a tack, not all
    /// triangles of either panel and not permission to disable whole-panel
    /// collision. Untacked folds must retain ordinary cloth contact.
    struct ContactNeighborhood: Codable,Sendable {
        let anchorIndex: Int
        let constraintIndex: Int?
        let a: Location
        let b: Location
        let rightWrong: Bool
        let adjacentTrianglePairs: [TrianglePair]
    }
    /// Ordinary equal-length seams additionally cover their complete meshed
    /// boundary polyline. Union-of-knot anchors ensure each interval lies in
    /// exactly one source boundary segment on each side. This still permits
    /// only matched boundary contact, never an interior face crossing.
    struct BoundaryIntervalContact: Codable,Sendable {
        let seamID: String
        let stitchIndex: Int
        let startAnchorIndex: Int
        let endAnchorIndex: Int
        let normalizedSeamRange: ClosedRange<Double>
        let aStart: Location
        let aEnd: Location
        let bStart: Location
        let bEnd: Location
        let aSegment: BoundarySegment
        let bSegment: BoundarySegment
        let rightWrong: Bool
    }
    struct FoldInterval: Codable,Sendable {
        let seamID: String
        let intent: Intent
        let longerEdge: EdgeKey
        let sourceArcRange: ClosedRange<Double>
        let sourceIntervalLengthMeters: Double
        /// These IDs participate in no sewing attachment anywhere in the plan.
        /// They are not certified free of body/other caller-defined constraints.
        let untackedBoundaryVertexIDs: [Int]
        let minimumFreeBoundaryNodes: Int
    }
    struct Plan: Codable,Sendable {
        let sourceSHA256: String
        let constraints: [Constraint]
        let anchors: [Anchor]
        let allBoundaryPaths: [BoundaryPath]
        let foldIntervals: [FoldInterval]
        let contactNeighborhoods: [ContactNeighborhood]
        /// Historical serialized field name: actual continuous ordinary OR
        /// eased source-local boundary intervals, never gathered face masks.
        let ordinaryBoundaryIntervals: [BoundaryIntervalContact]
        let deduplicatedCornerConstraints: Int
        let sharedTopologicalCornerAnchors: Int
        /// True only for explicitly gathered coarse tacks with free fold
        /// nodes between them. Ordinary/eased seams retain the complete union-of-
        /// knots boundary polyline and do not use this coarse-fold warning.
        /// Coarse anchor gaps do not certify a continuously closed seam.
        let usesFiniteCoarseTacks: Bool
    }
    struct BuildLimits: Sendable {
        var maximumPanels=128
        var maximumConstraints=4096
        var maximumAnchors=8192
        var maximumTriangles=240_000
        var maximumAnchorIntervalsPerStitch=256
        var maximumBoundarySamples=100_000
        var maximumContactTrianglePairs=40_000
        var maximumRefinementRequests=4096
    }
    private struct VertexPair: Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int) {self.a=min(a,b);self.b=max(a,b)}
    }
    private struct AttachmentPair: Hashable {
        let a:Attachment,b:Attachment
        init(_ a:Attachment,_ b:Attachment) {
            let first:Bool
            if a.vertexIDs != b.vertexIDs {first=a.vertexIDs.lexicographicallyPrecedes(b.vertexIDs)}
            else {first=a.weights.lexicographicallyPrecedes(b.weights)}
            self.a=first ? a : b;self.b=first ? b : a
        }
    }
    private struct PendingFold {
        let seamID:String,intent:Intent,path:BoundaryPath,range:ClosedRange<Double>
        let minimum:Int
        let candidates:[Int]
        let suggestedSpacing:Double
    }

    private static func validHash(_ hash:String)->Bool {
        hash.utf8.count==64 && hash.utf8.allSatisfy {($0>=48 && $0<=57) || ($0>=97 && $0<=102)}
    }
    private static func location(_ path:BoundaryPath,arcFraction:Double) throws -> Location {
        let fractions=path.sourceArcFractions,last=fractions.count-1
        let f=max(0,min(1,arcFraction)),tolerance=1e-12
        var low=0,high=last
        while high-low>1 {let mid=(low+high)/2;if fractions[mid]<f {low=mid}else{high=mid}}
        let vertex:Int?
        if abs(f-fractions[low])<=tolerance {vertex=low}
        else if abs(f-fractions[high])<=tolerance {vertex=high}
        else {vertex=nil}
        let attachment:Attachment,segments:[BoundarySegment],actualFraction:Double
        if let vertex {
            attachment=try .init(vertexID:path.vertexIDs[vertex]);actualFraction=fractions[vertex]
            var ids:[Int]=[]
            if vertex>0 {ids.append(vertex-1)}
            if vertex<last {ids.append(vertex)}
            segments=ids.map {path.segments[$0]}
        } else {
            let weight=(f-fractions[low])/(fractions[high]-fractions[low])
            attachment=try .init(vertexIDs:[path.vertexIDs[low],path.vertexIDs[high]],weights:[1-weight,weight])
            segments=[path.segments[low]];actualFraction=f
        }
        let first=segments.map(\.segmentIndex).min()!,end=segments.map(\.segmentIndex).max()!+1
        return .init(edge:path.edge,edgeID:path.edgeID,sourceArcFraction:actualFraction,
                     sourceLengthMeters:path.sourceLengthMeters,
                     sourceParameterRange:path.sourceParameters[first]...path.sourceParameters[end],
                     attachment:attachment,boundarySegments:segments)
    }

    /// Build only a runtime sidecar. The source SHA is supplied by the caller's
    /// canonical document hashing layer and must match exactly. Every source
    /// stitch needs one explicit hint; no unmatched component is silently omitted.
    static func build(bindings:[PanelBinding],positions:[Vector3],sourceStitches:[SourceStitch],
                      actualSourceSHA256:String,assembly:RuntimeAssembly,
                      limits:BuildLimits = .init(),
                      isCancelled:@Sendable()->Bool={false}) throws -> Plan {
        if isCancelled() {throw CancellationError()}
        try validatePositions(positions)
        guard validHash(actualSourceSHA256),assembly.sourceSHA256==actualSourceSHA256 else {
            throw SewingError.invalid("运行时装配必须绑定同一份规范化源文件的 64 位小写 SHA-256。")
        }
        guard (1...128).contains(limits.maximumPanels),(1...20_000).contains(limits.maximumConstraints),
              (1...40_000).contains(limits.maximumAnchors),(1...1_000_000).contains(limits.maximumTriangles),
              (1...512).contains(limits.maximumAnchorIntervalsPerStitch),
              (2...200_000).contains(limits.maximumBoundarySamples),
              (1...200_000).contains(limits.maximumContactTrianglePairs),
              (1...20_000).contains(limits.maximumRefinementRequests),
              !bindings.isEmpty,bindings.count<=limits.maximumPanels,sourceStitches.count<=2048,
              assembly.hints.count==sourceStitches.count else {
            throw SewingError.budgetExceeded("裁片、源接缝、提示或资源上限无效。")
        }
        var paths:[EdgeKey:BoundaryPath]=[:],orderedPaths:[BoundaryPath]=[]
        var panels=Set<String>(),globalVertices=Set<Int>(),globalTriangles=Set<Int>(),boundaryCount=0
        for binding in bindings {
            if isCancelled() {throw CancellationError()}
            let mesh=binding.mesh
            guard !mesh.panelID.isEmpty,mesh.panelID.utf8.count<=256,panels.insert(mesh.panelID).inserted,
                  binding.vertexIDs.count==mesh.flatPositions.count,
                  !mesh.triangleIndices.isEmpty,mesh.triangleIndices.count%3==0,
                  binding.triangleIDs.count==mesh.triangleIndices.count/3,
                  mesh.flatPositions.allSatisfy({$0.isFinite}),
                  binding.vertexIDs.allSatisfy({positions.indices.contains($0)}),
                  Set(binding.vertexIDs).count==binding.vertexIDs.count,
                  binding.triangleIDs.allSatisfy({$0>=0 && $0<1_000_000}),
                  Set(binding.triangleIDs).count==binding.triangleIDs.count else {
                throw SewingError.invalid("裁片绑定、源坐标或三角面映射无效。")
            }
            for id in binding.vertexIDs {
                guard globalVertices.insert(id).inserted else {
                    throw SewingError.invalid("不同裁片已经合并了顶点；缝合前必须保留各自的源自由度。")
                }
            }
            for id in binding.triangleIDs {
                guard globalTriangles.insert(id).inserted else {throw SewingError.invalid("裁片三角面 ID 重复。")}
            }
            guard globalTriangles.count<=limits.maximumTriangles else {throw SewingError.budgetExceeded("源裁片三角面总数过多。")}
            var adjacency:[VertexPair:[Int]]=[:]
            for t in stride(from:0,to:mesh.triangleIndices.count,by:3) {
                if t%768==0 && isCancelled() {throw CancellationError()}
                let ids=(0..<3).map {Int(mesh.triangleIndices[t+$0])}
                guard Set(ids).count==3,ids.allSatisfy({mesh.flatPositions.indices.contains($0)}) else {
                    throw SewingError.invalid("源三角网格索引无效。")
                }
                for (a,b) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                    adjacency[.init(a,b),default:[]].append(binding.triangleIDs[t/3])
                }
            }
            guard adjacency.values.allSatisfy({$0.count<=2}),
                  Set(mesh.boundaries.map(\.edgeIndex))==Set(mesh.boundaries.indices) else {
                throw SewingError.invalid("源网格不是一致的简单裁片边界。")
            }
            for b in mesh.boundaries.sorted(by:{$0.edgeIndex<$1.edgeIndex}) {
                boundaryCount += b.vertexIDs.count
                guard boundaryCount<=limits.maximumBoundarySamples else {
                    throw SewingError.budgetExceeded("源边界采样点过多。")
                }
                let count=b.vertexIDs.count
                guard count>=2,b.sourceParameters.count==count,b.arcFractions.count==count,
                      !b.edgeID.isEmpty,b.edgeID.utf8.count<=512,
                      b.sourceLengthMeters.isFinite,b.sourceLengthMeters>1e-9,b.sourceLengthMeters<100,
                      b.vertexIDs.allSatisfy({mesh.flatPositions.indices.contains($0)}),
                      b.sourceParameters.allSatisfy({$0.isFinite && (0...1).contains($0)}),
                      b.arcFractions.allSatisfy({$0.isFinite && (0...1).contains($0)}),
                      abs(b.arcFractions[0])<1e-10,abs(b.arcFractions[count-1]-1)<1e-10,
                      abs(b.sourceParameters[0])<1e-10,abs(b.sourceParameters[count-1]-1)<1e-10,
                      zip(b.arcFractions,b.arcFractions.dropFirst()).allSatisfy({$0.0<$0.1}),
                      zip(b.sourceParameters,b.sourceParameters.dropFirst()).allSatisfy({$0.0<$0.1}) else {
                    throw SewingError.invalid("源边界 ID、弧长或参数采样无效。")
                }
                let key=EdgeKey(panelID:mesh.panelID,edgeIndex:b.edgeIndex)
                var segments:[BoundarySegment]=[]
                for i in 0..<(count-1) {
                    let a=b.vertexIDs[i],c=b.vertexIDs[i+1]
                    guard a != c,let adjacent=adjacency[.init(a,c)],adjacent.count==1 else {
                        throw SewingError.invalid("源边界线段没有唯一的相邻三角面。")
                    }
                    segments.append(.init(edge:key,edgeID:b.edgeID,segmentIndex:i,
                        vertexIDs:[binding.vertexIDs[a],binding.vertexIDs[c]],adjacentTriangleID:adjacent[0],
                        sourceArcRange:b.arcFractions[i]...b.arcFractions[i+1]))
                }
                let path=BoundaryPath(edge:key,edgeID:b.edgeID,vertexIDs:b.vertexIDs.map {binding.vertexIDs[$0]},
                    sourceParameters:b.sourceParameters,sourceArcFractions:b.arcFractions,
                    sourceLengthMeters:b.sourceLengthMeters,segments:segments)
                guard paths[key]==nil else {throw SewingError.invalid("源边界键重复。")}
                paths[key]=path;orderedPaths.append(path)
            }
        }
        guard Set(assembly.hints.map(\.stitchIndex))==Set(sourceStitches.indices),
              Set(assembly.hints.map(\.seamID)).count==assembly.hints.count else {
            throw SewingError.invalid("每条源接缝都需要唯一且完整的运行时提示。")
        }
        var constraints:[Constraint]=[],anchors:[Anchor]=[],neighborhoods:[ContactNeighborhood]=[]
        var ordinaryContacts:[BoundaryIntervalContact]=[]
        var constraintLookup:[AttachmentPair:Int]=[:],usedEdges=Set<EdgeKey>(),allAnchorVertices=Set<Int>()
        var pendingFolds:[PendingFold]=[],deduplicated=0,sharedCorners=0,totalPairs=0
        for hint in assembly.hints.sorted(by:{$0.stitchIndex<$1.stitchIndex}) {
            if isCancelled() {throw CancellationError()}
            let source=sourceStitches[hint.stitchIndex]
            guard hint.a==source.a,hint.b==source.b,hint.rightWrong==source.rightWrong,hint.a != hint.b,
                  !hint.seamID.isEmpty,hint.seamID.utf8.count<=256,
                  let aPath=paths[hint.a],let bPath=paths[hint.b],
                  hint.maximumTackSpacingMeters.isFinite,(0.001...0.25).contains(hint.maximumTackSpacingMeters),
                  (0...16).contains(hint.minimumFreeBoundaryNodes),
                  hint.ordinaryLengthToleranceMeters.isFinite,
                  (1e-9...0.001).contains(hint.ordinaryLengthToleranceMeters),
                  usedEdges.insert(hint.a).inserted,usedEdges.insert(hint.b).inserted else {
                throw SewingError.invalid("运行时提示与源边界、方向标记或接缝用途不一致；重复使用的边需要先显式分段。")
            }
            let longer:Side?
            let continuousCorrespondence:Bool
            switch hint.intent {
            case .ordinary:
                guard abs(aPath.sourceLengthMeters-bPath.sourceLengthMeters)<=hint.ordinaryLengthToleranceMeters else {
                    throw SewingError.invalid("普通接缝两侧源长度不同，需要明确的吃势或抽褶提示，不能自动合并。")
                }
                longer=nil;continuousCorrespondence=true
            case let .eased(side,maximum),let .gathered(side,maximum):
                let long=side == .a ? aPath.sourceLengthMeters : bPath.sourceLengthMeters
                let short=side == .a ? bPath.sourceLengthMeters : aPath.sourceLengthMeters
                guard maximum.isFinite,(1...10).contains(maximum),long+1e-10>=short,long/short<=maximum+1e-9 else {
                    throw SewingError.invalid("明确指定的吃势／抽褶侧与源长度倍率不一致。")
                }
                if case .gathered=hint.intent {
                    guard hint.minimumFreeBoundaryNodes>=1,long>short+max(1e-9,short*1e-6) else {throw SewingError.invalid("抽褶提示需要真实的较长源边与自由节点。")}
                    continuousCorrespondence=false
                } else {continuousCorrespondence=true}
                longer=side
            }
            let shortLength=min(aPath.sourceLengthMeters,bPath.sourceLengthMeters)
            let required=ceil(shortLength/hint.maximumTackSpacingMeters)
            guard required.isFinite,required<=Double(limits.maximumAnchorIntervalsPerStitch) else {
                throw SewingError.budgetExceeded("有限缝合点的数量超过本轮上限。")
            }
            let intervals=max(1,Int(required))
            var fractions=(0...intervals).map {Double($0)/Double(intervals)}
            if continuousCorrespondence {
                fractions += aPath.sourceArcFractions.map {hint.aDirection == .forward ? $0 : 1-$0}
                fractions += bPath.sourceArcFractions.map {hint.bDirection == .forward ? $0 : 1-$0}
                let sorted=fractions.sorted();fractions=[]
                // Preserve ordinary serialized plans. Eased correspondence
                // retains EVERY distinct actual source knot, without epsilon
                // merging; the independent whole-boundary check does likewise.
                for f in sorted where fractions.last.map({last in
                    if case .ordinary=hint.intent{return abs(last-f)>1e-12}
                    return last != f
                }) ?? true {fractions.append(f)}
                if fractions.count-1>limits.maximumAnchorIntervalsPerStitch,
                   case .eased=hint.intent {
                    // Preserve every already-admissible plan exactly. Only an
                    // over-budget eased plan may discard redundant UNIFORM
                    // tacks; every distinct oriented source knot stays present.
                    var knots=aPath.sourceArcFractions.map {hint.aDirection == .forward ? $0 : 1-$0}
                    knots += bPath.sourceArcFractions.map {hint.bDirection == .forward ? $0 : 1-$0}
                    knots.sort();var sourceKnots:[Double]=[]
                    for f in knots where sourceKnots.last != f {sourceKnots.append(f)}
                    guard sourceKnots.count-1<=limits.maximumAnchorIntervalsPerStitch else {
                        throw SewingError.budgetExceeded("吃势接缝的实际源节点本身超过分段上限。")
                    }
                    func checkFallback()throws {
                        guard closureNearestRounding() else {throw SewingError.precisionUnresolved}
                        if isCancelled(){throw CancellationError()}
                        guard closureNearestRounding() else {throw SewingError.precisionUnresolved}
                    }
                    try checkFallback()
                    var pending=zip(sourceKnots,sourceKnots.dropFirst()).map {($0,$1)}.reversed().map {$0}
                    var refined=[sourceKnots[0]],intervalCount=sourceKnots.count-1
                    while let (lo,hi)=pending.popLast() {
                        try checkFallback()
                        // Both operands are positive. Two outward-rounded
                        // operations bound the real stored-binary arc span.
                        let spanUpper=((hi-lo).nextUp*shortLength).nextUp
                        guard spanUpper.isFinite,spanUpper>0 else {throw SewingError.precisionUnresolved}
                        if spanUpper>hint.maximumTackSpacingMeters {
                            guard intervalCount<limits.maximumAnchorIntervalsPerStitch else {
                                throw SewingError.budgetExceeded("吃势接缝保留全部源节点后仍无法满足有限缝合间距。")
                            }
                            let mid=lo+(hi-lo)/2
                            guard mid>lo,mid<hi else {throw SewingError.precisionUnresolved}
                            intervalCount += 1;pending.append((mid,hi));pending.append((lo,mid))
                        } else {refined.append(hi)}
                    }
                    try checkFallback();fractions=refined
                }
                guard fractions.count-1<=limits.maximumAnchorIntervalsPerStitch else {
                    throw SewingError.budgetExceeded("普通接缝的源边界分段过多，不能省略其实际折线节点。")
                }
            }
            let firstAnchorIndex=anchors.count
            var seamAnchors:[Anchor]=[]
            for (i,fraction) in fractions.enumerated() {
                if i%64==0 && isCancelled() {throw CancellationError()}
                guard anchors.count<limits.maximumAnchors else {throw SewingError.budgetExceeded("有限缝合点过多。")}
                let a=try location(aPath,arcFraction:hint.aDirection == .forward ? fraction : 1-fraction)
                let b=try location(bPath,arcFraction:hint.bDirection == .forward ? fraction : 1-fraction)
                allAnchorVertices.formUnion(a.attachment.vertexIDs);allAnchorVertices.formUnion(b.attachment.vertexIDs)
                let constraintIndex:Int?
                if a.attachment==b.attachment {constraintIndex=nil;sharedCorners += 1}
                else {
                    let key=AttachmentPair(a.attachment,b.attachment)
                    if let existing=constraintLookup[key] {constraintIndex=existing;deduplicated += 1}
                    else {
                        guard constraints.count<limits.maximumConstraints else {throw SewingError.budgetExceeded("缝合约束过多。")}
                        let delta=try a.attachment.point(in:positions)-b.attachment.point(in:positions)
                        constraintIndex=constraints.count;constraintLookup[key]=constraints.count
                        constraints.append(try .init(a:a.attachment,b:b.attachment,initialGapMeters:delta.length,initialDirection:delta))
                    }
                    let index=constraintIndex!
                    let origin=Origin(seamID:hint.seamID,stitchIndex:hint.stitchIndex,a:a,b:b,
                        aDirection:hint.aDirection,bDirection:hint.bDirection,intent:hint.intent,rightWrong:hint.rightWrong,
                        reversedRelativeToConstraint:constraints[index].a != a.attachment)
                    // Distinct normalized knots can resolve to exactly the
                    // same source Location at binary64 precision. Keep every
                    // Anchor/interval, but this provenance is a SET of exact
                    // source origins, not a multiplicity/stiffness count.
                    if !constraints[index].origins.contains(origin) {constraints[index].origins.append(origin)}
                }
                let anchor=Anchor(seamID:hint.seamID,stitchIndex:hint.stitchIndex,
                    normalizedSeamFraction:fraction,a:a,b:b,constraintIndex:constraintIndex)
                let anchorIndex=anchors.count;anchors.append(anchor);seamAnchors.append(anchor)
                var pairs=Set<TrianglePair>()
                for x in a.boundarySegments {for y in b.boundarySegments where x.adjacentTriangleID != y.adjacentTriangleID {
                    pairs.insert(.init(a:x.adjacentTriangleID,b:y.adjacentTriangleID))
                }}
                totalPairs += pairs.count
                guard totalPairs<=limits.maximumContactTrianglePairs else {throw SewingError.budgetExceeded("局部接缝邻接信息过多。")}
                neighborhoods.append(.init(anchorIndex:anchorIndex,constraintIndex:constraintIndex,a:a,b:b,
                    rightWrong:hint.rightWrong,adjacentTrianglePairs:pairs.sorted {$0.a == $1.a ? $0.b<$1.b : $0.a<$1.a}))
            }
            if continuousCorrespondence {
                for i in 0..<(seamAnchors.count-1) {
                    if i%64==0 && isCancelled() {throw CancellationError()}
                    let start=seamAnchors[i],end=seamAnchors[i+1]
                    func segment(_ path:BoundaryPath,_ a:Location,_ b:Location)throws->BoundarySegment {
                        let low=min(a.sourceArcFraction,b.sourceArcFraction),high=max(a.sourceArcFraction,b.sourceArcFraction)
                        guard let value=path.segments.first(where:{$0.sourceArcRange.lowerBound<=low+1e-12 && $0.sourceArcRange.upperBound>=high-1e-12}) else {
                            throw SewingError.invalid("普通接缝区间跨过了未保留的边界节点。")
                        }
                        return value
                    }
                    totalPairs += 1
                    guard totalPairs<=limits.maximumContactTrianglePairs else {throw SewingError.budgetExceeded("局部接缝区间信息过多。")}
                    ordinaryContacts.append(.init(seamID:hint.seamID,stitchIndex:hint.stitchIndex,
                        startAnchorIndex:firstAnchorIndex+i,endAnchorIndex:firstAnchorIndex+i+1,
                        normalizedSeamRange:fractions[i]...fractions[i+1],
                        aStart:start.a,aEnd:end.a,bStart:start.b,bEnd:end.b,
                        aSegment:try segment(aPath,start.a,end.a),bSegment:try segment(bPath,start.b,end.b),rightWrong:hint.rightWrong))
                }
            }
            if !continuousCorrespondence,let longer {
                let path=longer == .a ? aPath : bPath
                for i in 0..<intervals {
                    let first=longer == .a ? seamAnchors[i].a : seamAnchors[i].b
                    let last=longer == .a ? seamAnchors[i+1].a : seamAnchors[i+1].b
                    let low=min(first.sourceArcFraction,last.sourceArcFraction),high=max(first.sourceArcFraction,last.sourceArcFraction)
                    let ids=path.vertexIDs.indices.filter {path.sourceArcFractions[$0]>low+1e-12 && path.sourceArcFractions[$0]<high-1e-12}.map {path.vertexIDs[$0]}
                    pendingFolds.append(.init(seamID:hint.seamID,intent:hint.intent,path:path,range:low...high,
                        minimum:hint.minimumFreeBoundaryNodes,candidates:ids,
                        suggestedSpacing:path.sourceLengthMeters*(high-low)/Double(hint.minimumFreeBoundaryNodes+3)))
                }
            }
        }
        var folds:[FoldInterval]=[],refinements:[RefinementRequest]=[]
        for item in pendingFolds {
            if isCancelled() {throw CancellationError()}
            let free=item.candidates.filter {!allAnchorVertices.contains($0)}
            if free.count<item.minimum {
                guard refinements.count<limits.maximumRefinementRequests else {
                    throw SewingError.budgetExceeded("需要细分的接缝区间过多。")
                }
                refinements.append(.init(edge:item.path.edge,edgeID:item.path.edgeID,sourceArcRange:item.range,
                    existingFreeBoundaryNodes:free.count,minimumFreeBoundaryNodes:item.minimum,
                    requiredMaximumBoundarySpacingMeters:item.suggestedSpacing,
                    reason:"较长的吃势／抽褶边在相邻有限缝合点之间没有足够未附着节点。"))
            }
            folds.append(.init(seamID:item.seamID,intent:item.intent,longerEdge:item.path.edge,
                sourceArcRange:item.range,sourceIntervalLengthMeters:item.path.sourceLengthMeters*(item.range.upperBound-item.range.lowerBound),
                untackedBoundaryVertexIDs:free,minimumFreeBoundaryNodes:item.minimum))
        }
        if !refinements.isEmpty {throw SewingError.refinementNeeded(refinements)}
        return .init(sourceSHA256:actualSourceSHA256,constraints:constraints,anchors:anchors,
            allBoundaryPaths:orderedPaths,foldIntervals:folds,contactNeighborhoods:neighborhoods,
            ordinaryBoundaryIntervals:ordinaryContacts,
            deduplicatedCornerConstraints:deduplicated,sharedTopologicalCornerAnchors:sharedCorners,
            usesFiniteCoarseTacks:!folds.isEmpty)
    }
}

// Complete source-boundary metric. No force, rest metric, mass or collision
// mask is changed here. The supplied plan must pass SewnInput's full-source
// validation before its data can authorize an R capability.
extension GarmentCodeSewing {
    nonisolated private struct ClosureInterval {
        let lo:Double,hi:Double
        init(_ x:Double){lo=x;hi=x}
        init(_ lo:Double,_ hi:Double){self.lo=lo;self.hi=hi}
        var finite:Bool {lo.isFinite && hi.isFinite && lo<=hi}
        static func +(a:Self,b:Self)->Self {.init((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp)}
        static func -(a:Self,b:Self)->Self {.init((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp)}
        static func *(a:Self,b:Self)->Self {
            let v=[a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi]
            return .init(v.min()!.nextDown,v.max()!.nextUp)
        }
        static func /(a:Self,b:Self)->Self {
            guard b.lo>0 else{return .init(-.infinity,.infinity)}
            let v=[a.lo/b.lo,a.lo/b.hi,a.hi/b.lo,a.hi/b.hi]
            return .init(v.min()!.nextDown,v.max()!.nextUp)
        }
        var square:Self {
            let m=max(abs(lo),abs(hi)),upper=(m*m).nextUp
            if lo<=0 && hi>=0{return .init(0,upper)}
            let n=min(abs(lo),abs(hi));return .init(max(0,(n*n).nextDown),upper)
        }
    }
    nonisolated private static func closureNearestRounding()->Bool {
        #if os(macOS)
        Darwin.fegetround()==FE_TONEAREST
        #elseif canImport(NativeClothCollision)
        FloatingPointEnvironment.isNearestRounding
        #else
        false
        #endif
    }
    /// Evaluates all actual source knots of BOTH oriented piecewise-linear
    /// boundaries. On each union-knot interval their difference is affine;
    /// convexity of its norm makes the endpoint upper bounds sufficient for
    /// the ENTIRE interval. This is not sampling the tacks or a fixed grid.
    nonisolated static func inspect(positions:[Vector3],plan:Plan,rampFraction:Double=1,
        limits:InspectionLimits=InspectionLimits(),isCancelled:@Sendable()->Bool={false})throws->Quality {
        func check()throws {
            guard closureNearestRounding() else{throw SewingError.precisionUnresolved}
            if isCancelled(){throw CancellationError()}
            guard closureNearestRounding() else{throw SewingError.precisionUnresolved}
        }
        try check()
        guard validHash(plan.sourceSHA256) else {throw SewingError.invalid("整边计划缺少规范化源 SHA。")}
        guard (1...4096).contains(limits.maximumSeams),(2...100_000).contains(limits.maximumBoundaryKnots),
              (2...100_000).contains(limits.maximumEvaluatedSourceKnots),
              (2...400_000).contains(limits.maximumSegmentEnclosures),
              (1...256*1024*1024).contains(limits.maximumEstimatedWorkingBytes),
              plan.allBoundaryPaths.count<=limits.maximumSeams*2,plan.anchors.count<=8192,
              plan.constraints.count<=20_000 else {throw SewingError.budgetExceeded("整边检查来源或工作预算无效。")}
        try validatePositions(positions);try validateRamp(rampFraction)
        // Same anchor arithmetic/order as legacy inspect, but every callback
        // here is latched before/after RNE rather than permitting a callback
        // to contaminate arithmetic and restore the mode on a later call.
        var maximum=0.0,squared=0.0,maxResidual=0.0,squaredResidual=0.0
        for (i,c) in plan.constraints.enumerated() {
            if i%64==0 {try check()}
            let gap=(try c.a.point(in:positions)-c.b.point(in:positions)).length
            let residual=abs(gap-c.initialGapMeters*(1-rampFraction))
            maximum=max(maximum,gap);squared+=gap*gap
            maxResidual=max(maxResidual,residual);squaredResidual+=residual*residual
        }
        let count=Double(max(1,plan.constraints.count))
        var q=Quality(anchorConstraintCount:plan.constraints.count,maximumGapMeters:maximum,rmsGapMeters:sqrt(squared/count),
            maximumTargetResidualMeters:maxResidual,rmsTargetResidualMeters:sqrt(squaredResidual/count),rampFraction:rampFraction,measuresOnlyAnchorGaps:true)
        try check()
        var sampleCount=0
        for (i,path) in plan.allBoundaryPaths.enumerated() {
            if i%32==0 {try check()}
            guard path.vertexIDs.count<=limits.maximumBoundaryKnots-sampleCount else {throw SewingError.budgetExceeded("整边源节点过多。")}
            sampleCount += path.vertexIDs.count
        }
        let estimated=sampleCount*128+plan.anchors.count*128+4096
        guard estimated<=limits.maximumEstimatedWorkingBytes else{throw SewingError.budgetExceeded("整边检查空间不足。")}
        var paths:[EdgeKey:BoundaryPath]=[:]
        for (i,path) in plan.allBoundaryPaths.enumerated() {
            if i%32==0 {try check()}
            guard paths[path.edge]==nil,path.sourceArcFractions.count==path.vertexIDs.count,path.vertexIDs.count>=2,
                  path.sourceArcFractions.first==0,path.sourceArcFractions.last==1,
                  path.vertexIDs.allSatisfy({positions.indices.contains($0)}),
                  path.sourceArcFractions.allSatisfy({$0.isFinite && (0...1).contains($0)}),
                  zip(path.sourceArcFractions,path.sourceArcFractions.dropFirst()).allSatisfy({$0<$1}) else {
                throw SewingError.invalid("完整接缝检查需要唯一、完整且严格单调的实际源边。")
            }
            paths[path.edge]=path
        }
        let grouped=Dictionary(grouping:plan.anchors,by:\.stitchIndex)
        guard grouped.count<=limits.maximumSeams else{throw SewingError.budgetExceeded("整边接缝数量过多。")}
        var records:[ContinuousSeamQuality]=[],excluded=0,totalKnots=0,segmentEnclosures=0
        for index in grouped.keys.sorted() {
            try check()
            let anchors=grouped[index]!.sorted{$0.normalizedSeamFraction<$1.normalizedSeamFraction}
            guard let first=anchors.first,let last=anchors.last,anchors.count>=2,first.normalizedSeamFraction==0,last.normalizedSeamFraction==1,
                  anchors.allSatisfy({$0.seamID==first.seamID}),
                  let a=paths[first.a.edge],let b=paths[first.b.edge],
                  (first.a.sourceArcFraction==0 || first.a.sourceArcFraction==1),
                  (first.b.sourceArcFraction==0 || first.b.sourceArcFraction==1) else{throw SewingError.invalid("整边接缝来源不完整。")}
            let origins=anchors.compactMap{anchor in anchor.constraintIndex.flatMap {c in
                plan.constraints.indices.contains(c) ? plan.constraints[c].origins.first{$0.stitchIndex==index && $0.a==anchor.a && $0.b==anchor.b}:nil
            }}
            guard let intent=origins.first?.intent,origins.allSatisfy({$0.intent==intent && $0.seamID==first.seamID}) else{
                throw SewingError.invalid("整边检查缺少明确的源接缝意图。")
            }
            if case .gathered=intent {excluded+=1;continue}
            // Never round 1-f into a new singleton curve knot. Visit every
            // original vertex of BOTH source paths. At its exact knot its own
            // position is known; the other raw source parameter is f or the
            // outward enclosure of the REAL complement 1-f. This covering
            // set includes the entire true union, with duplicates honestly
            // counted. No uncertain sorting or fixed-density samples.
            let knotCount=a.vertexIDs.count+b.vertexIDs.count
            guard knotCount<=limits.maximumEvaluatedSourceKnots-totalKnots else{
                throw SewingError.budgetExceeded("完整真实源节点超过检查预算。")
            }
            totalKnots += knotCount
            let sameDirection=(first.a.sourceArcFraction==0)==(first.b.sourceArcFraction==0)
            func image(_ path:BoundaryPath,_ parameter:ClosureInterval)throws->[ClosureInterval] {
                guard parameter.finite else{throw SewingError.precisionUnresolved}
                let f=ClosureInterval(max(0,parameter.lo),min(1,parameter.hi))
                guard f.finite else{throw SewingError.precisionUnresolved}
                // Find the first original segment that can contain f.lo.
                var low=0,high=path.sourceArcFractions.count-1
                while high-low>1 {let mid=(low+high)/2;if path.sourceArcFractions[mid]<f.lo {low=mid}else{high=mid}}
                var result:[ClosureInterval]?,i=low
                while i+1<path.vertexIDs.count && path.sourceArcFractions[i]<=f.hi {
                    if segmentEnclosures%64==0 {try check()}
                    guard segmentEnclosures<limits.maximumSegmentEnclosures else{throw SewingError.budgetExceeded("反向参数包络的实际源段超过检查预算。")}
                    segmentEnclosures+=1
                    let fa=path.sourceArcFractions[i],fb=path.sourceArcFractions[i+1]
                    let lo=max(f.lo,fa),hi=min(f.hi,fb)
                    if lo<=hi {
                        let p=positions[path.vertexIDs[i]],r=positions[path.vertexIDs[i+1]],value:[ClosureInterval]
                        if lo==hi && lo==fa {value=[.init(p.x),.init(p.y),.init(p.z)]}
                        else if lo==hi && lo==fb {value=[.init(r.x),.init(r.y),.init(r.z)]}
                        else {
                            let raw=(ClosureInterval(lo,hi)-ClosureInterval(fa))/(ClosureInterval(fb)-ClosureInterval(fa))
                            guard raw.finite else{throw SewingError.precisionUnresolved}
                            // We intersect with THIS source interval, so its
                            // mathematical barycentric fraction is in[0,1].
                            let w=ClosureInterval(max(0,raw.lo),min(1,raw.hi))
                            guard w.finite else{throw SewingError.precisionUnresolved}
                            value=zip([p.x,p.y,p.z],[r.x,r.y,r.z]).map{ClosureInterval($0)+(ClosureInterval($1)-ClosureInterval($0))*w}
                        }
                        guard value.allSatisfy(\.finite) else{throw SewingError.precisionUnresolved}
                        if let prior=result {result=zip(prior,value).map{ClosureInterval(min($0.lo,$1.lo),max($0.hi,$1.hi))}}
                        else{result=value}
                    }
                    i+=1
                }
                guard let result else{throw SewingError.precisionUnresolved}
                return result
            }
            var maximum=0.0,evaluated=0
            for (own,other) in [(a,b),(b,a)] {
                for (i,f) in own.sourceArcFractions.enumerated() {
                    if evaluated%32==0 {try check()};evaluated+=1
                    let point=positions[own.vertexIDs[i]],ownValue:[ClosureInterval]=[.init(point.x),.init(point.y),.init(point.z)]
                    let parameter=sameDirection ? ClosureInterval(f):ClosureInterval(1)-ClosureInterval(f)
                    // A complement enclosure can straddle a true other-side
                    // knot. Bound EVERY overlapped source segment's image;
                    // inability/budget is non-success, never skip a segment.
                    let paired=try image(other,parameter)
                    let d=zip(ownValue,paired).map{$0-$1},squared=d.reduce(ClosureInterval(0)){$0+$1.square}
                    guard squared.finite,squared.hi>=0 else{throw SewingError.precisionUnresolved}
                    let upper=sqrt(squared.hi).nextUp
                    guard upper.isFinite else{throw SewingError.precisionUnresolved}
                    maximum=max(maximum,upper)
                }
            }
            records.append(.init(seamID:first.seamID,stitchIndex:index,evaluatedSourceKnots:evaluated,maximumGapUpperBoundMeters:maximum))
        }
        try check()
        q.continuousBoundary = .init(sourceSHA256:plan.sourceSHA256,declaredSeams:grouped.count,
            measuredContinuousSeams:records.count,gatheredSeamsUnproven:excluded,evaluatedSourceKnots:totalKnots,evaluatedSegmentEnclosures:segmentEnclosures,
            completedAllContinuousSeams:true,maximumGapUpperBoundMeters:records.map(\.maximumGapUpperBoundMeters).max(),seams:records)
        try check()
        return q
    }
}
