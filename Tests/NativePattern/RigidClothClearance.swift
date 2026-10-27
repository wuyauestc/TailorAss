import Foundation

@main @MainActor struct RigidClothClearanceRegression {
    typealias C=GarmentCodeRigidClothClearance
    typealias R=GarmentCodeRigidBodyClearance
    typealias O=BodySurfaceContactRegression
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error{case check(String)}
    static func require(_ value:Bool,_ s:String)throws{if !value{throw Failure.check(s)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V{.init(x:x,y:y,z:z)}
    static let quad:[UInt32]=[0,1,2,0,2,3]
    static func panel(_ id:String,_ axis:Int=2,_ size:Double=0.02,_ offset:Double=0,_ error:Double=0)->R.Panel{
        let square=[(-size,-size),(size,-size),(size,size),(-size,size)]
        let p=square.map{axis==2 ? v($0.0,$0.1,offset):(axis==0 ? v(offset,$0.0,$0.1):v($0.1,offset,$0.0))}
        return .init(panelID:id,positions:p,u:axis==2 ? v(1,0,0):(axis==0 ? v(0,1,0):v(0,0,1)),v:axis==2 ? v(0,1,0):(axis==0 ? v(0,0,1):v(1,0,0)),normal:axis==2 ? v(0,0,1):(axis==0 ? v(1,0,0):v(0,1,0)),maximumBoundaryDeviationMeters:error)
    }
    static func body()->O.Mesh{O.box(center:.zero,half:v(0.001,0.001,0.001))}
    static func cleared(_ panels:[R.Panel])throws->R.Result{let b=body();return try R.prepare(panels:panels,bodyPositions:b.positions,bodyTriangleIndices:b.indices)}
    static func independent(_ result:C.Result,_ triangles:[String:[UInt32]])throws {
        let ids=result.positionsByPanel.keys.sorted(),b=body()
        for id in ids{try require(O.oracleCount(cloth:.init(positions:result.positionsByPanel[id]!,indices:triangles[id]!),body:b)==0,"actual body proper crossing")}
        for a in ids.indices{for b in ids.indices where b>a{
            let first=O.Mesh(positions:result.positionsByPanel[ids[a]]!,indices:triangles[ids[a]]!),second=O.Mesh(positions:result.positionsByPanel[ids[b]]!,indices:triangles[ids[b]]!)
            try require(O.oracleCount(cloth:first,body:second)==0,"independent Moller-Trumbore crossing remains")
            for x in O.faces(first){for y in O.faces(second) where x.overlaps(y){try require(!RigidBodyClearanceRegression.coplanarOverlap(x,y),"independent positive-area coplanar overlap remains")}}
        }}
    }
    nonisolated final class Counter:@unchecked Sendable {
        private let lock=NSLock();private var value=0
        let limit:Int
        init(_ limit:Int){self.limit=limit}
        func cancel()->Bool{lock.lock();defer{lock.unlock()};value += 1;return value>=limit}
    }
    static func main()throws {
        var cases:[String]=[];let sheets=[panel("A"),panel("B"),panel("C")],input=try cleared(sheets),triangles=Dictionary(uniqueKeysWithValues:sheets.map{($0.panelID,quad)})
        let result=try C.prepare(bodyCleared:input,trianglesByPanel:triangles)
        try independent(result,triangles)
        try require(result.proof.steps.count==2 && result.proof.initialInspection.coplanarTrianglePairs==6 && result.proof.finalInspection.conflicts.isEmpty,"three sheets did not satisfy N-1")
        try require(abs(result.proof.steps[0].appliedTranslation.z-0.005000001)<1e-12 && abs(result.proof.steps[1].appliedTranslation.z-0.010000002)<1e-12,"second sheet did not include already-cleared sheet in ALL-other support")
        cases.append("three coincident panels, all-other support, strict N-1 and independent final oracle")
        let axes=[panel("A",2),panel("B",0),panel("C",1)],orthogonal=try cleared(axes),orthogonalResult=try C.prepare(bodyCleared:orthogonal,trianglesByPanel:triangles)
        try independent(orthogonalResult,triangles);try require(orthogonalResult.proof.steps.count==2,"three different normals did not clear in N-1")
        cases.append("three mutually perpendicular planes and fixed outward signs")
        let a=panel("A",2,0.01),b=R.Panel(panelID:"B",positions:[v(0.005,0.005,-0.02),v(0.005,0.005,0.02),v(0.005,0.2,0)],u:v(0,1,0),v:v(0,0,1),normal:v(1,0,0))
        let rangeInput=try cleared([a,b]),rangeTriangles:[String:[UInt32]]=["A":quad,"B":[0,1,2]],rangeResult=try C.prepare(bodyCleared:rangeInput,trianglesByPanel:rangeTriangles)
        try independent(rangeResult,rangeTriangles)
        let option=rangeResult.proof.steps[0].supportOptions.first{$0.panelID=="A"}!,center=rangeInput.positionsByPanel["B"]!.reduce(V.zero,+)/3
        let d=center-option.origin,projected=d.x*option.v.x+d.y*option.v.y+d.z*option.v.z
        try require(projected>option.uvBounds.maximumV+option.projectionPaddingMeters && option.candidateTriangles.contains(.init(panelID:"B",triangleIndex:0)),"centroid-only filtering silently missed real overlap")
        cases.append("centroid outside rectangle but whole triangle AABB overlaps")
        let x0=0.015025,x1=0.02,edge=R.Panel(panelID:"C",positions:[v(x0,-0.005,0.01),v(x1,-0.005,0.01),v(x1,0.005,0.01),v(x0,0.005,0.01)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1),maximumBoundaryDeviationMeters:0.00005)
        let errorInput=try cleared([a,panel("B",2,0.01),edge]),errorResult=try C.prepare(bodyCleared:errorInput,trianglesByPanel:triangles)
        try independent(errorResult,triangles)
        let errorSupport=errorResult.proof.steps[0].supportOptions.first{$0.panelID=="A"}!
        try require(errorSupport.candidateTriangles.contains(.init(panelID:"C",triangleIndex:0)) && abs(errorSupport.requiredExtraTranslationMeters-0.015050001)<1e-12 && errorSupport.maximumOtherBoundaryDeviationMeters==0.00005,"other curved-boundary uncertainty lost in UV/normal support")
        cases.append("thin source-boundary uncertainty in BOTH projection and normal support")
        let separate=try cleared([panel("A",2,0.01,0.02),panel("B",2,0.01,0.04)]),separateTriangles:[String:[UInt32]]=["A":quad,"B":quad],unchanged=try C.prepare(bodyCleared:separate,trianglesByPanel:separateTriangles)
        try require(unchanged.proof.steps.isEmpty && unchanged.positionsByPanel==separate.positionsByPanel,"already-clear geometry was moved")
        cases.append("already-clear points remain exactly unchanged")
        var rejects=0
        func reject(_ name:String,_ work:()throws->Void)throws{do{try work()}catch is C.ClearanceError{rejects += 1;return}catch is CancellationError{rejects += 1;return};throw Failure.check("accepted "+name)}
        try reject("unknown/missing source component"){_=try C.prepare(bodyCleared:input,trianglesByPanel:["A":quad])}
        try reject("bad triangle index"){var t=triangles;t["A"]=[0,1,999];_=try C.prepare(bodyCleared:input,trianglesByPanel:t)}
        try reject("duplicate source triangle"){var t=triangles;t["A"]=[0,1,2,2,1,0];_=try C.prepare(bodyCleared:input,trianglesByPanel:t)}
        try reject("changed body result UV bounds"){var p=input.positionsByPanel;p["A"]![1].x += 0.001;_=try C.prepare(bodyCleared:.init(positionsByPanel:p,proof:input.proof),trianglesByPanel:triangles)}
        try reject("changed body result plane"){var p=input.positionsByPanel;p["A"]![0].z += 0.001;_=try C.prepare(bodyCleared:.init(positionsByPanel:p,proof:input.proof),trianglesByPanel:triangles)}
        for kind in 0..<6{try reject("bounded resource \(kind)"){
            var limits=C.Limits()
            switch kind{case 0:limits.maximumPanels=1;case 1:limits.maximumTrianglePairTests=1;case 2:limits.maximumTrianglePanelTests=1;case 3:limits.maximumMoves=0;case 4:limits.maximumExtraShiftPerPanelMeters=0.001;default:limits.maximumTotalExtraShiftMeters=0.009}
            _=try C.prepare(bodyCleared:input,trianglesByPanel:triangles,limits:limits)
        }}
        try reject("cannot loosen fixed shift budget"){var limits=C.Limits();limits.maximumExtraShiftPerPanelMeters=0.051;_=try C.prepare(bodyCleared:input,trianglesByPanel:triangles,limits:limits)}
        let original=try NativeAssemblyRegression.encode(input.positionsByPanel)
        for limit in [1,5,15]{let counter=Counter(limit);try reject("cancel \(limit)"){_=try C.prepare(bodyCleared:input,trianglesByPanel:triangles,isCancelled:{counter.cancel()})}}
        try require(try NativeAssemblyRegression.encode(input.positionsByPanel)==original,"cancel/budget mutated caller's original positions")
        // The old mode deliberately allows boundary-only contact. The new
        // opt-in must separate the actual independent IDs without a seam mask.
        let left=panel("A"),right=R.Panel(panelID:"B",positions:left.positions.map{$0+v(0.04,0,0)},u:left.u,v:left.v,normal:left.normal)
        let touching=try cleared([left,right]),two:[String:[UInt32]]=["A":quad,"B":quad]
        let oldTouch=try C.prepare(bodyCleared:touching,trianglesByPanel:two)
        let positive=try C.prepare(bodyCleared:touching,trianglesByPanel:two,policy:.positiveGap)
        try require(oldTouch.proof.steps.isEmpty && oldTouch.positionsByPanel==touching.positionsByPanel,"old crossing-only boundary semantics changed")
        try require(positive.proof.steps.count==1 && positive.proof.initialInspection.nearTrianglePairs!>0 && positive.proof.finalInspection.conflicts.isEmpty && positive.proof.positiveGapTargetMeters==0.00005,"boundary-only independent contact not cleared")
        try require(abs(positive.proof.totalExtraTranslationMeters-0.000050001)<1e-12 && positive.proof.nearContactsNotCertifiedAbsent==false,"positive bootstrap margin was changed or called fabric thickness")
        try independent(positive,two);cases.append("explicit positive gap clears boundary contact; old mode byte behavior unchanged")
        let upper=R.Panel(panelID:"A",positions:[v(-0.02,-0.01,0),v(0.02,-0.01,0),v(0,0.025,0)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))
        let lower=R.Panel(panelID:"B",positions:[v(-0.02,0.01,0.000025),v(0.02,0.01,0.000025),v(0,-0.025,0.000025)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))
        let eeInput=try cleared([upper,lower]),eeTriangles:[String:[UInt32]]=["A":[0,1,2],"B":[0,1,2]]
        let eePositive=try C.prepare(bodyCleared:eeInput,trianglesByPanel:eeTriangles,policy:.positiveGap)
        try require(eePositive.proof.steps.count==1 && eePositive.proof.finalInspection.conflicts.isEmpty,"edge-interior proximity without VF was missed")
        try independent(eePositive,eeTriangles);cases.append("EE-first proximity, strict all-other support and actual final inspection")
        let duplicated=R.Panel(panelID:"A",positions:upper.positions+upper.positions,u:upper.u,v:upper.v,normal:upper.normal)
        let duplicateInput=try cleared([duplicated]),duplicateTriangles:[String:[UInt32]]=["A":[0,1,2,3,4,5]]
        try reject("same-panel distinct IDs at zero distance"){_=try C.prepare(bodyCleared:duplicateInput,trianglesByPanel:duplicateTriangles,policy:.positiveGap)}
        try reject("positive mode keeps original shift budget"){var limits=C.Limits();limits.maximumExtraShiftPerPanelMeters=0.00001;_=try C.prepare(bodyCleared:touching,trianglesByPanel:two,policy:.positiveGap,limits:limits)}
        try reject("positive mode cancellation"){let counter=Counter(8);_=try C.prepare(bodyCleared:touching,trianglesByPanel:two,policy:.positiveGap,isCancelled:{counter.cancel()})}
        let cut=R.Panel(panelID:"A",positions:[v(-0.01,-0.01,0),v(0.01,-0.01,0),v(-0.01,0.01,0)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))
        let cutCopy=R.Panel(panelID:"B",positions:cut.positions,u:cut.u,v:cut.v,normal:cut.normal)
        let opening=R.Panel(panelID:"C",positions:[v(0.004,0.008,0.06),v(0.004,0.009,0.06),v(0.004,0.008,0.08)],u:v(0,1,0),v:v(0,0,1),normal:v(1,0,0),maximumBoundaryDeviationMeters:0.00001)
        let cutInput=try cleared([cut,cutCopy,opening]),cutTriangles:[String:[UInt32]]=["A":[0,1,2],"B":[0,1,2],"C":[0,1,2]]
        let refined=try C.prepare(bodyCleared:cutInput,trianglesByPanel:cutTriangles,policy:.positiveGap)
        try require(refined.proof.supportRefinements?.count==1 && refined.proof.projectionClipTests!>0 && refined.proof.projectionBVHVisits!>0,"source-opening refinement was not explicit or budgeted")
        try require(refined.proof.steps.count==1 && refined.proof.totalExtraTranslationMeters<0.001 && refined.proof.steps[0].supportOptions.allSatisfy{$0.projectionMethod != nil},"full rectangle was used for an actual source opening")
        try independent(refined,cutTriangles);cases.append("expanded actual source footprint, projected-line other triangle, full candidate retention and bounded refinement")
        try reject("clip tests share the original triangle-pair budget"){var limits=C.Limits();limits.maximumTrianglePairTests=1;_=try C.prepare(bodyCleared:cutInput,trianglesByPanel:cutTriangles,policy:.positiveGap,limits:limits)}
        let cover=R.Panel(panelID:"C",positions:[v(-0.1,-0.1,0.06),v(0.1,-0.1,0.06),v(0,0.1,0.06)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))
        let coverInput=try cleared([cut,cutCopy,cover])
        try reject("all projected vertices outside but face interior covers source"){_=try C.prepare(bodyCleared:coverInput,trianglesByPanel:cutTriangles,policy:.positiveGap)}
        // Exercise actual internal BVH splits, rather than only one-leaf
        // triangle examples. Source IDs remain shared only within each grid.
        var gridPoints:[V]=[],gridTriangles:[UInt32]=[]
        let divisions=12
        for y in 0...divisions {for x in 0...divisions {
            gridPoints.append(v((Double(x)/Double(divisions)-0.5)*0.04,(Double(y)/Double(divisions)-0.5)*0.04,0))
        }}
        for y in 0..<divisions {for x in 0..<divisions {
            let a=UInt32(y*(divisions+1)+x),b=a+1,c=a+UInt32(divisions+1),d=c+1
            gridTriangles += [a,b,d,a,d,c]
        }}
        let densePanels=[R.Panel(panelID:"A",positions:gridPoints,u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1)),
                         R.Panel(panelID:"B",positions:gridPoints,u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))]
        let dense=try cleared(densePanels),denseTriangles=["A":gridTriangles,"B":gridTriangles]
        let indexed=try C.prepare(bodyCleared:dense,trianglesByPanel:denseTriangles,policy:.positiveGap)
        try independent(indexed,denseTriangles)
        try require(indexed.proof.steps.count==1 && indexed.proof.finalInspection.conflicts.isEmpty &&
            indexed.proof.broadPhaseBuildVisits!>0 && indexed.proof.broadPhaseSortComparisons!>0 && indexed.proof.broadPhaseNodeVisits!>0 &&
            indexed.proof.broadPhaseLeafPairTests!<2*(gridTriangles.count/3)*(gridTriangles.count/3),"complete indexed grid clearance or charged sparse work")
        try require(indexed.proof.broadPhaseAdditionalBytesUpperBound!>0 && indexed.proof.broadPhaseAdditionalBytesUpperBound!<=32*1_024*1_024,
            "additional index/sort/candidate/recursion storage has no fixed bound")
        let denseOriginal=try NativeAssemblyRegression.encode(dense.positionsByPanel)
        try reject("index construction and sorting share the original support budget") {
            var limited=C.Limits();limited.maximumTrianglePanelTests=300
            _=try C.prepare(bodyCleared:dense,trianglesByPanel:denseTriangles,limits:limited)
        }
        for limit in [8,10,20,40] {
            let counter=Counter(limit)
            try reject("cancel during indexed construction/sort/query \(limit)") {
                _=try C.prepare(bodyCleared:dense,trianglesByPanel:denseTriangles,isCancelled:{counter.cancel()})
            }
        }
        try require(try NativeAssemblyRegression.encode(dense.positionsByPanel)==denseOriginal,"cancelled index mutated caller source")
        let afterCancelled=try C.prepare(bodyCleared:dense,trianglesByPanel:denseTriangles,policy:.positiveGap)
        try require(afterCancelled.positionsByPanel==indexed.positionsByPanel,"cancelled temporary index leaked into next preparation")
        cases.append("split BVH, sparse complete grid candidates, all work charged, bounded temporary memory and cancellation atomicity")
        // Rounding at the exact existing positive-gap floor: a conservative
        // node filter cannot discard a face accepted by the original predicate.
        let farBody=O.box(center:v(0,0,-2),half:v(0.001,0.001,0.001)),floor=C.positiveGapTargetMeters
        for gap in [floor.nextDown,floor,floor.nextUp] {
            let first=panel("A",2,0.01),second=panel("B",2,0.01,gap)
            let atFloor=try R.prepare(panels:[first,second],bodyPositions:farBody.positions,bodyTriangleIndices:farBody.indices)
            try require(atFloor.positionsByPanel["A"]==first.positions && atFloor.positionsByPanel["B"]==second.positions,"far body must preserve exact floor-control coordinates")
            let checked=try C.prepare(bodyCleared:atFloor,trianglesByPanel:two,policy:.positiveGap)
            try require((checked.proof.initialInspection.nearTrianglePairs!>0)==(gap<=floor),"ULP floor candidate was missed or original near predicate changed")
            try require(checked.proof.finalInspection.conflicts.isEmpty,"ULP floor control did not finish actual clearance")
        }
        cases.append("positive-gap nextDown/exact/nextUp floor keeps original full narrow-phase classification")
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_RIGID_CLOTH_OUTPUT"] ?? "/private/tmp/TailorAssRigidClothClearance")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let proof:[String:Any]=["passed":true,"cases":cases,"explicitRejections":rejects,"threePanelProof":try NativeAssemblyRegression.object(result.proof),"differentNormalsProof":try NativeAssemblyRegression.object(orthogonalResult.proof),"candidateRangeProof":try NativeAssemblyRegression.object(rangeResult.proof),"boundaryErrorProof":try NativeAssemblyRegression.object(errorResult.proof),"positiveBoundaryProof":try NativeAssemblyRegression.object(positive.proof),"positiveEEFirstProof":try NativeAssemblyRegression.object(eePositive.proof),"sourceOpeningRefinementProof":try NativeAssemblyRegression.object(refined.proof),"indexedGridProof":try NativeAssemblyRegression.object(indexed.proof),"physicalAcceptance":false]
        try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys,.prettyPrinted]).write(to:out.appendingPathComponent("analytic-proof.json"))
        print("PASS rigid cloth clearance analytic proof",cases.count,"explicit refusals",rejects)
    }
}
