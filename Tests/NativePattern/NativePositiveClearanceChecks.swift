import Foundation

@MainActor enum NativePositiveClearanceChecks {
    typealias A=GarmentCodeNativeAssembly
    typealias N=NativeAssemblyRegression
    typealias Q=RigidBodyClearanceRegression
    struct Golden:Decodable {let format:String,stateHasherSHA256:String,cases:[String:[String:String]]}
    struct Geometry:Encodable {
        let caseID:String,sourceSHA256:String,stateSignature:String
        let positions:[GarmentCodeCircleDrape.Vector3],triangleIndices:[UInt32]
        let panelNames:[String],vertexPanelIDs:[Int],trianglePanelIDs:[Int]
    }
    static var golden:Golden?
    static var out:URL?
    static func run(id:String,document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,native:GarmentCodeSewnDrape.PreparedInput)throws->[String:Any] {
        if golden==nil {
            golden=try JSONDecoder().decode(Golden.self,from:Data(contentsOf:N.root.appendingPathComponent("Tests/NativePattern/Fixtures/native-initialization-three-mode-goldens.json")))
            try N.require(golden!.format=="GarmentCodeNativeInitializationThreeModeGoldens/v1" && golden!.cases.count==211,"incomplete old three-mode signatures")
            try N.require(NativeInitializationState.hash(Data(contentsOf:N.root.appendingPathComponent("Tests/NativePattern/NativeInitializationState.swift")))==golden!.stateHasherSHA256,"state signature definition changed")
            out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_NATIVE_OUTPUT"] ?? "/private/tmp/TailorAssNativePositiveClearance")
        }
        guard let expected=golden!.cases[id] else{throw N.Failure.check("missing exact three-mode case")}
        let nativeHash=try NativeInitializationState.signature(native)
        try N.require(nativeHash==expected["nativeConstruction"],"\(id): original native construction changed")
        let oldBody=try A.prepare(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyClearance)
        let oldBodyHash=try NativeInitializationState.signature(oldBody)
        try N.require(oldBodyHash==expected["rigidBodyClearance"],"\(id): original body-only mode changed")
        let oldCloth=try A.prepare(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyAndClothClearance)
        let oldClothHash=try NativeInitializationState.signature(oldCloth)
        try N.require(oldClothHash==expected["rigidBodyAndClothClearance"],"\(id): original crossing-only mode changed")
        let final=try A.prepareWithReport(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyAndClothPositiveClearance)
        guard let proof=final.clothClearanceProof,let bodyProof=final.bodyClearanceProof else{throw N.Failure.check("new opt-in missing support proofs")}
        let prepared=final.preparedInput,input=prepared.cloth
        var row=try N.check(prepared,document:document)
        try N.require(proof.positiveGapTargetMeters==0.00005 && !proof.nearContactsNotCertifiedAbsent && proof.finalInspection.conflicts.isEmpty && proof.finalInspection.nearTrianglePairs==0,"new bootstrap did not inspect all positive-gap conflicts")
        try N.require(proof.steps.count<=prepared.panelBindings.count-1 && proof.totalExtraTranslationMeters<=0.15+1e-12 && proof.translationsByPanel.values.allSatisfy{$0.length<=0.05+1e-12},"fixed N-1/per-panel/total translation budget changed")
        try N.require(bodyProof.bodyGeometrySHA256==proof.bodyGeometrySHA256 && input.mannequinPositions==native.cloth.mannequinPositions && input.mannequinTriangleIndices==native.cloth.mannequinTriangleIndices,"visible source body changed")
        try N.require(input.referencePositions==native.cloth.referencePositions && input.referenceTriangles==native.cloth.referenceTriangles && input.triangleIndices==native.cloth.triangleIndices && input.inverseMasses==native.cloth.inverseMasses && input.pinned==native.cloth.pinned && input.referenceToSimulation==native.cloth.referenceToSimulation,"source metric, mass or independent DOFs changed")
        let signature=try NativeInitializationState.signature(prepared)
        if proof.initialInspection.conflicts.isEmpty{try N.require(proof.steps.isEmpty && signature==oldBodyHash,"already positive body-clear source was moved or its plan changed")}
        var gapError=0.0,directionError=0.0
        for c in prepared.plan.constraints {
            let d=try c.a.point(in:input.positions)-c.b.point(in:input.positions),gap=d.length
            gapError=max(gapError,abs(gap-c.initialGapMeters))
            let direction=gap>1e-12 ? d/gap:GarmentCodeCircleDrape.Vector3.zero
            directionError=max(directionError,(direction-c.initialDirection).length)
        }
        try N.require(gapError<1e-10 && directionError<1e-9,"positive-gap final positions reused stale sewing initial state")
        let tethers=try GarmentCodeSourceTethers.prepare(input:prepared)
        try N.require(tethers.provenance == .verifiedSourceSHA256(prepared.sourceSHA256) && tethers.tethers.isEmpty && tethers.unreachableVertexIDs.count==input.positions.count,"new complete plan gained pins or source aliases")
        Q.currentDocument=document
        let geometry=try Q.quality(prepared)
        for key in ["independentBodyTriangleCrossings","independentInterPanelProperCrossings","independentInterPanelCoplanarOverlaps","insideVertices","insideCentroids","ambiguousVertices","ambiguousCentroids"] {try N.require((geometry[key] as! Int)==0,"\(id): independent \(key) remains")}
        var vp=Array(repeating:-1,count:input.positions.count),tp=Array(repeating:-1,count:input.triangleIndices.count/3)
        for (panel,binding) in prepared.panelBindings.enumerated(){
            for v in binding.vertexIDs{try N.require(vp[v] == -1,"source vertex shared between panels");vp[v]=panel}
            for t in binding.triangleIDs{try N.require(tp[t] == -1,"source face shared between panels");tp[t]=panel}
        }
        try N.require(!vp.contains(-1) && !tp.contains(-1),"incomplete positive-gap source export")
        let saved=Geometry(caseID:id,sourceSHA256:prepared.sourceSHA256,stateSignature:signature,positions:input.positions,triangleIndices:input.triangleIndices,panelNames:prepared.panelBindings.map{$0.mesh.panelID},vertexPanelIDs:vp,trianglePanelIDs:tp)
        let stem=id.map{$0.isLetter || $0.isNumber || $0=="-" || $0=="_" ? $0:"_"}.map(String.init).joined()
        try N.encode(saved).write(to:out!.appendingPathComponent(stem+"-positive-input.json"))
        if !proof.steps.isEmpty{try N.encode(proof).write(to:out!.appendingPathComponent(stem+"-positive-proof.json"))}
        row["oldThreeModeSignatures"]=["nativeConstruction":nativeHash,"rigidBodyClearance":oldBodyHash,"rigidBodyAndClothClearance":oldClothHash]
        row["finalStateSHA256"]=signature;row["movedPanels"]=proof.steps.count;row["extraShiftMeters"]=proof.totalExtraTranslationMeters
        row["translationsByPanel"]=try N.object(proof.translationsByPanel);row["positiveBootstrapTargetMeters"]=proof.positiveGapTargetMeters!
        row["supportRefinementCount"]=proof.supportRefinements?.count ?? 0
        row["samePanelPrimitiveTests"]=proof.samePanelNonAdjacentPrimitivePairsTested!;row["geometry"]=geometry
        row["initialGapMaximumErrorMeters"]=gapError;row["initialDirectionMaximumError"]=directionError
        row["completePlanSHA256"]=NativeInitializationState.hash(try N.encode(prepared.plan));row["physicalAcceptance"]=false
        return row
    }
}
