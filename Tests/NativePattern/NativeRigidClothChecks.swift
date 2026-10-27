import Foundation

@MainActor enum NativeRigidClothChecks {
    typealias A=GarmentCodeNativeAssembly
    typealias N=NativeAssemblyRegression
    typealias Q=RigidBodyClearanceRegression
    struct Golden:Decodable {let format:String,stateHasherSHA256:String,cases:[String:[String:String]]}
    static var golden:Golden?
    static var out:URL?
    static func run(id:String,document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,native:GarmentCodeSewnDrape.PreparedInput)throws->[String:Any] {
        let root=N.root
        if golden==nil {
            golden=try JSONDecoder().decode(Golden.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/native-initialization-old-mode-goldens.json")))
            try N.require(golden!.format=="GarmentCodeNativeInitializationOldModeGoldens/v1" && golden!.cases.count==211,"incomplete pre-new-option signatures")
            try N.require(NativeInitializationState.hash(Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/NativeInitializationState.swift")))==golden!.stateHasherSHA256,"state signature definition changed")
            out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_NATIVE_OUTPUT"] ?? "/private/tmp/TailorAssNativeRigidCloth")
        }
        guard let expected=golden!.cases[id] else{throw N.Failure.check("missing exact old-option case")}
        let nativeHash=try NativeInitializationState.signature(native)
        try N.require(nativeHash==expected["nativeConstruction"],"\(id): old nativeConstruction values/plan changed")
        let oldBody=try A.prepareWithReport(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyClearance)
        try N.require(oldBody.clothClearanceProof==nil && oldBody.bodyClearanceProof != nil,"old body-only semantics changed")
        let bodyHash=try NativeInitializationState.signature(oldBody.preparedInput)
        try N.require(bodyHash==expected["rigidBodyClearance"],"\(id): old rigidBodyClearance values/plan changed")
        let final=try A.prepareWithReport(document:document,body:body,design:design,settings:N.settings(),initialization:.rigidBodyAndClothClearance)
        guard let proof=final.clothClearanceProof,let bodyProof=final.bodyClearanceProof else{throw N.Failure.check("explicit new mode missing both proofs")}
        let prepared=final.preparedInput,input=prepared.cloth
        var source=try N.check(prepared,document:document)
        try N.require(proof.finalInspection.conflicts.isEmpty && proof.steps.count<=prepared.panelBindings.count-1 && proof.totalExtraTranslationMeters<=0.15+1e-12,"new initializer not strictly bounded/clear")
        try N.require(bodyProof.bodyGeometrySHA256==proof.bodyGeometrySHA256 && input.referencePositions==oldBody.preparedInput.cloth.referencePositions && input.referenceTriangles==oldBody.preparedInput.cloth.referenceTriangles && input.triangleIndices==oldBody.preparedInput.cloth.triangleIndices && input.inverseMasses==oldBody.preparedInput.cloth.inverseMasses && input.pinned==oldBody.preparedInput.cloth.pinned,"source/mass/DOFs/body proof changed")
        let finalHash=try NativeInitializationState.signature(prepared)
        if proof.initialInspection.conflicts.isEmpty{try N.require(proof.steps.isEmpty && finalHash==bodyHash,"already-clear source moved or its complete plan changed")}
        var gapError=0.0,directionError=0.0
        for c in prepared.plan.constraints {
            let delta=try c.a.point(in:input.positions)-c.b.point(in:input.positions),gap=delta.length
            gapError=max(gapError,abs(gap-c.initialGapMeters))
            let direction=gap>1e-12 ? delta/gap:GarmentCodeCircleDrape.Vector3.zero
            directionError=max(directionError,(direction-c.initialDirection).length)
        }
        try N.require(gapError<1e-10 && directionError<1e-9,"Builder reused stale initialGap or direction from body-only positions")
        let tethers=try GarmentCodeSourceTethers.prepare(input:prepared)
        try N.require(tethers.provenance == .verifiedSourceSHA256(prepared.sourceSHA256) && tethers.tethers.isEmpty && tethers.unreachableVertexIDs.count==input.positions.count,"new source/plan graph failed or gained hidden support pins")
        Q.currentDocument=document
        let quality=try Q.quality(prepared)
        try N.require((quality["independentBodyTriangleCrossings"] as! Int)==0 && (quality["independentInterPanelProperCrossings"] as! Int)==0 && (quality["independentInterPanelCoplanarOverlaps"] as! Int)==0 && (quality["insideVertices"] as! Int)==0 && (quality["insideCentroids"] as! Int)==0 && (quality["ambiguousVertices"] as! Int)==0 && (quality["ambiguousCentroids"] as! Int)==0,"independent body/self/inside oracle did not clear")
        let selfQuality=quality["selfQuality"] as! [String:Any],bodyQuality=quality["bodyQuality"] as! [String:Any]
        try N.require((selfQuality["intersectingTrianglePairs"] as! Int)==0 && (bodyQuality["intersectingTrianglePairs"] as! Int)==0,"production contact inspector disagrees with independent geometry")
        source["oldNativeConstructionStateSHA256"]=nativeHash;source["oldRigidBodyClearanceStateSHA256"]=bodyHash
        source["initialConflictTrianglePairs"]=proof.initialInspection.conflicts.count;source["movedPanels"]=proof.steps.count
        source["finalStateSHA256"]=finalHash;source["clothClearanceProof"]=try N.object(proof)
        source["initialGapMaximumErrorMeters"]=gapError;source["initialDirectionMaximumError"]=directionError
        source["newPlanTetherGraphNodes"]=tethers.graphNodeCount;source["newPlanTetherGraphEdges"]=tethers.graphEdgeCount
        source["unreachableComponentsWithoutHiddenPins"]=tethers.unreachableComponentCount
        source["geometry"]=quality;source["physicalAcceptance"]=false
        let stem=id.map{$0.isLetter || $0.isNumber || $0=="-" || $0=="_" ? $0:"_"}.map(String.init).joined()
        if !proof.steps.isEmpty {
            try N.encode(proof).write(to:out!.appendingPathComponent(stem+"-cloth-proof.json"))
            try N.encode(prepared.plan).write(to:out!.appendingPathComponent(stem+"-new-plan.json"))
            try N.encode(input.positions).write(to:out!.appendingPathComponent(stem+"-new-positions.json"))
        }
        return source
    }
}
