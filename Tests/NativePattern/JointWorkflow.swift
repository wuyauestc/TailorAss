import Foundation

@main @MainActor struct JointWorkflowRegression {
    typealias W = GarmentCodeJointWorkflow
    enum Failure: Error { case failed(String) }
    nonisolated enum WorkerFailure:Error {case budget}
    static func require(_ v: Bool, _ message: String) throws { if !v { throw Failure.failed(message) } }
    nonisolated final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var began = false, cancelled = false, ended = false
        func start() { lock.lock(); began = true; lock.unlock() }
        func stop(cancelled: Bool) { lock.lock(); self.cancelled = cancelled; ended = true; lock.unlock() }
        var snapshot: (began: Bool, cancelled: Bool, ended: Bool) {
            lock.lock(); defer { lock.unlock() }; return (began, cancelled, ended)
        }
    }
    final class Observer {
        var task: Task<W.Result, Error>?
        var events: [W.Progress] = []
        var cancellation: Task<Void, Never>?
        func record(_ value: W.Progress, cancelAt: W.Phase?) {
            events.append(value)
            if value.phase == cancelAt && cancellation == nil {
                cancellation = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(15))
                    task?.cancel()
                }
            }
        }
    }
    static func verifyGatheredBoundary(resources:URL,out:URL)async throws->[String:Any] {
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        var design=GarmentCodeDesignParameters(catalog:catalog)
        try require(design.setValue(.null,at:["meta","upper"]) &&
                    design.setValue(.string("StraightWB"),at:["meta","wb"]) &&
                    design.setValue(.string("Skirt2"),at:["meta","bottom"]) &&
                    design.setValue(.number(1.3),at:["skirt","ruffle"]),"Real gathered source parameters")
        let paper=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        let sourceSHA=try GarmentCodeSewnDrape.canonicalSourceSHA256(document:paper)
        let observer=Observer()
        let expected="这份纸样包含抽褶接缝，整衣3D的抽褶缝合仍在完善，暂时无法生成可验收结果。二维纸样可以正常使用。"
        observer.task=Task {
            try await W.generate(document:paper,body:body,design:design,material:.medium,bodyResourceDirectory:resources) { value in
                observer.events.append(value)
                // A failed early guard must fail this test without starting
                // an accidental cloth solve on an unrecognized fixture.
                if value.phase == .assembling {observer.task?.cancel()}
            }
        }
        do {
            _ = try await observer.task!.value
            throw Failure.failed("Unfinished actual gathered sewing returned a result")
        } catch W.WorkflowError.gatheredSeamsUnavailable {
            try require(W.WorkflowError.gatheredSeamsUnavailable.localizedDescription==expected,"Readable gathered-seam failure")
        }
        try require(observer.events.map(\.phase)==[.capturing,.preparing],"Gathered source reached numerical assembly or returned completion")
        let count=observer.events.count
        try await Task.sleep(for:.milliseconds(30))
        try require(observer.events.count==count,"Late progress after actual gathered refusal")
        try require(try GarmentCodeSewnDrape.canonicalSourceSHA256(document:paper)==sourceSHA,"Gathered refusal changed 2D paper")
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(paper).write(to:out.appendingPathComponent("gathered-paper-source.json"),options:.atomic)
        let result:[String:Any]=["passed":true,"sourceSHA256":sourceSHA,"panels":paper.pattern.panels.count,
            "stitchGroups":paper.pattern.stitches.count,"ruffleRatio":1.3,"phases":observer.events.map{$0.phase.rawValue},
            "localizedError":expected,"completeGarmentAccepted":false,"validatedStandaloneComponentProduced":false,
            "noWorkflowResultReturned":true,"assemblingReached":false,"completedReached":false,
            "scope":"Real complete WB+Skirt2 gathered source passes S.prepare, then the actual plan flag refuses App execution before any Session/Newton or result capability. CLI S.prepare/solve unchanged."]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("gathered-boundary.json"),options:.atomic)
        return result
    }
    static func main() async throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let out = URL(fileURLWithPath: CommandLine.arguments[2])
        if CommandLine.arguments.dropFirst(3).contains("--gathered-only") {
            let result=try await verifyGatheredBoundary(resources:resources,out:out)
            try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("workflow-tests.json"),options:.atomic)
            print("PASS real gathered source refused before numerical assembly")
            return
        }
        var checks: [String: Bool] = [:]

        let probe = Probe()
        let parent = Task {
            try await W.detached {
                probe.start()
                let until = ContinuousClock.now.advanced(by: .seconds(3))
                while ContinuousClock.now < until {
                    if Task.isCancelled { probe.stop(cancelled: true); throw CancellationError() }
                    Thread.sleep(forTimeInterval: 0.001)
                }
                probe.stop(cancelled: false)
                return 7
            }
        }
        let until = ContinuousClock.now.advanced(by: .seconds(3))
        while !probe.snapshot.began && ContinuousClock.now < until { try await Task.sleep(for: .milliseconds(1)) }
        try require(probe.snapshot.began, "Detached child did not start")
        parent.cancel()
        do { _ = try await parent.value; throw Failure.failed("Parent cancellation returned a value") }
        catch is CancellationError {}
        try require(probe.snapshot.ended && probe.snapshot.cancelled, "Parent returned while detached work was still running")
        checks["parentCancellationWaitsForChildExit"] = true

        let failingProbe=Probe()
        let failingParent=Task {
            try await W.detached { ()throws->Int in
                failingProbe.start()
                let deadline=ContinuousClock.now.advanced(by:.seconds(3))
                while !Task.isCancelled && ContinuousClock.now<deadline {Thread.sleep(forTimeInterval:0.001)}
                failingProbe.stop(cancelled:Task.isCancelled)
                throw WorkerFailure.budget
            }
        }
        let failureDeadline=ContinuousClock.now.advanced(by:.seconds(3))
        while !failingProbe.snapshot.began && ContinuousClock.now<failureDeadline {try await Task.sleep(for:.milliseconds(1))}
        try require(failingProbe.snapshot.began,"Failing worker did not start")
        failingParent.cancel()
        do {_ = try await failingParent.value;throw Failure.failed("Cancelled parent returned")}
        catch is CancellationError {}
        try require(failingProbe.snapshot.ended && failingProbe.snapshot.cancelled,"Cancellation returned before throwing worker exited")
        checks["parentCancellationTakesPriorityOverWorkerError"]=true
        do {_ = try await W.detached { ()throws->Int in throw WorkerFailure.budget };throw Failure.failed("Worker failure lost")}
        catch WorkerFailure.budget {}
        checks["uncancelledWorkerErrorPreserved"]=true

        let early = Probe()
        let alreadyCancelled = Task { () throws -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await W.detached { early.start(); return 1 }
        }
        do { _ = try await alreadyCancelled.value; throw Failure.failed("Already cancelled task returned") }
        catch is CancellationError {}
        try require(!early.snapshot.began, "Already cancelled parent started detached work")
        checks["alreadyCancelledParentStartsNoWorker"] = true

        let selfCancelled = Task {
            try await W.detached { () throws -> Int in
                withUnsafeCurrentTask { $0?.cancel() }
                return 1
            }
        }
        do { _ = try await selfCancelled.value; throw Failure.failed("Cancelled child published its return value") }
        catch is CancellationError {}
        checks["childReturnCancellationChecked"] = true

        let observer = Observer()
        let relay = W.ProgressRelay { observer.events.append($0) }
        func event(_ steps: Int) -> W.Progress {
            .init(phase: .assembling, completedSteps: steps, maximumSteps: 2400,
                  phaseCompletedSteps: steps, phaseMaximumSteps: 480, consecutiveQuietSteps: 0, requiredQuietSteps: 24)
        }
        relay.send(event(2), sequence: 4)
        relay.send(event(1), sequence: 3)
        relay.send(event(2), sequence: 4)
        relay.send(event(3), sequence: 5)
        relay.finish()
        relay.send(event(4), sequence: 6)
        try require(observer.events.map(\.completedSteps) == [2, 3], "Stale/duplicate/finished progress was delivered")
        checks["progressCannotRegressOrPublishAfterFinish"] = true

        let catalog = try GarmentCodeParameterCatalog.load(from: resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body = GarmentCodeBodyParameters(values: catalog.body)
        _ = try await verifyGatheredBoundary(resources:resources,out:out)
        checks["actualGatheredSourceRejectedBeforeNumericalAssembly"]=true
        var design = GarmentCodeDesignParameters(catalog: catalog)
        _ = design.setValue(.null, at: ["meta", "upper"])
        _ = design.setValue(.string("StraightWB"), at: ["meta", "wb"])
        _ = design.setValue(.string("SkirtCircle"), at: ["meta", "bottom"])
        _ = design.setValue(.number(0.75), at: ["flare-skirt", "suns"])
        let document = try GarmentCodeNativeGenerator.generate(body: body, design: design)
        let originalSHA = try GarmentCodeSewnDrape.canonicalSourceSHA256(document: document)
        let frozenDesign = design
        for phase in [W.Phase.preparing, .assembling] {
            let o = Observer()
            o.task = Task {
                try await W.generate(document: document, body: body, design: frozenDesign, material: .medium,
                                     bodyResourceDirectory: resources) { o.record($0, cancelAt: phase) }
            }
            do { _ = try await o.task!.value; throw Failure.failed("Cancelled generation produced result") }
            catch is CancellationError {}
            try require(o.events.contains(where: { $0.phase == phase }), "Requested cancellation phase was not reached")
            try require(!o.events.contains(where: { $0.phase == .completed }), "Cancelled generation published completion")
            let count = o.events.count
            try await Task.sleep(for: .milliseconds(30))
            try require(o.events.count == count, "Queued progress arrived after cancellation returned")
            checks["real_\(phase.rawValue)_cancellationNoResultOrLateProgress"] = true
        }

        var tiny = W.S.WorkerLimits()
        tiny.newton.maximumNewtonIterations = 1
        let failureObserver = Observer()
        do {
            _ = try await W.generate(document: document, body: body, design: design, material: .medium,
                                     bodyResourceDirectory: resources, workerLimits: tiny) {
                failureObserver.events.append($0)
            }
            throw Failure.failed("Insufficient actual Newton work produced a complete garment")
        } catch W.WorkflowError.rejected(let step, let phase, let reason) {
            try require(step == 1 && phase == .assembling && reason == "Newton newtonBudget", "Unexpected real negative control")
        }
        try require(failureObserver.events.map(\.phase) == [.capturing, .preparing, .assembling], "Rejected first step reported accepted work or completion")
        checks["realRejectedStepCannotProduceOutput"] = true
        // The opt-in pose must reach the same source/validation boundary, and
        // cancellation there must stop before any result can be published.
        var posedValues=catalog.body
        posedValues["arm_pose_angle"]=45
        let posedBody=GarmentCodeBodyParameters(values:posedValues)
        let posedDocument=try GarmentCodeNativeGenerator.generate(body:posedBody,design:design)
        let posedObserver=Observer()
        posedObserver.task=Task {
            try await W.generate(document:posedDocument,body:posedBody,design:frozenDesign,material:.medium,
                bodyPoseSelection:.matchPatternReference,bodyResourceDirectory:resources) { value in
                posedObserver.events.append(value)
                if value.phase == .assembling {posedObserver.task?.cancel()}
            }
        }
        do {_ = try await posedObserver.task!.value;throw Failure.failed("Cancelled posed preparation returned a result")}
        catch is CancellationError {}
        try require(posedObserver.events.contains{$0.phase == .assembling} &&
                    !posedObserver.events.contains{$0.phase == .completed},"Posed body failed to reach source binding or published after cancellation")
        checks["posedPreparationAndSourceBindingReachCancellableWorker"] = true

        // This template's real 90-degree candidate folds/crosses. Ignoring the
        // selection would instead run the legacy template and fail this check.
        posedValues["arm_pose_angle"]=90
        let invalidPoseBody=GarmentCodeBodyParameters(values:posedValues)
        let invalidPoseDocument=try GarmentCodeNativeGenerator.generate(body:invalidPoseBody,design:design)
        let invalidObserver=Observer()
        do {
            _ = try await W.generate(document:invalidPoseDocument,body:invalidPoseBody,design:design,material:.medium,
                bodyPoseSelection:.matchPatternReference,bodyResourceDirectory:resources,workerLimits:tiny) {
                invalidObserver.events.append($0)
            }
            throw Failure.failed("Rejected body pose returned a garment")
        } catch GarmentCodeBodySurfaceContact.ContactError.invalid(let message) {
            try require(message.contains("参考摆臂"),"Unexpected posed surface failure")
        }
        try require(invalidObserver.events.map(\.phase) == [.capturing,.preparing],"Unvalidated pose reached numerical stepping")
        checks["poseSelectionPropagatesAndInvalidSurfaceIsRejected"] = true
        try require(try GarmentCodeSewnDrape.canonicalSourceSHA256(document: document) == originalSHA, "Workflow changed source paper")
        checks["canonicalPaperUnchanged"] = true
        let runPositive=CommandLine.arguments.dropFirst(3).contains("--positive-waistband")
        if runPositive {
            var positiveDesign=GarmentCodeDesignParameters(catalog:catalog)
            _ = positiveDesign.setValue(.null,at:["meta","upper"])
            _ = positiveDesign.setValue(.string("StraightWB"),at:["meta","wb"])
            _ = positiveDesign.setValue(.null,at:["meta","bottom"])
            let positivePaper=try GarmentCodeNativeGenerator.generate(body:body,design:positiveDesign)
            let positiveSHA=try GarmentCodeSewnDrape.canonicalSourceSHA256(document:positivePaper)
            let positiveObserver=Observer()
            let result=try await W.generate(document:positivePaper,body:body,design:positiveDesign,material:.medium,
                bodyResourceDirectory:resources) { positiveObserver.events.append($0) }
            let validated=result.validated,events=positiveObserver.events
            try require(validated.proof.sourceSHA256==positiveSHA && validated.metrics.verifiedQuietFrames==24 &&
                validated.output.diagnostics.converged,"Workflow returned no complete source-bound validated output")
            try require(events.first?.phase == .capturing && events.last?.phase == .completed &&
                events.filter{$0.phase == .completed}.count==1 &&
                events.last?.completedSteps==validated.metrics.completedSteps,"Final workflow progress differs from actual result")
            for phase in [W.Phase.preparing,.assembling,.gravityRamp,.settling,.validating] {
                try require(events.contains{$0.phase==phase},"Successful workflow omitted a generation phase")
            }
            try require(zip(events,events.dropFirst()).allSatisfy{$0.completedSteps<=$1.completedSteps},"Successful progress regressed")
            let count=events.count
            try await Task.sleep(for:.milliseconds(30))
            try require(positiveObserver.events.count==count,"Late progress after successful workflow return")
            try require(try GarmentCodeSewnDrape.canonicalSourceSHA256(document:positivePaper)==positiveSHA,"Successful workflow changed source paper")
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(validated.output).write(to:out.appendingPathComponent("positive-output.json"),options:.atomic)
            try encoder.encode(validated.proof).write(to:out.appendingPathComponent("positive-proof.json"),options:.atomic)
            try encoder.encode(validated.metrics).write(to:out.appendingPathComponent("positive-metrics.json"),options:.atomic)
            try validated.output.objString.write(to:out.appendingPathComponent("positive-output.obj"),atomically:true,encoding:.utf8)
            checks["actualValidatedStandaloneComponentAndFinalProgress"] = true
        }
        let report: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks,
            "sourceSHA256": originalSHA, "completeGarmentAccepted": false,
            "validatedStandaloneComponentProduced": runPositive,
            "scope": "Actual async preparation, cancellation, ordered progress and rejected-step boundary; optional real default waistband final acceptance. No fabricated successful state or all-style acceptance."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("workflow-tests.json"), options: .atomic)
        print("PASS", checks.count, "workflow checks; validated standalone component:",runPositive)
    }
}
