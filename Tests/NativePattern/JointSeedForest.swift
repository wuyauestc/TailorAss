import Foundation
import NativeClothCollision

@main @MainActor struct JointSeedForestChecks {
    typealias S=GarmentCodeJointSimulation
    typealias R=GarmentCodeJointResult
    typealias V=S.V
    nonisolated struct Initial:Decodable,Sendable {
        let sourceSHA256:String,positions:[V],referencePositions:[V],bodyPositions:[V],massesKg:[Double],pinMask:[Bool]
        let triangleIndices:[UInt32],referenceTriangles:[UInt32],bodyTriangleIndices:[UInt32],referenceToSimulation:[Int]
        let panelGroups:[S.K.PanelGroup]
    }
    nonisolated struct StateFile:Codable,Sendable {
        let completedSteps:Int,consecutiveQuietSteps:Int,positions:[V],velocities:[V]
        init(_ state:S.State){completedSteps=state.completedSteps;consecutiveQuietSteps=state.consecutiveQuietSteps;positions=state.positions;velocities=state.velocities}
    }
    nonisolated struct JournalFile:Encodable,Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String,previous:StateFile,accepted:StateFile,predictor:[V],report:S.StepReport,configurationSegmentCount:Int
        init(_ r:S.AcceptedFrame){sourceSHA256=r.sourceSHA256;bodyGeometrySHA256=r.bodyGeometrySHA256;previous=StateFile(r.previous);accepted=StateFile(r.accepted);predictor=r.predictor;report=r.report;configurationSegmentCount=r.configurationSegments.count}
    }
    nonisolated struct PhysicalArchive:Encodable,Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V]
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:S.StepReport,sourceMotion:GarmentCodeMembranePath.Report
        init(_ x:S.PhysicalSubstep) {
            sourceSHA256=x.sourceSHA256;bodyGeometrySHA256=x.bodyGeometrySHA256
            previousPositions=x.previousPositions;previousVelocities=x.previousVelocities
            acceptedPositions=x.acceptedPositions;acceptedVelocities=x.acceptedVelocities;predictor=x.predictor
            startTick=x.startTick;endTick=x.endTick;ticksPerMacroStep=x.ticksPerMacroStep;timeStepSeconds=x.timeStepSeconds
            sewingRamp=x.sewingRamp;gravityFraction=x.gravityFraction;report=x.report;sourceMotion=x.sourceMotion
        }
    }
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
    nonisolated enum Failure:Error {case failed(String)}
    nonisolated static func require(_ b:Bool,_ m:String)throws{if !b{throw Failure.failed(m)}}
    nonisolated static func exact(_ a:[V],_ b:[V])->Bool {a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}}
    nonisolated static func bits(_ a:[V])->[[String]] {a.map{[String($0.x.bitPattern,radix:16),String($0.y.bitPattern,radix:16),String($0.z.bitPattern,radix:16)]}}
    nonisolated static func write<T:Encodable>(_ value:T,_ url:URL)throws {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];try e.encode(value).write(to:url,options:.atomic)}
    nonisolated static func object<T:Encodable>(_ v:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(v))}
    nonisolated static func writeObject(_ v:[String:Any],_ url:URL)throws {try JSONSerialization.data(withJSONObject:v,options:[.sortedKeys,.prettyPrinted]).write(to:url,options:.atomic)}

    nonisolated struct LegacyLeaf:Decodable,Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String
        let previousPositions:[V],previousVelocities:[V],acceptedPositions:[V],acceptedVelocities:[V],predictor:[V]
        let startTick:Int,endTick:Int,ticksPerMacroStep:Int
        let timeStepSeconds:Double,sewingRamp:Double,gravityFraction:Double
        let report:S.StepReport,sourceMotion:GarmentCodeMembranePath.Report,bodyMotion:R.MotionProof,selfMotion:R.MotionProof
    }
    nonisolated struct LegacyFrame:Decodable,Sendable {
        let sourceSHA256:String,bodyGeometrySHA256:String,previous:StateFile,accepted:StateFile,physicalSubsteps:[LegacyLeaf]
    }
    nonisolated struct Configuration:Decodable,Sendable {
        let accepted:[V]
        enum CodingKeys:String,CodingKey {case accepted}
        init(from decoder:Decoder)throws {
            let c=try decoder.container(keyedBy:CodingKeys.self),rows=try c.decode([[Double]].self,forKey:.accepted)
            guard rows.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}) else{throw Failure.failed("Bad legacy trajectory triplet")}
            accepted=rows.map{V(x:$0[0],y:$0[1],z:$0[2])}
        }
    }
    nonisolated struct Trajectory:Decodable,Sendable {let sourceSHA256:String,bodyGeometrySHA256:String,step:Int,configurationSegments:[Configuration],physicalSubsteps:[LegacyLeaf]}
    nonisolated struct Fixture:Decodable,Sendable {let sourceSHA256:String,bodyGeometrySHA256:String,legacyOriginTag:UUID}
    nonisolated struct Record:Encodable,Sendable {
        let identity:UUID,previous:StateFile,accepted:StateFile,predictor:[V],report:S.StepReport
        let previousSeedControl:S.PhysicalSeedControl,usedPhysicalSeeds:[S.PhysicalSeedSpan],acceptedSeedControl:S.PhysicalSeedControl
        let physicalAttemptLedger:[S.PhysicalAttemptLedger],physicalSubsteps:[PhysicalArchive]
        init(_ r:S.AcceptedFrame) {identity=r.identity;previous=StateFile(r.previous);accepted=StateFile(r.accepted);predictor=r.predictor;report=r.report;previousSeedControl=r.previousSeedControl;usedPhysicalSeeds=r.usedPhysicalSeeds;acceptedSeedControl=r.acceptedSeedControl;physicalAttemptLedger=r.physicalAttemptLedger;physicalSubsteps=r.physicalSubsteps.map(PhysicalArchive.init)}
    }
    nonisolated static func state(_ f:StateFile)->S.State {.init(completedSteps:f.completedSteps,positions:f.positions,velocities:f.velocities,consecutiveQuietSteps:f.consecutiveQuietSteps)}
    nonisolated static func same(_ a:S.State,_ b:S.State)->Bool {a.completedSteps==b.completedSteps && a.consecutiveQuietSteps==b.consecutiveQuietSteps && exact(a.positions,b.positions) && exact(a.velocities,b.velocities)}
    nonisolated static func inspect(_ session:S.Session,_ receipt:R.Prepared,_ input:Initial,_ out:URL)throws {
        let proof=try receipt.inspectLastAcceptedFrame(session:session)
        try write(proof,out.appendingPathComponent("fresh-frame-proof.json"))
        try require(proof.meetsFreshEquilibrium && proof.actualTrajectoryMode == .physicalLinearStep && proof.sourceMotions.count==proof.segmentCount && proof.bodyMotions.count==proof.segmentCount && proof.selfMotions.count==proof.segmentCount && proof.sourceMotions.allSatisfy{$0.status == .clear && $0.completedAllTriangles} && proof.bodyMotions.allSatisfy{$0.status=="clear" && $0.completedAllFeatures} && proof.selfMotions.allSatisfy{$0.status=="clear" && $0.completedAllFeatures && $0.completedDomainCertificates==true},"Fresh complete source/body/self and KKT must pass")
        let body=try GarmentCodeBodySurfaceContact.BodyMesh(positions:input.bodyPositions,triangleIndices:input.bodyTriangleIndices)
        let field=try GarmentCodeBodyMeshQueries.Prepared(body:body)
        let visible=try GarmentCodeVisibleBodyInspection.Prepared(sourceSHA256:session.prepared.sourceSHA256,vertexCount:input.positions.count,triangleIndices:input.triangleIndices,body:field).inspect(positions:session.state.positions)
        try write(visible,out.appendingPathComponent("independent-visible-body.json"));try require(visible.meetsFinalBodyGate,"Same visible body query/SAT must pass")
    }
    nonisolated static func advance(_ session:S.Session,_ receipt:R.Prepared,_ input:Initial,_ out:URL)throws->S.Attempt {
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let old=session.state,control=session.committedSeedControl,oldQuiet=session.consecutiveQuietFrames.count,start=ContinuousClock.now
        let attempt=try session.advanceStep()
        try write(attempt.report,out.appendingPathComponent("step-report.json"));try write(attempt.physicalAttempts.map(PhysicalAttemptArchive.init),out.appendingPathComponent("physical-attempts.json"));try write(attempt.physicalAttemptLedger,out.appendingPathComponent("attempt-ledger.json"))
        try write(StateFile(session.state),out.appendingPathComponent("after-state.json"));try write(attempt.candidatePositions,out.appendingPathComponent("candidate.json"));try write(["positions":bits(attempt.candidatePositions)],out.appendingPathComponent("runtime-candidate-bits.json"))
        if let trial=attempt.lastRejectedNewtonCandidate {try write(trial,out.appendingPathComponent("last-rejected-trial.json"));try write(["positions":bits(trial)],out.appendingPathComponent("runtime-last-trial-bits.json"))}
        if attempt.report.accepted {
            guard let r=session.lastAcceptedFrame else{throw Failure.failed("Missing production journal")}
            try require(same(r.previous,old) && r.previousSeedControl==control && r.usedPhysicalSeeds==control.nextSeeds && r.acceptedSeedControl==session.committedSeedControl && r.acceptedSeedControl.originCompletedStep==session.state.completedSteps && r.acceptedSeedControl.originAcceptedFrameIdentity==r.identity,"Actual accepted control lineage must bind")
            let forest=try R.checkedPhysicalSeedForest(seeds:r.usedPhysicalSeeds,leaves:r.physicalSubsteps.map{.init(startTick:$0.startTick,endTick:$0.endTick,ticksPerMacroStep:$0.ticksPerMacroStep)},maximumDepth:session.limits.maximumPhysicalSubstepDepth,reportedAttempts:r.report.physicalSubstepAttempts,ledger:r.physicalAttemptLedger)
            try require(forest.attemptCount==2*forest.leafCount-forest.seedCount,"Actual forest identity 2L-K")
            try write(forest,out.appendingPathComponent("forest-proof.json"));try write(Record(r),out.appendingPathComponent("accepted-frame.json"));try inspect(session,receipt,input,out)
        } else {try require(same(session.state,old) && session.committedSeedControl==control && session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.count==oldQuiet,"Failure committed provisional physical prefix/state/control/journal")}
        try writeObject(["accepted":attempt.report.accepted,"step":attempt.report.attemptedStep,"wallSeconds":S.elapsedSeconds(since:start),"physicalAttemptCount":attempt.report.physicalSubstepAttempts,"acceptedLeaves":attempt.report.physicalSubstepCount,"seedRoots":attempt.report.physicalSeedRootCount ?? 0,"failedAttemptSeconds":attempt.physicalAttemptLedger.filter{!$0.accepted}.reduce(0){$0+$1.computationSeconds},"acceptedAttemptSeconds":attempt.physicalAttemptLedger.filter{$0.accepted}.reduce(0){$0+$1.computationSeconds},"RValidatedProduced":false,"historicalInitial0Qualification":false],out.appendingPathComponent("summary.json"))
        return attempt
    }
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),original=URL(fileURLWithPath:CommandLine.arguments[2]),out=URL(fileURLWithPath:CommandLine.arguments[3]),mode=CommandLine.arguments[4],decoder=JSONDecoder()
        let document=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:original.appendingPathComponent("complete-paper-source.json")))
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let parameters=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
        let input=try decoder.decode(Initial.self,from:Data(contentsOf:original.appendingPathComponent("complete-initial-input.json")))
        let before=try decoder.decode(StateFile.self,from:Data(contentsOf:original.appendingPathComponent("last-accepted-state.json")))
        let numerical=try decoder.decode([String:Double].self,from:Data(contentsOf:original.appendingPathComponent("numerical-settings.json")))
        let oldPlan=try decoder.decode(JSONValue.self,from:Data(contentsOf:original.appendingPathComponent("complete-sewing-plan.json")))
        let materials=S.Materials(membrane:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),bending:try .init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8,bodyContact:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),selfContact:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        var settings=S.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyPoseSelection = .legacyTemplate;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let p=try S.prepare(document:document,body:parameters.body,design:parameters.design,sourceSettings:settings,materials:materials),receipt=try R.prepare(document:document,simulation:p)
        let cloth=p.input.source.cloth,groups=p.input.source.panelBindings.map{S.K.PanelGroup(panelID:$0.mesh.panelID,vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs)}
        try require(p.sourceSHA256==input.sourceSHA256 && exact(p.initialPositions,input.positions) && exact(cloth.referencePositions,input.referencePositions) && cloth.referenceTriangles==input.referenceTriangles && cloth.triangleIndices==input.triangleIndices && cloth.referenceToSimulation==input.referenceToSimulation && p.input.objective.massesKg.map(\.bitPattern)==input.massesKg.map(\.bitPattern) && exact(cloth.mannequinPositions,input.bodyPositions) && cloth.mannequinTriangleIndices==input.bodyTriangleIndices && cloth.pinned==input.pinMask && input.pinMask.allSatisfy{!$0},"Entire original native source/rest/body/mass/0pins must match")
        let encode=JSONEncoder();encode.outputFormatting=[.sortedKeys]
        try require(try encode.encode(groups)==encode.encode(input.panelGroups),"All original panel/face membership must match")
        let reproducedPlan=try decoder.decode(JSONValue.self,from:encode.encode(p.input.source.plan));try require(try encode.encode(reproducedPlan)==encode.encode(oldPlan),"Raw original sewing rows/intent/interval/direction must match, no second Constraint decode normalization")
        let j=p.input.objective,b=p.objective.body.parameters,c=p.objective.parameters,s=p.settings
        let values:[String:Double]=["dynamicTimeStepSeconds":s.timeStepSeconds,"staticProximalTimeScaleSeconds":s.timeStepSeconds,"staticAssemblyIterations":Double(s.staticAssemblySteps),"gravityRampSteps":Double(s.gravityRampSteps),"velocityDampingPerSecond":s.velocityDampingPerSecond,"gravityMetersPerSecondSquared":s.gravityMetersPerSecondSquared,"requiredQuietSteps":Double(s.requiredQuietSteps),"shearStiffnessNewtonPerMeter":j.material.shearStiffnessNewtonPerMeter,"areaStiffnessNewtonPerMeter":j.material.areaStiffnessNewtonPerMeter,"bendingStiffnessNewtonMeter":j.bendingMaterial.bendingStiffnessNewtonMeter,"finalSewingStiffnessNewtonPerMeter":j.sewingStiffnessNewtonPerMeter,"principalLowerLimit":j.strainBarrier.lowerLimit,"principalLowerActivation":j.strainBarrier.lowerActivation,"principalUpperActivation":j.strainBarrier.upperActivation,"principalUpperLimit":j.strainBarrier.upperLimit,"principalBarrierStiffnessNewtonPerMeter":j.strainBarrier.stiffnessNewtonPerMeter,"bodyStiffnessPascals":b.stiffnessPascals,"bodyMinimumDistanceMeters":b.minimumDistanceMeters,"bodyActivationGapMeters":b.activationGapMeters,"selfStiffnessPascals":c.stiffnessPascals,"selfMinimumDistanceMeters":c.minimumDistanceMeters,"selfActivationGapMeters":c.activationGapMeters]
        try require(Set(values.keys).isSubset(of:Set(numerical.keys)) && values.allSatisfy{numerical[$0.key]!.bitPattern==$0.value.bitPattern},"Every original numerical/material parameter must match")

        let fixture=try decoder.decode(Fixture.self,from:Data(contentsOf:original.appendingPathComponent("manifest.json")))
        let legacy=try decoder.decode(LegacyFrame.self,from:Data(contentsOf:original.appendingPathComponent("last-accepted-frame.json")))
        let tr480=try decoder.decode(Trajectory.self,from:Data(contentsOf:original.appendingPathComponent("trajectory-0480.json")))
        let tr481=try decoder.decode(Trajectory.self,from:Data(contentsOf:original.appendingPathComponent("trajectory-0481.json")))
        try require(before.completedSteps==922 && before.consecutiveQuietSteps==0 && exact(before.positions,legacy.accepted.positions) && exact(before.velocities,legacy.accepted.velocities) && legacy.accepted.completedSteps==922,"Legacy922 entire state binding")
        try require(fixture.sourceSHA256==p.sourceSHA256 && legacy.sourceSHA256==p.sourceSHA256 && legacy.bodyGeometrySHA256==fixture.bodyGeometrySHA256 && legacy.physicalSubsteps.count==2,"Legacy source/body/twohalf binding")
        var x=legacy.previous.positions,v=legacy.previous.velocities
        for (i,leaf) in legacy.physicalSubsteps.enumerated() {
            try require(leaf.sourceSHA256==p.sourceSHA256 && leaf.bodyGeometrySHA256==fixture.bodyGeometrySHA256 && leaf.startTick==i && leaf.endTick==i+1 && leaf.ticksPerMacroStep==2 && leaf.timeStepSeconds.bitPattern==(s.timeStepSeconds/2).bitPattern && leaf.gravityFraction==1 && leaf.sewingRamp==1 && leaf.report.accepted && exact(leaf.previousPositions,x) && exact(leaf.previousVelocities,v) && leaf.sourceMotion.status == .clear && leaf.sourceMotion.completedAllTriangles && leaf.bodyMotion.status=="clear" && leaf.bodyMotion.completedAllFeatures && leaf.selfMotion.status=="clear" && leaf.selfMotion.completedAllFeatures && leaf.selfMotion.completedDomainCertificates==true,"Legacy922 actual whole physical leaf chain")
            x=leaf.acceptedPositions;v=leaf.acceptedVelocities
        }
        try require(exact(x,before.positions) && exact(v,before.velocities),"Legacy leaf endpoint must bind State922")
        try write(values,out.appendingPathComponent("reproduced-numerical-settings.json"));try write(["positions":bits(before.positions),"velocities":bits(before.velocities)],out.appendingPathComponent("legacy922-runtime-bits.json"))
        print("SOURCE_LEGACY_STATE_AND_TWO_HALF_SEEDS_BOUND",mode);fflush(stdout)
        try await Task.detached {
            if mode=="seed923924" || mode=="depth2" {
                var limits=S.WorkerLimits();limits.maximumPhysicalSubstepDepth=mode=="depth2" ? 2:3;limits.physicalSeedPolicy = .committedPartition
                let session=try p.makeSession(limits:limits);try session.diagnosticLoadSeedState(state(before),legacyOriginTag:fixture.legacyOriginTag)
                try write(session.committedSeedControl,out.appendingPathComponent("loaded-legacy-control.json"))
                let step923=try advance(session,receipt,input,out.appendingPathComponent("step923"))
                if mode=="depth2" {
                    try require(!step923.report.accepted && session.state.completedSteps==922 && session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.isEmpty,"Depth2 must reject with complete rollback")
                    try writeObject(["passed":true,"actualDepth2Rejected":true,"stateControlJournalQuietUnchanged":true,"completeGarmentAccepted":false],out.appendingPathComponent("mode-summary.json"))
                } else {
                    try require(step923.report.accepted,"Seed923 did not qualify")
                    let r923=session.lastAcceptedFrame!,expected=r923.acceptedSeedControl
                    try require(r923.usedPhysicalSeeds==[.init(startTick:0,endTick:4,ticksPerMacroStep:8),.init(startTick:4,endTick:8,ticksPerMacroStep:8)] && r923.previousSeedControl.originAcceptedFrameIdentity==fixture.legacyOriginTag,"Only original922 halves may seed923")
                    let step924=try advance(session,receipt,input,out.appendingPathComponent("step924"))
                    try require(step924.report.accepted && session.lastAcceptedFrame!.previousSeedControl==expected && session.lastAcceptedFrame!.usedPhysicalSeeds==expected.nextSeeds && session.lastAcceptedFrame!.previousSeedControl.originAcceptedFrameIdentity==r923.identity,"924 may inherit only actual accepted923 partition")
                    var refused=false;do{_ = try receipt.validate(session:session,acceptedStepComputationSeconds:step924.report.computationSeconds)}catch{refused=true}
                    try require(refused,"Legacy diagnostic may not mint final garment")
                    try writeObject(["passed":true,"actual923And924Accepted":true,"onlyLegacy922HalvesUsedFor923":true,"onlyTrueCommitted923LeavesUsedFor924":true,"RValidatedProduced":false,"historicalInitial0Qualification":false],out.appendingPathComponent("mode-summary.json"))
                }
            } else if mode=="cancel" {
#if DIAGNOSTIC_SEED_CANCELLATION
                var limits=S.WorkerLimits();limits.maximumPhysicalSubstepDepth=3;limits.physicalSeedPolicy = .committedPartition
                let signal=DiagnosticSeedCancellation.shared
                let session=try p.makeSession(limits:limits,isCancelled:{signal.isCancelled})
                try session.diagnosticLoadSeedState(state(before),legacyOriginTag:fixture.legacyOriginTag)
                let old=session.state,control=session.committedSeedControl
                try write(control,out.appendingPathComponent("before-control.json"));try write(StateFile(old),out.appendingPathComponent("before-state.json"))
                var cancelled=false
                do{_ = try session.advanceStep(isCancelled:{signal.isCancelled})}catch is CancellationError{cancelled=true}
                guard let leaf=signal.actualAcceptedLeaf else{throw Failure.failed("Actual [6,7]/8 accepted leaf observer was never reached")}
                try write(PhysicalArchive(leaf),out.appendingPathComponent("actual-provisional-leaf-6-7.json"))
                try require(cancelled && signal.isCancelled && leaf.startTick==6 && leaf.endTick==7 && leaf.ticksPerMacroStep==8 && leaf.report.accepted && leaf.sourceMotion.status == .clear && leaf.sourceMotion.completedAllTriangles && leaf.bodyMotion.statistics.completedAllFeatures && leaf.selfMotion.statistics.completedAllFeatures && leaf.selfMotion.statistics.completedDomainCertificates,"Cancellation must follow true qualified [6,7]/8 leaf")
                try require(same(session.state,old) && session.committedSeedControl==control && session.lastAcceptedFrame==nil && session.consecutiveQuietFrames.isEmpty,"Cancelled partial forest committed state/control/journal/quiet")
                try write(StateFile(session.state),out.appendingPathComponent("after-state.json"));try write(session.committedSeedControl,out.appendingPathComponent("after-control.json"))
                try writeObject(["passed":true,"caughtCancellationError":true,"actualAcceptedProvisionalLeaf":[6,7,8],"stateControlJournalQuietUnchanged":true,"RValidatedProduced":false],out.appendingPathComponent("mode-summary.json"))
#else
                throw Failure.failed("Cancellation control requires separately frozen observer-only binary")
#endif
            } else if mode=="first481" {
                guard let endpoint=tr480.configurationSegments.last?.accepted,let first=tr481.physicalSubsteps.first else{throw Failure.failed("Missing real480/481 archive")}
                let zero=Array(repeating:V.zero,count:endpoint.count)
                try require(tr480.step==480 && tr481.step==481 && tr480.sourceSHA256==p.sourceSHA256 && tr481.sourceSHA256==p.sourceSHA256 && tr480.bodyGeometrySHA256==fixture.bodyGeometrySHA256 && tr481.bodyGeometrySHA256==fixture.bodyGeometrySHA256 && tr480.physicalSubsteps.isEmpty && tr481.physicalSubsteps.count==1 && exact(endpoint,first.previousPositions) && exact(zero,first.previousVelocities),"Actual480 endpoint/staticzero velocity must bitwise match actual481 first previous x/v")
                let loaded=S.State(completedSteps:480,positions:endpoint,velocities:zero,consecutiveQuietSteps:0)
                var results:[S.State]=[]
                for policy in [S.PhysicalSeedPolicy.rootOnly,.committedPartition] {
                    var limits=S.WorkerLimits();limits.physicalSeedPolicy=policy
                    let session=try p.makeSession(limits:limits);try session.diagnosticLoadSeedState(loaded,legacyOriginTag:nil)
                    let attempt=try advance(session,receipt,input,out.appendingPathComponent(policy.rawValue))
                    try require(attempt.report.accepted && session.lastAcceptedFrame!.usedPhysicalSeeds==session.initialSeedControl.nextSeeds && attempt.report.physicalSubstepCount==1 && attempt.report.physicalSubstepAttempts==1,"Initial481 must begin with one full root for both policies")
                    results.append(session.state)
                }
                let identical=same(results[0],results[1])
                try writeObject(["passed":identical,"bothActual481Accepted":true,"allPositionVelocityBitsIdentical":identical,"actual480MatchesOriginal481LeafPreviousBits":true,"bothRootCount":1,"completeGarmentAccepted":false],out.appendingPathComponent("mode-summary.json"))
                try require(identical,"First481 policy changed physical x/v bits")
            } else {throw Failure.failed("Unknown focused mode")}
            print("SEED_FOREST_MODE_DONE",mode);fflush(stdout)
        }.value
    }
}
