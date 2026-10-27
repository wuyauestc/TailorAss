import Foundation

/// Contact for the real affine sewing points between source mesh vertices.
/// Vertex contact alone cannot keep a coarse boundary chord outside a curved
/// body shell. These constraints preserve the original independent masses and
/// source geometry; the caller supplies that same body's point projector.
nonisolated enum GarmentCodeSewnBodyContact {
    typealias Vector3=GarmentCodeCircleDrape.Vector3
    typealias Sewing=GarmentCodeSewing

    enum ContactError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded(String)
        var errorDescription:String? {
            switch self {
            case let .invalid(reason):return "缝合点人体接触无效：\(reason)"
            case let .budgetExceeded(reason):return "缝合点人体接触超出预算：\(reason)"
            }
        }
    }
    struct Statistics:Codable,Sendable {
        var examinedAttachments=0
        var projectedAttachments=0
        var cappedAttachments=0
        var unresolvedPinnedAttachments=0
        var unresolvedConditionedAttachments=0
        var unresolvedFinalAttachments=0
        var maximumRequestedPointCorrectionMeters=0.0
        var maximumAppliedPointCorrectionMeters=0.0
        var maximumSingleVertexCorrectionMeters=0.0
        var maximumFinalResidualMeters=0.0
        var rmsFinalResidualMeters=0.0
        /// Other virtual contacts may reopen an earlier contact. The final
        /// residual is recomputed after the entire pass, never assumed zero.
        var measuresOnlyVirtualAttachments=true
    }
    private struct Entry:Sendable {
        let attachment:Sewing.Attachment
        let factors:[Double]
        let effectiveInverseMass:Double
        let allPinned:Bool
    }
    struct Prepared:Sendable {
        let vertexCount:Int
        let providedAttachmentCount:Int
        let uniqueVirtualAttachmentCount:Int
        let skippedUniqueVertexAttachmentCount:Int
        let maximumPositionMagnitudeMeters:Double
        private let entries:[Entry]

        init(vertexCount:Int,attachments:[Sewing.Attachment],normalizedInverseMass:[Double],
             maximumAttachments:Int=40_000,maximumPositionMagnitudeMeters:Double=5,
             isCancelled:@Sendable()->Bool={false}) throws {
            if isCancelled(){throw CancellationError()}
            guard (1...200_000).contains(vertexCount),
                  (1...200_000).contains(maximumAttachments),
                  maximumPositionMagnitudeMeters.isFinite,(0.01...100).contains(maximumPositionMagnitudeMeters),
                  normalizedInverseMass.count==vertexCount,
                  normalizedInverseMass.allSatisfy({$0.isFinite && (0...1e12).contains($0)}) else {
                throw ContactError.invalid("顶点数量、源逆质量或坐标范围无效。")
            }
            guard attachments.count<=maximumAttachments else {throw ContactError.budgetExceeded("实际缝合附着点过多。")}
            var seen=Set<Sewing.Attachment>(),prepared:[Entry]=[],vertices=0
            for (index,attachment) in attachments.enumerated() {
                if index%64==0 && isCancelled(){throw CancellationError()}
                guard (1...2).contains(attachment.vertexIDs.count),
                      attachment.vertexIDs.count==attachment.weights.count,
                      Set(attachment.vertexIDs).count==attachment.vertexIDs.count,
                      attachment.vertexIDs.allSatisfy({(0..<vertexCount).contains($0)}),
                      attachment.weights.allSatisfy({$0.isFinite && $0>0 && $0<=1}),
                      abs(attachment.weights.reduce(0,+)-1)<=1e-12 else {
                    throw ContactError.invalid("缝合附着点引用或系数无效。")
                }
                if !seen.insert(attachment).inserted{continue}
                if attachment.vertexIDs.count==1 {vertices += 1;continue}
                let denominator=zip(attachment.vertexIDs,attachment.weights).reduce(0.0) {$0+normalizedInverseMass[$1.0]*$1.1*$1.1}
                guard denominator.isFinite else {throw ContactError.invalid("缝合点有效逆质量换算溢出。")}
                let pinned=attachment.vertexIDs.allSatisfy{normalizedInverseMass[$0]==0}
                let factors=zip(attachment.vertexIDs,attachment.weights).map {id,coefficient in
                    denominator>1e-24 ? normalizedInverseMass[id]*coefficient/denominator : 0
                }
                guard factors.allSatisfy({$0.isFinite && $0>=0}) else {throw ContactError.invalid("缝合点位移权重无效。")}
                prepared.append(.init(attachment:attachment,factors:factors,effectiveInverseMass:denominator,allPinned:pinned))
            }
            self.vertexCount=vertexCount;self.providedAttachmentCount=attachments.count
            self.uniqueVirtualAttachmentCount=prepared.count;self.skippedUniqueVertexAttachmentCount=vertices
            self.maximumPositionMagnitudeMeters=maximumPositionMagnitudeMeters;self.entries=prepared
        }

        init(vertexCount:Int,constraints:[Sewing.Constraint],normalizedInverseMass:[Double],
             maximumAttachments:Int=40_000,maximumPositionMagnitudeMeters:Double=5,
             isCancelled:@Sendable()->Bool={false}) throws {
            if isCancelled(){throw CancellationError()}
            guard constraints.count<=maximumAttachments/2 else {throw ContactError.budgetExceeded("实际缝合约束过多。")}
            try self.init(vertexCount:vertexCount,attachments:constraints.flatMap{[$0.a,$0.b]},
                normalizedInverseMass:normalizedInverseMass,maximumAttachments:maximumAttachments,
                maximumPositionMagnitudeMeters:maximumPositionMagnitudeMeters,isCancelled:isCancelled)
        }

        /// A pass is transactional on cancellation or invalid point-projector
        /// output. Per-contact common scaling keeps the inverse-mass ratios;
        /// shared vertices may receive several bounded corrections in one pass.
        func project(positions:inout[Vector3],projectPoint:@Sendable(Vector3)->Vector3,
                     maximumSingleVertexCorrectionMeters:Double=0.02,
                     residualToleranceMeters:Double=1e-8,
                     isCancelled:@Sendable()->Bool={false}) throws -> Statistics {
            if isCancelled(){throw CancellationError()}
            guard positions.count==vertexCount,valid(positions),
                  maximumSingleVertexCorrectionMeters.isFinite,(1e-8...0.1).contains(maximumSingleVertexCorrectionMeters),
                  residualToleranceMeters.isFinite,(0...0.001).contains(residualToleranceMeters) else {
                throw ContactError.invalid("缝合点接触坐标、修正上限或残余容差无效。")
            }
            var candidate=positions,stats=Statistics()
            for (index,entry) in entries.enumerated() {
                if index%32==0 && isCancelled(){throw CancellationError()}
                let point=affine(entry.attachment,candidate),target=projectPoint(point),delta=target-point
                guard valid(target),delta.isFinite else {throw ContactError.invalid("同源人体投影返回了无效坐标。")}
                let distance=delta.length
                stats.examinedAttachments += 1;stats.maximumRequestedPointCorrectionMeters=max(stats.maximumRequestedPointCorrectionMeters,distance)
                if distance<=residualToleranceMeters{continue}
                if entry.effectiveInverseMass<=1e-24 {
                    if entry.allPinned{stats.unresolvedPinnedAttachments += 1}else{stats.unresolvedConditionedAttachments += 1}
                    continue
                }
                let maximumFactor=entry.factors.max() ?? 0
                let proposed=distance*maximumFactor
                guard proposed.isFinite,proposed>0 else {throw ContactError.invalid("缝合点接触修正无法可靠分配。")}
                let scale=min(1,maximumSingleVertexCorrectionMeters/proposed)
                if scale<1-1e-12{stats.cappedAttachments += 1}
                for (id,factor) in zip(entry.attachment.vertexIDs,entry.factors) {
                    if factor==0 {continue}
                    let correction=delta*(factor*scale)
                    candidate[id]=candidate[id]+correction
                    guard valid(candidate[id]) else {throw ContactError.invalid("缝合点接触修正超出有效坐标范围。")}
                    stats.maximumSingleVertexCorrectionMeters=max(stats.maximumSingleVertexCorrectionMeters,correction.length)
                }
                let applied=(affine(entry.attachment,candidate)-point).length
                stats.maximumAppliedPointCorrectionMeters=max(stats.maximumAppliedPointCorrectionMeters,applied)
                stats.projectedAttachments += 1
            }
            var residualSquares=0.0
            for (index,entry) in entries.enumerated() {
                if index%32==0 && isCancelled(){throw CancellationError()}
                let point=affine(entry.attachment,candidate),target=projectPoint(point)
                guard valid(target) else {throw ContactError.invalid("接触残余检查得到无效人体投影。")}
                let residual=(target-point).length
                guard residual.isFinite else {throw ContactError.invalid("接触残余不是有限值。")}
                stats.maximumFinalResidualMeters=max(stats.maximumFinalResidualMeters,residual)
                residualSquares += residual*residual
                if residual>residualToleranceMeters {stats.unresolvedFinalAttachments += 1}
            }
            stats.rmsFinalResidualMeters=sqrt(residualSquares/Double(max(1,entries.count)))
            if isCancelled(){throw CancellationError()}
            positions=candidate
            return stats
        }

        private func valid(_ point:Vector3)->Bool {point.isFinite && point.length<=maximumPositionMagnitudeMeters}
        private func valid(_ points:[Vector3])->Bool {points.allSatisfy{valid($0)}}
        private func affine(_ attachment:Sewing.Attachment,_ positions:[Vector3])->Vector3 {
            zip(attachment.vertexIDs,attachment.weights).reduce(.zero){$0+positions[$1.0]*$1.1}
        }
    }
}
