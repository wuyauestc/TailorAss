import Foundation
import NativeClothCollision

/// A final acceptance boundary, not another cloth solver. The only constructor
/// of Validated is below the fresh same-worker checks. No diagnostic State or
/// Report can be decoded into this capability, and validation never moves cloth.
nonisolated enum GarmentCodeJointResult {
    typealias S=GarmentCodeJointSimulation
    typealias K=S.K
    typealias V=S.V
    typealias C=GarmentCodeClothContact
    typealias B=GarmentCodeBodySurfaceContact
    typealias I=GarmentCodeVisibleBodyInspection
    typealias P=GarmentCodeJointPreconditioner
    typealias CP=GarmentCodeJointContactPreconditioner
    typealias Sewing=GarmentCodeSewing

    struct Limits:Sendable {
        var visibleBody=I.Limits()
        var maximumSurfaceCandidatePairs=200_000
    }
    enum ValidationError:LocalizedError,Sendable {
        case invalidSource(String),foreignPrepared,missingAcceptedFrame,insufficientQuietFrames
        case inconsistentRecord(String),gate(String,step:Int?),invalidBudget,invalidTiming
        var errorDescription:String? {
            switch self {
            case let .invalidSource(s):return "整衣结果来源不完整："+s
            case .foreignPrepared:return "整衣结果与本次求解的源网格实例不一致。"
            case .missingAcceptedFrame:return "尚无真实接受的整衣状态。"
            case .insufficientQuietFrames:return "尚未取得连续 24 帧全重力、全缝合稳定记录。"
            case let .inconsistentRecord(s):return "整衣接受记录不一致："+s
            case let .gate(s,step):return "整衣最终验收未通过："+s+(step.map{"（第 \($0) 帧）"} ?? "")
            case .invalidBudget:return "整衣最终验收工作预算无效。"
            case .invalidTiming:return "需要全部真实已接受步骤的有限非负计算耗时。"
            }
        }
    }
    struct PanelMetrics:Codable,Sendable {
        let panelID:String
        let vertices:Int,triangles:Int
        let sourceAreaSquareMeters:Double,massKg:Double
    }
    struct Metrics:Codable,Sendable {
        let panels:[PanelMetrics]
        let sourceAreaSquareMeters:Double,totalFabricMassKg:Double
        let vertices:Int,triangles:Int,sourceEdges:Int,sourceStitches:Int,sewingConstraints:Int
        let completedSteps:Int,assemblyIterations:Int,verifiedQuietFrames:Int
        /// Static assembly is a configuration homotopy, not elapsed physics.
        let dynamicSimulatedSeconds:Double
        /// Compatibility name; exactly the dynamic seconds above.
        let simulatedSeconds:Double
        let maximumSourceEdgeRelativeChange:Double,meanSourceEdgeRelativeChange:Double
        let maximumActualSeamGapMeters:Double,rmsActualSeamGapMeters:Double
        let maximumSpeedMetersPerSecond:Double
        let maximumFreshGradientInfinityNewton:Double,maximumFreshPCorrectionInfinityMeters:Double
        let maximumFreshPzRelativeResidual:Double
        let acceptedStepComputationSeconds:Double,validationSeconds:Double,totalComputationSeconds:Double
        /// These are measured mesh/source quantities, not a personal-fit proof.
        let personalFitVerified:Bool
    }
    struct MotionProof:Codable,Sendable {
        let status:String,safeTime:Double,minimumSeparationMeters:Double
        let completedAllFeatures:Bool,completedDomainCertificates:Bool?
        let nativeQueries:Int,trianglePairs:Int
        let euclideanCertificateAttempts:Int,euclideanCertifiedFeatures:Int,euclideanCertificateNodes:Int
        /// Absent only in historical proofs predating this diagnostic field.
        let euclideanCertifiedAfterPrecisionLimit:Int?
    }
    /// Data-only kinematic audit input. Passing this helper never mints an
    /// accepted frame, a path certificate or a final result capability.
    struct PhysicalKinematics:Sendable {
        let previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V]
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
    }
    @discardableResult static func checkedPhysicalSubstepKinematics(previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],
        finalPredictor:[V],macroStep:Int,settings:S.Settings,maximumSubdivisionDepth:Int,leaves:[PhysicalKinematics],
        isCancelled:@Sendable()->Bool={false})throws->Int {
        if isCancelled(){throw CancellationError()}
        guard (0...4).contains(maximumSubdivisionDepth),macroStep>settings.staticAssemblySteps,
              !previousPositions.isEmpty,previousVelocities.count==previousPositions.count,
              acceptedPositions.count==previousPositions.count,acceptedVelocities.count==previousPositions.count,
              finalPredictor.count==previousPositions.count else {throw ValidationError.inconsistentRecord("物理叶步数量、阶段或自由度无效。")}
        let ticks=1<<maximumSubdivisionDepth,n=previousPositions.count
        guard !leaves.isEmpty,leaves.count<=ticks else {throw ValidationError.inconsistentRecord("物理叶步超过有界分区。")}
        func finite(_ x:[V])throws {
            guard x.count==n else {throw ValidationError.inconsistentRecord("物理叶步自由度不一致。")}
            for i in x.indices {
                if i%128==0 && isCancelled(){throw CancellationError()}
                guard x[i].isFinite else {throw ValidationError.inconsistentRecord("物理叶步包含非有限值。")}
            }
        }
        try finite(previousPositions);try finite(previousVelocities);try finite(acceptedPositions);try finite(acceptedVelocities);try finite(finalPredictor)
        var position=previousPositions,velocity=previousVelocities,cursor=0,minimumWidth=ticks
        for leaf in leaves {
            if isCancelled(){throw CancellationError()}
            for x in [leaf.previousPositions,leaf.previousVelocities,leaf.acceptedPositions,leaf.acceptedVelocities,leaf.predictor] {try finite(x)}
            guard (0...ticks).contains(leaf.startTick),(0...ticks).contains(leaf.endTick) else {throw ValidationError.inconsistentRecord("物理叶步分数超出宏步。")}
            let width=leaf.endTick-leaf.startTick
            guard leaf.ticksPerMacroStep==ticks,leaf.startTick==cursor,leaf.endTick>cursor,leaf.endTick<=ticks,
                  width>0,width&(width-1)==0,leaf.startTick%width==0,
                  same(position,leaf.previousPositions),same(velocity,leaf.previousVelocities) else {
                throw ValidationError.inconsistentRecord("物理叶步的分数覆盖或逐位位置／速度链不一致。")
            }
            let dt=settings.timeStepSeconds*Double(width)/Double(ticks)
            let gravity=min(1,max(0,(Double(macroStep-settings.staticAssemblySteps-1)+Double(leaf.endTick)/Double(ticks))/Double(settings.gravityRampSteps)))
            let ramp=min(1,Double(macroStep)/Double(settings.staticAssemblySteps))
            guard leaf.timeStepSeconds.isFinite,(1e-5...1).contains(leaf.timeStepSeconds),leaf.timeStepSeconds.bitPattern==dt.bitPattern,
                  leaf.gravityFraction.bitPattern==gravity.bitPattern,leaf.sewingRamp.bitPattern==ramp.bitPattern else {
                throw ValidationError.inconsistentRecord("物理叶步的真实时长或端点载荷不一致。")
            }
            let damping=exp(-settings.velocityDampingPerSecond*dt),a=V(x:0,y:-settings.gravityMetersPerSecondSquared*gravity,z:0)
            let predictor=zip(position,velocity).map{$0+$1*(damping*dt)+a*(dt*dt)}
            let nextVelocity=zip(leaf.acceptedPositions,position).map{($0-$1)/dt}
            guard same(leaf.predictor,predictor),same(leaf.acceptedVelocities,nextVelocity) else {
                throw ValidationError.inconsistentRecord("物理叶步必须使用自己的预测位置和位移／真实时长速度。")
            }
            position=leaf.acceptedPositions;velocity=leaf.acceptedVelocities;cursor=leaf.endTick;minimumWidth=min(minimumWidth,width)
        }
        guard cursor==ticks,same(position,acceptedPositions),same(velocity,acceptedVelocities),
              leaves.last.map({same($0.predictor,finalPredictor)}) == true else {
            throw ValidationError.inconsistentRecord("物理叶步未覆盖完整宏步或未到达真实末态／末速。")
        }
        if isCancelled(){throw CancellationError()}
        // Width is an aligned power of two, so this is an exact integer depth.
        // It is data validation only, not a physical acceptance capability.
        return (ticks/minimumWidth).trailingZeroBitCount
    }
    /// Independent data audit of the complete attempted forest. This proof
    /// describes timing/control provenance; it cannot grant physical safety.
    struct PhysicalSeedForestProof:Codable,Sendable {
        let seedCount:Int,leafCount:Int,attemptCount:Int,actualMaximumDepth:Int
        let leafSeedIndices:[Int],acceptedAttemptIndices:[Int]
    }
    static func checkedPhysicalSeedForest(seeds:[S.PhysicalSeedSpan],leaves:[S.PhysicalSeedSpan],maximumDepth:Int,
        reportedAttempts:Int,ledger:[S.PhysicalAttemptLedger],maximumAttempts:Int=15,isCancelled:@Sendable()->Bool={false})throws->PhysicalSeedForestProof {
        if isCancelled(){throw CancellationError()}
        guard (0...4).contains(maximumDepth),(1...15).contains(maximumAttempts) else {throw ValidationError.inconsistentRecord("时间分区深度或工作预算超出有界范围。")}
        let ticks=1<<maximumDepth
        guard !seeds.isEmpty,!leaves.isEmpty,seeds.count<=leaves.count,leaves.count<=ticks,
              (1...min(maximumAttempts,2*ticks-1)).contains(reportedAttempts),ledger.count==reportedAttempts,
              reportedAttempts==2*leaves.count-seeds.count else {throw ValidationError.inconsistentRecord("完整尝试森林必须满足 2L−K 及原工作预算。")}
        func partition(_ spans:[S.PhysicalSeedSpan])throws {
            var cursor=0
            for span in spans {
                if isCancelled(){throw CancellationError()}
                guard span.ticksPerMacroStep==ticks,(0...ticks).contains(span.startTick),(0...ticks).contains(span.endTick),
                      span.startTick==cursor,span.endTick>span.startTick else {throw ValidationError.inconsistentRecord("时间分区存在缺口、重叠或错误分母。")}
                let width=span.endTick-span.startTick
                guard width&(width-1)==0,span.startTick%width==0 else {throw ValidationError.inconsistentRecord("时间分区没有按二分网格对齐。")}
                cursor=span.endTick
            }
            guard cursor==ticks else {throw ValidationError.inconsistentRecord("时间分区没有覆盖完整宏步。")}
        }
        try partition(seeds);try partition(leaves)
        var nextAttempt=0,nextLeaf=0,owners:[Int]=[],acceptedIndices:[Int]=[],actualDepth=0
        func walk(_ first:Int,_ end:Int,_ seedIndex:Int,_ parent:Int?)throws {
            if isCancelled(){throw CancellationError()}
            guard nextAttempt<ledger.count,nextLeaf<leaves.count else {throw ValidationError.inconsistentRecord("尝试森林缺少真实节点或叶步。")}
            let index=nextAttempt,node=ledger[index],leaf=leaves[nextLeaf]
            nextAttempt+=1
            let isLeaf=leaf.startTick==first && leaf.endTick==end
            guard node.seedIndex==seedIndex,node.parentAttemptIndex==parent,node.startTick==first,node.endTick==end,
                  node.ticksPerMacroStep==ticks,node.accepted==isLeaf,
                  node.computationSeconds.isFinite,node.computationSeconds>=0,
                  (isLeaf ? node.rejectionReason==nil:node.rejectionReason.map{!$0.isEmpty}==true) else {
                throw ValidationError.inconsistentRecord("尝试森林的根、父节点、先序或真实接受／拒绝状态不一致。")
            }
            actualDepth=max(actualDepth,(ticks/(end-first)).trailingZeroBitCount)
            if isLeaf {owners.append(seedIndex);acceptedIndices.append(index);nextLeaf+=1;return}
            guard first<=leaf.startTick,leaf.endTick<=end,end-first>1 else {throw ValidationError.inconsistentRecord("实际叶步越过其来源根或无法由真实失败节点细分。")}
            let middle=(first+end)/2
            try walk(first,middle,seedIndex,index);try walk(middle,end,seedIndex,index)
        }
        for (i,seed) in seeds.enumerated() {try walk(seed.startTick,seed.endTick,i,nil)}
        guard nextLeaf==leaves.count,nextAttempt==ledger.count else {throw ValidationError.inconsistentRecord("尝试森林包含未执行根、伪造节点或遗漏叶步。")}
        if isCancelled(){throw CancellationError()}
        return .init(seedCount:seeds.count,leafCount:leaves.count,attemptCount:ledger.count,actualMaximumDepth:actualDepth,
            leafSeedIndices:owners,acceptedAttemptIndices:acceptedIndices)
    }
    struct PhysicalSubstepProof:Codable,Sendable {
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int,timeStepSeconds:Double
        let sewingRamp:Double,gravityFraction:Double
        let energyJoules:Double,gradientInfinityNewton:Double,preconditionedGradientInfinityMeters:Double,pzRelativeResidual:Double
        let maximumSourceEdgeRelativeChange:Double,meanSourceEdgeRelativeChange:Double
        let maximumSpeedMetersPerSecond:Double,sewing:Sewing.Quality
        let sourceMotion:GarmentCodeMembranePath.Report,bodyMotion:MotionProof,selfMotion:MotionProof
        let bodySurface:B.Quality,selfSurface:C.Quality
        var meetsFreshEquilibrium:Bool {gradientInfinityNewton<1e-6 && preconditionedGradientInfinityMeters<1e-7 && pzRelativeResidual<1e-6}
        var meetsQuietScalarGates:Bool {sewingRamp==1 && gravityFraction==1 && maximumSourceEdgeRelativeChange<0.08 && sewing.hasCompleteBoundaryClosureEvidence && sewing.maximumMeasuredGapMeters<0.0005 && maximumSpeedMetersPerSecond<0.025}
    }
    struct FrameProof:Codable,Sendable {
        let step:Int,sewingRamp:Double,gravityFraction:Double
        let energyJoules:Double,gradientInfinityNewton:Double
        let preconditionedGradientInfinityMeters:Double,pzRelativeResidual:Double
        let maximumSourceEdgeRelativeChange:Double,meanSourceEdgeRelativeChange:Double
        let sewing:Sewing.Quality
        let actualTrajectoryMode:S.N.TrajectoryMode,segmentCount:Int
        let maximumPhysicalSpeedMetersPerSecond:Double?
        /// |configuration delta|/proximal scale only, not physical velocity.
        let maximumConfigurationChangeRateMetersPerSecond:Double?
        /// One aligned triple per ACTUAL line. Static polylines never pretend
        /// their unexecuted outer chord was a certified physical trajectory.
        let sourceMotions:[GarmentCodeMembranePath.Report]
        let bodyMotions:[MotionProof],selfMotions:[MotionProof]
        /// Present in new proofs. Dynamic entries are true timed implicit
        /// solves; static proofs contain an empty list. Nil is historical data.
        let physicalSubsteps:[PhysicalSubstepProof]?
        /// Nil only in historical proofs predating source-bound seed forests.
        let physicalSeedForest:PhysicalSeedForestProof?
        var meetsFreshEquilibrium:Bool {
            gradientInfinityNewton<1e-6 && preconditionedGradientInfinityMeters<1e-7 && pzRelativeResidual<1e-6 &&
            physicalSubsteps.map{$0.allSatisfy(\.meetsFreshEquilibrium)} == true
        }
        var meetsQuietScalarGates:Bool {
            actualTrajectoryMode == .physicalLinearStep && gravityFraction==1 && sewingRamp==1 && maximumSourceEdgeRelativeChange<0.08 &&
            sewing.hasCompleteBoundaryClosureEvidence && sewing.maximumMeasuredGapMeters<0.0005 && maximumPhysicalSpeedMetersPerSecond.map{$0<0.025} == true &&
            physicalSubsteps.map{!$0.isEmpty && $0.allSatisfy(\.meetsQuietScalarGates)} == true && physicalSeedForest != nil
        }
    }
    struct Proof:Codable,Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String,linearizationSourceIdentity:UUID
        let frames:[FrameProof]
        let visibleBody:I.Report
        let selfSurface:C.Quality
    }
    /// Immutable source receipt. Main-thread preparation does only canonical
    /// source and original membership/path checks; BVHs/factors stay in worker.
    struct Prepared:Sendable {
        let simulation:S.Prepared
        let linearizationSourceIdentity:UUID
        let seamGroupIDs:[Int]
        fileprivate let panelGroups:[K.PanelGroup],sourceStitchCount:Int
        fileprivate init(simulation:S.Prepared,seamGroupIDs:[Int],panelGroups:[K.PanelGroup],sourceStitchCount:Int) {
            self.simulation=simulation;self.linearizationSourceIdentity=simulation.input.objective.linearizationSource.identity
            self.seamGroupIDs=seamGroupIDs;self.panelGroups=panelGroups;self.sourceStitchCount=sourceStitchCount
        }

        /// A diagnostic of a real captured frame, including early assembly.
        /// This does not mint Validated and does not assert quiet/final fit.
        func inspectLastAcceptedFrame(session:S.Session,isCancelled:@escaping @Sendable()->Bool={false})throws->FrameProof {
            try identity(session,isCancelled)
            guard let record=session.lastAcceptedFrame else {throw ValidationError.missingAcceptedFrame}
            try latest(record,session:session)
            let worker=try Worker(prepared:self,session:session,isCancelled:isCancelled)
            return try worker.inspect(record,isCancelled:isCancelled)
        }

        /// Diagnostic audit of an actual captured record bound to the current
        /// serial session. This returns data only and never mints Validated.
        func inspectAcceptedFrame(_ record:S.AcceptedFrame,session:S.Session,isCancelled:@escaping @Sendable()->Bool={false})throws->FrameProof {
            try identity(session,isCancelled)
            try latest(record,session:session)
            let worker=try Worker(prepared:self,session:session,isCancelled:isCancelled)
            return try worker.inspect(record,isCancelled:isCancelled)
        }

        /// Invoke on the serial simulation worker after advanceStep returns.
        /// Unknown/budget/cancel/stale/unstable results yield no output capability.
        /// The caller accumulates EVERY accepted StepReport.computationSeconds;
        /// the bounded journal alone cannot reconstruct the full generation cost.
        func validate(session:S.Session,acceptedStepComputationSeconds:Double,limits:Limits=Limits(),isCancelled:@escaping @Sendable()->Bool={false})throws->Validated {
            let start=ContinuousClock.now
            try identity(session,isCancelled)
            guard acceptedStepComputationSeconds.isFinite,acceptedStepComputationSeconds>=0 else {throw ValidationError.invalidTiming}
            guard (1...200_000).contains(limits.maximumSurfaceCandidatePairs) else {throw ValidationError.invalidBudget}
            guard let last=session.lastAcceptedFrame else {throw ValidationError.missingAcceptedFrame}
            try latest(last,session:session)
            let records=session.consecutiveQuietFrames,required=simulation.settings.requiredQuietSteps
            guard !simulation.input.source.plan.usesFiniteCoarseTacks else {
                throw ValidationError.gate("抽褶边界尚无完整连续闭合证明",step:session.state.completedSteps)
            }
            guard required==24,records.count==required,session.state.consecutiveQuietSteps>=required,
                  last.report.numericallyStableCandidate else {throw ValidationError.insufficientQuietFrames}
            guard let tail=records.last,tail.identity==last.identity,sameControl(tail.acceptedSeedControl,last.acceptedSeedControl),
                  sameState(tail.previous,last.previous),sameState(tail.accepted,last.accepted),
                  same(tail.predictor,last.predictor) else {throw ValidationError.inconsistentRecord("最新记录与稳定窗口末尾不符。")}
            guard acceptedStepComputationSeconds>=records.reduce(0,{$0+$1.report.computationSeconds}) else {
                throw ValidationError.invalidTiming
            }
            var previous:S.State?,previousRecord:S.AcceptedFrame?,proofs:[FrameProof]=[]
            let worker=try Worker(prepared:self,session:session,isCancelled:isCancelled)
            for record in records {
                if isCancelled(){throw CancellationError()}
                if let previous,!sameState(record.previous,previous) {throw ValidationError.inconsistentRecord("稳定窗口的前后状态不连续。")}
                if let prior=previousRecord {
                    guard sameControl(record.previousSeedControl,prior.acceptedSeedControl),
                          record.previousSeedControl.originAcceptedFrameIdentity==prior.identity else {
                        throw ValidationError.inconsistentRecord("稳定窗口的已提交分区身份链不连续。")
                    }
                }
                guard record.accepted.consecutiveQuietSteps==record.previous.consecutiveQuietSteps+1,
                      record.report.sewingRamp==1,record.report.gravityFraction==1,
                      record.report.trajectoryMode == .physicalLinearStep,record.configurationSegments.isEmpty else {
                    throw ValidationError.insufficientQuietFrames
                }
                let p=try worker.inspect(record,isCancelled:isCancelled)
                guard p.meetsFreshEquilibrium else {throw ValidationError.gate("freshForceAndCurrentPCorrection",step:p.step)}
                guard p.meetsQuietScalarGates else {throw ValidationError.gate("quietSpeedSourceAndActualBarycentricSeams",step:p.step)}
                proofs.append(p);previous=record.accepted;previousRecord=record
            }
            guard previous.map({sameState($0,session.state)}) == true,
                  previousRecord.map({sameControl($0.acceptedSeedControl,session.committedSeedControl)}) == true else {throw ValidationError.inconsistentRecord("验收末态与会话当前状态不符。")}
            let source=simulation.input.source,cloth=source.cloth,x=session.state.positions
            let body=try GarmentCodeBodyMeshQueries.Prepared(body:worker.bodyMesh,isCancelled:isCancelled)
            guard body.geometrySHA256==simulation.bodyClearanceProof.bodyGeometrySHA256 else {throw ValidationError.foreignPrepared}
            let inspector=try I.Prepared(sourceSHA256:source.sourceSHA256,vertexCount:x.count,
                triangleIndices:cloth.triangleIndices,body:body,limits:limits.visibleBody,isCancelled:isCancelled)
            let visible=try inspector.inspect(positions:x,isCancelled:isCancelled)
            guard visible.meetsFinalBodyGate,visible.completedAllSamples,visible.uncertainSamples==0,
                  visible.insideSamples==0,visible.onSurfaceSamples==0,visible.stopReason==nil,
                  visible.surfaceSeparation.status == .clear else {throw ValidationError.gate("exactVisibleBodyStrictSATAndAllOutside",step:nil)}
            let selfSurface=try C.inspect(positions:x,topology:worker.topology,thickness:0.0005,
                maximumCandidatePairs:limits.maximumSurfaceCandidatePairs,isCancelled:isCancelled)
            guard selfSurface.intersectingTrianglePairs==0,selfSurface.degenerateTriangles==0 else {
                throw ValidationError.gate("independentSelfSurface",step:nil)
            }
            guard let final=proofs.last else {throw ValidationError.insufficientQuietFrames}
            let metrics=try worker.metrics(proofs:proofs,sourceStitches:sourceStitchCount,
                completedSteps:session.state.completedSteps,acceptedStepComputationSeconds:acceptedStepComputationSeconds,
                validationStartedAt:start,isCancelled:isCancelled)
            var diagnostics=K.Diagnostics(vertexCount:x.count,triangleCount:cloth.triangleIndices.count/3,
                simulatedSeconds:metrics.simulatedSeconds,computationSeconds:metrics.totalComputationSeconds,
                maxEdgeStrain:final.maximumSourceEdgeRelativeChange,meanEdgeStrain:final.meanSourceEdgeRelativeChange,
                maxSpeedMetersPerSecond:metrics.maximumSpeedMetersPerSecond,maxBodyPenetrationMeters:visible.maximumPenetrationMeters!,
                maxSeamGapMeters:final.sewing.maximumMeasuredGapMeters,
                // Required legacy scalar fields have no meaning for arbitrary
                // complete garments; zero denotes absent, never a measured size.
                waistCircumferenceMeters:0,hemCircumferenceMeters:0,radialLengthMeters:0,
                referenceAreaSquareMeters:metrics.sourceAreaSquareMeters,converged:true,
                warnings:cloth.preparationWarnings+["实验材料与标准人体；未验证个体合身。","通用腰围、下摆周长与长度未定义；兼容字段 0 不是量体结果。"])
            diagnostics.bodyModel=cloth.standardBody?.profileName ?? cloth.fixedBodySurface.map {
                String(format:"MakeHuman · 参考摆臂人台（%.2f°）",$0.requestedAlphaDegrees)
            } ?? cloth.fittedBodySurface.map { _ in "MakeHuman · 表面尺寸拟合／参考摆臂人台（实验）" }
            diagnostics.materialName=cloth.settings.material?.title
            diagnostics.totalFabricMassKg=metrics.totalFabricMassKg;diagnostics.garmentStyle=cloth.garmentStyle
            diagnostics.surfaceIntersectionCount=0;diagnostics.closeSurfacePairCount=selfSurface.closeSurfacePairs
            diagnostics.bodySurfaceIntersectionCount=0;diagnostics.bodySurfaceCandidatePairCount=visible.surface.candidateTrianglePairs
            diagnostics.bodySurfaceClearanceMeters=0.0005;diagnostics.sewingConstraintCount=source.plan.constraints.count
            diagnostics.sewingRMSGapMeters=final.sewing.rmsGapMeters;diagnostics.sewingUsesFiniteTacks=source.plan.usesFiniteCoarseTacks
            diagnostics.sewnTimeStepSeconds=simulation.settings.timeStepSeconds;diagnostics.usesContinuousBodyContact=true
            diagnostics.staticAssemblyFrameCount=simulation.settings.staticAssemblySteps;diagnostics.gravityRampFrameCount=simulation.settings.gravityRampSteps
            var output=K.Output(positions:x,triangleIndices:cloth.triangleIndices,mannequinPositions:cloth.mannequinPositions,
                mannequinTriangleIndices:cloth.mannequinTriangleIndices,seamPaths:cloth.seamPaths,
                seamVertexPairs:cloth.seamVertexPairs,diagnostics:diagnostics)
            output.panelGroups=panelGroups
            guard output.validatedPanelGroups != nil,seamGroupIDs.count==output.seamPaths.count else {
                throw ValidationError.invalidSource("完整裁片分组或真实成对接缝丢失。")
            }
            if isCancelled(){throw CancellationError()}
            // Recheck the immutable snapshots at the acceptance boundary. No
            // result is returned if an owner violated serial worker usage.
            guard sameState(session.state,last.accepted),sameControl(session.committedSeedControl,last.acceptedSeedControl),
                  session.lastAcceptedFrame.map({$0.identity==last.identity && sameState($0.accepted,last.accepted) && sameControl($0.acceptedSeedControl,last.acceptedSeedControl)}) == true else {
                throw ValidationError.inconsistentRecord("验收期间会话状态发生变化。")
            }
            return Validated(output:output,seamGroupIDs:seamGroupIDs,metrics:metrics,
                proof:.init(sourceSHA256:source.sourceSHA256,bodyGeometrySHA256:body.geometrySHA256,
                    linearizationSourceIdentity:linearizationSourceIdentity,frames:proofs,visibleBody:visible,selfSurface:selfSurface))
        }
        private func identity(_ session:S.Session,_ cancelled:@Sendable()->Bool)throws {
            if cancelled(){throw CancellationError()}
            let id=linearizationSourceIdentity
            guard session.prepared.input.objective.linearizationSource.identity==id,
                  session.prepared.objective.body.cloth.linearizationSource.identity==id,
                  simulation.objective.body.cloth.linearizationSource.identity==id,
                  session.prepared.sourceSHA256==simulation.sourceSHA256,
                  session.prepared.bodyClearanceProof.bodyGeometrySHA256==simulation.bodyClearanceProof.bodyGeometrySHA256 else {
                throw ValidationError.foreignPrepared
            }
        }
        private func latest(_ record:S.AcceptedFrame,session:S.Session)throws {
            guard sameState(record.accepted,session.state),
                  session.lastAcceptedFrame.map({$0.identity==record.identity && sameControl($0.previousSeedControl,record.previousSeedControl) && $0.usedPhysicalSeeds==record.usedPhysicalSeeds}) == true,
                  sameControl(record.acceptedSeedControl,session.committedSeedControl),record.sourceSHA256==simulation.sourceSHA256,
                  record.bodyGeometrySHA256==simulation.bodyClearanceProof.bodyGeometrySHA256 else {
                throw ValidationError.inconsistentRecord("最新真实接受记录未绑定当前状态／人体／源。")
            }
        }
    }
    struct Validated:Sendable {
        let output:K.Output
        /// One group ID per original source path; exactly [0,0,1,1,...].
        let seamGroupIDs:[Int]
        let metrics:Metrics
        let proof:Proof
        fileprivate init(output:K.Output,seamGroupIDs:[Int],metrics:Metrics,proof:Proof) {
            self.output=output;self.seamGroupIDs=seamGroupIDs;self.metrics=metrics;self.proof=proof
        }
    }
    @MainActor static func prepare(document:GarmentCodePatternFile,simulation:S.Prepared,
        isCancelled:@Sendable()->Bool={false})throws->Prepared {
        if isCancelled(){throw CancellationError()}
        let source=simulation.input.source,cloth=source.cloth
        guard try GarmentCodeSewnDrape.canonicalSourceSHA256(document:document)==source.sourceSHA256,
              source.plan.sourceSHA256==source.sourceSHA256,
              simulation.objective.body.cloth.linearizationSource.identity==simulation.input.objective.linearizationSource.identity else {
            throw ValidationError.invalidSource("完整纸样或联立网格实例不符。")
        }
        var names=Set<String>(),vertices=Set<Int>(),faces=Set<Int>(),groups:[K.PanelGroup]=[]
        for binding in source.panelBindings {
            if isCancelled(){throw CancellationError()}
            guard names.insert(binding.mesh.panelID).inserted,!binding.vertexIDs.isEmpty,!binding.triangleIDs.isEmpty else {
                throw ValidationError.invalidSource("裁片重复或为空。")
            }
            let local=Set(binding.vertexIDs)
            guard local.count==binding.vertexIDs.count else {throw ValidationError.invalidSource("裁片顶点重复。")}
            for v in binding.vertexIDs {guard cloth.positions.indices.contains(v),vertices.insert(v).inserted else {throw ValidationError.invalidSource("源顶点遗漏或重复绑定。")}}
            for f in binding.triangleIDs {
                guard (0..<cloth.triangleIndices.count/3).contains(f),faces.insert(f).inserted,
                      (0..<3).allSatisfy({local.contains(Int(cloth.triangleIndices[3*f+$0]))}) else {throw ValidationError.invalidSource("源面遗漏或跨裁片。")}
            }
            groups.append(.init(panelID:binding.mesh.panelID,vertexIDs:binding.vertexIDs,triangleIDs:binding.triangleIDs))
        }
        guard names==Set(document.pattern.panels.keys),vertices.count==cloth.positions.count,faces.count==cloth.triangleIndices.count/3 else {
            throw ValidationError.invalidSource("完整源裁片覆盖不符。")
        }
        var paths:[Sewing.EdgeKey:[Int]]=[:]
        for p in source.plan.allBoundaryPaths {
            guard paths.updateValue(p.vertexIDs,forKey:p.edge)==nil else {throw ValidationError.invalidSource("源边界重复。")}
        }
        guard cloth.seamPaths.count==2*document.pattern.stitches.count else {throw ValidationError.invalidSource("源接缝必须各保留两条原路径。")}
        var ids:[Int]=[]
        for (index,stitch) in document.pattern.stitches.enumerated() {
            if isCancelled(){throw CancellationError()}
            guard stitch.sides.count==2 else {throw ValidationError.invalidSource("源接缝缺一侧。")}
            let a=stitch.sides[0],b=stitch.sides[1]
            let ka=Sewing.EdgeKey(panelID:a.panel,edgeIndex:a.edge),kb=Sewing.EdgeKey(panelID:b.panel,edgeIndex:b.edge)
            guard let pa=paths[ka],let pb=paths[kb],cloth.seamPaths[2*index]==pa,cloth.seamPaths[2*index+1]==pb,
                  source.plan.anchors.contains(where:{$0.stitchIndex==index && $0.a.edge==ka && $0.b.edge==kb}) else {
                throw ValidationError.invalidSource("接缝两侧路径与真实源引用不符。")
            }
            ids += [index,index]
        }
        if isCancelled(){throw CancellationError()}
        return .init(simulation:simulation,seamGroupIDs:ids,panelGroups:groups,sourceStitchCount:document.pattern.stitches.count)
    }

    private struct SourceEdge {let a:Int,b:Int,length:Double}
    private final class Worker {
        let prepared:Prepared,session:S.Session
        let topology:C.Topology,bodyMesh:B.BodyMesh
        let selfMotion:SelfContactGuard.Prepared,sourceMotion:GarmentCodeMembranePath.Prepared
        let factor:CP.Workspace,edges:[SourceEdge]
        init(prepared:Prepared,session:S.Session,isCancelled:@escaping @Sendable()->Bool)throws {
            self.prepared=prepared;self.session=session
            let source=prepared.simulation.input.source,cloth=source.cloth
            topology=try C.Topology(vertexCount:cloth.positions.count,triangleIndices:cloth.triangleIndices,isCancelled:isCancelled)
            bodyMesh=try B.BodyMesh(positions:cloth.mannequinPositions,triangleIndices:cloth.mannequinTriangleIndices)
            selfMotion=try SelfContactGuard.Prepared(vertexCount:cloth.positions.count,triangleIndices:cloth.triangleIndices,isCancelled:isCancelled)
            sourceMotion=try GarmentCodeMembranePath.Prepared(membrane:prepared.simulation.input.objective.membrane,limits:session.limits.newton.sourcePath)
            let plan=try P.Plan(prepared:prepared.simulation.input.objective,limits:session.limits.preconditioner,isCancelled:isCancelled)
            factor=CP.Workspace(base:try plan.makeWorkspace(isCancelled:isCancelled))
            var keys=Set<UInt64>()
            for i in stride(from:0,to:cloth.referenceTriangles.count,by:3) {
                if i%768==0 && isCancelled(){throw CancellationError()}
                let t=(0..<3).map{Int(cloth.referenceTriangles[i+$0])}
                for j in 0..<3 {let a=min(t[j],t[(j+1)%3]),b=max(t[j],t[(j+1)%3]);keys.insert(UInt64(a)<<32|UInt64(b))}
            }
            edges=keys.sorted().map {let a=Int($0>>32),b=Int($0&0xffffffff);return .init(a:a,b:b,length:(cloth.referencePositions[a]-cloth.referencePositions[b]).length)}
        }
        func inspect(_ r:S.AcceptedFrame,isCancelled:@escaping @Sendable()->Bool)throws->FrameProof {
            if isCancelled(){throw CancellationError()}
            let p=prepared.simulation,s=p.settings,dt=s.timeStepSeconds,n=p.initialPositions.count,index=r.previous.completedSteps+1
            guard r.sourceSHA256==p.sourceSHA256,r.bodyGeometrySHA256==p.bodyClearanceProof.bodyGeometrySHA256,
                  r.accepted.completedSteps==index,r.report.completedStepsBefore==r.previous.completedSteps,
                  r.report.attemptedStep==index,r.report.accepted,r.report.newton.converged,
                  r.report.sourceSHA256==p.sourceSHA256,r.previous.positions.count==n,r.previous.velocities.count==n,
                  r.accepted.positions.count==n,r.accepted.velocities.count==n,r.predictor.count==n,
                  (r.previous.positions+r.previous.velocities+r.accepted.positions+r.accepted.velocities+r.predictor).allSatisfy(\.isFinite) else {
                throw ValidationError.inconsistentRecord("接受帧的来源、计数或自由度不符。")
            }
            let phase:S.Phase=index<=s.staticAssemblySteps ? .staticAssembly:(index<=s.staticAssemblySteps+s.gravityRampSteps ? .gravityRamp:.settling)
            try seedControl(r,phase:phase,index:index)
            if phase != .staticAssembly {return try inspectPhysical(r,phase:phase,index:index,isCancelled:isCancelled)}
            guard r.physicalSubsteps.isEmpty,r.report.physicalSubstepCount==0 else {throw ValidationError.inconsistentRecord("静态装配不得伪装成物理叶步。")}
            let ramp=min(1,Double(index)/Double(s.staticAssemblySteps))
            let gravity=min(1,max(0,Double(index-s.staticAssemblySteps)/Double(s.gravityRampSteps)))
            let v=zip(r.accepted.positions,r.previous.positions).map{($0-$1)/dt}
            let damping=exp(-s.velocityDampingPerSecond*dt),a=V(x:0,y:-s.gravityMetersPerSecondSquared*gravity,z:0)
            let predictor=phase == .staticAssembly ? r.previous.positions:zip(r.previous.positions,r.previous.velocities).map{$0+$1*(damping*dt)+a*(dt*dt)}
            guard r.report.phase==phase,r.report.sewingRamp==ramp,r.report.gravityFraction==gravity,r.predictor==predictor,
                  r.accepted.velocities==(phase == .staticAssembly ? Array(repeating:.zero,count:n):v) else {
                throw ValidationError.inconsistentRecord("必须使用真实调度、位移速度和原隐式预测位置。")
            }
            let frame=try p.objective.frame(predictor:r.predictor,timeStepSeconds:dt,sewingRamp:ramp,sewingSchedule:s.sewingSchedule)
            let e=try frame.evaluate(positions:r.accepted.positions,isCancelled:isCancelled)
            let blocks=try frame.preconditionerBlocks(at:e,isCancelled:isCancelled)
            let token=try factor.update(frame:frame.cloth,positions:r.accepted.positions,blocks:blocks,isCancelled:isCancelled)
            let correction=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:token,isCancelled:isCancelled)
            guard let residual=factor.latestSolveRelativeResidual,residual.isFinite,residual>=0 else {throw ValidationError.gate("unresolvedFreshPzSolve",step:index)}
            var maxStrain=0.0,sum=0.0
            for (i,edge) in edges.enumerated() {
                if i%256==0 && isCancelled(){throw CancellationError()}
                let change=abs((r.accepted.positions[edge.a]-r.accepted.positions[edge.b]).length/edge.length-1)
                guard change.isFinite else {throw ValidationError.gate("nonfiniteSourceEdge",step:index)}
                maxStrain=max(maxStrain,change);sum += change
            }
            let sewing=try Sewing.inspect(positions:r.accepted.positions,plan:p.input.source.plan,rampFraction:ramp,isCancelled:isCancelled)
            let mode=r.report.trajectoryMode
            let expectedMode:S.N.TrajectoryMode=phase == .staticAssembly ? .configurationPolyline:.physicalLinearStep
            guard mode==expectedMode,r.report.newton.trajectoryMode==mode else {
                throw ValidationError.inconsistentRecord("实际轨迹模式与阶段不符。")
            }
            var lines:[(from:[V],to:[V])]=[]
            if mode == .configurationPolyline {
                guard r.configurationSegments.count==r.report.newton.history.count,
                      r.configurationSegments.count<=session.limits.newton.maximumNewtonIterations else {
                    throw ValidationError.inconsistentRecord("配置轨迹与接受的 Newton 分段数不符。")
                }
                var previous=r.previous.positions
                for segment in r.configurationSegments {
                    guard segment.previous==previous,segment.accepted.count==n,
                          segment.sourceMotion.status == .clear,segment.sourceMotion.completedAllTriangles,
                          segment.bodyMotion.permitsWholeCandidate,segment.bodyMotion.statistics.completedAllFeatures,
                          segment.selfMotion.permitsWholeCandidate,segment.selfMotion.statistics.completedAllFeatures,
                          segment.selfMotion.statistics.completedDomainCertificates else {
                        throw ValidationError.inconsistentRecord("原配置分段未完整连接或缺少源／人体／自接触证书。")
                    }
                    lines.append((segment.previous,segment.accepted));previous=segment.accepted
                }
                guard previous==r.accepted.positions else {throw ValidationError.inconsistentRecord("配置分段未到达实际接受末态。")}
                if lines.isEmpty {
                    guard r.previous.positions==r.accepted.positions,r.report.newton.history.isEmpty else {
                        throw ValidationError.inconsistentRecord("空配置轨迹只能表示真实零位移。")
                    }
                }
            } else {
                guard r.configurationSegments.isEmpty else {throw ValidationError.inconsistentRecord("物理步不得冒用配置折线。")}
                lines=[(r.previous.positions,r.accepted.positions)]
            }
            var sources:[GarmentCodeMembranePath.Report]=[],bodies:[MotionProof]=[],selves:[MotionProof]=[]
            for line in lines {
                if isCancelled(){throw CancellationError()}
                let source=try sourceMotion.certify(from:line.from,to:line.to,barrier:p.input.objective.strainBarrier,isCancelled:isCancelled)
                guard source.status == .clear,source.completedAllTriangles else {throw ValidationError.gate("freshActualSegmentSourcePath",step:index)}
                let body=try p.objective.body.bodyMotion(from:line.from,to:line.to,isCancelled:isCancelled)
                guard body.permitsWholeCandidate,body.statistics.completedAllFeatures else {throw ValidationError.gate("freshActualSegmentBodyPath:"+body.status.rawValue,step:index)}
                let cloth=selfMotion.guardMotion(previous:line.from.map(native),candidate:line.to.map(native),options:session.limits.selfMotion,isCancelled:isCancelled)
                if isCancelled() || cloth.status == .cancelled {throw CancellationError()}
                guard cloth.permitsWholeCandidate,cloth.statistics.completedAllFeatures,cloth.statistics.completedDomainCertificates else {
                    throw ValidationError.gate("freshActualSegmentSelfPath:"+cloth.status.rawValue,step:index)
                }
                sources.append(source)
                bodies.append(.init(status:body.status.rawValue,safeTime:body.safeTime,minimumSeparationMeters:body.minimumSeparation,
                    completedAllFeatures:body.statistics.completedAllFeatures,completedDomainCertificates:nil,nativeQueries:body.statistics.nativeQueries,
                    trianglePairs:body.statistics.trianglePairs,euclideanCertificateAttempts:body.statistics.euclideanCertificateAttempts,
                    euclideanCertifiedFeatures:body.statistics.euclideanCertifiedFeatures,euclideanCertificateNodes:body.statistics.euclideanCertificateNodes,
                    euclideanCertifiedAfterPrecisionLimit:body.statistics.euclideanCertifiedAfterPrecisionLimit))
                selves.append(.init(status:cloth.status.rawValue,safeTime:cloth.safeTime,minimumSeparationMeters:cloth.minimumSeparation,
                    completedAllFeatures:cloth.statistics.completedAllFeatures,completedDomainCertificates:cloth.statistics.completedDomainCertificates,
                    nativeQueries:cloth.statistics.nativeQueries,trianglePairs:cloth.statistics.trianglePairs,
                    euclideanCertificateAttempts:cloth.statistics.euclideanCertificateAttempts,
                    euclideanCertifiedFeatures:cloth.statistics.euclideanCertifiedFeatures,
                    euclideanCertificateNodes:cloth.statistics.euclideanCertificateNodes,
                    euclideanCertifiedAfterPrecisionLimit:cloth.statistics.euclideanCertifiedAfterPrecisionLimit))
            }
            let rate=v.reduce(0){max($0,$1.length)}
            return .init(step:index,sewingRamp:ramp,gravityFraction:gravity,energyJoules:e.energyJoules,
                gradientInfinityNewton:infinity(e.gradientNewton),preconditionedGradientInfinityMeters:infinity(correction),pzRelativeResidual:residual,
                maximumSourceEdgeRelativeChange:maxStrain,meanSourceEdgeRelativeChange:sum/Double(edges.count),sewing:sewing,
                actualTrajectoryMode:mode,segmentCount:lines.count,
                maximumPhysicalSpeedMetersPerSecond:mode == .physicalLinearStep ? rate:nil,
                maximumConfigurationChangeRateMetersPerSecond:mode == .configurationPolyline ? rate:nil,
                sourceMotions:sources,bodyMotions:bodies,selfMotions:selves,physicalSubsteps:[],physicalSeedForest:nil)
        }

        private func seedControl(_ r:S.AcceptedFrame,phase:S.Phase,index:Int)throws {
            let p=prepared.simulation,initial=session.initialSeedControl,policy=session.limits.physicalSeedPolicy
            let depth=session.limits.maximumPhysicalSubstepDepth
            let attemptBudget=session.limits.maximumPhysicalSubstepAttempts
            guard (0...4).contains(depth),(1...15).contains(attemptBudget) else {throw ValidationError.inconsistentRecord("时间分区深度或工作预算无效。")}
            let root=[S.PhysicalSeedSpan(startTick:0,endTick:1<<depth,ticksPerMacroStep:1<<depth)]
            func bound(_ c:S.PhysicalSeedControl)throws {
                guard c.contextIdentity==session.seedContextIdentity,c.policyVersion==policy.version,
                      c.sourceSHA256==p.sourceSHA256,c.bodyGeometrySHA256==p.bodyClearanceProof.bodyGeometrySHA256,
                      c.linearizationSourceIdentity==prepared.linearizationSourceIdentity,
                      c.baseTimeStepSeconds.bitPattern==p.settings.timeStepSeconds.bitPattern,c.maximumDepth==depth,c.maximumAttempts==attemptBudget else {
                    throw ValidationError.inconsistentRecord("时间分区与本会话不可变来源、材料／设置或时间尺度不符。")
                }
            }
            try bound(initial);try bound(r.previousSeedControl);try bound(r.acceptedSeedControl)
            guard initial.originCompletedStep==0,initial.originAcceptedFrameIdentity==nil,initial.nextSeeds==root else {
                throw ValidationError.inconsistentRecord("初始时间控制不能继承未来或外来分区。")
            }
            if phase == .staticAssembly {
                guard sameControl(r.previousSeedControl,initial),sameControl(r.acceptedSeedControl,initial),
                      r.usedPhysicalSeeds.isEmpty,r.physicalAttemptLedger.isEmpty,
                      r.report.physicalSubstepAttempts==0,r.report.physicalSubdivisionDepth==0,
                      r.report.seedPolicyVersion==nil,r.report.physicalSeedRootCount==nil,r.report.seedOriginStep==nil,
                      r.report.seedReused==nil,r.report.usedPhysicalSeeds==nil else {
                    throw ValidationError.inconsistentRecord("静态装配不能持有或更新物理分区控制。")
                }
                return
            }
            if r.previous.completedSteps==p.settings.staticAssemblySteps {
                guard sameControl(r.previousSeedControl,initial) else {throw ValidationError.inconsistentRecord("首个物理宏步必须从真实初始完整时长开始。")}
            } else {
                guard r.previousSeedControl.originCompletedStep==r.previous.completedSteps,
                      r.previousSeedControl.originAcceptedFrameIdentity != nil else {
                    throw ValidationError.inconsistentRecord("复用分区没有上一真实已提交宏步的身份。")
                }
            }
            let next=policy == .committedPartition ? r.physicalSubsteps.map {
                S.PhysicalSeedSpan(startTick:$0.startTick,endTick:$0.endTick,ticksPerMacroStep:$0.ticksPerMacroStep)
            }:root
            guard r.usedPhysicalSeeds==r.previousSeedControl.nextSeeds,
                  policy != .rootOnly || r.usedPhysicalSeeds==root,
                  r.acceptedSeedControl.originCompletedStep==index,r.acceptedSeedControl.originAcceptedFrameIdentity==r.identity,
                  r.acceptedSeedControl.nextSeeds==next,
                  r.report.seedPolicyVersion==policy.version,r.report.physicalSeedRootCount==r.usedPhysicalSeeds.count,
                  r.report.seedOriginStep==r.previousSeedControl.originCompletedStep,
                  r.report.seedReused==(policy == .committedPartition && r.previousSeedControl.originCompletedStep>0),
                  r.report.usedPhysicalSeeds==r.usedPhysicalSeeds else {
                throw ValidationError.inconsistentRecord("宏步使用／提交的分区、来源身份或报告不一致。")
            }
        }

        private func inspectPhysical(_ r:S.AcceptedFrame,phase:S.Phase,index:Int,isCancelled:@escaping @Sendable()->Bool)throws->FrameProof {
            let p=prepared.simulation,leaves=r.physicalSubsteps,allowedDepth=session.limits.maximumPhysicalSubstepDepth
            guard (0...4).contains(allowedDepth) else {throw ValidationError.inconsistentRecord("物理递归深度超出有界范围。")}
            let maximumLeaves=1<<allowedDepth,maximumAttempts=min(session.limits.maximumPhysicalSubstepAttempts,2*maximumLeaves-r.usedPhysicalSeeds.count)
            guard !leaves.isEmpty,leaves.count<=maximumLeaves, r.configurationSegments.isEmpty,r.report.phase==phase,r.report.trajectoryMode == .physicalLinearStep,
                  r.report.physicalSubstepCount==leaves.count,
                  r.report.physicalSubstepAttempts<=maximumAttempts,(0...allowedDepth).contains(r.report.physicalSubdivisionDepth),
                  leaves.allSatisfy({$0.report.newton.converged && $0.report.newton.trajectoryMode == .physicalLinearStep}) else {
                throw ValidationError.inconsistentRecord("动态宏步必须保留全部真实叶步与有界尝试统计。")
            }
            let forest=try checkedPhysicalSeedForest(seeds:r.usedPhysicalSeeds,leaves:leaves.map {
                .init(startTick:$0.startTick,endTick:$0.endTick,ticksPerMacroStep:$0.ticksPerMacroStep)
            },maximumDepth:allowedDepth,reportedAttempts:r.report.physicalSubstepAttempts,ledger:r.physicalAttemptLedger,
                maximumAttempts:session.limits.maximumPhysicalSubstepAttempts,isCancelled:isCancelled)
            for (leafIndex,attemptIndex) in forest.acceptedAttemptIndices.enumerated() {
                guard r.physicalAttemptLedger[attemptIndex].computationSeconds.bitPattern==leaves[leafIndex].report.computationSeconds.bitPattern else {
                    throw ValidationError.inconsistentRecord("成功尝试与真实叶步的计算记录不一致。")
                }
            }
            let metadata=leaves.map {leaf in PhysicalKinematics(previousPositions:leaf.previousPositions,previousVelocities:leaf.previousVelocities,
                acceptedPositions:leaf.acceptedPositions,acceptedVelocities:leaf.acceptedVelocities,predictor:leaf.predictor,
                startTick:leaf.startTick,endTick:leaf.endTick,ticksPerMacroStep:leaf.ticksPerMacroStep,
                timeStepSeconds:leaf.timeStepSeconds,sewingRamp:leaf.sewingRamp,gravityFraction:leaf.gravityFraction)}
            let actualDepth=try checkedPhysicalSubstepKinematics(previousPositions:r.previous.positions,previousVelocities:r.previous.velocities,
                acceptedPositions:r.accepted.positions,acceptedVelocities:r.accepted.velocities,finalPredictor:r.predictor,
                macroStep:index,settings:p.settings,maximumSubdivisionDepth:session.limits.maximumPhysicalSubstepDepth,leaves:metadata,isCancelled:isCancelled)
            guard let last=leaves.last,r.report.sewingRamp==last.sewingRamp,r.report.gravityFraction==last.gravityFraction,
                  r.report.newton.trajectoryMode==last.report.newton.trajectoryMode,
                  r.report.newton.finalGradientInfinityNewton==last.report.newton.finalGradientInfinityNewton,
                  r.report.physicalSubdivisionDepth==actualDepth,forest.actualMaximumDepth==actualDepth,
                  r.report.maximumSourceEdgeRelativeChange==leaves.reduce(0,{max($0,$1.report.maximumSourceEdgeRelativeChange)}),
                  r.report.maximumActualSeamGapMeters==leaves.reduce(0,{max($0,$1.report.maximumActualSeamGapMeters)}),
                  r.report.maximumSewingTargetResidualMeters==leaves.reduce(0,{max($0,$1.report.maximumSewingTargetResidualMeters)}),
                  r.report.maximumSpeedMetersPerSecond==leaves.reduce(0,{max($0,$1.report.maximumSpeedMetersPerSecond)}),
                  r.report.maximumPhysicalSubstepGradientInfinityNewton==leaves.reduce(0,{max($0,$1.report.newton.finalGradientInfinityNewton)}) else {
                throw ValidationError.inconsistentRecord("宏步末叶的载荷／Newton 语义不一致。")
            }
            var proofs:[PhysicalSubstepProof]=[]
            for leaf in leaves {
                if isCancelled(){throw CancellationError()}
                guard leaf.sourceSHA256==p.sourceSHA256,leaf.bodyGeometrySHA256==p.bodyClearanceProof.bodyGeometrySHA256,
                      leaf.report.accepted,leaf.report.sourceSHA256==p.sourceSHA256,leaf.report.phase==phase,
                      leaf.report.attemptedStep==index,leaf.report.completedStepsBefore==r.previous.completedSteps,
                      leaf.report.sewingRamp==leaf.sewingRamp,leaf.report.gravityFraction==leaf.gravityFraction,
                      leaf.sourceMotion.status == .clear,leaf.sourceMotion.completedAllTriangles,
                      leaf.bodyMotion.permitsWholeCandidate,leaf.bodyMotion.statistics.completedAllFeatures,
                      leaf.bodyMotion.minimumSeparation.bitPattern==p.objective.body.parameters.minimumDistanceMeters.bitPattern,
                      leaf.selfMotion.permitsWholeCandidate,leaf.selfMotion.statistics.completedAllFeatures,
                      leaf.selfMotion.statistics.completedDomainCertificates,
                      leaf.selfMotion.minimumSeparation.bitPattern==p.objective.parameters.minimumDistanceMeters.bitPattern else {
                    throw ValidationError.inconsistentRecord("物理叶步未绑定完整源／人体或缺少原始全路径证书。")
                }
                let frame=try p.objective.frame(predictor:leaf.predictor,timeStepSeconds:leaf.timeStepSeconds,sewingRamp:leaf.sewingRamp,sewingSchedule:p.settings.sewingSchedule)
                let e=try frame.evaluate(positions:leaf.acceptedPositions,isCancelled:isCancelled)
                let blocks=try frame.preconditionerBlocks(at:e,isCancelled:isCancelled)
                let token=try factor.update(frame:frame.cloth,positions:leaf.acceptedPositions,blocks:blocks,isCancelled:isCancelled)
                let correction=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:token,isCancelled:isCancelled)
                guard let residual=factor.latestSolveRelativeResidual,residual.isFinite,residual>=0 else {throw ValidationError.gate("unresolvedFreshLeafPzSolve",step:index)}
                var maximum=0.0,sum=0.0
                for (i,edge) in edges.enumerated() {
                    if i%256==0 && isCancelled(){throw CancellationError()}
                    let change=abs((leaf.acceptedPositions[edge.a]-leaf.acceptedPositions[edge.b]).length/edge.length-1)
                    guard change.isFinite else {throw ValidationError.gate("nonfiniteLeafSourceEdge",step:index)}
                    maximum=max(maximum,change);sum+=change
                }
                let sewing=try Sewing.inspect(positions:leaf.acceptedPositions,plan:p.input.source.plan,rampFraction:leaf.sewingRamp,isCancelled:isCancelled)
                let source=try sourceMotion.certify(from:leaf.previousPositions,to:leaf.acceptedPositions,barrier:p.input.objective.strainBarrier,isCancelled:isCancelled)
                guard source.status == .clear,source.completedAllTriangles else {throw ValidationError.gate("freshPhysicalLeafSourcePath",step:index)}
                let body=try p.objective.body.bodyMotion(from:leaf.previousPositions,to:leaf.acceptedPositions,isCancelled:isCancelled)
                guard body.permitsWholeCandidate,body.statistics.completedAllFeatures else {throw ValidationError.gate("freshPhysicalLeafBodyPath:"+body.status.rawValue,step:index)}
                let cloth=selfMotion.guardMotion(previous:leaf.previousPositions.map(native),candidate:leaf.acceptedPositions.map(native),options:session.limits.selfMotion,isCancelled:isCancelled)
                if isCancelled() || cloth.status == .cancelled {throw CancellationError()}
                guard cloth.permitsWholeCandidate,cloth.statistics.completedAllFeatures,cloth.statistics.completedDomainCertificates else {throw ValidationError.gate("freshPhysicalLeafSelfPath:"+cloth.status.rawValue,step:index)}
                let bodySurface=try B.inspect(positions:leaf.acceptedPositions,topology:topology,body:bodyMesh,thickness:0.0005,
                    maximumCandidatePairs:session.limits.maximumSurfaceCandidatePairs,isCancelled:isCancelled)
                let selfSurface=try C.inspect(positions:leaf.acceptedPositions,topology:topology,thickness:0.0005,
                    maximumCandidatePairs:session.limits.maximumSurfaceCandidatePairs,isCancelled:isCancelled)
                guard bodySurface.intersectingTrianglePairs==0,bodySurface.degenerateClothTriangles==0,
                      selfSurface.intersectingTrianglePairs==0,selfSurface.degenerateTriangles==0 else {throw ValidationError.gate("freshPhysicalLeafIndependentSurface",step:index)}
                let speed=leaf.acceptedVelocities.reduce(0){max($0,$1.length)}
                proofs.append(.init(startTick:leaf.startTick,endTick:leaf.endTick,ticksPerMacroStep:leaf.ticksPerMacroStep,timeStepSeconds:leaf.timeStepSeconds,
                    sewingRamp:leaf.sewingRamp,gravityFraction:leaf.gravityFraction,energyJoules:e.energyJoules,gradientInfinityNewton:infinity(e.gradientNewton),
                    preconditionedGradientInfinityMeters:infinity(correction),pzRelativeResidual:residual,maximumSourceEdgeRelativeChange:maximum,
                    meanSourceEdgeRelativeChange:sum/Double(edges.count),maximumSpeedMetersPerSecond:speed,sewing:sewing,sourceMotion:source,
                    bodyMotion:bodyProof(body),selfMotion:selfProof(cloth),bodySurface:bodySurface,selfSurface:selfSurface))
            }
            guard let final=proofs.last else {throw ValidationError.inconsistentRecord("动态宏步缺少真实叶步。")}
            if isCancelled(){throw CancellationError()}
            // Force/correction/source/speed below are conservative maxima over
            // actual leaves. Energy, mean strain and sewing RMS are final-leaf
            // values, each from a real fresh frame; no aggregate fake frame.
            return .init(step:index,sewingRamp:final.sewingRamp,gravityFraction:final.gravityFraction,energyJoules:final.energyJoules,
                gradientInfinityNewton:proofs.reduce(0){max($0,$1.gradientInfinityNewton)},
                preconditionedGradientInfinityMeters:proofs.reduce(0){max($0,$1.preconditionedGradientInfinityMeters)},
                pzRelativeResidual:proofs.reduce(0){max($0,$1.pzRelativeResidual)},maximumSourceEdgeRelativeChange:proofs.reduce(0){max($0,$1.maximumSourceEdgeRelativeChange)},
                meanSourceEdgeRelativeChange:final.meanSourceEdgeRelativeChange,sewing:final.sewing,
                actualTrajectoryMode:.physicalLinearStep,segmentCount:proofs.count,maximumPhysicalSpeedMetersPerSecond:proofs.reduce(0){max($0,$1.maximumSpeedMetersPerSecond)},
                maximumConfigurationChangeRateMetersPerSecond:nil,sourceMotions:proofs.map(\.sourceMotion),bodyMotions:proofs.map(\.bodyMotion),selfMotions:proofs.map(\.selfMotion),physicalSubsteps:proofs,physicalSeedForest:forest)
        }
        private func bodyProof(_ body:ContinuousBodyContact.Report)->MotionProof {
            .init(status:body.status.rawValue,safeTime:body.safeTime,minimumSeparationMeters:body.minimumSeparation,
                completedAllFeatures:body.statistics.completedAllFeatures,completedDomainCertificates:nil,nativeQueries:body.statistics.nativeQueries,
                trianglePairs:body.statistics.trianglePairs,euclideanCertificateAttempts:body.statistics.euclideanCertificateAttempts,
                euclideanCertifiedFeatures:body.statistics.euclideanCertifiedFeatures,euclideanCertificateNodes:body.statistics.euclideanCertificateNodes,
                euclideanCertifiedAfterPrecisionLimit:body.statistics.euclideanCertifiedAfterPrecisionLimit)
        }
        private func selfProof(_ cloth:SelfContactGuard.Report)->MotionProof {
            .init(status:cloth.status.rawValue,safeTime:cloth.safeTime,minimumSeparationMeters:cloth.minimumSeparation,
                completedAllFeatures:cloth.statistics.completedAllFeatures,completedDomainCertificates:cloth.statistics.completedDomainCertificates,
                nativeQueries:cloth.statistics.nativeQueries,trianglePairs:cloth.statistics.trianglePairs,
                euclideanCertificateAttempts:cloth.statistics.euclideanCertificateAttempts,euclideanCertifiedFeatures:cloth.statistics.euclideanCertifiedFeatures,
                euclideanCertificateNodes:cloth.statistics.euclideanCertificateNodes,euclideanCertifiedAfterPrecisionLimit:cloth.statistics.euclideanCertifiedAfterPrecisionLimit)
        }

        func metrics(proofs:[FrameProof],sourceStitches:Int,completedSteps:Int,acceptedStepComputationSeconds:Double,
                     validationStartedAt:ContinuousClock.Instant,isCancelled:@Sendable()->Bool)throws->Metrics {
            let input=prepared.simulation.input,cloth=input.source.cloth
            var panels:[PanelMetrics]=[]
            for group in prepared.panelGroups {
                if isCancelled(){throw CancellationError()}
                var area=0.0
                for f in group.triangleIDs {
                    let a=cloth.referencePositions[Int(cloth.referenceTriangles[3*f])],b=cloth.referencePositions[Int(cloth.referenceTriangles[3*f+1])],c=cloth.referencePositions[Int(cloth.referenceTriangles[3*f+2])]
                    area += (b-a).cross(c-a).length*0.5
                }
                let mass=group.vertexIDs.reduce(0){$0+input.objective.massesKg[$1]}
                guard area.isFinite,area>0,mass.isFinite,mass>0 else {throw ValidationError.invalidSource("裁片原始面积或质量无效。")}
                panels.append(.init(panelID:group.panelID,vertices:group.vertexIDs.count,triangles:group.triangleIDs.count,sourceAreaSquareMeters:area,massKg:mass))
            }
            let totalArea=panels.reduce(0){$0+$1.sourceAreaSquareMeters},totalMass=panels.reduce(0){$0+$1.massKg}
            guard abs(totalArea-cloth.referenceAreaSquareMeters)<=max(1e-12,totalArea*1e-10),
                  let mass=cloth.totalFabricMassKg,abs(totalMass-mass)<=max(1e-12,totalMass*1e-10),let last=proofs.last,let speed=last.maximumPhysicalSpeedMetersPerSecond else {throw ValidationError.invalidSource("完整源面积、质量或真实物理速度校验不符。")}
            let validationSeconds=S.elapsedSeconds(since:validationStartedAt),totalSeconds=acceptedStepComputationSeconds+validationSeconds
            guard validationSeconds.isFinite,validationSeconds>=0,totalSeconds.isFinite else {throw ValidationError.invalidTiming}
            return .init(panels:panels,sourceAreaSquareMeters:totalArea,totalFabricMassKg:totalMass,
                vertices:cloth.positions.count,triangles:cloth.triangleIndices.count/3,sourceEdges:edges.count,sourceStitches:sourceStitches,
                sewingConstraints:input.source.plan.constraints.count,completedSteps:completedSteps,
                assemblyIterations:min(completedSteps,prepared.simulation.settings.staticAssemblySteps),verifiedQuietFrames:proofs.count,
                dynamicSimulatedSeconds:Double(max(0,completedSteps-prepared.simulation.settings.staticAssemblySteps))*prepared.simulation.settings.timeStepSeconds,
                simulatedSeconds:Double(max(0,completedSteps-prepared.simulation.settings.staticAssemblySteps))*prepared.simulation.settings.timeStepSeconds,
                maximumSourceEdgeRelativeChange:last.maximumSourceEdgeRelativeChange,meanSourceEdgeRelativeChange:last.meanSourceEdgeRelativeChange,
                maximumActualSeamGapMeters:last.sewing.maximumMeasuredGapMeters,rmsActualSeamGapMeters:last.sewing.rmsGapMeters,
                maximumSpeedMetersPerSecond:speed,
                maximumFreshGradientInfinityNewton:proofs.reduce(0){max($0,$1.gradientInfinityNewton)},
                maximumFreshPCorrectionInfinityMeters:proofs.reduce(0){max($0,$1.preconditionedGradientInfinityMeters)},
                maximumFreshPzRelativeResidual:proofs.reduce(0){max($0,$1.pzRelativeResidual)},
                acceptedStepComputationSeconds:acceptedStepComputationSeconds,validationSeconds:validationSeconds,totalComputationSeconds:totalSeconds,
                personalFitVerified:false)
        }
    }
    private static func same(_ a:[V],_ b:[V])->Bool {
        a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}
    }
    private static func sameControl(_ a:S.PhysicalSeedControl,_ b:S.PhysicalSeedControl)->Bool {
        a==b && a.baseTimeStepSeconds.bitPattern==b.baseTimeStepSeconds.bitPattern
    }
    private static func sameState(_ a:S.State,_ b:S.State)->Bool {
        a.completedSteps==b.completedSteps && a.consecutiveQuietSteps==b.consecutiveQuietSteps && same(a.positions,b.positions) && same(a.velocities,b.velocities)
    }
    private static func infinity(_ x:[V])->Double {x.reduce(0){max($0,abs($1.x),abs($1.y),abs($1.z))}}
    private static func native(_ v:V)->SIMD3<Double>{SIMD3(v.x,v.y,v.z)}
}
