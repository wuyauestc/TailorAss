import Foundation
import NativeClothCollision

@main @MainActor struct JointSimulationRegression {
    typealias T=GarmentCodeJointSimulation
    typealias V=T.V
    enum Failure:Error {case failed(String)}
    nonisolated final class Counter:@unchecked Sendable {
        private let lock=NSLock()
        private var count=0
        func cancelled()->Bool {lock.lock();defer{lock.unlock()};count+=1;return count>=100}
    }
    nonisolated static func require(_ b:Bool,_ s:String)throws {if !b {throw Failure.failed(s)}}
    nonisolated static func object<A:Encodable>(_ a:A)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(a))}
    nonisolated static func write(_ a:Any,to path:URL)throws {
        try JSONSerialization.data(withJSONObject:a,options:[.prettyPrinted,.sortedKeys]).write(to:path,options:.atomic)
    }
    nonisolated static func pose(_ x:[V])->[[String:Double]] {x.map{["x":$0.x,"y":$0.y,"z":$0.z]}}
    nonisolated static func run(_ p:T.Prepared,output:URL,steps:Int)throws->Data {
        let session=try p.makeSession(),initial=session.state
        do {_ = try session.advanceStep(isCancelled:{true});throw Failure.failed("Cancellation ignored")}catch is CancellationError{}
        try require(session.state==initial,"Early cancellation changed physical state")
        let counter=Counter()
        do {_ = try session.advanceStep(isCancelled:{counter.cancelled()});throw Failure.failed("In-progress cancellation ignored")}catch is CancellationError{}
        try require(session.state==initial,"In-progress cancellation changed physical state")
        var short=T.WorkerLimits();short.newton.maximumNewtonIterations=1
        let bounded=try p.makeSession(limits:short),boundedInitial=bounded.state
        let rejected=try bounded.advanceStep()
        try require(!rejected.report.accepted && !rejected.report.newton.converged,"One-Newton negative control unexpectedly converged")
        try require(bounded.state==boundedInitial,"Unconverged Newton committed a partial step")
        try write(try object(rejected.report),to:output.appendingPathComponent("one-newton-rejection.json"))
        var tiny=T.WorkerLimits();tiny.selfMotion.limits.maximumCertificateNodes=1
        let budget=try p.makeSession(limits:tiny),budgetInitial=budget.state
        do {
            let a=try budget.advanceStep()
            try write(try object(a.report),to:output.appendingPathComponent("path-budget-attempt.json"))
            throw Failure.failed("Forced complete path budget did not throw")
        }catch T.SimulationError.pathFailure(let detail) {
            try require(detail=="self budgetExceeded","Unexpected forced path failure: "+detail)
        }
        try require(budget.state==budgetInitial,"Path budget failure committed physical state")
        var reports:[Any]=[],last:T.Attempt?,failure:String?
        let stamp=Date()
        for i in 1...steps {
            let before=session.state
            do {
                let a=try session.advanceStep();last=a
                reports.append(try object(a.report))
                try write(try object(a.report),to:output.appendingPathComponent(String(format:"step-%04d.json",i)))
                if a.report.accepted {
                    try require(session.state.completedSteps==i && session.state.positions==a.candidatePositions,"Accepted step/source mismatch")
                    if i<=8 || i%24==0 {print("STEP",output.lastPathComponent,i,"accepted",a.report.newton.history.count,"source",a.report.maximumSourceEdgeRelativeChange,"gap",a.report.maximumActualSeamGapMeters,"seconds",a.report.computationSeconds);fflush(stdout)}
                } else {
                    try require(session.state==before,"Rejected complete step mutated physical state")
                    failure=a.report.rejectionReason ?? "unaccepted"
                    try write(["positions":pose(a.candidatePositions)],to:output.appendingPathComponent("uncommitted-candidate.json"))
                    if let x=a.lastRejectedNewtonCandidate {try write(["positions":pose(x)],to:output.appendingPathComponent("last-rejected-newton-trial.json"))}
                    print("STOP",output.lastPathComponent,i,failure!);fflush(stdout);break
                }
            } catch {
                try require(session.state==before,"Thrown failure mutated complete physical state")
                failure=String(describing:error)
                print("THROW",output.lastPathComponent,i,failure!);fflush(stdout);break
            }
        }
        try write(["positions":pose(session.state.positions),"velocities":pose(session.state.velocities),"completedSteps":session.state.completedSteps],to:output.appendingPathComponent("last-accepted-state.json"))
        try write(reports,to:output.appendingPathComponent("step-reports.json"))
        var summary:[String:Any]=["sourceSHA256":p.sourceSHA256,"requestedSteps":steps,"actualCompletedSteps":session.state.completedSteps,
            "allRequestedStepsAccepted":session.state.completedSteps==steps,"atomicCancellationVerified":true,"atomicNewtonBudgetVerified":true,
            "atomicPathBudgetVerified":true,"panels":p.input.source.panelBindings.count,"vertices":p.initialPositions.count,
            "triangles":p.input.source.cloth.triangleIndices.count/3,"sewingRows":p.input.objective.sewingRows.count,
            "sourcePins":p.input.source.cloth.pinned.filter{$0}.count,"staticAssemblySteps":p.settings.staticAssemblySteps,
            "gravityRampSteps":p.settings.gravityRampSteps,"timeStepSeconds":p.settings.timeStepSeconds,
            "exactVisibleBodyContainmentVerified":false,"garmentOutputProduced":false,"computationSeconds":Date().timeIntervalSince(stamp)]
        if let failure {summary["failure"]=failure}
        if let last {summary["lastAttempt"]=try object(last.report)}
        try write(summary,to:output.appendingPathComponent("case-summary.json"))
        return try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys])
    }
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let steps=Int(CommandLine.arguments[3]) ?? 8
        try require((1...2400).contains(steps),"Bounded requested steps")
        let filter=CommandLine.arguments.count>4 ? CommandLine.arguments[4]:"all"
        var simulationSettings=T.Settings()
        if CommandLine.arguments.count>5 {
            guard let start=Double(CommandLine.arguments[5]) else {throw Failure.failed("Invalid diagnostic sewing stiffness")}
            simulationSettings.sewingSchedule = .quadraticStiffness(initialNewtonPerMeter:start)
        }
        try require(["all","circle-straight-band","shirt-sleeved"].contains(filter),"Known complete-source test case")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        let materials=T.Materials(membrane:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bending:try .init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8,
            bodyContact:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfContact:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        var rows:[Any]=[]
        for name in ["circle-straight-band","shirt-sleeved"] where filter=="all" || name==filter {
            var design=GarmentCodeDesignParameters(catalog:catalog)
            _ = design.setValue(name=="shirt-sleeved" ? .string("Shirt"):.null,at:["meta","upper"])
            _ = design.setValue(name=="circle-straight-band" ? .string("StraightWB"):.null,at:["meta","wb"])
            _ = design.setValue(name=="circle-straight-band" ? .string("SkirtCircle"):.null,at:["meta","bottom"])
            if name=="circle-straight-band" {_ = design.setValue(.number(0.75),at:["flare-skirt","suns"])}
            else {_ = design.setValue(.bool(false),at:["sleeve","sleeveless"])}
            let doc=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            var settings=T.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
            settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
            let p=try T.prepare(document:doc,body:body,design:design,sourceSettings:settings,materials:materials,settings:simulationSettings)
            let path=out.appendingPathComponent(name);try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
            try write(try object(doc),to:path.appendingPathComponent("complete-paper-source.json"))
            try write(try object(p.input.source.plan),to:path.appendingPathComponent("complete-plan.json"))
            try write(["sourceSHA256":p.sourceSHA256,"positions":pose(p.initialPositions),"referencePositions":pose(p.input.source.cloth.referencePositions),
                "triangleIndices":p.input.source.cloth.triangleIndices,"massesKg":p.input.objective.massesKg,
                "bodyPositions":pose(p.input.source.cloth.mannequinPositions),"bodyTriangleIndices":p.input.source.cloth.mannequinTriangleIndices,
                "bodyClearanceProof":try object(p.bodyClearanceProof),"clothClearanceProof":try object(p.clothClearanceProof),
                "initialBodySurface":try object(p.initialBodySurface),"initialSelfSurface":try object(p.initialSelfSurface)],to:path.appendingPathComponent("complete-initial-input.json"))
            let result=try await Task.detached(priority:.userInitiated) {try run(p,output:path,steps:steps)}.value
            rows.append(try JSONSerialization.jsonObject(with:result))
            try write(["cases":rows,"scope":"Complete source joint integration; rejected steps remain uncommitted; no garment output"],to:out.appendingPathComponent("joint-simulation-summary.json"))
        }
    }
}
