import Foundation

/// Simultaneous Cartesian XPBD for the existing final point-coincidence rows.
/// It neither welds particles nor changes source edges, masses or pinned DOFs.
/// Callers explicitly opt in only after the original sewing ramp reaches one.
nonisolated enum GarmentCodeSewnPointBlock {
    typealias Vector3=GarmentCodeCircleDrape.Vector3
    typealias Sewing=GarmentCodeSewing

    struct Limits: Sendable {
        var maximumVertices=20_000
        var maximumConstraints=4_096
        var maximumAttachmentTerms=16_384
        var maximumDenseBlockRows=96
        var maximumDenseEntries=262_144
        var maximumDenseFactorOperations=8_000_000
        var maximumCGIterationsPerBlock=256
        var absoluteLinearResidualToleranceMeters=1e-12
        var relativeLinearResidualTolerance=1e-10
        var maximumPositionMagnitudeMeters=100.0
    }
    enum BlockError: LocalizedError, Sendable {
        case invalid(String),budgetExceeded(String)
        var errorDescription:String? {
            switch self {
            case let .invalid(reason):return "点缝合联立投影无效：\(reason)"
            case let .budgetExceeded(reason):return "点缝合联立投影超出预算：\(reason)"
            }
        }
    }
    fileprivate struct Row: Sendable {
        let ids:[Int],coefficients:[Double]
    }
    fileprivate struct Incident: Sendable {
        let row:Int,coefficient:Double
    }
    fileprivate struct Column: Sendable {
        let vertexID:Int
        let entries:[Incident]
    }
    fileprivate struct Block: Sendable {
        let rowIDs:[Int]
        let columns:[Column]
        let diagonal:[Double]
        let lower:[Double]?
        let denseRankFallback:Bool
    }
    struct FrameState: Sendable {
        fileprivate let preparedID:UUID
        /// A fresh state is required every frame. Repeated projections within
        /// that frame retain the three signed Cartesian multipliers per row.
        fileprivate var lambda:[Vector3]
        var cartesianLambda:[Vector3] {lambda}
    }
    struct BlockStatistics: Codable, Sendable {
        let constraintIndices:[Int]
        let solver:String
        let denseRankFallback:Bool
        let linearSystemConverged:Bool
        let iterations:Int
        let linearResidualNormMeters:Double
        let linearToleranceMeters:Double
        let failureReason:String?
        let appliedScale:Double
        let maximumUncappedCorrectionMeters:Double
        let maximumAppliedCorrectionMeters:Double
    }
    struct Statistics: Codable, Sendable {
        let blockCount:Int
        let denseBlockCount:Int
        let matrixFreeBlockCount:Int
        let allLinearSystemsConverged:Bool
        let unconvergedConstraintIndices:[Int]
        /// Kinematic rows can remain separated even when a compliant linear
        /// multiplier equation is solved. Their actual gaps are never hidden.
        let unresolvedPinnedConstraintIndices:[Int]
        let maximumActualGapMeters:Double
        let maximumAppliedCorrectionMeters:Double
        let maximumFrameTravelMeters:Double
        let blocks:[BlockStatistics]
    }

    struct Prepared: Sendable {
        let vertexCount:Int
        let constraintCount:Int
        let alpha:Double
        let blockCount:Int
        let denseBlockCount:Int
        let matrixFreeBlockCount:Int
        fileprivate let id:UUID
        fileprivate let rows:[Row]
        fileprivate let weights:[Double]
        fileprivate let blocks:[Block]
        fileprivate let limits:Limits

        init(vertexCount:Int,constraints:[Sewing.Constraint],normalizedInverseMass:[Double],
             physicalCompliance:Double,meanParticleMassKg:Double,timeStepSeconds:Double,
             limits:Limits = .init(),isCancelled:@Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            guard (1...200_000).contains(limits.maximumVertices),
                  (1...20_000).contains(limits.maximumConstraints),
                  (1...80_000).contains(limits.maximumAttachmentTerms),
                  (0...256).contains(limits.maximumDenseBlockRows),
                  (0...4_000_000).contains(limits.maximumDenseEntries),
                  (0...100_000_000).contains(limits.maximumDenseFactorOperations),
                  (1...4096).contains(limits.maximumCGIterationsPerBlock),
                  limits.absoluteLinearResidualToleranceMeters.isFinite,
                  (1e-15...1e-4).contains(limits.absoluteLinearResidualToleranceMeters),
                  limits.relativeLinearResidualTolerance.isFinite,
                  (1e-15...1e-4).contains(limits.relativeLinearResidualTolerance),
                  limits.maximumPositionMagnitudeMeters.isFinite,
                  (0.01...1000).contains(limits.maximumPositionMagnitudeMeters),
                  vertexCount>0,normalizedInverseMass.count==vertexCount,
                  normalizedInverseMass.allSatisfy({$0.isFinite && (0...1e12).contains($0)}),
                  !constraints.isEmpty,physicalCompliance.isFinite,(0...1).contains(physicalCompliance),
                  meanParticleMassKg.isFinite,(1e-20...1e8).contains(meanParticleMassKg),
                  timeStepSeconds.isFinite,(1e-6...1).contains(timeStepSeconds) else {
                throw BlockError.invalid("质量、物理顺应度、时间步或求解配置无效。")
            }
            guard vertexCount<=limits.maximumVertices,constraints.count<=limits.maximumConstraints else {
                throw BlockError.budgetExceeded("顶点或真实约束数量过多。")
            }
            let alpha=physicalCompliance*meanParticleMassKg/(timeStepSeconds*timeStepSeconds)
            guard alpha.isFinite,alpha>=0,physicalCompliance==0 || alpha>0 else {
                throw BlockError.invalid("物理顺应度换算溢出或下溢。")
            }
            var rows:[Row]=[],incidence=Array(repeating:[Int](),count:vertexCount),termCount=0
            for (index,constraint) in constraints.enumerated() {
                if index%64==0,isCancelled(){throw CancellationError()}
                guard constraint.finalGapMeters==0,constraint.initialGapMeters.isFinite,
                      constraint.initialGapMeters>=0,constraint.initialDirection.isFinite else {
                    throw BlockError.invalid("此模块只接受最终间距严格为零的原始点重合约束。")
                }
                var combined:[Int:Double]=[:]
                for (attachment,sign) in [(constraint.a,1.0),(constraint.b,-1.0)] {
                    guard (1...2).contains(attachment.vertexIDs.count),
                          attachment.vertexIDs.count==attachment.weights.count,
                          Set(attachment.vertexIDs).count==attachment.vertexIDs.count,
                          attachment.vertexIDs.allSatisfy({(0..<vertexCount).contains($0)}),
                          attachment.weights.allSatisfy({$0.isFinite && $0>0 && $0<=1}),
                          abs(attachment.weights.reduce(0,+)-1)<=1e-12 else {
                        throw BlockError.invalid("原始缝点的顶点引用或仿射权重无效。")
                    }
                    termCount+=attachment.vertexIDs.count
                    guard termCount<=limits.maximumAttachmentTerms else {
                        throw BlockError.budgetExceeded("真实附着系数过多。")
                    }
                    for (vertex,weight) in zip(attachment.vertexIDs,attachment.weights) {
                        combined[vertex,default:0]+=sign*weight
                    }
                }
                let ids=combined.keys.filter{combined[$0] != 0}.sorted()
                rows.append(.init(ids:ids,coefficients:ids.map{combined[$0]!}))
                for vertex in ids where normalizedInverseMass[vertex]>0 {incidence[vertex].append(index)}
            }
            var parent=Array(rows.indices)
            func root(_ value:Int)->Int {var r=value;while parent[r] != r {r=parent[r]};return r}
            for (vertex,incident) in incidence.enumerated() {
                if vertex%128==0,isCancelled(){throw CancellationError()}
                guard let first=incident.first else {continue}
                for next in incident.dropFirst() {
                    let a=root(first),b=root(next)
                    if a != b {parent[max(a,b)]=min(a,b)}
                }
            }
            var grouped:[Int:[Int]]=[:]
            for row in rows.indices {grouped[root(row),default:[]].append(row)}
            var blocks:[Block]=[],denseEntries=0,denseOperations=0
            for key in grouped.keys.sorted() {
                if isCancelled(){throw CancellationError()}
                let indices=grouped[key]!,count=indices.count
                var local:[Int:[Incident]]=[:]
                for (i,global) in indices.enumerated() {
                    for (vertex,coefficient) in zip(rows[global].ids,rows[global].coefficients) where normalizedInverseMass[vertex]>0 {
                        local[vertex,default:[]].append(.init(row:i,coefficient:coefficient))
                    }
                }
                let columns=local.keys.sorted().map{Column(vertexID:$0,entries:local[$0]!)}
                var diagonal=Array(repeating:alpha,count:count)
                for column in columns {for entry in column.entries {
                    diagonal[entry.row]+=normalizedInverseMass[column.vertexID]*entry.coefficient*entry.coefficient
                }}
                guard diagonal.allSatisfy({$0.isFinite && $0>=0}) else {
                    throw BlockError.invalid("原质量矩阵换算超出有限范围。")
                }
                var lower:[Double]?,rankFallback=false
                // Resource exhaustion changes the exact solver algorithm,
                // never the constraints, mass or physical compliance.
                let entries=count*count,operations=count*count*count/6
                if count<=limits.maximumDenseBlockRows,
                   entries<=limits.maximumDenseEntries-denseEntries,
                   operations<=limits.maximumDenseFactorOperations-denseOperations {
                    denseEntries+=entries;denseOperations+=operations
                    var gram=Array(repeating:0.0,count:entries)
                    for column in columns {for a in column.entries {for b in column.entries {
                        gram[a.row*count+b.row]+=normalizedInverseMass[column.vertexID]*a.coefficient*b.coefficient
                    }}}
                    for i in 0..<count {gram[i*count+i]+=alpha}
                    lower=try Self.factor(gram,count:count,isCancelled:isCancelled)
                    rankFallback=lower==nil
                }
                blocks.append(.init(rowIDs:indices,columns:columns,diagonal:diagonal,lower:lower,denseRankFallback:rankFallback))
            }
            if isCancelled(){throw CancellationError()}
            self.vertexCount=vertexCount;constraintCount=constraints.count;self.alpha=alpha
            self.rows=rows;weights=normalizedInverseMass;self.blocks=blocks;self.limits=limits;id=UUID()
            blockCount=blocks.count;denseBlockCount=blocks.filter{$0.lower != nil}.count
            matrixFreeBlockCount=blocks.count-denseBlockCount
        }

        func makeFrameState()->FrameState {
            .init(preparedID:id,lambda:Array(repeating:.zero,count:constraintCount))
        }

        /// A failed Cholesky is a rank/conditioning observation, not permission
        /// to add diagonal regularization. PSD CG handles consistent redundant
        /// hard rows; an unresolved system is reported without applying it.
        private static func factor(_ gram:[Double],count:Int,
            isCancelled:@Sendable()->Bool)throws->[Double]? {
            var lower=Array(repeating:0.0,count:gram.count)
            let scale=(0..<count).map{gram[$0*count+$0]}.max() ?? 0
            let pivotFloor=scale*Double.ulpOfOne*32
            for i in 0..<count {
                if i%16==0,isCancelled(){throw CancellationError()}
                for j in 0...i {
                    var value=gram[i*count+j]
                    for k in 0..<j {value-=lower[i*count+k]*lower[j*count+k]}
                    if i==j {
                        guard value.isFinite,value>pivotFloor else {return nil}
                        lower[i*count+j]=sqrt(value)
                    } else {lower[i*count+j]=value/lower[j*count+j]}
                }
            }
            return lower.allSatisfy(\.isFinite) ? lower:nil
        }
    }

    private struct Solve {
        let change:[Vector3]
        let converged:Bool
        let iterations:Int
        let residual:Double
        let tolerance:Double
        let failure:String?
    }
    private static func scalarProduct(_ a:[Vector3],_ b:[Vector3])->Double {
        zip(a,b).reduce(0.0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}
    }
    private static func norm(_ a:[Vector3])->Double {
        let squared=scalarProduct(a,a)
        return squared.isFinite && squared>=0 ? sqrt(squared):.infinity
    }
    private static func apply(_ x:[Vector3],block:Block,prepared:Prepared)->[Vector3] {
        var result=x.map{$0*prepared.alpha}
        for column in block.columns {
            var value=Vector3.zero
            for entry in column.entries {value=value+x[entry.row]*entry.coefficient}
            value=value*prepared.weights[column.vertexID]
            for entry in column.entries {result[entry.row]=result[entry.row]+value*entry.coefficient}
        }
        return result
    }
    private static func solve(_ rhs:[Vector3],block:Block,prepared:Prepared,
        isCancelled:@Sendable()->Bool)throws->Solve {
        let count=rhs.count,tolerance=prepared.limits.absoluteLinearResidualToleranceMeters +
            prepared.limits.relativeLinearResidualTolerance*norm(rhs)
        func verify(_ change:[Vector3],iterations:Int,failure:String?)->Solve {
            let residual=norm(zip(apply(change,block:block,prepared:prepared),rhs).map{$0-$1})
            let finite=change.allSatisfy(\.isFinite) && residual.isFinite
            return .init(change:change,converged:finite && residual<=tolerance,iterations:iterations,
                residual:residual.isFinite ? residual:Double.greatestFiniteMagnitude,
                tolerance:tolerance,failure:finite && residual<=tolerance ? nil:failure)
        }
        if norm(rhs)<=tolerance {return verify(Array(repeating:.zero,count:count),iterations:0,failure:nil)}
        if let lower=block.lower {
            var change=rhs
            for i in 0..<count {
                if i%16==0,isCancelled(){throw CancellationError()}
                for k in 0..<i {change[i]=change[i]-change[k]*lower[i*count+k]}
                change[i]=change[i]/lower[i*count+i]
            }
            for i in (0..<count).reversed() {
                for k in (i+1)..<count {change[i]=change[i]-change[k]*lower[k*count+i]}
                change[i]=change[i]/lower[i*count+i]
            }
            return verify(change,iterations:1,failure:"denseResidualNotConverged")
        }
        var change=Array(repeating:Vector3.zero,count:count),residual=rhs
        func precondition(_ values:[Vector3])->[Vector3]? {
            var result=values
            for i in 0..<count {
                if block.diagonal[i]>0 {result[i]=result[i]/block.diagonal[i]}
                else if result[i].lengthSquared==0 {result[i] = .zero}
                else {return nil}
            }
            return result.allSatisfy(\.isFinite) ? result:nil
        }
        guard var z=precondition(residual) else {
            return verify(change,iterations:0,failure:"zeroMassUnresolvedRow")
        }
        var direction=z,rho=scalarProduct(residual,z)
        for iteration in 0..<prepared.limits.maximumCGIterationsPerBlock {
            if iteration%8==0,isCancelled(){throw CancellationError()}
            let product=apply(direction,block:block,prepared:prepared),denominator=scalarProduct(direction,product)
            guard denominator.isFinite,denominator>0,rho.isFinite,rho>0 else {
                return verify(change,iterations:iteration,failure:"rankOrConditioningBreakdown")
            }
            let step=rho/denominator
            guard step.isFinite else {return verify(change,iterations:iteration,failure:"nonfiniteCGStep")}
            for i in 0..<count {change[i]=change[i]+direction[i]*step;residual[i]=residual[i]-product[i]*step}
            if norm(residual)<=tolerance {return verify(change,iterations:iteration+1,failure:"recursiveResidualNotConverged")}
            guard let next=precondition(residual) else {
                return verify(change,iterations:iteration+1,failure:"zeroMassUnresolvedRow")
            }
            z=next
            let nextRho=scalarProduct(residual,z),beta=nextRho/rho
            guard nextRho.isFinite,beta.isFinite else {
                return verify(change,iterations:iteration+1,failure:"nonfiniteCGDirection")
            }
            for i in 0..<count {direction[i]=z[i]+direction[i]*beta}
            rho=nextRho
        }
        return verify(change,iterations:prepared.limits.maximumCGIterationsPerBlock,failure:"cgIterationBudgetExceeded")
    }

    /// Positions, lambda and frame travel publish together after all checks.
    /// A CG failure leaves that block unchanged and explicitly unresolved;
    /// independent blocks still receive their own full correction budget.
    static func project(positions:inout[Vector3],prepared:Prepared,state:inout FrameState,
        frameTravelMeters:inout[Double],rampFraction:Double=1,
        maximumFrameTravelMeters:Double=0.5,maximumSingleProjectionMeters:Double=0.02,
        isCancelled:@Sendable()->Bool={false})throws->Statistics {
        if isCancelled(){throw CancellationError()}
        guard rampFraction==1,state.preparedID==prepared.id,
              positions.count==prepared.vertexCount,state.lambda.count==prepared.constraintCount,
              frameTravelMeters.count==prepared.vertexCount,
              maximumFrameTravelMeters.isFinite,(1e-9...10).contains(maximumFrameTravelMeters),
              maximumSingleProjectionMeters.isFinite,(1e-9...10).contains(maximumSingleProjectionMeters),
              positions.allSatisfy({$0.isFinite && max(abs($0.x),abs($0.y),abs($0.z))<=prepared.limits.maximumPositionMagnitudeMeters}),
              state.lambda.allSatisfy(\.isFinite),
              frameTravelMeters.allSatisfy({$0.isFinite && $0>=0 && $0<=maximumFrameTravelMeters+1e-12}) else {
            throw BlockError.invalid("仅允许最终收缝阶段，且坐标、帧状态、路径预算必须有效并属于同一准备结果。")
        }
        var nextPositions=positions,nextState=state,nextTravel=frameTravelMeters
        var reports:[BlockStatistics]=[],unconverged:[Int]=[],maximumApplied=0.0
        for block in prepared.blocks {
            if isCancelled(){throw CancellationError()}
            let rhs=block.rowIDs.map {index -> Vector3 in
                let row=prepared.rows[index]
                let c=zip(row.ids,row.coefficients).reduce(Vector3.zero){$0+nextPositions[$1.0]*$1.1}
                return (c+nextState.lambda[index]*prepared.alpha)*(-1)
            }
            guard rhs.allSatisfy(\.isFinite),norm(rhs).isFinite else {
                throw BlockError.invalid("点约束或累积乘子超出有限范围。")
            }
            let solution=try solve(rhs,block:block,prepared:prepared,isCancelled:isCancelled)
            var scale=0.0,maximumUncapped=0.0,blockMaximumApplied=0.0
            if solution.converged {
                var corrections:[Vector3]=[]
                for column in block.columns {
                    let correction=column.entries.reduce(Vector3.zero){$0+solution.change[$1.row]*$1.coefficient}*prepared.weights[column.vertexID]
                    corrections.append(correction)
                }
                guard corrections.allSatisfy(\.isFinite) else {throw BlockError.invalid("原质量加权投影产生非有限修正。")}
                scale=1
                for (column,correction) in zip(block.columns,corrections) {
                    let length=correction.length
                    maximumUncapped=max(maximumUncapped,length)
                    if length>0 {
                        scale=min(scale,maximumSingleProjectionMeters/length,
                            max(0,maximumFrameTravelMeters-nextTravel[column.vertexID])/length)
                    }
                }
                scale=max(0,min(1,scale))
                for (index,change) in zip(block.rowIDs,solution.change) {
                    nextState.lambda[index]=nextState.lambda[index]+change*scale
                }
                for (column,correction) in zip(block.columns,corrections) {
                    let applied=correction*scale,length=applied.length
                    nextPositions[column.vertexID]=nextPositions[column.vertexID]+applied
                    nextTravel[column.vertexID]+=length
                    blockMaximumApplied=max(blockMaximumApplied,length)
                }
                maximumApplied=max(maximumApplied,blockMaximumApplied)
            } else {unconverged+=block.rowIDs}
            reports.append(.init(constraintIndices:block.rowIDs,solver:block.lower==nil ? "matrixFreeDiagonalPCG":"cachedCholesky",
                denseRankFallback:block.denseRankFallback,linearSystemConverged:solution.converged,
                iterations:solution.iterations,linearResidualNormMeters:solution.residual,linearToleranceMeters:solution.tolerance,
                failureReason:solution.failure,appliedScale:scale,maximumUncappedCorrectionMeters:maximumUncapped,
                maximumAppliedCorrectionMeters:blockMaximumApplied))
        }
        var maximumGap=0.0,pinned:[Int]=[]
        for (i,row) in prepared.rows.enumerated() {
            if i%128==0,isCancelled(){throw CancellationError()}
            let gap=zip(row.ids,row.coefficients).reduce(Vector3.zero){$0+nextPositions[$1.0]*$1.1}.length
            guard gap.isFinite else {throw BlockError.invalid("最终实际点间距超出有限范围。")}
            maximumGap=max(maximumGap,gap)
            if gap>prepared.limits.absoluteLinearResidualToleranceMeters && row.ids.allSatisfy({prepared.weights[$0]==0}) {pinned.append(i)}
        }
        guard nextPositions.allSatisfy(\.isFinite),nextState.lambda.allSatisfy(\.isFinite),
              nextTravel.allSatisfy({$0.isFinite && $0<=maximumFrameTravelMeters+1e-12}) else {
            throw BlockError.invalid("联立投影结果或路径预算无效。")
        }
        if isCancelled(){throw CancellationError()}
        positions=nextPositions;state=nextState;frameTravelMeters=nextTravel
        return .init(blockCount:prepared.blockCount,denseBlockCount:prepared.denseBlockCount,
            matrixFreeBlockCount:prepared.matrixFreeBlockCount,allLinearSystemsConverged:unconverged.isEmpty,
            unconvergedConstraintIndices:unconverged.sorted(),unresolvedPinnedConstraintIndices:pinned,
            maximumActualGapMeters:maximumGap,maximumAppliedCorrectionMeters:maximumApplied,
            maximumFrameTravelMeters:nextTravel.max() ?? 0,blocks:reports)
    }
}
