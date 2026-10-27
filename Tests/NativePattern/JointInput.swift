import Foundation

@main @MainActor struct JointInputRegression {
    typealias K=GarmentCodeCircleDrape
    typealias J=GarmentCodeJointObjective
    enum Failure:Error {case failed(String)}
    static func require(_ b:Bool,_ message:String)throws {if !b{throw Failure.failed(message)}}
    static func main()throws {
        let args=CommandLine.arguments,root=URL(fileURLWithPath:args[1]),out=URL(fileURLWithPath:args[2])
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        let m=try J.M.Material(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170)
        let b=try J.M.StrainBarrier(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)
        let h=try J.H.Material(bendingStiffnessNewtonMeter:2e-4)
        var cases:[[String:Any]]=[]
        for configuration in [("circleAndBand",Optional<String>.none,Optional("StraightWB"),Optional("SkirtCircle")),
                              ("shirtSleevesHood",Optional("Shirt"),Optional<String>.none,Optional<String>.none)] {
            var design=GarmentCodeDesignParameters(catalog:catalog)
            _ = design.setValue(configuration.1.map(JSONValue.string) ?? .null,at:["meta","upper"])
            _ = design.setValue(configuration.2.map(JSONValue.string) ?? .null,at:["meta","wb"])
            _ = design.setValue(configuration.3.map(JSONValue.string) ?? .null,at:["meta","bottom"])
            if configuration.0=="circleAndBand" {_ = design.setValue(.number(0.75),at:["flare-skirt","suns"])}
            else {
                try require(design.setValue(.string("Hood2Panels"),at:["collar","component","style"]),"Hood parameter path")
                try require(design.setValue(.bool(false),at:["sleeve","sleeveless"]),"Sleeve parameter path")
            }
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            if configuration.0=="shirtSleevesHood" {
                try require(document.pattern.panels.keys.contains{$0.contains("hood")},"Actual hood source panels")
                try require(document.pattern.panels.keys.contains{$0.contains("sleeve")},"Actual sleeve source panels")
            }
            var settings=K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
            settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true
            settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
            let source=try GarmentCodeNativeAssembly.prepare(document:document,body:body,design:design,settings:settings,
                initialization:.rigidBodyAndClothPositiveClearance)
            let input=try GarmentCodeJointInput.prepare(source:source,material:m,strainBarrier:b,bendingMaterial:h,sewingComplianceMetersPerNewton:1e-8)
            try require(input.sourceSHA256==source.sourceSHA256 && input.source.plan.sourceSHA256==source.plan.sourceSHA256,"Source identity")
            try require(input.source.cloth.positions==source.cloth.positions && input.source.cloth.referencePositions==source.cloth.referencePositions,"Original coordinates")
            try require(input.source.cloth.mannequinPositions==source.cloth.mannequinPositions && input.source.cloth.mannequinTriangleIndices==source.cloth.mannequinTriangleIndices,"Original body")
            try require(input.objective.massesKg.count==source.cloth.positions.count && input.objective.sewingRows.count==source.plan.constraints.count,"Complete source DOFs/constraints")
            let total=input.objective.massesKg.reduce(0,+)
            try require(abs(total-source.cloth.totalFabricMassKg!)<1e-12,"Original SI mass")
            for (mass,inverse) in zip(input.objective.massesKg,source.cloth.inverseMasses) {
                try require(abs(mass*inverse-source.cloth.meanParticleMassKg)<1e-12,"SI mass vs verified normalized mass")
            }
            let frame=try input.objective.frame(predictor:source.cloth.positions,timeStepSeconds:1/240,sewingRamp:0)
            let evaluation=try frame.evaluate(positions:source.cloth.positions)
            try require(evaluation.inertiaJoules==0 && evaluation.sewingJoules<1e-18,"Initial source predictor/sewing rest")
            cases.append(["case":configuration.0,"sourceSHA256":input.sourceSHA256,"panels":source.panelBindings.count,
                "vertices":input.objective.massesKg.count,"constraints":input.objective.sewingRows.count,
                "hinges":input.objective.bending.hinges.count,"massKg":total,"initialEnergyJoules":evaluation.energyJoules])
            do {
                _ = try GarmentCodeJointInput.prepare(source:source,material:m,strainBarrier:b,bendingMaterial:h,sewingComplianceMetersPerNewton:1e-8,isCancelled:{true})
                throw Failure.failed("Cancellation ignored")
            } catch is CancellationError {}
        }
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:["passed":true,"cases":cases,"physicalStepAccepted":false,
            "scope":"Real full-source PreparedInput to joint objective, all source/body/seams and SI mass retained; no cloth dynamics"],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("joint-input-summary.json"))
        print("Joint input: complete source/body/real sewing and original SI masses retained; no physical step claimed.")
    }
}
