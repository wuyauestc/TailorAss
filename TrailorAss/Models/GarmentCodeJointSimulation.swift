import Foundation
import NativeClothCollision

/// Serial implicit time integration of the complete original garment. This
/// prepares numerical candidates, not K.Output or a validated garment/fit.
nonisolated enum GarmentCodeJointSimulation {
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias G=GarmentCodeJointGarmentObjective
    typealias J=GarmentCodeJointObjective
    typealias N=GarmentCodeJointNewton
    typealias P=GarmentCodeJointPreconditioner
    typealias C=GarmentCodeClothContact
    typealias B=GarmentCodeBodySurfaceContact

    /// Explicit experimental coefficients; no extra contact or cloth penalty
    /// is introduced by the integrator.
    struct Materials:Sendable {
        let membrane:J.M.Material
        let strainBarrier:J.M.StrainBarrier
        let bending:J.H.Material
        let sewingComplianceMetersPerNewton:Double
        let bodyContact:G.T.B.Parameters
        let selfContact:G.S.Parameters
    }
    struct Settings:Sendable {
        let timeStepSeconds=1.0/240
        let staticAssemblySteps=480
        let gravityRampSteps=240
        let velocityDampingPerSecond=log(2.0)*120
        let gravityMetersPerSecondSquared=9.81
        let requiredQuietSteps=24
        /// Additional fully loaded steps after the fixed 480+240 schedule.
        var maximumAdditionalSteps=1680
        /// Explicit solver loading, independent of measured fabric properties.
        var sewingSchedule:J.SewingSchedule = .quadraticStiffness(initialNewtonPerMeter:0.001)
        var maximumSteps:Int {staticAssemblySteps+gravityRampSteps+maximumAdditionalSteps}
    }
    struct WorkerLimits:Sendable {
        var newton=N.Limits()
        var preconditioner=P.Limits()
        var selfMotion=SelfContactGuard.Options()
        var maximumSurfaceCandidatePairs=200_000
        /// Resolution and computational work are independent. Depth four can
        /// resolve a short contact interval without allowing 31 Newton solves.
        /// Keep depth three as the default until complete-macro validation.
        var maximumPhysicalSubstepDepth=3
        var maximumPhysicalSubstepAttempts=15
        var physicalSeedPolicy:PhysicalSeedPolicy = .committedPartition
    }
    enum PhysicalSeedPolicy:String,Codable,Sendable {
        case rootOnly,committedPartition
        var version:String {rawValue+"-v2"}
    }
    /// Timing data only; neither a trajectory nor an acceptance capability.
    struct PhysicalSeedSpan:Codable,Equatable,Sendable {
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
    }
    /// The per-session identity binds immutable prepared materials, settings
    /// and worker limits. Controls cannot be transferred between sessions.
    struct PhysicalSeedControl:Codable,Equatable,Sendable {
        let policyVersion:String,contextIdentity:UUID
        let sourceSHA256:String,bodyGeometrySHA256:String,linearizationSourceIdentity:UUID
        let baseTimeStepSeconds:Double,maximumDepth:Int,maximumAttempts:Int,originCompletedStep:Int
        let originAcceptedFrameIdentity:UUID?
        let nextSeeds:[PhysicalSeedSpan]
        fileprivate init(policyVersion:String,contextIdentity:UUID,sourceSHA256:String,bodyGeometrySHA256:String,
            linearizationSourceIdentity:UUID,baseTimeStepSeconds:Double,maximumDepth:Int,maximumAttempts:Int,originCompletedStep:Int,
            originAcceptedFrameIdentity:UUID?,nextSeeds:[PhysicalSeedSpan]) {
            self.policyVersion=policyVersion;self.contextIdentity=contextIdentity;self.sourceSHA256=sourceSHA256
            self.bodyGeometrySHA256=bodyGeometrySHA256;self.linearizationSourceIdentity=linearizationSourceIdentity
            self.baseTimeStepSeconds=baseTimeStepSeconds;self.maximumDepth=maximumDepth;self.originCompletedStep=originCompletedStep
            self.maximumAttempts=maximumAttempts
            self.originAcceptedFrameIdentity=originAcceptedFrameIdentity;self.nextSeeds=nextSeeds
        }
    }
    /// A compact record of the real depth-first attempts. Failed entries are
    /// diagnostics, never pieces of the accepted physical trajectory.
    struct PhysicalAttemptLedger:Codable,Equatable,Sendable {
        let seedIndex:Int,parentAttemptIndex:Int?
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let accepted:Bool,rejectionReason:String?,computationSeconds:Double
    }
    enum Phase:String,Codable,Sendable {case staticAssembly,gravityRamp,settling}
    enum SimulationError:LocalizedError,Sendable {
        case invalid(String),stepBudget,pathFailure(String)
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "整衣联立推进输入无效："+s
            case .stepBudget:return "整衣联立推进已达到本次完整步数预算。"
            case let .pathFailure(s):return "整衣运动未完整确认安全，本步未提交："+s
            }
        }
    }
    /// Endpoint data only, not a physical/path capability. The caller must
    /// separately retain and verify the native reports at returned indices.
    struct ConfigurationLineEndpoints:Sendable {
        let previous:[V],candidate:[V]
    }
    /// A comparison can certify a normal proposal, then commit a better
    /// coordinate proposal. Match only the actual accepted chain against the
    /// chronological certified attempts; never count discarded attempts as
    /// executed motion. Work is bounded by the existing96 Newton updates and
    /// at most one extra clear comparison proposal per update.
    static func configurationCertificateIndices(initial:[V],final:[V],trajectory:[ConfigurationLineEndpoints],
        checkedLines:[ConfigurationLineEndpoints],isCancelled:@Sendable()->Bool={false})throws->[Int] {
        if isCancelled(){throw CancellationError()}
        guard !initial.isEmpty,initial.count==final.count,trajectory.count<=96,checkedLines.count<=192 else {
            throw SimulationError.invalid("配置轨迹或已认证候选超过有界工作范围。")
        }
        func finite(_ positions:[V])throws {
            guard positions.count==initial.count else {throw SimulationError.invalid("配置证书的顶点数量不同。")}
            for i in positions.indices {
                if i%128==0 && isCancelled(){throw CancellationError()}
                guard positions[i].isFinite else {throw SimulationError.invalid("配置证书包含非有限坐标。")}
            }
        }
        func same(_ a:[V],_ b:[V])->Bool {
            a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern &&
                $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}
        }
        try finite(initial);try finite(final)
        for line in checkedLines {try finite(line.previous);try finite(line.candidate)}
        var cursor=0,previous=initial,indices:[Int]=[]
        for segment in trajectory {
            try finite(segment.previous);try finite(segment.candidate)
            guard same(segment.previous,previous),!same(segment.previous,segment.candidate) else {
                throw SimulationError.invalid("配置轨迹的实际接受段不连续或是零位移。")
            }
            var matched:Int?
            while cursor<checkedLines.count {
                if isCancelled(){throw CancellationError()}
                let index=cursor;cursor+=1
                if same(checkedLines[index].previous,segment.previous) && same(checkedLines[index].candidate,segment.candidate) {
                    matched=index;break
                }
            }
            guard let matched else {throw SimulationError.invalid("实际配置段缺少按时间顺序完全匹配的接触证书。")}
            indices.append(matched);previous=segment.candidate
        }
        guard same(previous,final) else {throw SimulationError.invalid("配置轨迹未到达本次实际末态。")}
        if isCancelled(){throw CancellationError()}
        return indices
    }
    struct PathStatistics:Codable,Sendable {
        var calls=0,completeBodyQueries=0,completeSelfQueries=0
        var bodyNativeQueries=0,selfNativeQueries=0,bodyTrianglePairs=0,selfTrianglePairs=0
        var bodyEuclideanCertificateAttempts=0,bodyEuclideanCertifiedFeatures=0,bodyEuclideanCertificateNodes=0
        var bodyEuclideanCertifiedAfterPrecisionLimit=0
        var selfEuclideanCertificateAttempts=0,selfEuclideanCertifiedFeatures=0,selfEuclideanCertificateNodes=0
        var selfEuclideanCertifiedAfterPrecisionLimit=0
        var selfCertifiedTriangles=0,selfCertifiedEdges=0,selfAABBPrunedPrimitiveVisits=0
        var limitedBodyQueries=0,limitedSelfQueries=0,rejectedBodyQueries=0,rejectedSelfQueries=0
        var bodySeconds=0.0,selfSeconds=0.0
        mutating func add(_ other:Self) {
            calls += other.calls
            completeBodyQueries += other.completeBodyQueries
            completeSelfQueries += other.completeSelfQueries
            bodyNativeQueries += other.bodyNativeQueries
            selfNativeQueries += other.selfNativeQueries
            bodyTrianglePairs += other.bodyTrianglePairs
            selfTrianglePairs += other.selfTrianglePairs
            bodyEuclideanCertificateAttempts += other.bodyEuclideanCertificateAttempts
            bodyEuclideanCertifiedFeatures += other.bodyEuclideanCertifiedFeatures
            bodyEuclideanCertificateNodes += other.bodyEuclideanCertificateNodes
            bodyEuclideanCertifiedAfterPrecisionLimit += other.bodyEuclideanCertifiedAfterPrecisionLimit
            selfEuclideanCertificateAttempts += other.selfEuclideanCertificateAttempts
            selfEuclideanCertifiedFeatures += other.selfEuclideanCertifiedFeatures
            selfEuclideanCertificateNodes += other.selfEuclideanCertificateNodes
            selfEuclideanCertifiedAfterPrecisionLimit += other.selfEuclideanCertifiedAfterPrecisionLimit
            selfCertifiedTriangles += other.selfCertifiedTriangles
            selfCertifiedEdges += other.selfCertifiedEdges
            selfAABBPrunedPrimitiveVisits += other.selfAABBPrunedPrimitiveVisits
            limitedBodyQueries += other.limitedBodyQueries
            limitedSelfQueries += other.limitedSelfQueries
            rejectedBodyQueries += other.rejectedBodyQueries
            rejectedSelfQueries += other.rejectedSelfQueries
            bodySeconds += other.bodySeconds
            selfSeconds += other.selfSeconds
        }
    }
    struct State:Sendable,Equatable {
        let completedSteps:Int
        let positions:[V],velocities:[V]
        let consecutiveQuietSteps:Int
    }
    struct StepReport:Codable,Sendable {
        let accepted:Bool
        let sourceSHA256:String
        let completedStepsBefore:Int,attemptedStep:Int
        let phase:Phase,sewingRamp:Double,gravityFraction:Double
        let sewingStiffnessNewtonPerMeter:Double,usesQuadraticSewingContinuation:Bool
        let maximumActualSeamGapMeters:Double,maximumSewingTargetResidualMeters:Double
        let maximumSourceEdgeRelativeChange:Double,maximumSpeedMetersPerSecond:Double
        let bodySurface:B.Quality,selfSurface:C.Quality
        /// Dynamic macro reports retain the LAST leaf (or last failed attempt)
        /// Newton report. Path costs aggregate every attempt, while the
        /// physical scalar maxima aggregate only the accepted leaf trajectory.
        let newton:N.Report,path:PathStatistics
        let trajectoryMode:N.TrajectoryMode
        let bodyContactStencils:Int,selfContactStencils:Int
        let bodyContactEnergyJoules:Double,selfContactEnergyJoules:Double
        let consecutiveQuietSteps:Int
        /// The original scalar and sampled-surface gates only. Exact visible
        /// body containment and the final product validator are still required.
        let numericallyStableCandidate:Bool
        let exactVisibleBodyContainmentVerified:Bool
        let rejectionReason:String?
        let computationSeconds:Double
        /// Dynamic reports use real physical leaves; static reports keep zero.
        var physicalSubstepCount=0
        var physicalSubstepAttempts=0
        var physicalSubdivisionDepth=0
        var maximumPhysicalSubstepGradientInfinityNewton:Double?=nil
        var seedPolicyVersion:String?=nil
        var physicalSeedRootCount:Int?=nil
        var seedOriginStep:Int?=nil
        var seedReused:Bool?=nil
        var usedPhysicalSeeds:[PhysicalSeedSpan]?=nil
        /// Dynamic macro metadata retains the actual LAST leaf/failed attempt,
        /// as for Newton. Scalar maxima above cover all accepted leaves.
        var continuousSeamQuality:GarmentCodeSewing.ContinuousBoundaryQuality?=nil
        var maximumAnchorSeamGapMeters:Double?=nil
    }
    struct Attempt:Sendable {
        let report:StepReport
        /// Diagnostic candidate; on failure it is NOT the committed state.
        let candidatePositions:[V]
        let lastRejectedNewtonCandidate:[V]?
        /// Bounded diagnostics, including failed parent/leaf attempts. These
        /// are not an executed trajectory or an accepted physical capability.
        var physicalAttempts:[PhysicalAttempt]=[]
        var physicalAttemptLedger:[PhysicalAttemptLedger]=[]
    }
    struct PhysicalAttempt:Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],predictor:[V],candidatePositions:[V]
        let lastRejectedNewtonCandidate:[V]?
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:StepReport
        fileprivate init(sourceSHA256:String,bodyGeometrySHA256:String,previousPositions:[V],previousVelocities:[V],predictor:[V],candidatePositions:[V],
            lastRejectedNewtonCandidate:[V]?,startTick:Int,endTick:Int,ticksPerMacroStep:Int,
            timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double,report:StepReport) {
            self.sourceSHA256=sourceSHA256;self.bodyGeometrySHA256=bodyGeometrySHA256
            self.previousPositions=previousPositions;self.previousVelocities=previousVelocities;self.predictor=predictor
            self.candidatePositions=candidatePositions;self.lastRejectedNewtonCandidate=lastRejectedNewtonCandidate
            self.startTick=startTick;self.endTick=endTick;self.ticksPerMacroStep=ticksPerMacroStep
            self.timeStepSeconds=timeStepSeconds;self.sewingRamp=sewingRamp;self.gravityFraction=gravityFraction;self.report=report
        }
    }
    /// Actual work completed before the next solve would exceed the budget.
    /// This is a diagnostic error, never an accepted trajectory or fake Newton
    /// result. The public session remains at the preceding full macrostep.
    struct PhysicalAttemptBudgetExceeded:LocalizedError,Sendable {
        let attemptedStep:Int,maximumAttempts:Int
        let pendingSeedIndex:Int,pendingStartTick:Int,pendingEndTick:Int,ticksPerMacroStep:Int
        let attempts:[PhysicalAttempt],ledger:[PhysicalAttemptLedger]
        var errorDescription:String? {"本时间步已达到计算尝试上限，未提交未完成的运动；请调整参数后重试。"}
    }
    /// One actually executed, independently certifiable physical time chord.
    /// A failed/abandoned parent attempt can never be converted to this type.
    struct PhysicalSubstep:Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V]
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:StepReport
        let sourceMotion:GarmentCodeMembranePath.Report
        let bodyMotion:ContinuousBodyContact.Report,selfMotion:SelfContactGuard.Report
        fileprivate init(sourceSHA256:String,bodyGeometrySHA256:String,previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V],
            startTick:Int,endTick:Int,ticksPerMacroStep:Int,timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double,
            report:StepReport,sourceMotion:GarmentCodeMembranePath.Report,bodyMotion:ContinuousBodyContact.Report,selfMotion:SelfContactGuard.Report) {
            self.sourceSHA256=sourceSHA256;self.bodyGeometrySHA256=bodyGeometrySHA256
            self.previousPositions=previousPositions;self.previousVelocities=previousVelocities
            self.acceptedPositions=acceptedPositions;self.acceptedVelocities=acceptedVelocities;self.predictor=predictor
            self.startTick=startTick;self.endTick=endTick;self.ticksPerMacroStep=ticksPerMacroStep
            self.timeStepSeconds=timeStepSeconds;self.sewingRamp=sewingRamp;self.gravityFraction=gravityFraction;self.report=report
            self.sourceMotion=sourceMotion;self.bodyMotion=bodyMotion;self.selfMotion=selfMotion
        }
    }
    /// Captured only by the serial integrator after every acceptance check.
    /// Keeps the last leaf's real implicit predictor; it cannot be reconstructed later
    /// from just the new velocity or an unrelated diagnostic StepReport.
    struct AcceptedFrame:Sendable {
        let identity:UUID
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previous:State,accepted:State
        let predictor:[V]
        let report:StepReport
        let configurationSegments:[ConfigurationSegment]
        let physicalSubsteps:[PhysicalSubstep]
        let previousSeedControl:PhysicalSeedControl,usedPhysicalSeeds:[PhysicalSeedSpan],acceptedSeedControl:PhysicalSeedControl
        let physicalAttemptLedger:[PhysicalAttemptLedger]
        fileprivate init(identity:UUID,sourceSHA256:String,bodyGeometrySHA256:String,previous:State,accepted:State,predictor:[V],report:StepReport,
                         configurationSegments:[ConfigurationSegment],physicalSubsteps:[PhysicalSubstep]=[],
                         previousSeedControl:PhysicalSeedControl,usedPhysicalSeeds:[PhysicalSeedSpan],acceptedSeedControl:PhysicalSeedControl,
                         physicalAttemptLedger:[PhysicalAttemptLedger]) {
            self.identity=identity
            self.sourceSHA256=sourceSHA256;self.bodyGeometrySHA256=bodyGeometrySHA256
            self.previous=previous;self.accepted=accepted;self.predictor=predictor;self.report=report
            self.configurationSegments=configurationSegments;self.physicalSubsteps=physicalSubsteps
            self.previousSeedControl=previousSeedControl;self.usedPhysicalSeeds=usedPhysicalSeeds;self.acceptedSeedControl=acceptedSeedControl
            self.physicalAttemptLedger=physicalAttemptLedger
        }
    }
    struct ConfigurationSegment:Sendable {
        let previous:[V],accepted:[V]
        let sourceMotion:GarmentCodeMembranePath.Report
        let bodyMotion:ContinuousBodyContact.Report,selfMotion:SelfContactGuard.Report
        fileprivate init(previous:[V],accepted:[V],sourceMotion:GarmentCodeMembranePath.Report,
                         bodyMotion:ContinuousBodyContact.Report,selfMotion:SelfContactGuard.Report) {
            self.previous=previous;self.accepted=accepted;self.sourceMotion=sourceMotion
            self.bodyMotion=bodyMotion;self.selfMotion=selfMotion
        }
    }
    fileprivate struct SourceEdge:Sendable {let a:Int,b:Int,length:Double}
    struct Recipe:Sendable {
        fileprivate let native:GarmentCodeNativeAssembly.Recipe
        fileprivate let materials:Materials,settings:Settings
        fileprivate init(native:GarmentCodeNativeAssembly.Recipe,materials:Materials,settings:Settings) {
            self.native=native;self.materials=materials;self.settings=settings
        }
    }
    struct Prepared:Sendable {
        let input:GarmentCodeJointInput.Prepared
        let objective:G.Prepared
        let settings:Settings
        let bodyClearanceProof:GarmentCodeRigidBodyClearance.Proof
        let clothClearanceProof:GarmentCodeRigidClothClearance.Proof
        let initialBodySurface:B.Quality,initialSelfSurface:C.Quality
        fileprivate let topology:C.Topology,bodyMesh:B.BodyMesh,selfMotion:SelfContactGuard.Prepared
        fileprivate let sourceEdges:[SourceEdge]
        var sourceSHA256:String {input.sourceSHA256}
        var initialPositions:[V] {input.source.cloth.positions}
        fileprivate init(input:GarmentCodeJointInput.Prepared,objective:G.Prepared,settings:Settings,
            bodyProof:GarmentCodeRigidBodyClearance.Proof,clothProof:GarmentCodeRigidClothClearance.Proof,
            topology:C.Topology,bodyMesh:B.BodyMesh,selfMotion:SelfContactGuard.Prepared,sourceEdges:[SourceEdge],
            initialBodySurface:B.Quality,initialSelfSurface:C.Quality) {
            self.input=input;self.objective=objective;self.settings=settings
            bodyClearanceProof=bodyProof;clothClearanceProof=clothProof
            self.topology=topology;self.bodyMesh=bodyMesh;self.selfMotion=selfMotion;self.sourceEdges=sourceEdges
            self.initialBodySurface=initialBodySurface;self.initialSelfSurface=initialSelfSurface
        }
        /// Create inside the serial detached worker. The mutable numerical
        /// workspace intentionally has no Sendable conformance.
        func makeSession(limits:WorkerLimits=WorkerLimits(),isCancelled:@escaping @Sendable()->Bool={false})throws->Session {
            try Session(prepared:self,limits:limits,isCancelled:isCancelled)
        }
    }

    @MainActor static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,sourceSettings:K.Settings,materials:Materials,
        settings:Settings=Settings(),sourceLimits:GarmentCodeNativeAssembly.Limits = .init(),
        isCancelled:@escaping @Sendable()->Bool={false})throws->Prepared {
        let recipe=try capture(document:document,body:body,design:design,sourceSettings:sourceSettings,materials:materials,
            settings:settings,sourceLimits:sourceLimits,isCancelled:isCancelled)
        return try prepare(recipe:recipe,isCancelled:isCancelled)
    }
    /// Only actor-owned native source/parameters/body-cache work stays here.
    /// Await prepare(recipe:) in a cancellable detached numerical worker.
    @MainActor static func capture(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,sourceSettings:K.Settings,materials:Materials,
        settings:Settings=Settings(),sourceLimits:GarmentCodeNativeAssembly.Limits = .init(),
        isCancelled:@escaping @Sendable()->Bool={false})throws->Recipe {
        if isCancelled(){throw CancellationError()}
        guard (0...1680).contains(settings.maximumAdditionalSteps),materials.bodyContact.minimumDistanceMeters==0.0005,
              materials.selfContact.minimumDistanceMeters==0 else {throw SimulationError.invalid("需要固定时间调度、人体 0.5 mm 与布片 0 最小间隙。")}
        let native=try GarmentCodeNativeAssembly.capture(document:document,body:body,design:design,settings:sourceSettings,
            limits:sourceLimits,initialization:.rigidBodyAndClothPositiveClearance,isCancelled:isCancelled)
        return .init(native:native,materials:materials,settings:settings)
    }
    /// All meshing/refinement, rigid clearance, source validation, contact and
    /// numeric preparation execute on the calling numerical worker.
    static func prepare(recipe:Recipe,isCancelled:@escaping @Sendable()->Bool={false})throws->Prepared {
        let assembly=try GarmentCodeNativeAssembly.build(recipe:recipe.native,isCancelled:isCancelled)
        let materials=recipe.materials,settings=recipe.settings
        let source=assembly.preparedInput
        guard let bodyProof=assembly.bodyClearanceProof,let clothProof=assembly.clothClearanceProof,
              clothProof.positiveGapTargetMeters==GarmentCodeRigidClothClearance.positiveGapTargetMeters,
              !clothProof.nearContactsNotCertifiedAbsent,clothProof.finalInspection.properTrianglePairs==0,
              clothProof.finalInspection.coplanarTrianglePairs==0,clothProof.finalInspection.nearTrianglePairs==0,
              clothProof.samePanelNonAdjacentPrimitivePairsTested != nil,
              source.cloth.pinned.allSatisfy({!$0}) else {throw SimulationError.invalid("需要同源独立自由度与完整正间隙初始化证明。")}
        let input=try GarmentCodeJointInput.prepare(source:source,material:materials.membrane,strainBarrier:materials.strainBarrier,
            bendingMaterial:materials.bending,sewingComplianceMetersPerNewton:materials.sewingComplianceMetersPerNewton,isCancelled:isCancelled)
        let objective=try G.Prepared(input:input,bodyParameters:materials.bodyContact,selfParameters:materials.selfContact,isCancelled:isCancelled)
        _ = try objective.frame(predictor:source.cloth.positions,timeStepSeconds:settings.timeStepSeconds,sewingRamp:0,
                                sewingSchedule:settings.sewingSchedule)
        // No legacy sewn proximity ribbons or face-pair exclusions are supplied.
        let topology=try C.Topology(vertexCount:source.cloth.positions.count,triangleIndices:source.cloth.triangleIndices,isCancelled:isCancelled)
        let bodyMesh=try B.BodyMesh(positions:source.cloth.mannequinPositions,triangleIndices:source.cloth.mannequinTriangleIndices)
        let motion=try SelfContactGuard.Prepared(vertexCount:source.cloth.positions.count,triangleIndices:source.cloth.triangleIndices,isCancelled:isCancelled)
        var keys=Set<UInt64>()
        for i in stride(from:0,to:source.cloth.referenceTriangles.count,by:3) {
            if i%384==0 && isCancelled(){throw CancellationError()}
            let ids=source.cloth.referenceTriangles[i..<i+3].map(Int.init)
            for j in 0..<3 {let a=ids[j],b=ids[(j+1)%3];keys.insert((UInt64(min(a,b))<<32)|UInt64(max(a,b)))}
        }
        let edges=try keys.sorted().map {key->SourceEdge in
            let a=Int(key>>32),b=Int(key&0xffffffff),length=(source.cloth.referencePositions[a]-source.cloth.referencePositions[b]).length
            guard length.isFinite,length>0 else {throw SimulationError.invalid("源边长度无效。")}
            return .init(a:a,b:b,length:length)
        }
        let initialBody=try B.inspect(positions:source.cloth.positions,topology:topology,body:bodyMesh,thickness:0.0005,isCancelled:isCancelled)
        let initialSelf=try C.inspect(positions:source.cloth.positions,topology:topology,thickness:0.0005,maximumCandidatePairs:200_000,isCancelled:isCancelled)
        guard initialBody.intersectingTrianglePairs==0,initialBody.degenerateClothTriangles==0,
              initialSelf.intersectingTrianglePairs==0,initialSelf.degenerateTriangles==0 else {throw SimulationError.invalid("完整初始化的独立表面检查未通过。")}
        if isCancelled(){throw CancellationError()}
        return Prepared(input:input,objective:objective,settings:settings,bodyProof:bodyProof,clothProof:clothProof,
            topology:topology,bodyMesh:bodyMesh,selfMotion:motion,sourceEdges:edges,initialBodySurface:initialBody,initialSelfSurface:initialSelf)
    }

    /// One serial owner; never capture this mutable class across worker tasks.
    final class Session {
        let prepared:Prepared
        let limits:WorkerLimits
        let seedContextIdentity:UUID
        let initialSeedControl:PhysicalSeedControl
        private(set) var committedSeedControl:PhysicalSeedControl
        private let workspace:P.Workspace
        private let sourceMotion:GarmentCodeMembranePath.Prepared
        private(set) var state:State
        private(set) var lastAcceptedFrame:AcceptedFrame?
        /// Only the final bounded stability window is retained. Source arrays
        /// are immutable copy-on-write values, shared between linked records.
        private(set) var consecutiveQuietFrames:[AcceptedFrame]=[]
        fileprivate init(prepared:Prepared,limits:WorkerLimits,isCancelled:@escaping @Sendable()->Bool)throws {
            if isCancelled(){throw CancellationError()}
            guard (1...200_000).contains(limits.maximumSurfaceCandidatePairs),(0...4).contains(limits.maximumPhysicalSubstepDepth),
                  (1...15).contains(limits.maximumPhysicalSubstepAttempts),limits.selfMotion.minimumSeparation==0,
                  limits.selfMotion.distanceTolerance==1e-8,limits.selfMotion.safetyFactor==0.9,
                  limits.selfMotion.maximumIterationsPerFeature==10_000 else {throw SimulationError.invalid("工作区需要完整的原连续碰撞配置与有限预算。")}
            let plan=try P.Plan(prepared:prepared.input.objective,limits:limits.preconditioner,isCancelled:isCancelled)
            workspace=try plan.makeWorkspace(isCancelled:isCancelled)
            sourceMotion=try GarmentCodeMembranePath.Prepared(membrane:prepared.input.objective.membrane,limits:limits.newton.sourcePath)
            self.prepared=prepared;self.limits=limits
            let context=UUID(),ticks=1<<limits.maximumPhysicalSubstepDepth
            let control=PhysicalSeedControl(policyVersion:limits.physicalSeedPolicy.version,contextIdentity:context,
                sourceSHA256:prepared.sourceSHA256,bodyGeometrySHA256:prepared.bodyClearanceProof.bodyGeometrySHA256,
                linearizationSourceIdentity:prepared.input.objective.linearizationSource.identity,
                baseTimeStepSeconds:prepared.settings.timeStepSeconds,maximumDepth:limits.maximumPhysicalSubstepDepth,
                maximumAttempts:limits.maximumPhysicalSubstepAttempts,
                originCompletedStep:0,originAcceptedFrameIdentity:nil,nextSeeds:[.init(startTick:0,endTick:ticks,ticksPerMacroStep:ticks)])
            seedContextIdentity=context;initialSeedControl=control;committedSeedControl=control
            state = .init(completedSteps:0,positions:prepared.initialPositions,
                        velocities:Array(repeating:.zero,count:prepared.initialPositions.count),consecutiveQuietSteps:0)
        }
        private func checkedSeedRoots(before:State,control:PhysicalSeedControl,phase:Phase)throws->[PhysicalSeedSpan] {
            let initial=initialSeedControl,ticks=1<<limits.maximumPhysicalSubstepDepth
            guard control.contextIdentity==seedContextIdentity,control.policyVersion==limits.physicalSeedPolicy.version,
                  control.sourceSHA256==initial.sourceSHA256,control.bodyGeometrySHA256==initial.bodyGeometrySHA256,
                  control.linearizationSourceIdentity==initial.linearizationSourceIdentity,
                  control.baseTimeStepSeconds.bitPattern==initial.baseTimeStepSeconds.bitPattern,
                  control.maximumDepth==initial.maximumDepth,control.maximumAttempts==initial.maximumAttempts else {throw SimulationError.invalid("时间分区与当前工作区来源或配置不符。")}
            if phase == .staticAssembly {
                guard control==initial else {throw SimulationError.invalid("静态装配不能继承物理分区。")}
                return []
            }
            if before.completedSteps==prepared.settings.staticAssemblySteps {
                guard control==initial else {throw SimulationError.invalid("首个物理时间步必须从完整基础时长开始。")}
            } else {
                guard control.originCompletedStep==before.completedSteps,control.originAcceptedFrameIdentity != nil else {
                    throw SimulationError.invalid("时间分区不是上个已提交完整时间步的记录。")
                }
                if let record=lastAcceptedFrame {
                    guard record.identity==control.originAcceptedFrameIdentity,record.acceptedSeedControl==control else {
                        throw SimulationError.invalid("时间分区与上一真实提交记录不一致。")
                    }
                }
            }
            let seeds=control.nextSeeds
            guard !seeds.isEmpty,seeds.count<=ticks,seeds.count<=limits.maximumPhysicalSubstepAttempts else {throw SimulationError.invalid("时间分区数量超出预算。")}
            var cursor=0
            for seed in seeds {
                guard seed.ticksPerMacroStep==ticks,(0...ticks).contains(seed.startTick),(0...ticks).contains(seed.endTick),
                      seed.startTick==cursor,seed.endTick>seed.startTick else {throw SimulationError.invalid("时间分区存在缺口、重叠或越界。")}
                let width=seed.endTick-seed.startTick
                guard width&(width-1)==0,seed.startTick%width==0 else {throw SimulationError.invalid("时间分区必须按二等分网格对齐。")}
                cursor=seed.endTick
            }
            guard cursor==ticks,limits.physicalSeedPolicy != .rootOnly || seeds==initial.nextSeeds else {
                throw SimulationError.invalid("时间分区未覆盖基础时长或与完整时间步策略不符。")
            }
            return seeds
        }
        private struct SolvedSubproblem {
            let report:StepReport
            let positions:[V],velocities:[V],predictor:[V]
            let configuration:[ConfigurationSegment]
            let lastRejectedCandidate:[V]?
            let source:GarmentCodeMembranePath.Report?
            let body:ContinuousBodyContact.Report?,cloth:SelfContactGuard.Report?
        }
        private func solveSubproblem(before:State,index:Int,phase:Phase,startTick:Int,endTick:Int,ticksPerMacroStep:Int,
            isCancelled:@escaping @Sendable()->Bool)throws->SolvedSubproblem {
            if isCancelled(){throw CancellationError()}
            let stamp=ContinuousClock.now,s=prepared.settings
            let ramp=min(1,Double(index)/Double(s.staticAssemblySteps))
            let gravity=min(1,max(0,(Double(index-s.staticAssemblySteps-1)+Double(endTick)/Double(ticksPerMacroStep))/Double(s.gravityRampSteps)))
            let dt=s.timeStepSeconds*Double(endTick-startTick)/Double(ticksPerMacroStep),damping=exp(-s.velocityDampingPerSecond*dt)
            let acceleration=V(x:0,y:-s.gravityMetersPerSecondSquared*gravity,z:0)
            let predictor=phase == .staticAssembly ? before.positions:zip(before.positions,before.velocities).map{$0+$1*(damping*dt)+acceleration*(dt*dt)}
            let frame=try prepared.objective.frame(predictor:predictor,timeStepSeconds:dt,sewingRamp:ramp,sewingSchedule:s.sewingSchedule)
            var path=PathStatistics()
            let mode:N.TrajectoryMode=phase == .staticAssembly ? .configurationPolyline:.physicalLinearStep
            var checkedLines:[(from:[V],to:[V],body:ContinuousBodyContact.Report,cloth:SelfContactGuard.Report)]=[]
            func queryMotion(_ from:[V],_ to:[V])throws->(ContinuousBodyContact.Report,SelfContactGuard.Report,Bool) {
                path.calls+=1
                var tick=ContinuousClock.now
                let body=try self.prepared.objective.body.bodyMotion(from:from,to:to,isCancelled:isCancelled)
                path.bodySeconds+=GarmentCodeJointSimulation.elapsedSeconds(since:tick);path.bodyNativeQueries+=body.statistics.nativeQueries
                path.bodyTrianglePairs+=body.statistics.trianglePairs
                path.bodyEuclideanCertificateAttempts+=body.statistics.euclideanCertificateAttempts
                path.bodyEuclideanCertifiedFeatures+=body.statistics.euclideanCertifiedFeatures
                path.bodyEuclideanCertificateNodes+=body.statistics.euclideanCertificateNodes
                path.bodyEuclideanCertifiedAfterPrecisionLimit+=body.statistics.euclideanCertifiedAfterPrecisionLimit
                if body.statistics.completedAllFeatures {path.completeBodyQueries+=1}
                if body.status == .limited {path.limitedBodyQueries+=1}
                if body.status != .clear {path.rejectedBodyQueries+=1}
                switch body.status {
                case .cancelled:throw CancellationError()
                case .invalid,.budgetExceeded:throw SimulationError.pathFailure("body "+body.status.rawValue)
                default:break
                }
                tick=ContinuousClock.now
                let cloth=self.prepared.selfMotion.guardMotion(previous:from.map(native),candidate:to.map(native),options:self.limits.selfMotion,isCancelled:isCancelled)
                path.selfSeconds+=GarmentCodeJointSimulation.elapsedSeconds(since:tick);path.selfNativeQueries+=cloth.statistics.nativeQueries
                path.selfTrianglePairs+=cloth.statistics.trianglePairs;path.selfCertifiedTriangles+=cloth.statistics.certifiedTriangles
                path.selfCertifiedEdges+=cloth.statistics.certifiedEdges;path.selfAABBPrunedPrimitiveVisits+=cloth.statistics.aabbPrunedPrimitiveVisits
                path.selfEuclideanCertificateAttempts+=cloth.statistics.euclideanCertificateAttempts
                path.selfEuclideanCertifiedFeatures+=cloth.statistics.euclideanCertifiedFeatures
                path.selfEuclideanCertificateNodes+=cloth.statistics.euclideanCertificateNodes
                path.selfEuclideanCertifiedAfterPrecisionLimit+=cloth.statistics.euclideanCertifiedAfterPrecisionLimit
                if cloth.statistics.completedAllFeatures {path.completeSelfQueries+=1}
                if cloth.status == .limited {path.limitedSelfQueries+=1}
                if cloth.status != .clear {path.rejectedSelfQueries+=1}
                switch cloth.status {
                case .cancelled:throw CancellationError()
                case .invalid,.budgetExceeded:throw SimulationError.pathFailure("self "+cloth.status.rawValue)
                default:break
                }
                if isCancelled(){throw CancellationError()}
                let clear=body.permitsWholeCandidate && body.statistics.completedAllFeatures && cloth.permitsWholeCandidate && cloth.statistics.completedAllFeatures && cloth.statistics.completedDomainCertificates
                if clear && mode == .configurationPolyline {checkedLines.append((from,to,body,cloth))}
                return (body,cloth,clear)
            }
            let result=try N.solve(frame:frame,initialPositions:before.positions,preconditioner:workspace,limits:limits.newton,trajectoryMode:mode,pathGuard:{from,to in try queryMotion(from,to).2},isCancelled:isCancelled)
            var configuration:[ConfigurationSegment]=[]
            if mode == .configurationPolyline {
                let indices=try configurationCertificateIndices(initial:before.positions,final:result.positions,
                    trajectory:result.acceptedTrajectory.map{.init(previous:$0.previous,candidate:$0.accepted)},
                    checkedLines:checkedLines.map{.init(previous:$0.from,candidate:$0.to)},isCancelled:isCancelled)
                for (index,segment) in zip(indices,result.acceptedTrajectory) {
                    let line=checkedLines[index]
                    guard segment.sourceMotion.status == .clear,segment.sourceMotion.completedAllTriangles,
                          line.body.permitsWholeCandidate,line.body.statistics.completedAllFeatures,
                          line.cloth.permitsWholeCandidate,line.cloth.statistics.completedAllFeatures,
                          line.cloth.statistics.completedDomainCertificates else {
                        throw SimulationError.invalid("配置轨迹未逐段连接同一完整源。")
                    }
                    configuration.append(.init(previous:line.from,accepted:line.to,sourceMotion:segment.sourceMotion,
                        bodyMotion:line.body,selfMotion:line.cloth))
                }
            } else if !result.acceptedTrajectory.isEmpty {throw SimulationError.invalid("物理时间步不能冒用静态装配轨迹。")}
            let x=result.positions,velocities=zip(x,before.positions).map{($0-$1)/dt}
            let speed=velocities.reduce(0){max($0,$1.length)}
            let strain=prepared.sourceEdges.reduce(0.0){max($0,abs((x[$1.a]-x[$1.b]).length/$1.length-1))}
            let body=try B.inspect(positions:x,topology:prepared.topology,body:prepared.bodyMesh,thickness:0.0005,
                maximumCandidatePairs:limits.maximumSurfaceCandidatePairs,isCancelled:isCancelled)
            let cloth=try C.inspect(positions:x,topology:prepared.topology,thickness:0.0005,
                maximumCandidatePairs:limits.maximumSurfaceCandidatePairs,isCancelled:isCancelled)
            let surfacesClear=body.intersectingTrianglePairs==0 && body.degenerateClothTriangles==0 && cloth.intersectingTrianglePairs==0 && cloth.degenerateTriangles==0
            guard strain.isFinite,speed.isFinite else {throw SimulationError.invalid("子步的源应变或实际速度非有限。")}
            var sourceProof:GarmentCodeMembranePath.Report?,bodyProof:ContinuousBodyContact.Report?,selfProof:SelfContactGuard.Report?
            var completePhysicalPath=phase == .staticAssembly
            if phase != .staticAssembly && result.report.converged && surfacesClear {
                let source=try sourceMotion.certify(from:before.positions,to:x,barrier:prepared.input.objective.strainBarrier,isCancelled:isCancelled)
                if source.status == .budgetExceeded {throw SimulationError.pathFailure("source budgetExceeded")}
                let native=try queryMotion(before.positions,x)
                sourceProof=source;bodyProof=native.0;selfProof=native.1
                completePhysicalPath=source.status == .clear && source.completedAllTriangles && native.2
            }
            let accepted=result.report.converged && surfacesClear && completePhysicalPath
            let e=result.evaluation.body.cloth
            let seamQuality=try GarmentCodeSewing.inspect(positions:x,plan:prepared.input.source.plan,rampFraction:ramp,isCancelled:isCancelled)
            let reason=result.report.converged ? (surfacesClear ? (completePhysicalPath ? nil:"completePhysicalSubstepPath"):"independentSurfaceInspection"):"Newton "+result.report.status.rawValue
            var report=StepReport(accepted:accepted,sourceSHA256:prepared.sourceSHA256,completedStepsBefore:before.completedSteps,
                attemptedStep:index,phase:phase,sewingRamp:ramp,gravityFraction:gravity,
                sewingStiffnessNewtonPerMeter:frame.cloth.sewingStiffnessNewtonPerMeter,
                usesQuadraticSewingContinuation:s.sewingSchedule != .distanceTarget,
                maximumActualSeamGapMeters:seamQuality.maximumMeasuredGapMeters,maximumSewingTargetResidualMeters:e.maximumSewingTargetResidualMeters,
                maximumSourceEdgeRelativeChange:strain,maximumSpeedMetersPerSecond:speed,bodySurface:body,selfSurface:cloth,
                newton:result.report,path:path,trajectoryMode:mode,bodyContactStencils:result.evaluation.body.body.statistics.stencils,
                selfContactStencils:result.evaluation.selfContact.statistics.stencils,bodyContactEnergyJoules:result.evaluation.body.body.energyJoules,
                selfContactEnergyJoules:result.evaluation.selfContact.energyJoules,consecutiveQuietSteps:0,
                numericallyStableCandidate:false,exactVisibleBodyContainmentVerified:false,
                rejectionReason:reason,computationSeconds:GarmentCodeJointSimulation.elapsedSeconds(since:stamp))
            report.continuousSeamQuality=seamQuality.continuousBoundary
            report.maximumAnchorSeamGapMeters=seamQuality.maximumGapMeters
            if isCancelled(){throw CancellationError()}
            if phase != .staticAssembly {
                report.physicalSubstepCount=accepted ? 1:0;report.physicalSubstepAttempts=1
                report.physicalSubdivisionDepth=ticksPerMacroStep.trailingZeroBitCount-(endTick-startTick).trailingZeroBitCount
                report.maximumPhysicalSubstepGradientInfinityNewton=result.report.finalGradientInfinityNewton
            }
            return .init(report:report,positions:x,velocities:velocities,predictor:predictor,configuration:configuration,
                         lastRejectedCandidate:result.lastRejectedCandidate,source:sourceProof,body:bodyProof,cloth:selfProof)
        }
        func advanceStep(isCancelled:@escaping @Sendable()->Bool={false})throws->Attempt {
            if isCancelled(){throw CancellationError()}
            let stamp=ContinuousClock.now,before=state,beforeControl=committedSeedControl,s=prepared.settings,index=before.completedSteps+1
            guard index<=s.maximumSteps else {throw SimulationError.stepBudget}
            let phase:Phase=index<=s.staticAssemblySteps ? .staticAssembly:(index<=s.staticAssemblySteps+s.gravityRampSteps ? .gravityRamp:.settling)
            let dynamic=phase != .staticAssembly,denominator=dynamic ? 1<<limits.maximumPhysicalSubstepDepth:1
            let seeds=try checkedSeedRoots(before:before,control:beforeControl,phase:phase)
            let maximumAttempts=dynamic ? min(limits.maximumPhysicalSubstepAttempts,2*denominator-seeds.count):0
            var attempts:[PhysicalAttempt]=[],ledger:[PhysicalAttemptLedger]=[],leaves:[PhysicalSubstep]=[],path=PathStatistics()
            func solve(_ previous:State,_ first:Int,_ last:Int,_ seedIndex:Int,_ parent:Int?)throws->SolvedSubproblem {
                if isCancelled(){throw CancellationError()}
                if dynamic && attempts.count>=maximumAttempts {
                    throw PhysicalAttemptBudgetExceeded(attemptedStep:index,maximumAttempts:maximumAttempts,
                        pendingSeedIndex:seedIndex,pendingStartTick:first,pendingEndTick:last,ticksPerMacroStep:denominator,
                        attempts:attempts,ledger:ledger)
                }
                let value=try solveSubproblem(before:previous,index:index,phase:phase,startTick:first,endTick:last,
                    ticksPerMacroStep:denominator,isCancelled:isCancelled)
                path.add(value.report.path)
                if dynamic {
                    attempts.append(.init(sourceSHA256:prepared.sourceSHA256,bodyGeometrySHA256:prepared.bodyClearanceProof.bodyGeometrySHA256,
                        previousPositions:previous.positions,previousVelocities:previous.velocities,predictor:value.predictor,
                        candidatePositions:value.positions,lastRejectedNewtonCandidate:value.lastRejectedCandidate,
                        startTick:first,endTick:last,ticksPerMacroStep:denominator,
                        timeStepSeconds:s.timeStepSeconds*Double(last-first)/Double(denominator),
                        sewingRamp:value.report.sewingRamp,gravityFraction:value.report.gravityFraction,report:value.report))
                    ledger.append(.init(seedIndex:seedIndex,parentAttemptIndex:parent,startTick:first,endTick:last,ticksPerMacroStep:denominator,
                        accepted:value.report.accepted,rejectionReason:value.report.rejectionReason,computationSeconds:value.report.computationSeconds))
                }
                return value
            }
            func leaf(_ value:SolvedSubproblem,_ previous:State,_ first:Int,_ last:Int)throws->PhysicalSubstep {
                guard value.report.accepted,let source=value.source,let body=value.body,let cloth=value.cloth,
                      source.status == .clear,source.completedAllTriangles,body.permitsWholeCandidate,body.statistics.completedAllFeatures,
                      cloth.permitsWholeCandidate,cloth.statistics.completedAllFeatures,cloth.statistics.completedDomainCertificates else {
                    throw SimulationError.invalid("物理子步缺少真实完整路径证书。")
                }
                return .init(sourceSHA256:prepared.sourceSHA256,bodyGeometrySHA256:prepared.bodyClearanceProof.bodyGeometrySHA256,
                    previousPositions:previous.positions,previousVelocities:previous.velocities,
                    acceptedPositions:value.positions,acceptedVelocities:value.velocities,predictor:value.predictor,
                    startTick:first,endTick:last,ticksPerMacroStep:denominator,
                    timeStepSeconds:s.timeStepSeconds*Double(last-first)/Double(denominator),
                    sewingRamp:value.report.sewingRamp,gravityFraction:value.report.gravityFraction,report:value.report,
                    sourceMotion:source,bodyMotion:body,selfMotion:cloth)
            }
            func integrate(_ previous:State,_ first:Int,_ end:Int,_ seedIndex:Int,_ parent:Int?)throws->SolvedSubproblem {
                let currentAttempt=attempts.count
                let value=try solve(previous,first,end,seedIndex,parent)
                if value.report.accepted {
                    leaves.append(try leaf(value,previous,first,end))
                    return value
                }
                // Refine only the failed physical interval. Every child starts
                // from its real predecessor's x/v and recomputes inertia/load.
                // Finer resolution never increases the actual solve budget.
                // The guard is before each solve, including inherited roots.
                guard end-first>1 else {return value}
                let middle=(first+end)/2
                let left=try integrate(previous,first,middle,seedIndex,currentAttempt)
                guard left.report.accepted else {return left}
                let provisional=State(completedSteps:before.completedSteps,positions:left.positions,
                    velocities:left.velocities,consecutiveQuietSteps:before.consecutiveQuietSteps)
                return try integrate(provisional,middle,end,seedIndex,currentAttempt)
            }
            let last:SolvedSubproblem
            if dynamic {
                var previous=before,latest:SolvedSubproblem?
                for (seedIndex,seed) in seeds.enumerated() {
                    let value=try integrate(previous,seed.startTick,seed.endTick,seedIndex,nil)
                    latest=value
                    if !value.report.accepted {break}
                    previous=State(completedSteps:before.completedSteps,positions:value.positions,
                        velocities:value.velocities,consecutiveQuietSteps:before.consecutiveQuietSteps)
                }
                guard let latest else {throw SimulationError.invalid("物理时间步缺少真实分区求解。")}
                last=latest
            } else {last=try solve(before,0,denominator,-1,nil)}
            let accepted=last.report.accepted
            if isCancelled(){throw CancellationError()}
            func sameBits(_ a:[V],_ b:[V])->Bool {
                a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern &&
                    $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}
            }
            if accepted && dynamic {
                guard !leaves.isEmpty,leaves.count<=denominator,attempts.count<=maximumAttempts,attempts.count==2*leaves.count-seeds.count,
                      leaves.first!.startTick==0,leaves.last!.endTick==denominator,
                      leaves.allSatisfy({$0.ticksPerMacroStep==denominator}),
                      sameBits(leaves[0].previousPositions,before.positions),sameBits(leaves[0].previousVelocities,before.velocities),
                      sameBits(leaves.last!.acceptedPositions,last.positions),sameBits(leaves.last!.acceptedVelocities,last.velocities),
                      zip(leaves,leaves.dropFirst()).allSatisfy({$0.endTick==$1.startTick &&
                        sameBits($0.acceptedPositions,$1.previousPositions) && sameBits($0.acceptedVelocities,$1.previousVelocities)}) else {
                    throw SimulationError.invalid("完整宏步的真实物理子步未连续覆盖全部时间。")
                }
            }
            let reference=last.report
            let strain=accepted && dynamic ? leaves.map{$0.report.maximumSourceEdgeRelativeChange}.max()!:reference.maximumSourceEdgeRelativeChange
            let gap=accepted && dynamic ? leaves.map{$0.report.maximumActualSeamGapMeters}.max()!:reference.maximumActualSeamGapMeters
            let residual=accepted && dynamic ? leaves.map{$0.report.maximumSewingTargetResidualMeters}.max()!:reference.maximumSewingTargetResidualMeters
            let speed=accepted && dynamic ? leaves.map{$0.report.maximumSpeedMetersPerSecond}.max()!:reference.maximumSpeedMetersPerSecond
            let ramp=min(1,Double(index)/Double(s.staticAssemblySteps)),gravity=min(1,max(0,Double(index-s.staticAssemblySteps)/Double(s.gravityRampSteps)))
            let quiet=accepted && dynamic && leaves.allSatisfy{$0.gravityFraction==1 && $0.sewingRamp==1} &&
                leaves.allSatisfy{$0.report.continuousSeamQuality?.allSourceSeamsCovered == true} &&
                strain<0.08 && gap<0.0005 && speed<0.025
            let quietCount=accepted ? (quiet ? before.consecutiveQuietSteps+1:0):before.consecutiveQuietSteps
            var report=StepReport(accepted:accepted,sourceSHA256:prepared.sourceSHA256,completedStepsBefore:before.completedSteps,
                attemptedStep:index,phase:phase,sewingRamp:ramp,gravityFraction:gravity,
                sewingStiffnessNewtonPerMeter:reference.sewingStiffnessNewtonPerMeter,
                usesQuadraticSewingContinuation:reference.usesQuadraticSewingContinuation,
                maximumActualSeamGapMeters:gap,maximumSewingTargetResidualMeters:residual,
                maximumSourceEdgeRelativeChange:strain,maximumSpeedMetersPerSecond:speed,
                bodySurface:reference.bodySurface,selfSurface:reference.selfSurface,newton:reference.newton,path:path,
                trajectoryMode:reference.trajectoryMode,bodyContactStencils:reference.bodyContactStencils,selfContactStencils:reference.selfContactStencils,
                bodyContactEnergyJoules:reference.bodyContactEnergyJoules,selfContactEnergyJoules:reference.selfContactEnergyJoules,
                consecutiveQuietSteps:quietCount,numericallyStableCandidate:accepted && quietCount>=s.requiredQuietSteps,
                exactVisibleBodyContainmentVerified:false,rejectionReason:reference.rejectionReason,
                computationSeconds:GarmentCodeJointSimulation.elapsedSeconds(since:stamp))
            report.continuousSeamQuality=reference.continuousSeamQuality
            report.maximumAnchorSeamGapMeters=accepted && dynamic ? leaves.compactMap{$0.report.maximumAnchorSeamGapMeters}.max():reference.maximumAnchorSeamGapMeters
            if dynamic {
                report.physicalSubstepCount=accepted ? leaves.count:0;report.physicalSubstepAttempts=attempts.count
                report.physicalSubdivisionDepth=attempts.map{$0.ticksPerMacroStep.trailingZeroBitCount-($0.endTick-$0.startTick).trailingZeroBitCount}.max() ?? 0
                report.maximumPhysicalSubstepGradientInfinityNewton=accepted ? leaves.map{$0.report.newton.finalGradientInfinityNewton}.max():attempts.map{$0.report.newton.finalGradientInfinityNewton}.max()
                report.seedPolicyVersion=beforeControl.policyVersion;report.physicalSeedRootCount=seeds.count
                report.seedOriginStep=beforeControl.originCompletedStep
                report.seedReused=limits.physicalSeedPolicy == .committedPartition && beforeControl.originCompletedStep>0
                report.usedPhysicalSeeds=seeds
            }
            if isCancelled(){throw CancellationError()}
            // Atomic outer commit: all provisional leaves stay private if any
            // later interval fails, cancels or cannot finish every check.
            if accepted {
                let identity=UUID()
                let next=State(completedSteps:index,positions:last.positions,
                    velocities:dynamic ? last.velocities:Array(repeating:.zero,count:last.positions.count),consecutiveQuietSteps:quietCount)
                let nextSeeds=limits.physicalSeedPolicy == .committedPartition ? leaves.map {
                    PhysicalSeedSpan(startTick:$0.startTick,endTick:$0.endTick,ticksPerMacroStep:$0.ticksPerMacroStep)
                }:initialSeedControl.nextSeeds
                let nextControl=dynamic ? PhysicalSeedControl(policyVersion:beforeControl.policyVersion,contextIdentity:seedContextIdentity,
                    sourceSHA256:beforeControl.sourceSHA256,bodyGeometrySHA256:beforeControl.bodyGeometrySHA256,
                    linearizationSourceIdentity:beforeControl.linearizationSourceIdentity,baseTimeStepSeconds:beforeControl.baseTimeStepSeconds,
                    maximumDepth:beforeControl.maximumDepth,maximumAttempts:beforeControl.maximumAttempts,
                    originCompletedStep:index,originAcceptedFrameIdentity:identity,nextSeeds:nextSeeds):beforeControl
                let record=AcceptedFrame(identity:identity,sourceSHA256:prepared.sourceSHA256,bodyGeometrySHA256:prepared.bodyClearanceProof.bodyGeometrySHA256,
                    previous:before,accepted:next,predictor:last.predictor,report:report,
                    configurationSegments:dynamic ? []:last.configuration,physicalSubsteps:leaves,
                    previousSeedControl:beforeControl,usedPhysicalSeeds:seeds,acceptedSeedControl:nextControl,physicalAttemptLedger:ledger)
                if quiet {
                    consecutiveQuietFrames.append(record)
                    if consecutiveQuietFrames.count>s.requiredQuietSteps {consecutiveQuietFrames.removeFirst()}
                } else {consecutiveQuietFrames=[]}
                lastAcceptedFrame=record;state=next;committedSeedControl=nextControl
            }
            var attempt=Attempt(report:report,candidatePositions:last.positions,lastRejectedNewtonCandidate:last.lastRejectedCandidate)
            attempt.physicalAttempts=attempts
            attempt.physicalAttemptLedger=ledger
            return attempt
        }

    }
    /// Generation accounting uses a monotonic clock so system time changes
    /// cannot inflate a step, create negative costs or invalidate final timing.
    static func elapsedSeconds(since start:ContinuousClock.Instant)->Double {
        let parts=start.duration(to:ContinuousClock.now).components
        return Double(parts.seconds)+Double(parts.attoseconds)/1e18
    }
    private static func native(_ p:V)->SIMD3<Double>{SIMD3(p.x,p.y,p.z)}
}

// Additive physical-journal metadata remains compatible with historical JSON.
// An old report alone never qualifies a new physical substep capability.
extension GarmentCodeJointSimulation.StepReport {
    nonisolated init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        accepted=try c.decode(Bool.self,forKey:.accepted)
        sourceSHA256=try c.decode(String.self,forKey:.sourceSHA256)
        completedStepsBefore=try c.decode(Int.self,forKey:.completedStepsBefore)
        attemptedStep=try c.decode(Int.self,forKey:.attemptedStep)
        phase=try c.decode(GarmentCodeJointSimulation.Phase.self,forKey:.phase)
        sewingRamp=try c.decode(Double.self,forKey:.sewingRamp)
        gravityFraction=try c.decode(Double.self,forKey:.gravityFraction)
        sewingStiffnessNewtonPerMeter=try c.decode(Double.self,forKey:.sewingStiffnessNewtonPerMeter)
        usesQuadraticSewingContinuation=try c.decode(Bool.self,forKey:.usesQuadraticSewingContinuation)
        maximumActualSeamGapMeters=try c.decode(Double.self,forKey:.maximumActualSeamGapMeters)
        maximumSewingTargetResidualMeters=try c.decode(Double.self,forKey:.maximumSewingTargetResidualMeters)
        maximumSourceEdgeRelativeChange=try c.decode(Double.self,forKey:.maximumSourceEdgeRelativeChange)
        maximumSpeedMetersPerSecond=try c.decode(Double.self,forKey:.maximumSpeedMetersPerSecond)
        bodySurface=try c.decode(GarmentCodeJointSimulation.B.Quality.self,forKey:.bodySurface)
        selfSurface=try c.decode(GarmentCodeJointSimulation.C.Quality.self,forKey:.selfSurface)
        newton=try c.decode(GarmentCodeJointSimulation.N.Report.self,forKey:.newton)
        path=try c.decode(GarmentCodeJointSimulation.PathStatistics.self,forKey:.path)
        trajectoryMode=try c.decode(GarmentCodeJointSimulation.N.TrajectoryMode.self,forKey:.trajectoryMode)
        bodyContactStencils=try c.decode(Int.self,forKey:.bodyContactStencils)
        selfContactStencils=try c.decode(Int.self,forKey:.selfContactStencils)
        bodyContactEnergyJoules=try c.decode(Double.self,forKey:.bodyContactEnergyJoules)
        selfContactEnergyJoules=try c.decode(Double.self,forKey:.selfContactEnergyJoules)
        consecutiveQuietSteps=try c.decode(Int.self,forKey:.consecutiveQuietSteps)
        numericallyStableCandidate=try c.decode(Bool.self,forKey:.numericallyStableCandidate)
        exactVisibleBodyContainmentVerified=try c.decode(Bool.self,forKey:.exactVisibleBodyContainmentVerified)
        rejectionReason=try c.decodeIfPresent(String.self,forKey:.rejectionReason)
        computationSeconds=try c.decode(Double.self,forKey:.computationSeconds)
        physicalSubstepCount=try c.decodeIfPresent(Int.self,forKey:.physicalSubstepCount) ?? 0
        physicalSubstepAttempts=try c.decodeIfPresent(Int.self,forKey:.physicalSubstepAttempts) ?? 0
        physicalSubdivisionDepth=try c.decodeIfPresent(Int.self,forKey:.physicalSubdivisionDepth) ?? 0
        maximumPhysicalSubstepGradientInfinityNewton=try c.decodeIfPresent(Double.self,forKey:.maximumPhysicalSubstepGradientInfinityNewton)
        seedPolicyVersion=try c.decodeIfPresent(String.self,forKey:.seedPolicyVersion)
        physicalSeedRootCount=try c.decodeIfPresent(Int.self,forKey:.physicalSeedRootCount)
        seedOriginStep=try c.decodeIfPresent(Int.self,forKey:.seedOriginStep)
        seedReused=try c.decodeIfPresent(Bool.self,forKey:.seedReused)
        usedPhysicalSeeds=try c.decodeIfPresent([GarmentCodeJointSimulation.PhysicalSeedSpan].self,forKey:.usedPhysicalSeeds)
        continuousSeamQuality=try c.decodeIfPresent(GarmentCodeSewing.ContinuousBoundaryQuality.self,forKey:.continuousSeamQuality)
        maximumAnchorSeamGapMeters=try c.decodeIfPresent(Double.self,forKey:.maximumAnchorSeamGapMeters)
    }
}
