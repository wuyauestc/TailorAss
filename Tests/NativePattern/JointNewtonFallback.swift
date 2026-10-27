import Foundation
import NativeClothCollision
import Synchronization

@main @MainActor struct JointNewtonFallbackRegression {
    typealias S=GarmentCodeJointSimulation
    typealias N=GarmentCodeJointNewton
    typealias V=S.V
    struct Initial:Decodable {
        let sourceSHA256:String
        let positions:[V],referencePositions:[V],bodyPositions:[V],massesKg:[Double],pinMask:[Bool]
        let triangleIndices:[UInt32],referenceTriangles:[UInt32],bodyTriangleIndices:[UInt32]
    }
    struct State:Decodable {let completedSteps:Int;let positions:[V],velocities:[V]}
    enum Failure:Error {case failed(String)}
    nonisolated final class CancellationFlag:Sendable {
        private let flag=Mutex(false)
        func cancel(){flag.withLock{$0=true}}
        func check()->Bool {flag.withLock{$0}}
    }
    nonisolated static func require(_ value:Bool,_ message:String)throws {if !value {throw Failure.failed(message)}}
    nonisolated static func inf(_ values:[V])->Double {values.reduce(0){max($0,abs($1.x),abs($1.y),abs($1.z))}}
    nonisolated static func xyz(_ values:[V])->[[Double]] {values.map{[$0.x,$0.y,$0.z]}}
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
        let fixture=root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-joint-shirt403"),decoder=JSONDecoder()
        let document=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:fixture.appendingPathComponent("complete-paper-source.json")))
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let parameters=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
        let source=try decoder.decode(Initial.self,from:Data(contentsOf:fixture.appendingPathComponent("complete-initial-input.json")))
        let before=try decoder.decode(State.self,from:Data(contentsOf:fixture.appendingPathComponent("accepted402-state.json")))
        let inner=try decoder.decode([V].self,from:Data(contentsOf:fixture.appendingPathComponent("inner403-positions.json")))
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
        try require(before.completedSteps==402 && prepared.sourceSHA256==source.sourceSHA256 && prepared.initialPositions==source.positions &&
            prepared.input.source.cloth.referencePositions==source.referencePositions && prepared.input.source.cloth.referenceTriangles==source.referenceTriangles &&
            prepared.input.source.cloth.triangleIndices==source.triangleIndices && prepared.input.objective.massesKg==source.massesKg &&
            prepared.input.source.cloth.mannequinPositions==source.bodyPositions && prepared.input.source.cloth.mannequinTriangleIndices==source.bodyTriangleIndices &&
            prepared.input.source.cloth.pinned==source.pinMask && source.pinMask.allSatisfy{!$0},"Exact complete source/body/rest/mass/0-pin fixture binding")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try encode(prepared.input.source.plan).write(to:out.appendingPathComponent("reproduced-sewing-plan.json"))
        let actualPlan=try decoder.decode(JSONValue.self,from:encode(prepared.input.source.plan))
        try require(try encode(actualPlan)==encode(originalPlan),"Every actual raw source sewing row/interval/intent unchanged")
        try await Task.detached {
            let frame=try prepared.objective.frame(predictor:before.positions,timeStepSeconds:prepared.settings.timeStepSeconds,
                sewingRamp:403.0/480,sewingSchedule:prepared.settings.sewingSchedule)
            let selfMotion=try SelfContactGuard.Prepared(vertexCount:inner.count,triangleIndices:source.triangleIndices)
            let topology=try GarmentCodeClothContact.Topology(vertexCount:inner.count,triangleIndices:source.triangleIndices)
            let bodyMesh=try GarmentCodeBodySurfaceContact.BodyMesh(positions:source.bodyPositions,triangleIndices:source.bodyTriangleIndices)
            func run(_ label:String,start:[V],deny:Bool=false,cancel:Bool=false)throws->[String:Any] {
                let directory=out.appendingPathComponent(label);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let workspace=try N.P.Plan(prepared:frame.cloth.prepared).makeWorkspace(),flag=CancellationFlag()
                var checks:[(from:[V],to:[V],clear:Bool)]=[]
                let initial=try frame.evaluate(positions:start),stamp=ContinuousClock.now
                do {
                    let result=try N.solve(frame:frame,initialPositions:start,preconditioner:workspace,trajectoryMode:.configurationPolyline,pathGuard:{from,to in
                        let body=try prepared.objective.body.bodyMotion(from:from,to:to,isCancelled:{flag.check()})
                        let cloth=selfMotion.guardMotion(previous:from.map{SIMD3($0.x,$0.y,$0.z)},candidate:to.map{SIMD3($0.x,$0.y,$0.z)},isCancelled:{flag.check()})
                        let clear=body.permitsWholeCandidate && body.statistics.completedAllFeatures && cloth.permitsWholeCandidate &&
                            cloth.statistics.completedAllFeatures && cloth.statistics.completedDomainCertificates
                        checks.append((from,to,clear))
                        try write(["previous":xyz(from),"candidate":xyz(to),"body":reportObject(body),"self":reportObject(cloth),
                            "completeActualPathClear":clear,"injectedDenialControl":deny],to:directory.appendingPathComponent("path-\(checks.count).json"))
                        switch body.status {case .cancelled:throw CancellationError();case .invalid,.budgetExceeded:throw Failure.failed("body atomic failure");default:break}
                        switch cloth.status {case .cancelled:throw CancellationError();case .invalid,.budgetExceeded:throw Failure.failed("self atomic failure");default:break}
                        if cancel {flag.cancel()};return clear && !deny
                    },isCancelled:{flag.check()})
                    if cancel {throw Failure.failed("Cancellation after a real complete path did not throw")}
                    let fresh=try frame.evaluate(positions:result.positions),delta=try frame.energyDelta(from:initial,to:fresh)
                    var previous=start
                    for (segment,h) in zip(result.acceptedTrajectory,result.report.history) {
                        try require(segment.previous==previous && segment.previous != segment.accepted &&
                            segment.sourceMotion.status == .clear && segment.sourceMotion.completedAllTriangles &&
                            h.localSourcePath?.status == .clear && h.localSourcePath?.completedAllTriangles==true,
                            "Every nonzero configuration segment has complete actual source certificates")
                        try require(checks.contains{$0.clear && $0.from==segment.previous && $0.to==segment.accepted},"Accepted segment has exact same complete body/self certificates")
                        try require(h.energyDeltaEstimateJoules<=h.armijoIncrementJoules && h.armijoIncrementJoules<0,"Actual accepted energy must descend under original Armijo")
                        if h.directionKind == .conjugateGradient {try require(h.precedingCG==nil,"CG cannot carry a fictitious preceding attempt")}
                        else {try require(h.directionKind != nil && h.linear.reason == .preconditionedGradient && !h.linear.converged &&
                            h.linear.iterations==0 && h.precedingCG != nil,"Actual P direction must report its raw H residual, never previous converged CG")}
                        previous=segment.accepted
                    }
                    try require(previous==result.positions && result.acceptedTrajectory.count==result.report.history.count,"Complete recorded chain")
                    let body=try GarmentCodeBodySurfaceContact.inspect(positions:result.positions,topology:topology,body:bodyMesh,thickness:0.0005)
                    let cloth=try GarmentCodeClothContact.inspect(positions:result.positions,topology:topology,thickness:0.0005)
                    let quality=try frame.cloth.prepared.membrane.inspect(positions:result.positions)
                    var maximumEdgeChange=0.0
                    for triangle in frame.cloth.prepared.membrane.triangles {
                        for (a,b) in [(triangle.a,triangle.b),(triangle.b,triangle.c),(triangle.c,triangle.a)] {
                            maximumEdgeChange=max(maximumEdgeChange,abs((result.positions[a]-result.positions[b]).length/(source.referencePositions[a]-source.referencePositions[b]).length-1))
                        }
                    }
                    if deny {try require(!result.report.converged && result.positions==start && result.report.history.isEmpty,"Denied paths cannot publish any numerical movement")}
                    else {try require(result.report.converged && inf(fresh.gradientNewton)<1e-6 && result.report.finalPreconditionedGradientInfinityMeters!<1e-7 &&
                        result.report.finalPreconditionerRelativeResidual!<1e-6 && maximumEdgeChange<0.08 &&
                        body.intersectingTrianglePairs==0 && body.degenerateClothTriangles==0 && cloth.intersectingTrianglePairs==0 && cloth.degenerateTriangles==0,
                        "Observer-free production same exact frame must meet unchanged math/source/path/endpoint gates")}
                    try encode(result.report).write(to:directory.appendingPathComponent("newton-report.json"))
                    try write(["positions":xyz(result.positions),"sourceSHA256":prepared.sourceSHA256,
                        "lastRejectedCandidate":result.lastRejectedCandidate.map(xyz) as Any? ?? NSNull()],to:directory.appendingPathComponent("positions.json"))
                    let report:[String:Any]=["passed":true,"label":label,"status":result.report.status.rawValue,"mathematicalSubproblemConverged":result.report.converged,
                        "freshGradientInfinityN":inf(fresh.gradientNewton),"currentPCorrectionInfinityMeters":result.report.finalPreconditionedGradientInfinityMeters as Any? ?? NSNull(),
                        "currentPzRelativeResidual":result.report.finalPreconditionerRelativeResidual as Any? ?? NSNull(),"acceptedSegments":result.acceptedTrajectory.count,
                        "pFallbackSegments":result.report.history.filter{$0.directionKind == .preconditionedGradientAfterLineSearch}.count,
                        "completeBodySelfChecks":checks.count,"allActualPathsClear":checks.allSatisfy(\.clear),"energyDeltaJoules":delta.energyJoules,
                        "maximumSourceEdgeChange":maximumEdgeChange,"sourceQuality":try object(quality),"bodyQuality":try object(body),"selfQuality":try object(cloth),
                        "seconds":S.elapsedSeconds(since:stamp),"originalPhysicalFrameAccepted":false,"completeGarmentAccepted":false]
                    try write(report,to:directory.appendingPathComponent("result.json"));print(label,result.report.status.rawValue,inf(fresh.gradientNewton),result.report.history.count)
                    return report
                }catch is CancellationError {
                    try require(cancel && !checks.isEmpty,"Only requested cancellation after an actual path may exit here")
                    let originalInner=try decoder.decode([V].self,from:Data(contentsOf:fixture.appendingPathComponent("inner403-positions.json")))
                    try require(inner==originalInner,"Caller source snapshot unchanged after cancellation")
                    let report:[String:Any]=["passed":true,"label":label,"noResultReturned":true,"cancelledAfterCompletePath":checks.last!.clear,
                        "callerInputUnchanged":true,"originalPhysicalFrameAccepted":false,"completeGarmentAccepted":false]
                    try write(report,to:directory.appendingPathComponent("result.json"));return report
                }
            }
            // A real force-qualified but positive-energy P proposal must not
            // become acceptable merely because it crosses the force cutoff.
            let e=try frame.evaluate(positions:inner),cp=GarmentCodeJointContactPreconditioner.Workspace(base:try N.P.Plan(prepared:frame.cloth.prepared).makeWorkspace())
            try require(abs(inf(e.gradientNewton)-1.1996525586255302e-6)<1e-14,"Actual failed inner gradient reproduced")
            let generation=try cp.update(frame:frame.cloth,positions:inner,blocks:frame.preconditionerBlocks(at:e,isCancelled:{false}))
            let correction=try cp.solve(rhs:e.gradientNewton.map{$0 * -1},generation:generation)
            let positive=zip(inner,correction).map{$0+$1*0.25},pe=try frame.evaluate(positions:positive)
            let positiveDelta=try frame.energyDelta(from:e,to:pe).energyJoules
            try require(positiveDelta>0 && inf(pe.gradientNewton)<1e-6,"Genuinely positive-energy but force-qualified rejection control")
            let innerResult=try run("actual-inner403",start:inner)
            let actualPositions=try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("actual-inner403/positions.json"))) as! [String:Any]
            try require(actualPositions["positions"] as! [[Double]] != xyz(positive),"Positive-energy force-qualified candidate must not be the solved state")
            let denied=try run("negative-denied-path",start:inner,deny:true)
            let cancelled=try run("negative-cancel-after-path",start:inner,cancel:true)
            let whole=try run("actual-outer402-to-frame403",start:before.positions)
            try write(["passed":true,"sourceSHA256":prepared.sourceSHA256,"actualInner403":innerResult,"wholeFrame403":whole,
                "positiveEnergyForceQualifiedControl":["deltaJoules":positiveDelta,"gradientInfinityN":inf(pe.gradientNewton),"accepted":false],
                "deniedPathControl":denied,"cancelAfterPathControl":cancelled,"sourceAndMassAndBodyAndFullPlanBound":true,
                "scope":"Actual observer-free production N, one complete mathematical frame replay plus a separate saved-inner control. No Session state or garment output accepted.",
                "completeGarmentAccepted":false],to:out.appendingPathComponent("fallback-regression.json"))
        }.value
    }
}
