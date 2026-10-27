import Foundation
import Synchronization

/// Tests the two-stage boundary only; no cloth dynamics or garment-fit claim.
@main @MainActor struct PreparationBoundaryRegression {
    typealias A=GarmentCodeNativeAssembly
    typealias D=GarmentCodeSewnDrape
    typealias K=GarmentCodeCircleDrape
    typealias N=NativeAssemblyRegression
    struct Heartbeat:Sendable {let ticks:Int,maximumGapSeconds:Double}
    static func require(_ condition:@autoclosure()throws->Bool,_ message:String)throws {
        if try !condition(){throw N.Failure.check(message)}
    }
    static func timedBuild(_ recipe:A.Recipe)async throws->(A.Preparation,Heartbeat,Double) {
        let start=Date()
        let pulse=Task { @MainActor () throws -> Heartbeat in
            var ticks=0,gap=0.0,last=Date()
            while !Task.isCancelled {
                do {try await Task.sleep(nanoseconds:10_000_000)} catch {break}
                let now=Date();gap=max(gap,now.timeIntervalSince(last));last=now;ticks += 1
            }
            return Heartbeat(ticks:ticks,maximumGapSeconds:gap)
        }
        let worker=Task.detached(priority:.userInitiated) {
            try A.build(recipe:recipe,isCancelled:{Task.isCancelled})
        }
        do {
            let prepared=try await worker.value
            pulse.cancel();let heartbeat=try await pulse.value
            return (prepared,heartbeat,Date().timeIntervalSince(start))
        } catch {
            worker.cancel();pulse.cancel();_ = try? await pulse.value;throw error
        }
    }
    static func reject(_ label:String,_ operation:()throws->Void)throws {
        do {try operation()}catch {return}
        throw N.Failure.check("worker accepted invalid "+label)
    }
    static func copied(_ a:K.Input,flat:[K.Vector3]?=nil,triangles:[UInt32]?=nil,
                       area:Double?=nil,springs:[K.Spring]?=nil)->K.Input {
        var b=K.Input(positions:a.positions,triangleIndices:triangles ?? a.triangleIndices,
            referencePositions:flat ?? a.referencePositions,referenceTriangles:a.referenceTriangles,
            referenceToSimulation:a.referenceToSimulation,panelColumns:a.panelColumns,radialSegments:a.radialSegments,
            seamPaths:a.seamPaths,seamVertexPairs:a.seamVertexPairs,pinned:a.pinned,springs:springs ?? a.springs,
            bendingSprings:a.bendingSprings,body:a.body,mannequinPositions:a.mannequinPositions,
            mannequinTriangleIndices:a.mannequinTriangleIndices,waistCircumferenceMeters:a.waistCircumferenceMeters,
            hemCircumferenceMeters:a.hemCircumferenceMeters,radialLengthMeters:a.radialLengthMeters,
            referenceAreaSquareMeters:area ?? a.referenceAreaSquareMeters,settings:a.settings)
        b.standardBody=a.standardBody;b.surfaceTopology=a.surfaceTopology;b.bodySurfaceMesh=a.bodySurfaceMesh
        b.inverseMasses=a.inverseMasses;b.meanParticleMassKg=a.meanParticleMassKg;b.totalFabricMassKg=a.totalFabricMassKg
        b.garmentStyle=a.garmentStyle;b.patternLengthLabel=a.patternLengthLabel;b.preparationWarnings=a.preparationWarnings;b.waistGatherRatio=a.waistGatherRatio
        return b
    }
    static func main()async throws {
        let catalog=try GarmentCodeParameterCatalog.load(from:N.root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let upper=try JSONDecoder().decode(N.UpperFixture.self,from:Data(contentsOf:N.root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json")))
        var rows:[[String:Any]]=[]
        let ids=["all-Shirt-sleeved","all-Shirt-sleeved-Hood2Panels","layers-FittedShirt-FittedWB-SkirtLevels"]
        for id in ids {
            var design=GarmentCodeDesignParameters(catalog:catalog)
            let body:GarmentCodeBodyParameters
            if let fixture=upper.cases.first(where:{$0.id==id}) {
                body = .init(values:fixture.body)
                for edit in fixture.overrides{_=design.setValue(edit.value,at:edit.path)}
            } else {
                body = .init(values:catalog.body)
                for (key,value) in [("upper","FittedShirt"),("wb","FittedWB"),("bottom","SkirtLevels")] {
                    _=design.setValue(.string(value),at:["meta",key])
                }
            }
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            let sourceBytes=try N.encode(document),captureStart=Date()
            let recipe=try A.capture(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyAndClothPositiveClearance)
            let captureSeconds=Date().timeIntervalSince(captureStart)
            try require(recipe.source.canonicalData==sourceBytes,"complete canonical source bytes not retained")
            try require(recipe.source.geometry.count==document.pattern.panels.count && recipe.source.stitches.count==document.pattern.stitches.count,"partial source receipt")
            let (p,heartbeat,workerSeconds)=try await timedBuild(recipe)
            try require(heartbeat.ticks>0,"MainActor heartbeat did not run during worker preparation")
            let legacy=try A.prepareWithReport(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyAndClothPositiveClearance)
            let signature=try NativeInitializationState.signature(p.preparedInput)
            try require(signature==NativeInitializationState.signature(legacy.preparedInput),"legacy and worker state differs")
            // Two callers share the same immutable recipe but own all mutable
            // mesher/refinement/clearance/validation state independently.
            let first=Task.detached{try A.build(recipe:recipe,isCancelled:{Task.isCancelled})}
            let second=Task.detached{try A.build(recipe:recipe,isCancelled:{Task.isCancelled})}
            let pair=try await (first.value,second.value)
            try require(NativeInitializationState.signature(pair.0.preparedInput)==signature && NativeInitializationState.signature(pair.1.preparedInput)==signature,"concurrent same-recipe state differs")
            let state=Mutex(0)
            let cancelled=Task.detached { () throws -> A.Preparation in
                try A.build(recipe:recipe,isCancelled:{state.withLock{$0 += 1;return $0>=200}})
            }
            do {_ = try await cancelled.value;throw N.Failure.check("mid-worker cancellation accepted")}catch is CancellationError {}catch {throw error}
            try require(state.withLock{$0}>=200,"worker cancellation did not enter real preparation")
            let stream=AsyncStream<Void>.makeStream(bufferingPolicy:.bufferingNewest(1))
            let explicitlyCancelled=Task.detached { () throws -> A.Preparation in
                try A.build(recipe:recipe,isCancelled:{stream.continuation.yield(());return Task.isCancelled})
            }
            for await _ in stream.stream {break}
            explicitlyCancelled.cancel();stream.continuation.finish()
            do {_ = try await explicitlyCancelled.value;throw N.Failure.check("Task cancellation accepted")}catch is CancellationError {}catch {throw error}
            // The worker receipt still runs independent source/rest/facing/
            // area/mass/body/complete-sewing checks; hash equality cannot bypass.
            let input=p.preparedInput.cloth,plan=p.preparedInput.plan,bindings=p.preparedInput.panelBindings
            func validate(_ candidate:K.Input,_ candidatePlan:GarmentCodeSewing.Plan?=nil,_ candidateBindings:[GarmentCodeSewing.PanelBinding]?=nil)throws {
                _ = try D.prepare(input:candidate,plan:candidatePlan ?? plan,source:recipe.source,bindings:candidateBindings ?? bindings)
            }
            var flat=input.referencePositions;flat[0].x += 0.0001
            try reject("source point"){try validate(copied(input,flat:flat))}
            var faces=input.triangleIndices;faces.swapAt(1,2)
            try reject("face normal"){try validate(copied(input,triangles:faces))}
            try reject("source area"){try validate(copied(input,area:input.referenceAreaSquareMeters*1.01))}
            let spring=input.springs[0]
            var springs=input.springs;springs[0] = .init(a:spring.a,b:spring.b,length:spring.length*0.9)
            try reject("rest length"){try validate(copied(input,springs:springs))}
            var bad=copied(input);bad.totalFabricMassKg! *= 1.01
            try reject("physical mass"){try validate(bad)}
            bad=copied(input);bad.inverseMasses[0] += 0.01
            try reject("inverse mass"){try validate(bad)}
            bad=copied(input);bad.standardBody=nil
            try reject("body source"){try validate(bad)}
            try reject("missing panel"){try validate(input,nil,Array(bindings.dropLast()))}
            var object=try JSONSerialization.jsonObject(with:N.encode(plan)) as! [String:Any]
            var anchors=object["anchors"] as! [[String:Any]];anchors.removeLast();object["anchors"]=anchors
            let badPlan=try JSONDecoder().decode(GarmentCodeSewing.Plan.self,from:JSONSerialization.data(withJSONObject:object))
            try reject("incomplete source stitch"){try validate(input,badPlan)}
            rows.append(["case":id,"captureMainActorSeconds":captureSeconds,"workerSeconds":workerSeconds,
                "heartbeatTicks":heartbeat.ticks,"heartbeatMaximumGapSeconds":heartbeat.maximumGapSeconds,
                "stateSHA256":signature,"vertices":input.positions.count,"triangles":input.triangleIndices.count/3,
                "sameRecipeConcurrentBuilds":2,"workerCancellationPolls":state.withLock{$0},"taskCancellationRejected":true,
                "invalidWorkerInputsRejected":9,"legacyMatches":true])
            N.log("PASS preparation boundary "+id+" capture=\(captureSeconds)s worker=\(workerSeconds)s heartbeat=\(heartbeat.ticks)")
        }
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_PREPARATION_OUTPUT"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("TailorAssPreparationBoundary-"+UUID().uuidString).path)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let summary:[String:Any]=["passed":true,"scope":"Two-stage source-faithful preparation only; no dynamics, UI stale-publication, iPhone performance or fit claim","cases":rows,"remainingMainActorCapture":true]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("summary.json"))
    }
}
