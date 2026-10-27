import Foundation
import NativeClothCollision
import Synchronization

@main @MainActor struct JointCoordinateFallbackRegression {
    typealias S=GarmentCodeJointSimulation
    typealias N=GarmentCodeJointNewton
    typealias V=S.V
    struct Initial:Decodable {
        let sourceSHA256:String
        let positions:[V],referencePositions:[V],bodyPositions:[V],massesKg:[Double],pinMask:[Bool]
        let triangleIndices:[UInt32],referenceTriangles:[UInt32],bodyTriangleIndices:[UInt32]
        let referenceToSimulation:[Int],panelGroups:[S.K.PanelGroup]
        let bodyClearanceProof:BodyReceipt
    }
    struct BodyReceipt:Decodable {let bodyGeometrySHA256:String}
    struct State:Decodable {let completedSteps:Int;let positions:[V],velocities:[V]}
    nonisolated struct KKT:Codable,Sendable {let gradientInfinityN:Double,currentPCorrectionInfinityMeters:Double,currentPzRelativeResidual:Double}
    enum Failure:Error {case failed(String)}
    nonisolated final class CancellationFlag:Sendable {
        private let flag=Mutex(false)
        func cancel(){flag.withLock{$0=true}}
        func check()->Bool {flag.withLock{$0}}
    }
    nonisolated static func require(_ value:Bool,_ message:String)throws {if !value {throw Failure.failed(message)}}
    nonisolated static func inf(_ values:[V])->Double {values.reduce(0){max($0,abs($1.x),abs($1.y),abs($1.z))}}
    nonisolated static func xyz(_ values:[V])->[[Double]] {values.map{[$0.x,$0.y,$0.z]}}
    nonisolated static func singleULP(from:[V],to:[V])->Bool {
        var changed:[(Double,Double)]=[]
        for (a,b) in zip(from,to) {for (x,y) in zip([a.x,a.y,a.z],[b.x,b.y,b.z]) where x != y {changed.append((x,y))}}
        return changed.count==1 && (changed[0].1==changed[0].0.nextUp || changed[0].1==changed[0].0.nextDown)
    }
    nonisolated static func encode<T:Encodable>(_ value:T)throws->Data {
        let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)
    }
    nonisolated static func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:encode(value))}
    nonisolated static func write(_ value:[String:Any],to path:URL)throws {
        try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:path,options:.atomic)
    }
    /// Public native reports intentionally have no Codable conformance. Keep
    /// every actual field/statistic/witness rather than inventing a clear DTO.
    nonisolated static func reportObject(_ value:Any)->Any {
        if let n=value as? Double {return n.isFinite ? n:String(describing:n) as Any}
        if let n=value as? Int {return n};if let n=value as? UInt32 {return n};if let n=value as? Int64 {return n}
        if let n=value as? Bool {return n};if let n=value as? String {return n}
        let mirror=Mirror(reflecting:value)
        if mirror.displayStyle == .optional {return mirror.children.first.map{reportObject($0.value)} ?? NSNull()}
        if mirror.displayStyle == .collection {return mirror.children.map{reportObject($0.value)}}
        if mirror.displayStyle == .struct {return Dictionary(uniqueKeysWithValues:mirror.children.map{($0.label ?? "unknown",reportObject($0.value))})}
        return String(describing:value)
    }
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let step=Int(CommandLine.arguments[3])!,baseline=CommandLine.arguments[4]=="baseline"
        try require([403,405,406,407].contains(step),"Explicit bounded historical frame")
        let fixture=root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-joint-shirt\(step)"),decoder=JSONDecoder()
        let document=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:fixture.appendingPathComponent("complete-paper-source.json")))
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let parameters=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
        let source=try decoder.decode(Initial.self,from:Data(contentsOf:fixture.appendingPathComponent("complete-initial-input.json")))
        let before=try decoder.decode(State.self,from:Data(contentsOf:fixture.appendingPathComponent("accepted\(step-1)-state.json")))
        let inner=try decoder.decode([V].self,from:Data(contentsOf:fixture.appendingPathComponent("inner\(step)-positions.json")))
        // Constraint.init(from:) normalizes initialDirection again. Compare
        // the frozen original JSON values directly, without that side effect.
        let originalPlan=try decoder.decode(JSONValue.self,from:Data(contentsOf:fixture.appendingPathComponent("complete-sewing-plan.json")))
        let materials=S.Materials(membrane:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bending:try .init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8,
            bodyContact:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfContact:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        var settings=S.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin
        settings.material = .medium;settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true
        settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let prepared=try S.prepare(document:document,body:parameters.body,design:parameters.design,sourceSettings:settings,materials:materials)
        try require(before.completedSteps==step-1 && prepared.sourceSHA256==source.sourceSHA256 && prepared.initialPositions==source.positions &&
            prepared.input.source.cloth.referencePositions==source.referencePositions && prepared.input.source.cloth.referenceTriangles==source.referenceTriangles &&
            prepared.input.source.cloth.referenceToSimulation==source.referenceToSimulation &&
            prepared.input.source.cloth.triangleIndices==source.triangleIndices && prepared.input.objective.massesKg==source.massesKg &&
            prepared.input.source.cloth.mannequinPositions==source.bodyPositions && prepared.input.source.cloth.mannequinTriangleIndices==source.bodyTriangleIndices &&
            prepared.bodyClearanceProof.bodyGeometrySHA256==source.bodyClearanceProof.bodyGeometrySHA256 &&
            prepared.input.source.cloth.pinned==source.pinMask && source.pinMask.allSatisfy{!$0},"Exact complete source/body/rest/mass/0-pin fixture binding")
        let groups=prepared.input.source.panelBindings.map{S.K.PanelGroup(panelID:$0.mesh.panelID,vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs)}
        try require(try encode(groups)==encode(source.panelGroups),"Every original panel membership retained")
        if step==406 || step==407 {
            let originalSettings=try decoder.decode([String:Double].self,from:Data(contentsOf:fixture.appendingPathComponent("numerical-settings.json")))
            let expected:[String:Double]=["dynamicTimeStepSeconds":prepared.settings.timeStepSeconds,"staticProximalTimeScaleSeconds":prepared.settings.timeStepSeconds,
                "staticAssemblyIterations":Double(prepared.settings.staticAssemblySteps),"gravityRampSteps":Double(prepared.settings.gravityRampSteps),
                "velocityDampingPerSecond":prepared.settings.velocityDampingPerSecond,"gravityMetersPerSecondSquared":prepared.settings.gravityMetersPerSecondSquared,
                "requiredQuietSteps":Double(prepared.settings.requiredQuietSteps),"shearStiffnessNewtonPerMeter":310,"areaStiffnessNewtonPerMeter":170,
                "bendingStiffnessNewtonMeter":2e-4,"finalSewingStiffnessNewtonPerMeter":1e8,"principalLowerLimit":0.93,
                "principalLowerActivation":0.97,"principalUpperActivation":1.03,"principalUpperLimit":1.07,"principalBarrierStiffnessNewtonPerMeter":11,
                "bodyStiffnessPascals":35,"bodyMinimumDistanceMeters":0.0005,"bodyActivationGapMeters":0.002,
                "selfStiffnessPascals":35,"selfMinimumDistanceMeters":0,"selfActivationGapMeters":0.0005]
            try require(Set(expected.keys).isSubset(of:Set(originalSettings.keys)) && expected.allSatisfy{originalSettings[$0.key]!.bitPattern==$0.value.bitPattern},"Entire original406/407 material and frame settings bound")
        }
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try encode(prepared.input.source.plan).write(to:out.appendingPathComponent("reproduced-sewing-plan.json"))
        let actualPlan=try decoder.decode(JSONValue.self,from:encode(prepared.input.source.plan))
        try require(try encode(actualPlan)==encode(originalPlan),"Every actual raw source sewing row/interval/intent unchanged")
        try await Task.detached {
            let frame=try prepared.objective.frame(predictor:before.positions,timeStepSeconds:prepared.settings.timeStepSeconds,
                sewingRamp:Double(step)/480,sewingSchedule:prepared.settings.sewingSchedule)
            let selfMotion=try SelfContactGuard.Prepared(vertexCount:inner.count,triangleIndices:source.triangleIndices)
            let topology=try GarmentCodeClothContact.Topology(vertexCount:inner.count,triangleIndices:source.triangleIndices)
            let bodyMesh=try GarmentCodeBodySurfaceContact.BodyMesh(positions:source.bodyPositions,triangleIndices:source.bodyTriangleIndices)
            func run(_ label:String,start:[V],deny:Bool=false,denyCoordinates:Bool=false,cancel:Bool=false)throws->[String:Any] {
                let directory=out.appendingPathComponent(label);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let workspace=try N.P.Plan(prepared:frame.cloth.prepared).makeWorkspace(),flag=CancellationFlag()
                var checks:[(from:[V],to:[V],clear:Bool,permitted:Bool,body:ContinuousBodyContact.Report,cloth:SelfContactGuard.Report)]=[]
                var firstCertifiedNormal:[V]?,coordinateDenials=0,cancelledCoordinate:(from:[V],to:[V])?
                let initial=try frame.evaluate(positions:start),stamp=ContinuousClock.now
                // Identify the actual bounded coupled proposals for this fixed
                // initial state. This only arms fault injection; it neither
                // changes the solver nor accepts a candidate. Extra diagnostic
                // Hessian work is not counted as production solver work.
                var initialCoupledCandidates:[[V]]=[]
#if COUPLED_COORDINATE_PROPOSALS
                if cancel || denyCoordinates {
                    let proposals=try GarmentCodeCoupledCoordinateProposals.build(positions:start,gradient:initial.gradientNewton,
                        travel:Array(repeating:0,count:start.count),hessianColumn:{dof in
                            var unit=Array(repeating:V.zero,count:start.count),values=[0.0,0.0,0.0];values[dof%3]=1
                            unit[dof/3] = .init(x:values[0],y:values[1],z:values[2])
                            return try frame.hessianProduct(at:initial,direction:unit)
                        })
                    for proposal in proposals.proposals {
                        var candidate=start
                        for change in proposal.changes {
                            let i=change.dof/3;var row=[candidate[i].x,candidate[i].y,candidate[i].z];row[change.dof%3]=change.value
                            candidate[i] = .init(x:row[0],y:row[1],z:row[2])
                        }
                        initialCoupledCandidates.append(candidate)
                    }
                }
#endif
                var limits=N.Limits();if denyCoordinates {limits.maximumNewtonIterations=1}
                do {
                    let result=try N.solve(frame:frame,initialPositions:start,preconditioner:workspace,limits:limits,trajectoryMode:.configurationPolyline,pathGuard:{from,to in
                        let body=try prepared.objective.body.bodyMotion(from:from,to:to,isCancelled:{flag.check()})
                        let cloth=selfMotion.guardMotion(previous:from.map{SIMD3($0.x,$0.y,$0.z)},candidate:to.map{SIMD3($0.x,$0.y,$0.z)},isCancelled:{flag.check()})
                        let clear=body.permitsWholeCandidate && body.statistics.completedAllFeatures && cloth.permitsWholeCandidate &&
                            cloth.statistics.completedAllFeatures && cloth.statistics.completedDomainCertificates
                        let singleCoordinate=singleULP(from:from,to:to)
                        let coupledCoordinate=from==start && initialCoupledCandidates.contains{candidate in
                            zip(candidate,to).allSatisfy{a,b in a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern}
                        }
                        let coordinate=singleCoordinate || coupledCoordinate,injectedDenial=deny || (denyCoordinates && coordinate)
                        let permitted=clear && !injectedDenial
                        if permitted && !coordinate && firstCertifiedNormal==nil {firstCertifiedNormal=to}
                        if denyCoordinates && clear && coordinate {coordinateDenials+=1}
                        checks.append((from,to,clear,permitted,body,cloth))
                        try write(["previous":xyz(from),"candidate":xyz(to),"body":reportObject(body),"self":reportObject(cloth),
                            "completeActualPathClear":clear,"permittedByCallback":permitted,"singleULPCoordinate":singleCoordinate,"exactCoupledProposal":coupledCoordinate,
                            "injectedDenialControl":injectedDenial],to:directory.appendingPathComponent("path-\(checks.count).json"))
                        switch body.status {case .cancelled:throw CancellationError();case .invalid,.budgetExceeded:throw Failure.failed("body atomic failure");default:break}
                        switch cloth.status {case .cancelled:throw CancellationError();case .invalid,.budgetExceeded:throw Failure.failed("self atomic failure");default:break}
                        if cancel && clear && coordinate {cancelledCoordinate=(from,to);flag.cancel()}
                        return permitted
                    },isCancelled:{flag.check()})
                    if cancel {throw Failure.failed("Cancellation after a real complete coordinate path did not throw")}
                    let fresh=try frame.evaluate(positions:result.positions),delta=try frame.energyDelta(from:initial,to:fresh)
                    func currentKKT(_ positions:[V],_ e:GarmentCodeJointGarmentObjective.Evaluation)throws->KKT {
                        let cp=GarmentCodeJointContactPreconditioner.Workspace(base:try N.P.Plan(prepared:frame.cloth.prepared).makeWorkspace())
                        let gen=try cp.update(frame:frame.cloth,positions:positions,blocks:frame.preconditionerBlocks(at:e,isCancelled:{false}))
                        let dz=try cp.solve(rhs:e.gradientNewton.map{$0 * -1},generation:gen)
                        guard let residual=cp.latestSolveRelativeResidual,residual.isFinite else {throw Failure.failed("Fresh current P solve has no finite residual")}
                        return .init(gradientInfinityN:inf(e.gradientNewton),currentPCorrectionInfinityMeters:inf(dz),currentPzRelativeResidual:residual)
                    }
                    let startKKT=try currentKKT(start,initial),endKKT=try currentKKT(result.positions,fresh)
                    try require(result.acceptedTrajectory.count==result.report.history.count,"Every accepted segment has one actual numerical record")
                    let permittedChecks=checks.filter(\.permitted)
                    let indices=try S.configurationCertificateIndices(initial:start,final:result.positions,
                        trajectory:result.acceptedTrajectory.map{S.ConfigurationLineEndpoints(previous:$0.previous,candidate:$0.accepted)},
                        checkedLines:permittedChecks.map{S.ConfigurationLineEndpoints(previous:$0.from,candidate:$0.to)})
                    var previous=start,bound:[[String:Any]]=[]
                    for (offset,pair) in zip(result.acceptedTrajectory,result.report.history).enumerated() {
                        let segment=pair.0,h=pair.1,line=permittedChecks[indices[offset]]
                        try require(segment.previous==previous && segment.previous != segment.accepted &&
                            segment.sourceMotion.status == .clear && segment.sourceMotion.completedAllTriangles &&
                            h.localSourcePath?.status == .clear && h.localSourcePath?.completedAllTriangles==true,
                            "Every nonzero configuration segment has complete actual source certificates")
                        try require(line.from==segment.previous && line.to==segment.accepted && line.body.permitsWholeCandidate &&
                            line.body.statistics.completedAllFeatures && line.cloth.permitsWholeCandidate &&
                            line.cloth.statistics.completedAllFeatures && line.cloth.statistics.completedDomainCertificates,
                            "Production S indices bind the exact original complete body/self reports in temporal order")
                        try require(h.energyDeltaEstimateJoules<0 && h.energyDeltaEstimateJoules<=h.armijoIncrementJoules && h.armijoIncrementJoules<0,
                            "Actual accepted energy must descend under original Armijo")
                        if h.directionKind == .conjugateGradient {try require(h.precedingCG==nil,"CG cannot carry a fictitious preceding attempt")}
                        else if ["representableCoordinate","representableCoupledCoordinates"].contains(h.directionKind?.rawValue ?? "") {
                            try require(h.linear.reason.rawValue == h.directionKind?.rawValue && !h.linear.converged && h.linear.iterations==0 &&
                                h.precedingCG != nil && ((try object(h)) as? [String:Any])?["precedingP"] != nil,
                                "Coordinate direction preserves both attempted directions and actual raw H residual")
                        } else {try require(h.directionKind != nil && h.linear.reason == .preconditionedGradient && !h.linear.converged &&
                            h.linear.iterations==0 && h.precedingCG != nil,"Actual P direction reports its raw H residual")}
                        bound.append(["permittedCheckedIndex":indices[offset],"previous":xyz(segment.previous),"accepted":xyz(segment.accepted),
                            "source":try object(segment.sourceMotion),"body":reportObject(line.body),"self":reportObject(line.cloth)])
                        previous=segment.accepted
                    }
                    try require(previous==result.positions,"Complete recorded chain reaches the actual final iterate")
                    try write(["productionBindingHelperInvoked":true,"allAttemptedChecks":checks.count,"permittedClearChecks":permittedChecks.count,
                        "acceptedSegments":result.acceptedTrajectory.count,"productionIndices":indices,"boundSegments":bound,
                        "allAttemptsPreserved":true,"noSessionCreated":true],to:directory.appendingPathComponent("configuration-binding.json"))
                    let body=try GarmentCodeBodySurfaceContact.inspect(positions:result.positions,topology:topology,body:bodyMesh,thickness:0.0005)
                    let cloth=try GarmentCodeClothContact.inspect(positions:result.positions,topology:topology,thickness:0.0005)
                    let quality=try frame.cloth.prepared.membrane.inspect(positions:result.positions)
                    var maximumEdgeChange=0.0
                    for triangle in frame.cloth.prepared.membrane.triangles {
                        for (a,b) in [(triangle.a,triangle.b),(triangle.b,triangle.c),(triangle.c,triangle.a)] {
                            maximumEdgeChange=max(maximumEdgeChange,abs((result.positions[a]-result.positions[b]).length/(source.referencePositions[a]-source.referencePositions[b]).length-1))
                        }
                    }
                    // Preserve the actual report before evaluating positive expectations.
                    // A diagnostic failure must not erase the state needed to investigate it.
                    try encode(result.report).write(to:directory.appendingPathComponent("newton-report.json"))
                    try write(["positions":xyz(result.positions),"sourceSHA256":prepared.sourceSHA256,
                        "lastRejectedCandidate":result.lastRejectedCandidate.map(xyz) as Any? ?? NSNull()],to:directory.appendingPathComponent("positions.json"))
                    let searches=((try object(result.report)) as! [String:Any])["coordinateSearches"] as? [Any] ?? []
                    var report:[String:Any]=["passed":false,"checksPending":true,"label":label,"baseline":baseline,"status":result.report.status.rawValue,
                        "mathematicalSubproblemConverged":result.report.converged,"freshGradientInfinityN":endKKT.gradientInfinityN,
                        "currentPCorrectionInfinityMeters":endKKT.currentPCorrectionInfinityMeters,"currentPzRelativeResidual":endKKT.currentPzRelativeResidual,
                        "reportedCurrentPCorrectionInfinityMeters":result.report.finalPreconditionedGradientInfinityMeters as Any? ?? NSNull(),
                        "reportedCurrentPzRelativeResidual":result.report.finalPreconditionerRelativeResidual as Any? ?? NSNull(),
                        "independentStartKKT":try object(startKKT),"independentEndKKT":try object(endKKT),"acceptedSegments":result.acceptedTrajectory.count,
                        "pFallbackSegments":result.report.history.filter{$0.directionKind == .preconditionedGradientAfterLineSearch}.count,
                        "coordinateSegments":result.report.history.filter{$0.directionKind?.rawValue == "representableCoordinate"}.count,
                        "coupledCoordinateSegments":result.report.history.filter{$0.directionKind?.rawValue == "representableCoupledCoordinates"}.count,
                        "coordinateSearches":searches,"completeBodySelfChecks":checks.count,"permittedClearChecks":permittedChecks.count,
                        "productionCertificateIndices":indices,"allActualPathsClear":checks.allSatisfy(\.clear),"coordinateDenials":coordinateDenials,
                        "energyDeltaJoules":delta.energyJoules,"maximumSourceEdgeChange":maximumEdgeChange,
                        "sourceQuality":try object(quality),"bodyQuality":try object(body),"selfQuality":try object(cloth),
                        "seconds":S.elapsedSeconds(since:stamp),"known403FreshConvergenceNotRequired":step==403,
                        "originalPhysicalFrameAccepted":false,"completeGarmentAccepted":false]
                    try write(report,to:directory.appendingPathComponent("diagnostic-result.json"))
                    if result.report.converged {try require(endKKT.gradientInfinityN<1e-6 && endKKT.currentPCorrectionInfinityMeters<1e-7 &&
                        endKKT.currentPzRelativeResidual<1e-6,"Every reported convergence meets unchanged fresh current KKT")}
                    if deny {try require(!searches.isEmpty && !result.report.converged && result.positions==start && result.report.history.isEmpty,
                        "All denied paths exercise coordinate work but publish no movement")}
                    else if denyCoordinates {
                        try require(coordinateDenials>0,"Real representable-position denial was not exercised")
                        let hadNormal=result.report.coordinateSearches?.contains{$0.normalCandidateEnergyDeltaJoules != nil} ?? false
                        if hadNormal {
                            try require(firstCertifiedNormal != nil && result.positions==firstCertifiedNormal && result.report.history.count==1 &&
                                !["representableCoordinate","representableCoupledCoordinates"].contains(result.report.history[0].directionKind?.rawValue ?? "") &&
                                result.report.coordinateSearches!.contains{$0.termination=="normalCandidateRetained"},
                                "Denied real coordinates must retain any separately certified normal candidate")
                        } else {
                            try require(result.positions==start && result.report.history.isEmpty && !result.report.converged,
                                "Without a separately certified normal, denied representable positions must commit no movement")
                        }
                        report["retainedNormalCaseExercised"]=hadNormal
                        report["noCertifiedNormalCaseExercised"] = !hadNormal
                    }
                    else if !baseline && ((step==405 && label=="actual-inner405") || step==406 || step==407) {
                        try require(result.report.converged && endKKT.gradientInfinityN<1e-6 && endKKT.currentPCorrectionInfinityMeters<1e-7 &&
                            endKKT.currentPzRelativeResidual<1e-6 && maximumEdgeChange<0.08 && body.intersectingTrianglePairs==0 &&
                            body.degenerateClothTriangles==0 && cloth.intersectingTrianglePairs==0 && cloth.degenerateTriangles==0,
                            "Current positive405/406/407 subproblem meets original fresh KKT and source/endpoint gates")
                    }
                    report["passed"]=true;report["checksPending"]=false
                    try write(report,to:directory.appendingPathComponent("result.json"))
                    print(label,result.report.status.rawValue,inf(fresh.gradientNewton),result.report.history.count);fflush(stdout)
                    return report
                }catch is CancellationError {
                    try require(cancel && cancelledCoordinate != nil && checks.contains{
                        $0.from==cancelledCoordinate!.from && $0.to==cancelledCoordinate!.to && $0.clear
                    },"Cancellation follows a real current single-ULP or exactly identified coupled coordinate complete source/body/self path")
                    let originalInner=try decoder.decode([V].self,from:Data(contentsOf:fixture.appendingPathComponent("inner\(step)-positions.json")))
                    try require(inner==originalInner,"Caller snapshot unchanged after cancellation")
                    let report:[String:Any]=["passed":true,"label":label,"noResultReturned":true,"cancelledAfterCompletePath":true,
                        "pendingCertifiedNormalPresent":firstCertifiedNormal != nil,"pendingNormalNotCommitted":firstCertifiedNormal != nil,
                        "callerInputUnchanged":true,"originalPhysicalFrameAccepted":false,"completeGarmentAccepted":false]
                    try write(report,to:directory.appendingPathComponent("result.json"));return report
                }
            }
            let innerResult=try run("actual-inner\(step)",start:inner)
            let whole=try run("actual-outer\(step-1)-to-frame\(step)",start:before.positions)
            var controls:[String:Any]=[:]
            if !baseline && step==405 {
                controls["deniedPath"]=try run("negative-denied-path",start:inner,deny:true)
                controls["cancelAfterPath"]=try run("negative-cancel-after-path",start:inner,cancel:true)
            }
            if !baseline && step==406 {
                controls["deniedCoordinatesRetainNormal"]=try run("negative-denied-coordinates-retain-normal",start:inner,denyCoordinates:true)
                controls["cancelAfterCoordinate"]=try run("negative-cancel-after-coordinate",start:inner,cancel:true)
                try require((innerResult["coordinateSegments"] as! Int)+(innerResult["coupledCoordinateSegments"] as! Int)>0,"Actual406 saved inner exercises generic coordinate selection")
                // The current candidate may converge immediately, so a
                // fresh numerical workspace need not reproduce historical
                // unused normals. Exact ordered source/body/self binding is
                // checked above for every actual accepted segment regardless.
                controls["actualUnusedClearCandidates"]=(innerResult["permittedClearChecks"] as! Int)-(innerResult["acceptedSegments"] as! Int)
                controls["normalRetentionDeterministicallyCoveredByAnalyticSuite"]=true
            }
            try write(["passed":true,"sourceSHA256":prepared.sourceSHA256,"actualInner":innerResult,"wholeFrame":whole,
                "controls":controls,"sourceAndMassAndBodyAndFullPlanBound":true,"productionCertificateBindingChecked":true,
                "known403FreshConvergenceNotRequired":step==403,
                "scope":"Actual fixed mathematical frames with original gates, source, predictor and ordered path certificates. No Session state accepted; no historical final-bit/count requirement.",
                "completeGarmentAccepted":false],to:out.appendingPathComponent("coordinate-regression.json"))
        }.value
    }
}
