// Appended to the exact ViewModel slice in the test-only generated source file.
// No fake Workflow.Result or Validated garment is constructed.
extension GarmentCodeJointDrapeViewModel {
    static func verifyLifecycle(document:GarmentCodePatternFile,secondDocument:GarmentCodePatternFile,resources:URL)async throws->[String] {
        enum Failure:Error {case check(String)}
        func check(_ b:Bool,_ m:String)throws{if !b{throw Failure.check(m)}}
        let model=GarmentCodeJointDrapeViewModel();var passed:[String]=[]
        let catalog=resources.appendingPathComponent("GarmentCodeParameterCatalog.json")
        model.configure(document:document,resourceDirectory:resources,catalogURL:catalog,signatureIssue:nil)
        try check(model.sourceReady && model.bodyShapeSelection == .scaledTemplate && model.bodyPoseSelection == .legacyTemplate,"real complete parameters restored with unchanged default body")
        model.generate()
        let firstID=model.generationTaskID,firstTask=model.generationTask
        model.cancelGeneration()
        try check(model.running && model.cancelling && model.generationTask != nil && model.generationTaskID==firstID,"cancel must retain running owner until actual task exit")
        model.generate()
        try check(model.generationTaskID==firstID,"restart while cancelling was allowed")
        model.selectBodyShape(.surfaceMeasurements)
        try check(model.bodyPoseSelection == .matchPatternReference && model.running && model.cancelling &&
                  model.generationTaskID==firstID && model.presented==nil && model.exportArtifact==nil,
                  "fitted shape must select reference pose and invalidate publication without releasing its worker")
        passed.append("fitted shape selects its supported reference pose and retains the cancelling worker")
        model.selectBodyShape(.scaledTemplate)
        try check(model.bodyPoseSelection == .matchPatternReference && model.generationTaskID==firstID &&
                  model.presented==nil && model.exportArtifact==nil,"returning to scaled shape must retain pose and invalidate publication")
        passed.append("shape replacement invalidates result and export without resetting the selected reference pose")
        model.selectBodyPose(.legacyTemplate)
        model.selectBodyPose(.matchPatternReference)
        try check(model.running && model.cancelling && model.generationTaskID==firstID &&
                  model.presented==nil && model.exportArtifact==nil,"pose change released the numerical owner or retained old publication")
        passed.append("pose change invalidates result and export while retaining the cancelling worker")
        model.selectMaterial(.soft)
        try check(model.material == .soft && model.running && model.cancelling && model.generationTaskID==firstID &&
                  model.presented==nil && model.exportArtifact==nil,"material selection must synchronously invalidate old publication without releasing its task")
        passed.append("material selection invalidates publication synchronously and preserves task ownership")
        model.configure(document:secondDocument,resourceDirectory:resources,catalogURL:catalog,signatureIssue:nil)
        try check(model.sourceReady && model.running && model.cancelling && model.generationTaskID==firstID,"configuration change lost cancellation ownership")
        await firstTask?.value
        try check(!model.running && !model.cancelling && model.generationTask==nil && model.generationTaskID==nil,"cancel exit not acknowledged")
        try check(model.presented==nil && model.document.map{try? GarmentCodeJointParameters.signature($0)} == (try? GarmentCodeJointParameters.signature(secondDocument)),"old cancellation republished or replaced latest source")
        passed.append("actual task cancellation acknowledgement prevents overlap across configuration replacement")
        model.generate()
        guard let nextID=model.generationTaskID,let nextTask=model.generationTask else{throw Failure.check("new run blocked after actual cancellation exit")}
        try check(nextID != firstID && model.running && !model.cancelling,"new run did not obtain fresh ownership")
        if let firstID {model.finishGeneration(id:firstID,outcome:.failed("stale failure"),panelNames:[:])}
        try check(model.generationTaskID==nextID && model.running && model.issue==nil,"old completion cleared a new task")
        passed.append("stale owner cannot clear or fail new task")
        model.close()
        try check(model.running && model.cancelling && model.generationTaskID==nextID && !model.sourceReady,"close claimed physical worker already stopped")
        await nextTask.value
        try check(!model.running && !model.cancelling && model.presented==nil && !model.sourceReady && model.document==nil,"closed source was revived")
        passed.append("close cancels and awaits existing workflow without resurrecting source")
        model.configure(document:document,resourceDirectory:resources,catalogURL:catalog,signatureIssue:nil)
        model.bodyShapeSelection = .surfaceMeasurements;model.bodyPoseSelection = .legacyTemplate
        model.generate()
        try check(!model.running && model.generationTask==nil && model.issue != nil && model.presented==nil,
                  "an unsupported programmatic body combination must not start a worker or fall back to scaledTemplate")
        passed.append("unsupported fitted legacy pose cannot start or silently fall back")
        // Exercise cancellation after the real workflow enters detached prepare.
        model.configure(document:document,resourceDirectory:resources,catalogURL:catalog,signatureIssue:nil)
        model.bodyShapeChanged()
        try check(model.bodyShapeSelection == .surfaceMeasurements && model.bodyPoseSelection == .matchPatternReference,
                  "actual fitted worker must retain explicitly selected shape")
        model.generate()
        let clock=ContinuousClock(),deadline=clock.now.advanced(by:.seconds(30))
        while model.running && model.progress?.phase != .preparing && clock.now<deadline {await Task.yield()}
        guard model.progress?.phase == .preparing,let active=model.generationTask else {model.close();throw Failure.check("actual preparation phase not reached")}
        let activeID=model.generationTaskID
        model.selectMaterial(.firm)
        try check(model.material == .firm && model.running && model.cancelling && model.generationTaskID==activeID &&
                  model.presented==nil && model.exportArtifact==nil,"material change during fitted preparation marked stopped early or kept old publication")
        await active.value
        try check(!model.running && !model.cancelling && model.presented==nil && model.generationTask==nil,"real detached preparation did not exit cleanly")
        passed.append("material change cancels real fitted preparation and refuses old publication until worker exit")
        model.close()
        return passed
    }
}
@main @MainActor struct JointDrapeLifecycleRegression {
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]),resources=root.appendingPathComponent("Resources")
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body);var design=GarmentCodeDesignParameters(catalog:catalog)
        _=design.setValue(.null,at:["meta","upper"]);_=design.setValue(.string("StraightWB"),at:["meta","wb"]);_=design.setValue(.string("SkirtCircle"),at:["meta","bottom"])
        let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        _=design.setValue(.number(0.63),at:["flare-skirt","suns"])
        var secondBody=body;secondBody.set(body["waist"]!+1,for:"waist")
        let second=try GarmentCodeNativeGenerator.generate(body:secondBody,design:design)
        let passed=try await GarmentCodeJointDrapeViewModel.verifyLifecycle(document:document,secondDocument:second,resources:resources)
        let summary:[String:Any]=["passed":true,"tests":passed,"actualProductionViewModelExtracted":true,"workflowMocked":false,"fakeValidatedConstructed":false,"completeGarmentProduced":false,"scope":"Actual task/configuration/cancellation lifecycle only; no successful garment or UI rendering claim."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-drape-lifecycle-summary.json"));print(summary)
    }
}
