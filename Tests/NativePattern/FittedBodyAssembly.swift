import Foundation

@main @MainActor struct FittedBodyAssemblyRegression {
    typealias K=GarmentCodeCircleDrape
    typealias A=GarmentCodeNativeAssembly
    typealias W=GarmentCodeSewnDrape
    enum Failure:Error {case failed(String)}
    struct Edit:Decodable {let path:[String];let value:JSONValue}
    struct SourceCase:Decodable {let id:String;let body:[String:Double];let overrides:[Edit]}
    struct Fixtures:Decodable {let cases:[SourceCase]}
    struct Row:Codable,Sendable {
        let id:String,sourceSHA256:String,bodyGeometrySHA256:String,fitRecipeSHA256:String,poseRecipeSHA256:String
        let panels:Int,clothVertices:Int,bodyVertices:Int,bodyTriangles:Int,negativeControls:Int
        let maximumRestGoalResidualMeters:Double,initialEnergyJoules:Double
        let workerExecution:Bool,sourceMetricMassAndPinsPreserved:Bool,sameBodyForClearanceDisplayQueriesAndObjective:Bool
        let legacySDFUsed:Bool,clothDynamicsRun:Bool
    }
    nonisolated static func require(_ value:@autoclosure()throws->Bool,_ reason:String)throws {
        guard try value() else {throw Failure.failed(reason)}
    }
    nonisolated static func rejects(_ label:String,_ work:()throws->Void)throws {
        do {try work()}catch is Failure {throw Failure.failed("Unexpected test failure: "+label)}catch{return}
        throw Failure.failed("Accepted invalid route: "+label)
    }
    nonisolated static func check(id:String,recipe:A.Recipe,baseline:A.Recipe,source:W.SourceReceipt,output:URL)throws->Row {
        try require(!Thread.isMainThread,"Fitted preparation ran on the UI thread")
        let base=try A.build(recipe:baseline).preparedInput.cloth
        let prepared=try A.build(recipe:recipe),p=prepared.preparedInput,c=p.cloth
        guard let fitted=c.fittedBodySurface,let mesh=c.bodySurfaceMesh,let bodyValues=source.bodyValues else {
            throw Failure.failed("Missing fitted source capability")
        }
        try fitted.verify(positions:c.mannequinPositions,triangleIndices:c.mannequinTriangleIndices,bodyValues:bodyValues)
        try require(c.standardBody==nil && c.fixedBodySurface==nil && !fitted.compatibleWithLegacyInverseSDF,"Mixed body authority or inverse SDF")
        try require(c.settings.bodyShapeSelection == .surfaceMeasurements && c.settings.bodyPoseSelection == .matchPatternReference,"Fitted route metadata")
        try require(fitted.matchesPatternReference && fitted.alphaDegrees?.bitPattern==bodyValues["arm_pose_angle"]?.bitPattern,"Paper/body arm angle differs")
        try require(p.sourceSHA256==source.sourceSHA256 && p.plan.sourceSHA256==source.sourceSHA256,"Paper source differs")
        try require(c.referencePositions==base.referencePositions && c.referenceTriangles==base.referenceTriangles &&
                    c.inverseMasses==base.inverseMasses && c.totalFabricMassKg==base.totalFabricMassKg &&
                    c.referenceAreaSquareMeters==base.referenceAreaSquareMeters && c.pinned.allSatisfy{!$0},"Fitting changed source metrics, mass or free DOFs")
        try require(mesh.positions==c.mannequinPositions && mesh.triangleIndices==c.mannequinTriangleIndices &&
                    fitted.geometrySHA256==prepared.bodyClearanceProof?.bodyGeometrySHA256 &&
                    fitted.geometrySHA256==prepared.clothClearanceProof?.bodyGeometrySHA256,"Clearance/render/body surfaces differ")
        let exact=try GarmentCodeBodyMeshQueries.Prepared(body:mesh)
        try require(exact.geometrySHA256==fitted.geometrySHA256,"Exact query surface differs")
        for i in [0,1000,10000] {try require(exact.query(c.mannequinPositions[i]).classification == .onSurface,"Actual vertex not on exact body")}
        let input=try GarmentCodeJointInput.prepare(source:p,
            material:.init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:.init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bendingMaterial:.init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8)
        let objective=try GarmentCodeJointGarmentObjective.Prepared(input:input,
            bodyParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        let motion=try objective.body.bodyMotion(from:c.positions,to:c.positions)
        try require(motion.status == .clear && motion.safeTime==1 && motion.statistics.completedAllFeatures,"Actual fitted body CCD did not finish")
        let frame=try objective.frame(predictor:c.positions,timeStepSeconds:1/240,sewingRamp:0)
        let evaluation=try frame.evaluate(positions:c.positions)
        try require(evaluation.energyJoules.isFinite,"Nonfinite full initial fitted-body objective")
        var negatives=0
        func reject(_ label:String,_ work:()throws->Void)throws {try rejects(label,work);negatives += 1}
        try reject("missing fitted capability") {
            var x=c;x.fittedBodySurface=nil
            _=try W.prepare(input:x,plan:p.plan,source:source,bindings:p.panelBindings)
        }
        try reject("legacy inverse SDF attached to fitted surface") {
            var x=c;x.standardBody=base.standardBody
            _=try W.prepare(input:x,plan:p.plan,source:source,bindings:p.panelBindings)
        }
        try reject("fitted capability in legacy route") {
            var x=base;x.fittedBodySurface=fitted
            try K.attachBodySurfaceContact(to:&x)
        }
        try reject("foreign body parameters") {
            var values=bodyValues;values["bust"]! += 0.1
            try fitted.verify(positions:c.mannequinPositions,triangleIndices:c.mannequinTriangleIndices,bodyValues:values)
        }
        try reject("changed display geometry") {
            var positions=c.mannequinPositions;positions[0].x=positions[0].x.nextUp
            try fitted.verify(positions:positions,triangleIndices:c.mannequinTriangleIndices,bodyValues:bodyValues)
        }
        try reject("legacy cloth projection") {_=try K.simulate(input:c)}
        try reject("legacy sewn projection") {_=try W.simulate(input:p)}
        try reject("cancelled fitted assembly") {_=try A.build(recipe:recipe,isCancelled:{true})}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(fitted.bindings).write(to:output.appendingPathComponent(id+"-body-bindings.json"),options:.atomic)
        try encoder.encode(fitted.completeGeometryReport).write(to:output.appendingPathComponent(id+"-body-surface-report.json"),options:.atomic)
        try source.canonicalData.write(to:output.appendingPathComponent(id+"-paper-source.json"),options:.atomic)
        return .init(id:id,sourceSHA256:p.sourceSHA256,bodyGeometrySHA256:fitted.geometrySHA256,
            fitRecipeSHA256:fitted.fitRecipeSHA256,poseRecipeSHA256:fitted.poseRecipeSHA256,
            panels:p.panelBindings.count,clothVertices:c.positions.count,bodyVertices:mesh.positions.count,
            bodyTriangles:mesh.triangleIndices.count/3,negativeControls:negatives,
            maximumRestGoalResidualMeters:fitted.bindings.maximumRestGoalResidualMeters,initialEnergyJoules:evaluation.energyJoules,
            workerExecution:true,sourceMetricMassAndPinsPreserved:true,sameBodyForClearanceDisplayQueriesAndObjective:true,
            legacySDFUsed:false,clothDynamicsRun:false)
    }
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let resources=root.appendingPathComponent("TrailorAss/Resources")
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let fixtures=try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json")))
        var rows:[Row]=[]
        for profile in ["all","female"] {
            guard let selected=fixtures.cases.first(where:{$0.id==profile+"-Shirt-sleeved"}) else {throw Failure.failed("Missing actual body fixture")}
            let body=GarmentCodeBodyParameters(values:selected.body)
            for style in ["circle","shirt"] {
                var design=GarmentCodeDesignParameters(catalog:catalog)
                if style=="shirt" {for edit in selected.overrides {_=design.setValue(edit.value,at:edit.path)}}
                else {for(key,value)in [("upper",JSONValue.null),("wb",.string("StraightWB")),("bottom",.string("SkirtCircle"))] {_=design.setValue(value,at:["meta",key])}}
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
                let source=try W.captureSource(document:document)
                try require(source.bodyValues==body.values,"Paper body capture changed values")
                var settings=K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
                settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.solverIterations=32
                settings.sourceStrainLimit=0.05;settings.sourceStrainLimitPasses=40;settings.bodyResourceDirectory=resources
                let baseline=try A.capture(document:document,body:body,design:design,settings:settings,initialization:.nativeConstruction)
                settings.bodyShapeSelection = .surfaceMeasurements;settings.bodyPoseSelection = .matchPatternReference
                let recipe=try A.capture(document:document,body:body,design:design,settings:settings,initialization:.rigidBodyAndClothPositiveClearance)
                let id=profile+"-"+style
                let row=try await Task.detached {try check(id:id,recipe:recipe,baseline:baseline,source:source,output:out)}.value
                rows.append(row);print("PASS fitted assembly",id,row.clothVertices,"V",row.negativeControls,"negative")
            }
        }
        struct Summary:Codable {let passed:Bool,cases:[Row],wholeGarmentsValidated:Int,targetPhoneTested:Bool}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(Summary(passed:true,cases:rows,wholeGarmentsValidated:0,targetPhoneTested:false))
            .write(to:out.appendingPathComponent("fitted-body-assembly-summary.json"),options:.atomic)
    }
}
