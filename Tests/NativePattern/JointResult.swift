import Foundation
import NativeClothCollision

@main @MainActor struct JointResultRegression {
    typealias S=GarmentCodeJointSimulation
    typealias R=GarmentCodeJointResult
    typealias V=S.V
    enum Failure:Error {case failed(String)}
    nonisolated final class Counter:@unchecked Sendable {
        private let lock=NSLock();private var calls=0
        func cancelled()->Bool {lock.lock();defer{lock.unlock()};calls+=1;return calls>=100}
    }
    nonisolated static func require(_ v:Bool,_ s:String)throws {if !v {throw Failure.failed(s)}}
    nonisolated static func write<T:Encodable>(_ x:T,_ url:URL)throws {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];try e.encode(x).write(to:url,options:.atomic)}
    nonisolated static func journalEqual(_ a:S.AcceptedFrame?,_ b:S.AcceptedFrame?)->Bool {
        switch (a,b) {
        case (nil,nil):return true
        case let (a?,b?):return a.identity==b.identity && a.sourceSHA256==b.sourceSHA256 && a.bodyGeometrySHA256==b.bodyGeometrySHA256 &&
            a.previousSeedControl==b.previousSeedControl && a.acceptedSeedControl==b.acceptedSeedControl &&
            a.usedPhysicalSeeds==b.usedPhysicalSeeds && a.physicalAttemptLedger==b.physicalAttemptLedger &&
            a.previous==b.previous && a.accepted==b.accepted && a.predictor==b.predictor && a.report.attemptedStep==b.report.attemptedStep
            && a.configurationSegments.count==b.configurationSegments.count && zip(a.configurationSegments,b.configurationSegments).allSatisfy{
                $0.previous==$1.previous && $0.accepted==$1.accepted && $0.sourceMotion.status==$1.sourceMotion.status &&
                $0.bodyMotion.status==$1.bodyMotion.status && $0.selfMotion.status==$1.selfMotion.status
            }
            && a.physicalSubsteps.count==b.physicalSubsteps.count && zip(a.physicalSubsteps,b.physicalSubsteps).allSatisfy{
                $0.previousPositions==$1.previousPositions && $0.previousVelocities==$1.previousVelocities &&
                $0.acceptedPositions==$1.acceptedPositions && $0.acceptedVelocities==$1.acceptedVelocities &&
                $0.predictor==$1.predictor && $0.startTick==$1.startTick && $0.endTick==$1.endTick &&
                $0.ticksPerMacroStep==$1.ticksPerMacroStep && $0.timeStepSeconds==$1.timeStepSeconds &&
                $0.sourceMotion.status==$1.sourceMotion.status && $0.bodyMotion.status==$1.bodyMotion.status &&
                $0.selfMotion.status==$1.selfMotion.status
            }
        default:return false
        }
    }
    nonisolated static func exercise(_ prepared:R.Prepared,other:R.Prepared,output:URL)throws->[String:Bool] {
        let p=prepared.simulation,session=try p.makeSession(),initial=session.state,initialControl=session.committedSeedControl
        for depth in [-1,5,Int.max] {
            var invalid=S.WorkerLimits();invalid.maximumPhysicalSubstepDepth=depth
            do {_ = try p.makeSession(limits:invalid);throw Failure.failed("Invalid physical subdivision depth accepted")}
            catch S.SimulationError.invalid{}
        }
        for budget in [0,16,Int.max] {
            var invalid=S.WorkerLimits();invalid.maximumPhysicalSubstepAttempts=budget
            do {_ = try p.makeSession(limits:invalid);throw Failure.failed("Invalid physical attempt budget accepted")}
            catch S.SimulationError.invalid{}
        }
        try require(session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.isEmpty,"Fresh session has journal")
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:0);throw Failure.failed("Fresh state produced Validated")}
        catch R.ValidationError.missingAcceptedFrame{}
        do {_ = try prepared.inspectLastAcceptedFrame(session:session);throw Failure.failed("Missing real frame was synthesized")}
        catch R.ValidationError.missingAcceptedFrame{}
        do {_ = try other.validate(session:session,acceptedStepComputationSeconds:0);throw Failure.failed("Same paper, different mesh instance accepted")}
        catch R.ValidationError.foreignPrepared{}
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:Double.nan);throw Failure.failed("Nonfinite timing accepted")}
        catch R.ValidationError.invalidTiming{}
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:-1);throw Failure.failed("Negative timing accepted")}
        catch R.ValidationError.invalidTiming{}
        do {_ = try session.advanceStep(isCancelled:{true});throw Failure.failed("Early cancellation ignored")}
        catch is CancellationError{}
        try require(session.state==initial && session.committedSeedControl==initialControl && session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.isEmpty,"Early cancellation changed state/control/journal")
        let counter=Counter()
        do {_ = try session.advanceStep(isCancelled:{counter.cancelled()});throw Failure.failed("Mid-step cancellation ignored")}
        catch is CancellationError{}
        try require(session.state==initial && session.committedSeedControl==initialControl && session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.isEmpty,"Mid-step cancellation changed state/control/journal")
        var tiny=S.WorkerLimits();tiny.selfMotion.limits.maximumCertificateNodes=1
        let rejected=try p.makeSession(limits:tiny),rejectedInitial=rejected.state,rejectedControl=rejected.committedSeedControl
        do {_ = try rejected.advanceStep();throw Failure.failed("Forced complete-path budget did not reject")}
        catch S.SimulationError.pathFailure(let detail) {try require(detail=="self budgetExceeded","Unexpected forced failure "+detail)}
        try require(rejected.state==rejectedInitial && rejected.committedSeedControl==rejectedControl && rejected.lastAcceptedFrame==nil && rejected.consecutiveQuietFrames.isEmpty,"Budget failure committed state/control/journal")
        let before=session.state,attempt=try session.advanceStep()
        try require(attempt.report.accepted,"Actual first complete-source step did not accept: "+(attempt.report.rejectionReason ?? "unknown"))
        guard let record=session.lastAcceptedFrame else {throw Failure.failed("Accepted state missing real journal")}
        try require(record.previous==before && record.accepted==session.state && record.accepted.positions==attempt.candidatePositions,"Journal chain mismatch")
        try require(record.sourceSHA256==p.sourceSHA256 && record.bodyGeometrySHA256==p.bodyClearanceProof.bodyGeometrySHA256,"Journal source/body mismatch")
        try require(record.predictor==before.positions && record.report.phase == .staticAssembly,"Static first predictor mismatch")
        try require(record.physicalSubsteps.isEmpty && attempt.physicalAttempts.isEmpty &&
            record.report.physicalSubstepCount==0,"Static assembly cannot acquire physical time substeps")
        try require(record.previousSeedControl==initialControl && record.acceptedSeedControl==initialControl &&
            session.committedSeedControl==initialControl && record.usedPhysicalSeeds.isEmpty && record.physicalAttemptLedger.isEmpty &&
            record.report.seedPolicyVersion==nil && record.report.physicalSeedRootCount==nil,"Static assembly changed physical controller")
        try require(record.report.trajectoryMode == .configurationPolyline && record.report.newton.trajectoryMode == .configurationPolyline,
            "Static assembly must explicitly record configuration homotopy")
        try require(record.configurationSegments.count==record.report.newton.history.count && !record.configurationSegments.isEmpty,"Real configuration segment count")
        var previous=record.previous.positions
        for segment in record.configurationSegments {
            try require(segment.previous==previous && segment.sourceMotion.completedAllTriangles &&
                segment.bodyMotion.permitsWholeCandidate && segment.bodyMotion.statistics.completedAllFeatures &&
                segment.selfMotion.permitsWholeCandidate && segment.selfMotion.statistics.completedAllFeatures && segment.selfMotion.statistics.completedDomainCertificates,
                "Actual source/body/self segment chain")
            previous=segment.accepted
        }
        try require(previous==record.accepted.positions,"Actual configuration trajectory tail")
        let frame=try p.objective.frame(predictor:record.predictor,timeStepSeconds:p.settings.timeStepSeconds,sewingRamp:record.report.sewingRamp,sewingSchedule:p.settings.sewingSchedule)
        let fresh=try frame.evaluate(positions:record.accepted.positions)
        let g=fresh.gradientNewton.reduce(0){max($0,abs($1.x),abs($1.y),abs($1.z))}
        try require(abs(g-record.report.newton.finalGradientInfinityNewton)<=max(1e-14,abs(g)*1e-10),"Journal predictor force/report mismatch")
        let inspection=try prepared.inspectLastAcceptedFrame(session:session)
        try write(inspection,output.appendingPathComponent("fresh-accepted-frame-inspection.json"))
        try write(record.report,output.appendingPathComponent("actual-step-report.json"))
        try require(inspection.meetsFreshEquilibrium,"Fresh current-P and force KKT not satisfied")
        try require(inspection.actualTrajectoryMode == .configurationPolyline && inspection.segmentCount==record.configurationSegments.count,
            "Fresh inspector must use actual configuration segments")
        try require(inspection.sourceMotions.count==inspection.segmentCount && inspection.bodyMotions.count==inspection.segmentCount && inspection.selfMotions.count==inspection.segmentCount &&
            inspection.sourceMotions.allSatisfy(\.completedAllTriangles) && inspection.bodyMotions.allSatisfy(\.completedAllFeatures) &&
            inspection.selfMotions.allSatisfy({$0.completedAllFeatures && $0.completedDomainCertificates==true}),"Fresh per-segment complete path absent")
        try require(inspection.maximumPhysicalSpeedMetersPerSecond==nil && inspection.maximumConfigurationChangeRateMetersPerSecond != nil,
            "Static proximal change rate must not become physical speed")
        try require(inspection.gravityFraction==0 && inspection.sewingRamp<1 && !inspection.meetsQuietScalarGates,"Early prefix misclassified quiet")
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:0);throw Failure.failed("Early real prefix produced Validated")}
        catch R.ValidationError.insufficientQuietFrames{}
        var bad=R.Limits();bad.maximumSurfaceCandidatePairs=0
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:0,limits:bad);throw Failure.failed("Invalid budget accepted")}
        catch R.ValidationError.invalidBudget{}
        let state=session.state,saved=session.lastAcceptedFrame,window=session.consecutiveQuietFrames,control=session.committedSeedControl
        do {_ = try prepared.validate(session:session,acceptedStepComputationSeconds:0,isCancelled:{true});throw Failure.failed("Validation cancellation ignored")}
        catch is CancellationError{}
        let deepCancel=Counter()
        do {_ = try prepared.inspectLastAcceptedFrame(session:session,isCancelled:{deepCancel.cancelled()});throw Failure.failed("Fresh-inspection cancellation ignored")}
        catch is CancellationError{}
        do {_ = try session.advanceStep(isCancelled:{true});throw Failure.failed("Post-accept advance cancellation ignored")}
        catch is CancellationError{}
        try require(session.state==state && session.committedSeedControl==control && journalEqual(saved,session.lastAcceptedFrame) && session.consecutiveQuietFrames.count==window.count,"Post-accept cancellation changed state/control/journal")
        for (a,b) in zip(window,session.consecutiveQuietFrames) {try require(journalEqual(a,b),"Quiet window changed")}
        try require(prepared.seamGroupIDs==p.input.source.cloth.seamPaths.indices.map{$0/2},"Source stitch path colors not paired")
        return ["initialNoJournal":true,"earlyAndMidCancellationAtomic":true,"pathBudgetRejectionAtomic":true,
            "samePaperDifferentMeshRejected":true,"invalidPhysicalSubdivisionDepthRejected":true,"actualFirstStepAccepted":true,"actualJournalChainAndPredictorVerified":true,
            "freshForceMatchesRecordedPredictor":true,"freshForceAndCurrentPCorrectionKKT":true,"freshCompleteSourceBodySelfPaths":true,
            "actualConfigurationTrajectoryChain":true,"freshEveryConfigurationSegment":true,"staticRateIsNotPhysicalSpeed":true,
            "earlyPrefixNotValidated":true,"postAcceptCancellationJournalAtomic":true,"sourceStitchPathPairing":true,
            "noFabricatedStableState":true,"completeGarmentAccepted":false,"outputProduced":false]
    }
    nonisolated struct StateArchive:Codable {
        let completedSteps:Int,consecutiveQuietSteps:Int
        let positions:[V],velocities:[V]
        init(_ s:S.State){completedSteps=s.completedSteps;consecutiveQuietSteps=s.consecutiveQuietSteps;positions=s.positions;velocities=s.velocities}
    }
    nonisolated struct JournalArchive:Codable {
        let identity:UUID
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previous:StateArchive,accepted:StateArchive,predictor:[V],report:S.StepReport
        let configurationSegments:[ConfigurationArchive]
        let physicalSubsteps:[PhysicalSubstepArchive]
        let previousSeedControl:S.PhysicalSeedControl,usedPhysicalSeeds:[S.PhysicalSeedSpan],acceptedSeedControl:S.PhysicalSeedControl
        let physicalAttemptLedger:[S.PhysicalAttemptLedger]
        init(_ r:S.AcceptedFrame){identity=r.identity;sourceSHA256=r.sourceSHA256;bodyGeometrySHA256=r.bodyGeometrySHA256;previous=StateArchive(r.previous);accepted=StateArchive(r.accepted);predictor=r.predictor;report=r.report;configurationSegments=r.configurationSegments.map(ConfigurationArchive.init);physicalSubsteps=r.physicalSubsteps.map(PhysicalSubstepArchive.init);previousSeedControl=r.previousSeedControl;usedPhysicalSeeds=r.usedPhysicalSeeds;acceptedSeedControl=r.acceptedSeedControl;physicalAttemptLedger=r.physicalAttemptLedger}
    }
    /// Every leaf carries its own physical clock, predictor and velocities.
    /// These records must not be reconstructed from the macrostep's chord.
    nonisolated struct PhysicalSubstepArchive:Codable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V]
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:S.StepReport
        let sourceMotion:GarmentCodeMembranePath.Report
        let bodyMotion:R.MotionProof,selfMotion:R.MotionProof
        init(_ r:S.PhysicalSubstep) {
            sourceSHA256=r.sourceSHA256;bodyGeometrySHA256=r.bodyGeometrySHA256
            previousPositions=r.previousPositions;previousVelocities=r.previousVelocities
            acceptedPositions=r.acceptedPositions;acceptedVelocities=r.acceptedVelocities;predictor=r.predictor
            startTick=r.startTick;endTick=r.endTick;ticksPerMacroStep=r.ticksPerMacroStep
            timeStepSeconds=r.timeStepSeconds;sewingRamp=r.sewingRamp;gravityFraction=r.gravityFraction;report=r.report
            sourceMotion=r.sourceMotion
            let b=r.bodyMotion,c=r.selfMotion
            bodyMotion = .init(status:b.status.rawValue,safeTime:b.safeTime,minimumSeparationMeters:b.minimumSeparation,
                completedAllFeatures:b.statistics.completedAllFeatures,completedDomainCertificates:nil,nativeQueries:b.statistics.nativeQueries,
                trianglePairs:b.statistics.trianglePairs,euclideanCertificateAttempts:b.statistics.euclideanCertificateAttempts,
                euclideanCertifiedFeatures:b.statistics.euclideanCertifiedFeatures,euclideanCertificateNodes:b.statistics.euclideanCertificateNodes,
                euclideanCertifiedAfterPrecisionLimit:b.statistics.euclideanCertifiedAfterPrecisionLimit)
            selfMotion = .init(status:c.status.rawValue,safeTime:c.safeTime,minimumSeparationMeters:c.minimumSeparation,
                completedAllFeatures:c.statistics.completedAllFeatures,completedDomainCertificates:c.statistics.completedDomainCertificates,
                nativeQueries:c.statistics.nativeQueries,trianglePairs:c.statistics.trianglePairs,
                euclideanCertificateAttempts:c.statistics.euclideanCertificateAttempts,
                euclideanCertifiedFeatures:c.statistics.euclideanCertifiedFeatures,euclideanCertificateNodes:c.statistics.euclideanCertificateNodes,
                euclideanCertifiedAfterPrecisionLimit:c.statistics.euclideanCertifiedAfterPrecisionLimit)
        }
    }
    /// Attempted parent paths are diagnostic only and are stored separately
    /// from the actual accepted leaf trajectory.
    nonisolated struct PhysicalAttemptArchive:Codable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],predictor:[V],candidatePositions:[V]
        let lastRejectedNewtonCandidate:[V]?
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:S.StepReport
        init(_ r:S.PhysicalAttempt) {
            sourceSHA256=r.sourceSHA256;bodyGeometrySHA256=r.bodyGeometrySHA256
            previousPositions=r.previousPositions;previousVelocities=r.previousVelocities;predictor=r.predictor
            candidatePositions=r.candidatePositions;lastRejectedNewtonCandidate=r.lastRejectedNewtonCandidate
            startTick=r.startTick;endTick=r.endTick;ticksPerMacroStep=r.ticksPerMacroStep
            timeStepSeconds=r.timeStepSeconds;sewingRamp=r.sewingRamp;gravityFraction=r.gravityFraction;report=r.report
        }
    }
    /// Previous endpoint is the outer record's previous state for the first
    /// segment, then the preceding accepted endpoint. Nothing is skipped.
    nonisolated struct ConfigurationArchive:Codable {
        let accepted:[[Double]]
        let sourceMotion:GarmentCodeMembranePath.Report
        let bodyMotion:R.MotionProof,selfMotion:R.MotionProof
        init(_ r:S.ConfigurationSegment) {
            accepted=r.accepted.map{[$0.x,$0.y,$0.z]};sourceMotion=r.sourceMotion
            let b=r.bodyMotion,c=r.selfMotion
            bodyMotion = .init(status:b.status.rawValue,safeTime:b.safeTime,minimumSeparationMeters:b.minimumSeparation,
                completedAllFeatures:b.statistics.completedAllFeatures,completedDomainCertificates:nil,nativeQueries:b.statistics.nativeQueries,
                trianglePairs:b.statistics.trianglePairs,euclideanCertificateAttempts:b.statistics.euclideanCertificateAttempts,
                euclideanCertifiedFeatures:b.statistics.euclideanCertifiedFeatures,euclideanCertificateNodes:b.statistics.euclideanCertificateNodes,
                euclideanCertifiedAfterPrecisionLimit:b.statistics.euclideanCertifiedAfterPrecisionLimit)
            selfMotion = .init(status:c.status.rawValue,safeTime:c.safeTime,minimumSeparationMeters:c.minimumSeparation,
                completedAllFeatures:c.statistics.completedAllFeatures,completedDomainCertificates:c.statistics.completedDomainCertificates,
                nativeQueries:c.statistics.nativeQueries,trianglePairs:c.statistics.trianglePairs,
                euclideanCertificateAttempts:c.statistics.euclideanCertificateAttempts,
                euclideanCertifiedFeatures:c.statistics.euclideanCertifiedFeatures,
                euclideanCertificateNodes:c.statistics.euclideanCertificateNodes,
                euclideanCertifiedAfterPrecisionLimit:c.statistics.euclideanCertifiedAfterPrecisionLimit)
        }
    }
    nonisolated struct TrajectoryArchive:Codable {
        let schemaVersion:Int
        let identity:UUID
        let step:Int,sourceSHA256:String,bodyGeometrySHA256:String
        let actualTrajectoryMode:S.N.TrajectoryMode
        let previousPositions:[[Double]],physicalAcceptedPositions:[[Double]]?
        let configurationSegments:[ConfigurationArchive]
        let physicalSubsteps:[PhysicalSubstepArchive]
        let previousSeedControl:S.PhysicalSeedControl,usedPhysicalSeeds:[S.PhysicalSeedSpan],acceptedSeedControl:S.PhysicalSeedControl
        let physicalAttemptLedger:[S.PhysicalAttemptLedger]
        init(_ r:S.AcceptedFrame) {
            schemaVersion=3;identity=r.identity
            step=r.accepted.completedSteps;sourceSHA256=r.sourceSHA256;bodyGeometrySHA256=r.bodyGeometrySHA256
            actualTrajectoryMode=r.report.trajectoryMode;previousPositions=r.previous.positions.map{[$0.x,$0.y,$0.z]}
            // The legacy endpoint field denotes a single actual chord only.
            physicalAcceptedPositions=r.physicalSubsteps.count==1 ? r.accepted.positions.map{[$0.x,$0.y,$0.z]}:nil
            configurationSegments=r.configurationSegments.map(ConfigurationArchive.init)
            physicalSubsteps=r.physicalSubsteps.map(PhysicalSubstepArchive.init)
            previousSeedControl=r.previousSeedControl;usedPhysicalSeeds=r.usedPhysicalSeeds
            acceptedSeedControl=r.acceptedSeedControl;physicalAttemptLedger=r.physicalAttemptLedger
        }
    }
    nonisolated struct SourceArchive:Codable {
        let sourceSHA256:String,linearizationSourceIdentity:UUID
        let positions:[V],referencePositions:[V],triangleIndices:[UInt32],referenceTriangles:[UInt32],massesKg:[Double]
        let referenceToSimulation:[Int],pinMask:[Bool],panelGroups:[S.K.PanelGroup]
        let bodyPositions:[V],bodyTriangleIndices:[UInt32]
        let bodyClearanceProof:GarmentCodeRigidBodyClearance.Proof,clothClearanceProof:GarmentCodeRigidClothClearance.Proof
        init(_ p:S.Prepared) {
            let c=p.input.source.cloth
            sourceSHA256=p.sourceSHA256;linearizationSourceIdentity=p.input.objective.linearizationSource.identity
            positions=c.positions;referencePositions=c.referencePositions;triangleIndices=c.triangleIndices
            referenceTriangles=c.referenceTriangles;massesKg=p.input.objective.massesKg
            referenceToSimulation=c.referenceToSimulation;pinMask=c.pinned
            panelGroups=p.input.source.panelBindings.map{.init(panelID:$0.mesh.panelID,vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs)}
            bodyPositions=c.mannequinPositions;bodyTriangleIndices=c.mannequinTriangleIndices
            bodyClearanceProof=p.bodyClearanceProof;clothClearanceProof=p.clothClearanceProof
        }
    }
    nonisolated struct LongSummary:Codable {
        let mode:String,sourceSHA256:String,bodyGeometrySHA256:String,linearizationSourceIdentity:UUID
        let requestedSteps:Int,attemptedStep:Int,actualCompletedSteps:Int,assemblyIterations:Int
        let dynamicSimulatedSeconds:Double,trajectoryContract:String
        let physicalSeedPolicyVersion:String
        let stopReason:String,failure:String?
        let numericallyStableCandidateReached:Bool,resultAccepted:Bool,outputProduced:Bool
        let acceptedStepComputationSeconds:Double,totalWorkerWallSeconds:Double,validationSeconds:Double?
        let lastStep:S.StepReport?
        let fixed480And240IterationScheduleUnchanged:Bool,noSkippedSteps:Bool,noFabricatedStableStates:Bool
    }
    /// This mode has no artificial state loader: each actual frame starts at
    /// the preceding accepted state, from the complete native initial input.
    nonisolated static func simulate(_ receipt:R.Prepared,output:URL,steps:Int)throws->LongSummary {
        let p=receipt.simulation,session=try p.makeSession(),start=ContinuousClock.now
        try require((1...p.settings.maximumSteps).contains(steps),"Requested bounded original steps")
        var acceptedSeconds=0.0,attempted=0,reason="requestedPrefixEnded",failure:String?
        var stable=false,resultAccepted=false,validationSeconds:Double?,last:S.StepReport?
        try write(StateArchive(session.state),output.appendingPathComponent("initial-state.json"))
        try write(session.committedSeedControl,output.appendingPathComponent("initial-seed-control.json"))
        for index in 1...steps {
            let before=session.state,beforeControl=session.committedSeedControl
            let beforeFrame=session.lastAcceptedFrame,beforeQuiet=session.consecutiveQuietFrames.map(\.identity)
            attempted=index
            let attempt:S.Attempt
            do {attempt=try session.advanceStep()}
            catch let exhausted as S.PhysicalAttemptBudgetExceeded {
                try require(session.state==before && session.committedSeedControl==beforeControl &&
                    journalEqual(session.lastAcceptedFrame,beforeFrame) && session.consecutiveQuietFrames.map(\.identity)==beforeQuiet,
                    "Budget failure changed accepted state/control/frame/quiet window")
                reason="physicalAttemptBudget";failure=exhausted.localizedDescription;last=nil
                try write(exhausted.attempts.map(PhysicalAttemptArchive.init),
                    output.appendingPathComponent(String(format:"physical-attempts-%04d.json",index)))
                try write(exhausted.ledger,output.appendingPathComponent(String(format:"physical-ledger-%04d.json",index)))
                try write(["attemptedStep":index,"maximumAttempts":exhausted.maximumAttempts,
                    "actualAttempts":exhausted.attempts.count,"pendingSeedIndex":exhausted.pendingSeedIndex,
                    "pendingStartTick":exhausted.pendingStartTick,"pendingEndTick":exhausted.pendingEndTick,
                    "ticksPerMacroStep":exhausted.ticksPerMacroStep],output.appendingPathComponent("physical-attempt-budget.json"))
                try write(["step":String(index),"failure":failure!],output.appendingPathComponent("step-error.json"))
                break
            }
            catch {
                try require(session.state==before && session.committedSeedControl==beforeControl,"Thrown solve changed accepted state/control")
                reason="stepThrew";failure=String(describing:error);last=nil
                try write(["step":String(index),"failure":failure!],output.appendingPathComponent("step-error.json"))
                break
            }
            last=attempt.report
            try write(attempt.report,output.appendingPathComponent(String(format:"step-%04d.json",index)))
            if attempt.physicalAttempts.count>1 || (!attempt.report.accepted && !attempt.physicalAttempts.isEmpty) {
                try write(attempt.physicalAttempts.map(PhysicalAttemptArchive.init),
                    output.appendingPathComponent(String(format:"physical-attempts-%04d.json",index)))
            }
            if !attempt.physicalAttemptLedger.isEmpty {
                try write(attempt.physicalAttemptLedger,output.appendingPathComponent(String(format:"physical-ledger-%04d.json",index)))
            }
            if !attempt.report.accepted {
                try require(session.state==before && session.committedSeedControl==beforeControl,"Rejected solve committed state/control")
                reason="stepRejected";failure=attempt.report.rejectionReason ?? "unaccepted"
                try write(attempt.candidatePositions,output.appendingPathComponent("uncommitted-candidate-positions.json"))
                if let x=attempt.lastRejectedNewtonCandidate {try write(x,output.appendingPathComponent("last-rejected-newton-trial.json"))}
                break
            }
            try require(session.state.completedSteps==index && session.state.positions==attempt.candidatePositions,"Skipped or mismatched actual accepted frame")
            try require(attempt.report.computationSeconds.isFinite && attempt.report.computationSeconds>=0,"Invalid actual accepted computation time")
            acceptedSeconds += attempt.report.computationSeconds
            guard let record=session.lastAcceptedFrame else {throw Failure.failed("Accepted frame has no real trajectory journal")}
            try require(record.previousSeedControl==beforeControl && record.acceptedSeedControl==session.committedSeedControl,
                "Accepted frame has no matching control transition")
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            try encoder.encode(TrajectoryArchive(record)).write(to:output.appendingPathComponent(String(format:"trajectory-%04d.json",index)),options:.atomic)
            if index<=8 || index%24==0 {
                print("STEP",output.lastPathComponent,index,"N",attempt.report.newton.history.count,"source",attempt.report.maximumSourceEdgeRelativeChange,
                    "gap",attempt.report.maximumActualSeamGapMeters,"rate",attempt.report.maximumSpeedMetersPerSecond,"quiet",attempt.report.consecutiveQuietSteps,
                    "trajectory",attempt.report.trajectoryMode.rawValue,"configurationSegments",record.configurationSegments.count,
                    "physicalLeaves",record.physicalSubsteps.count,"physicalAttempts",attempt.report.physicalSubstepAttempts)
                fflush(stdout)
            }
            if attempt.report.numericallyStableCandidate {
                stable=true
                let validated:R.Validated
                do {validated=try receipt.validate(session:session,acceptedStepComputationSeconds:acceptedSeconds)}
                catch {reason="validationRejected";failure=String(describing:error);break}
                // Output artifacts only exist on the actual private Validated
                // route. A stable flag, process exit or diagnostic never writes them.
                try require(validated.output.diagnostics.computationSeconds==validated.metrics.totalComputationSeconds &&
                    validated.metrics.totalComputationSeconds==validated.metrics.acceptedStepComputationSeconds+validated.metrics.validationSeconds,
                    "Generation/validation timing semantics")
                try write(validated.output,output.appendingPathComponent("validated-output.json"))
                try validated.output.objString.write(to:output.appendingPathComponent("validated-output.obj"),atomically:true,encoding:.utf8)
                try write(validated.seamGroupIDs,output.appendingPathComponent("validated-seam-group-ids.json"))
                try write(validated.proof,output.appendingPathComponent("validated-proof.json"))
                try write(validated.metrics,output.appendingPathComponent("validated-metrics.json"))
                validationSeconds=validated.metrics.validationSeconds;resultAccepted=true;reason="stableValidated"
                break
            }
        }
        try write(StateArchive(session.state),output.appendingPathComponent("last-accepted-state.json"))
        try write(session.committedSeedControl,output.appendingPathComponent("last-accepted-seed-control.json"))
        if let record=session.lastAcceptedFrame {try write(JournalArchive(record),output.appendingPathComponent("last-accepted-frame.json"))}
        let summary=LongSummary(mode:"simulate",sourceSHA256:p.sourceSHA256,bodyGeometrySHA256:p.bodyClearanceProof.bodyGeometrySHA256,
            linearizationSourceIdentity:receipt.linearizationSourceIdentity,requestedSteps:steps,attemptedStep:attempted,
            actualCompletedSteps:session.state.completedSteps,assemblyIterations:min(session.state.completedSteps,p.settings.staticAssemblySteps),
            dynamicSimulatedSeconds:Double(max(0,session.state.completedSteps-p.settings.staticAssemblySteps))*p.settings.timeStepSeconds,
            trajectoryContract:"staticConfigurationPolyline_then_atomicPhysicalSeedForest",physicalSeedPolicyVersion:session.limits.physicalSeedPolicy.version,
            stopReason:reason,failure:failure,
            numericallyStableCandidateReached:stable,resultAccepted:resultAccepted,outputProduced:resultAccepted,
            acceptedStepComputationSeconds:acceptedSeconds,totalWorkerWallSeconds:S.elapsedSeconds(since:start),validationSeconds:validationSeconds,
            lastStep:last,fixed480And240IterationScheduleUnchanged:true,noSkippedSteps:true,noFabricatedStableStates:true)
        try write(summary,output.appendingPathComponent("case-summary.json"))
        print("STOP",output.lastPathComponent,"requested",steps,"accepted",session.state.completedSteps,reason,"resultAccepted",resultAccepted);fflush(stdout)
        return summary
    }
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let mode=CommandLine.arguments.count>3 ? CommandLine.arguments[3]:"controls"
        let filter=CommandLine.arguments.count>4 ? CommandLine.arguments[4]:"all"
        let steps=CommandLine.arguments.count>5 ? Int(CommandLine.arguments[5]) ?? 0:2400
        let poseText=CommandLine.arguments.count>6 ? CommandLine.arguments[6]:"legacyTemplate"
        guard let bodyPose=S.K.BodyPoseSelection(rawValue:poseText) else {throw Failure.failed("Known explicit body pose")}
        let inputPath=CommandLine.arguments.count>7 ? CommandLine.arguments[7]:"-"
        let shapeText=CommandLine.arguments.count>8 ? CommandLine.arguments[8]:"scaledTemplate"
        guard let bodyShape=S.K.BodyShapeSelection(rawValue:shapeText) else {throw Failure.failed("Known explicit body shape")}
        try require(bodyShape != .surfaceMeasurements || bodyPose == .matchPatternReference,"Fitted surface requires the same paper reference pose")
        try require(["controls","simulate"].contains(mode) && ["all","circle-straight-band","shirt-sleeved","source-pattern"].contains(filter),"Known explicit mode/case")
        try require((filter=="source-pattern") == (inputPath != "-"),"Custom source requires an explicit complete pattern file")
        try require(filter != "source-pattern" || mode=="simulate","Geometry-specific negative controls use the two built-in scenes")
        try require((1...2400).contains(steps),"Bounded physical step request")
        if mode=="controls" {
            let count=try JointPhysicalLeafValidationChecks.run()
            try write(["physicalKinematicsControlsPassed":count,"fabricatedSessions":0,"validatedGarments":0],
                out.appendingPathComponent("physical-kinematics-controls.json"))
        }
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let imported:GarmentCodePatternFile?
        let restored:GarmentCodeJointParameters.Restored?
        if inputPath != "-" {
            let document=try JSONDecoder().decode(GarmentCodePatternFile.self,from:Data(contentsOf:URL(fileURLWithPath:inputPath)))
            imported=document;restored=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
        } else {imported=nil;restored=nil}
        let body=restored?.body ?? GarmentCodeBodyParameters(values:catalog.body)
        let materials=S.Materials(membrane:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bending:try .init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8,
            bodyContact:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfContact:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        var results:[String:[String:Bool]]=[:],longResults:[String:LongSummary]=[:]
        let names=imported==nil ? ["circle-straight-band","shirt-sleeved"]:["source-pattern"]
        for name in names where filter=="all" || filter==name {
            let design:GarmentCodeDesignParameters,document:GarmentCodePatternFile
            if let restored,let imported {design=restored.design;document=imported}
            else {
                var selected=GarmentCodeDesignParameters(catalog:catalog)
                _ = selected.setValue(name=="shirt-sleeved" ? .string("Shirt"):.null,at:["meta","upper"])
                _ = selected.setValue(name=="circle-straight-band" ? .string("StraightWB"):.null,at:["meta","wb"])
                _ = selected.setValue(name=="circle-straight-band" ? .string("SkirtCircle"):.null,at:["meta","bottom"])
                if name=="circle-straight-band" {_ = selected.setValue(.number(0.75),at:["flare-skirt","suns"])}
                else {_ = selected.setValue(.bool(false),at:["sleeve","sleeveless"])}
                design=selected;document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            }
            var settings=S.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
            settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
            settings.bodyPoseSelection=bodyPose
            settings.bodyShapeSelection=bodyShape
            let recipe=try S.capture(document:document,body:body,design:design,sourceSettings:settings,materials:materials)
            let p=try await Task.detached(priority:.userInitiated){try S.prepare(recipe:recipe)}.value
            let receipt=try R.prepare(document:document,simulation:p)
            let path=out.appendingPathComponent(name);try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
            try write(["bodyShapeSelection":shapeText,"bodyPoseSelection":poseText],path.appendingPathComponent("body-selection.json"))
            if let fitted=p.input.source.cloth.fittedBodySurface {
                try write(fitted.bindings,path.appendingPathComponent("fitted-body-bindings.json"))
                try write(fitted.completeGeometryReport,path.appendingPathComponent("fitted-body-surface-report.json"))
            }
            if mode=="simulate" {
                try write(document,path.appendingPathComponent("complete-paper-source.json"))
                try write(p.input.source.plan,path.appendingPathComponent("complete-sewing-plan.json"))
                try write(SourceArchive(p),path.appendingPathComponent("complete-initial-input.json"))
                let j=p.input.objective,b=p.objective.body.parameters,c=p.objective.parameters,s=p.settings
                try write(["dynamicTimeStepSeconds":s.timeStepSeconds,"staticProximalTimeScaleSeconds":s.timeStepSeconds,"staticAssemblyIterations":Double(s.staticAssemblySteps),
                    "maximumPhysicalSubstepDepth":Double(S.WorkerLimits().maximumPhysicalSubstepDepth),
                    "maximumPhysicalAttemptsPerMacroStep":Double(S.WorkerLimits().maximumPhysicalSubstepAttempts),"requiredQuietPhysicalSeconds":Double(s.requiredQuietSteps)*s.timeStepSeconds,
                    "gravityRampSteps":Double(s.gravityRampSteps),"velocityDampingPerSecond":s.velocityDampingPerSecond,
                    "gravityMetersPerSecondSquared":s.gravityMetersPerSecondSquared,"requiredQuietSteps":Double(s.requiredQuietSteps),
                    "shearStiffnessNewtonPerMeter":j.material.shearStiffnessNewtonPerMeter,"areaStiffnessNewtonPerMeter":j.material.areaStiffnessNewtonPerMeter,
                    "bendingStiffnessNewtonMeter":j.bendingMaterial.bendingStiffnessNewtonMeter,"finalSewingStiffnessNewtonPerMeter":j.sewingStiffnessNewtonPerMeter,
                    "principalLowerLimit":j.strainBarrier.lowerLimit,"principalLowerActivation":j.strainBarrier.lowerActivation,
                    "principalUpperActivation":j.strainBarrier.upperActivation,"principalUpperLimit":j.strainBarrier.upperLimit,
                    "principalBarrierStiffnessNewtonPerMeter":j.strainBarrier.stiffnessNewtonPerMeter,
                    "bodyStiffnessPascals":b.stiffnessPascals,"bodyMinimumDistanceMeters":b.minimumDistanceMeters,"bodyActivationGapMeters":b.activationGapMeters,
                    "selfStiffnessPascals":c.stiffnessPascals,"selfMinimumDistanceMeters":c.minimumDistanceMeters,"selfActivationGapMeters":c.activationGapMeters],
                    path.appendingPathComponent("numerical-settings.json"))
                let summary=try await Task.detached(priority:.userInitiated){try simulate(receipt,output:path,steps:steps)}.value
                longResults[name]=summary;try write(longResults,out.appendingPathComponent("simulation-results.json"))
                continue
            }
            var changed=settings;changed.targetEdgeMeters=0.05
            let otherRecipe=try S.capture(document:document,body:body,design:design,sourceSettings:changed,materials:materials)
            let other=try await Task.detached(priority:.userInitiated){try S.prepare(recipe:otherRecipe)}.value
            try require(other.sourceSHA256==p.sourceSHA256 && other.input.objective.linearizationSource.identity != p.input.objective.linearizationSource.identity,"Foreign-instance negative-control premise")
            try require(other.input.source.cloth.referencePositions != p.input.source.cloth.referencePositions ||
                other.input.source.cloth.referenceTriangles != p.input.source.cloth.referenceTriangles,"Other actual mesh must differ, not merely its UUID")
            let otherReceipt=try R.prepare(document:document,simulation:other)
            let bad=GarmentCodePatternFile(pattern:document.pattern,parameters:document.parameters,parameterOrder:document.parameterOrder,properties:["result-test":.bool(true)])
            do {_ = try R.prepare(document:bad,simulation:p);throw Failure.failed("Changed canonical document accepted")}
            catch R.ValidationError.invalidSource{}
            do {_ = try R.prepare(document:document,simulation:p,isCancelled:{true});throw Failure.failed("Source receipt cancellation ignored")}
            catch is CancellationError{}
            let row=try await Task.detached(priority:.userInitiated){try exercise(receipt,other:otherReceipt,output:path)}.value
            results[name]=row;try write(results,out.appendingPathComponent("checks.json"));print("PASS",name);fflush(stdout)
        }
        if mode=="controls" {try write(["actualSourcesTested":results.count,"completeGarmentAccepted":0,"outputsProduced":0,"fakeStableStates":0],out.appendingPathComponent("claims.json"))}
    }
}
