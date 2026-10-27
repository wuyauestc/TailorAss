import Foundation
import CryptoKit

@main @MainActor struct FixedBodyAssemblyRegression {
    typealias K=GarmentCodeCircleDrape
    typealias A=GarmentCodeNativeAssembly
    typealias B=GarmentCodeAssemblyBuilder
    typealias J=GarmentCodeJointObjective
    enum Failure:Error {case failed(String)}
    struct Golden:Decodable {let cases:[String:[String:String]]}
    struct Edit:Decodable{let path:[String];let value:JSONValue}
    struct SourceCase:Decodable{let id:String;let body:[String:Double];let overrides:[Edit]}
    struct Upper:Decodable{let cases:[SourceCase]}
    static func check(_ x:@autoclosure()throws->Bool,_ m:String)throws {if try !x(){throw Failure.failed(m)}}
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let resources=root.appendingPathComponent("TrailorAss/Resources")
        let cat=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let upper=try JSONDecoder().decode(Upper.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/upper-placement-oracles.json")))
        let gold=try JSONDecoder().decode(Golden.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/native-initialization-three-mode-goldens.json")))
        var settings=K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.solverIterations=32;settings.sourceStrainLimit=0.05;settings.sourceStrainLimitPasses=40;settings.bodyResourceDirectory=resources
        var rows:[[String:Any]]=[],legacyChecks=0,negativeChecks=0
        for profile in ["all","female"] {
            let selected=try upper.cases.first{$0.id==profile+"-Shirt-sleeved"}.unwrap("Missing real complete Shirt fixture")
            let body=GarmentCodeBodyParameters(values:selected.body)
            for style in ["circle","shirt"] {
                var design=GarmentCodeDesignParameters(catalog:cat)
                if style=="shirt" {for edit in selected.overrides {_ = design.setValue(edit.value,at:edit.path)}}
                else {for(key,value)in [("upper",JSONValue.null),("wb",.string("StraightWB")),("bottom",.string("SkirtCircle"))] {_ = design.setValue(value,at:["meta",key])}}
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
                let id=style=="shirt" ? "upper:"+profile+"-Shirt-sleeved":(profile=="all" ? "meta-grid-defaults:":"meta-grid-female:")+"None|StraightWB|SkirtCircle"
                var baseline:GarmentCodeSewnDrape.PreparedInput?
                for mode in [A.Initialization.nativeConstruction,.rigidBodyClearance,.rigidBodyAndClothClearance] {
                    let p=try A.prepare(document:document,body:body,design:design,settings:settings,initialization:mode)
                    let signature=try NativeInitializationState.signature(p)
                    try check(signature==gold.cases[id]?[String(describing:mode)],"Legacy full-state bytes changed: "+id+" "+String(describing:mode))
                    try check(p.cloth.fixedBodySurface==nil && p.cloth.standardBody != nil,"Legacy received posed capability")
                    if mode == .nativeConstruction{baseline=p};legacyChecks += 1
                }
                for alpha in [30.0,45.0,60.0,body["arm_pose_angle"]!] {
                    var posedBody=body;posedBody.set(alpha,for:"arm_pose_angle")
                    let doc=try GarmentCodeNativeGenerator.generate(body:posedBody,design:design)
                    var ps=settings;ps.bodyPoseSelection = .matchPatternReference
                    let recipe=try A.capture(document:doc,body:posedBody,design:design,settings:ps,initialization:.rigidBodyAndClothPositiveClearance)
                    let prepared=try A.build(recipe:recipe),p=prepared.preparedInput,c=p.cloth
                    let receipt=try c.fixedBodySurface.unwrap("Missing posed surface capability")
                    try check(c.standardBody==nil,"Posed input acquired legacy inverseSDF")
                    if alpha==body["arm_pose_angle"]! {
                        try check(receipt.geometrySHA256 != receipt.sourceGeometrySHA256,"Raw default angle silently became legacy identity")
                    }
                    try receipt.verify(positions:c.mannequinPositions,triangleIndices:c.mannequinTriangleIndices)
                    try check(receipt.geometrySHA256==prepared.bodyClearanceProof?.bodyGeometrySHA256 && receipt.geometrySHA256==prepared.clothClearanceProof?.bodyGeometrySHA256,"Body proof SHA differs")
                    try check(prepared.clothClearanceProof?.finalInspection.conflicts.isEmpty==true,"Positive clearance incomplete")
                    let base=try baseline.unwrap("Missing native baseline").cloth
                    try check(c.referencePositions==base.referencePositions && c.referenceTriangles==base.referenceTriangles && c.inverseMasses==base.inverseMasses && c.totalFabricMassKg==base.totalFabricMassKg && c.pinned.allSatisfy{!$0},"Source metric/mass/DOFs changed")
                    let exact=try GarmentCodeBodyMeshQueries.Prepared(body:receipt.mesh)
                    try check(exact.geometrySHA256==receipt.geometrySHA256,"Exact body query mismatch")
                    for i in [0,1000,10000]{try check(exact.query(c.mannequinPositions[i]).classification == .onSurface,"Actual posed vertex is not on exact body")}
                    let ji=try GarmentCodeJointInput.prepare(source:p,material:.init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
                        strainBarrier:.init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),bendingMaterial:.init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8)
                    let objective=try GarmentCodeJointGarmentObjective.Prepared(input:ji,bodyParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),selfParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
                    let motion=try objective.body.bodyMotion(from:c.positions,to:c.positions)
                    try check(motion.status == .clear && motion.safeTime==1,"Actual posed body static CCD mismatch")
                    let frame=try objective.frame(predictor:c.positions,timeStepSeconds:1/240,sewingRamp:0),e=try frame.evaluate(positions:c.positions)
                    try check(e.energyJoules.isFinite,"Full posed-body force is nonfinite")
                    let source=try GarmentCodeSewnDrape.captureSource(document:doc)
                    func rejects(_ label:String,_ mutate:(inout K.Input)->Void)throws {
                        var x=c;mutate(&x)
                        do{_=try GarmentCodeSewnDrape.prepare(input:x,plan:p.plan,source:source,bindings:p.panelBindings);throw Failure.failed("Accepted tamper: "+label)}catch is Failure{throw Failure.failed("Accepted tamper: "+label)}catch{negativeChecks += 1}
                    }
                    var forged=c.mannequinPositions;forged[0].x += 1e-5
                    do{try receipt.verify(positions:forged,triangleIndices:c.mannequinTriangleIndices);throw Failure.failed("Altered mesh matched receipt")}catch is Failure{throw Failure.failed("Altered mesh matched receipt")}catch{negativeChecks += 1}
                    do{
                        _=try GarmentCodeBodySurfaceContact.captureFixedSurface(positions:forged,triangleIndices:c.mannequinTriangleIndices,
                            expectedGeometrySHA256:GarmentCodeBodyRig.geometryHash(forged,c.mannequinTriangleIndices),
                            sourcePositions:base.mannequinPositions,sourceTriangleIndices:base.mannequinTriangleIndices,
                            rigResourceSHA256:receipt.rigResourceSHA256,requestedAlphaDegrees:alpha,
                            templateData:Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json")),
                            rigData:Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodyRig/rig.json")),bodyValues:posedBody.values)
                        throw Failure.failed("Correct claimed hashes with arbitrary pose acquired receipt")
                    }catch is Failure{throw Failure.failed("Forged claimed pose acquired receipt")}catch{negativeChecks += 1}

                    try rejects("legacy inverse SDF"){$0.standardBody=base.standardBody}
                    try rejects("missing capability"){$0.fixedBodySurface=nil}
                    var foreignDesign=design
                    _=foreignDesign.setValue(.null,at:["meta","upper"]);_=foreignDesign.setValue(.null,at:["meta","bottom"]);_=foreignDesign.setValue(.string("StraightWB"),at:["meta","wb"])
                    let foreign=try GarmentCodeSewnDrape.captureSource(document:GarmentCodeNativeGenerator.generate(body:posedBody,design:foreignDesign))
                    do{_=try GarmentCodeSewnDrape.prepare(input:c,plan:p.plan,source:foreign,bindings:p.panelBindings);throw Failure.failed("Foreign paper source accepted")}catch is Failure{throw Failure.failed("Foreign paper source accepted")}catch{negativeChecks += 1}

                    do{_=try K.simulate(input:c);throw Failure.failed("Legacy K accepted posed input")}catch is K.DrapeError{negativeChecks += 1}
                    do{_=try GarmentCodeSewnDrape.simulate(input:p);throw Failure.failed("Legacy sewn accepted posed input")}catch is K.DrapeError{negativeChecks += 1}
                    do{_=try A.build(recipe:recipe,isCancelled:{true});throw Failure.failed("Cancellation accepted")}catch is CancellationError{negativeChecks += 1}
                    rows.append(["profile":profile,"style":style,"alpha":alpha,"sourceSHA":p.sourceSHA256,"bodySHA":receipt.geometrySHA256,"vertices":c.positions.count,"panels":p.panelBindings.count,"sourceMassKg":c.totalFabricMassKg!,"energyJoules":e.energyJoules,"legacySDF":false,"physicsRun":false])
                    print("PASS posed \(profile) \(style) \(alpha) \(c.positions.count)V")
                }
            }
            let standard=try GarmentCodeStandardBody.load(body:body,resourceDirectory:resources)
            var mismatched=body.values;mismatched["waist"]! *= 1.01
            let wrongShape=GarmentCodeFixedBody.recipe(source:standard,bodyValues:mismatched,resourceDirectory:resources)
            do{_=try GarmentCodeFixedBody.prepare(wrongShape);throw Failure.failed("Different source body shape accepted")}catch is Failure{throw Failure.failed("Different source body shape accepted")}catch{negativeChecks += 1}
            for value in [Double.nan,91] {
                var bad=body;bad.set(value,for:"arm_pose_angle");var ps=settings;ps.bodyPoseSelection = .matchPatternReference
                let r=try B.captureBody(body:bad,settings:ps)
                do{_=try B.prepareBody(r);throw Failure.failed("Bad pose acquired receipt")}catch is Failure{throw Failure.failed("Bad pose acquired receipt")}catch{negativeChecks += 1}
            }
        }
        try JSONSerialization.data(withJSONObject:["passed":true,"legacyByteChecks":legacyChecks,"posedFullSourceCases":rows,"negativeChecks":negativeChecks,"physicsRun":false,"personalMeasurementsFitted":false],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fixed-body-assembly-summary.json"))
    }
}
extension Optional {func unwrap(_ message:String)throws->Wrapped {guard let value=self else {throw FixedBodyAssemblyRegression.Failure.failed(message)};return value}}
