import Foundation
import CryptoKit
import NativeClothCollision
#if os(macOS)
import Darwin
#endif
@main @MainActor struct ContinuousEaseRegression {
    typealias S=GarmentCodeSewing
    typealias V=S.Vector3
    typealias Sim=GarmentCodeJointSimulation
    nonisolated struct Initial:Decodable,Sendable {
        let sourceSHA256:String,positions:[V],referencePositions:[V],bodyPositions:[V],massesKg:[Double],pinMask:[Bool]
        let triangleIndices:[UInt32],referenceTriangles:[UInt32],referenceToSimulation:[Int],bodyTriangleIndices:[UInt32]
        let panelGroups:[GarmentCodeCircleDrape.PanelGroup]
    }
    nonisolated final class Hooks:@unchecked Sendable {
        let lock=NSLock();var count=0,limit=1,flip=false
        func call()->Bool {lock.lock();defer{lock.unlock()};count+=1
            if count==limit {
                #if os(macOS)
                if flip {_ = Darwin.fesetround(FE_UPWARD);return false}
                #endif
                return true
            };return false
        }
    }
    nonisolated struct PriorProof:Decodable,Sendable {
        nonisolated struct PriorFrame:Decodable,Sendable {let sewing:S.Quality}
        let frames:[PriorFrame]
    }
    nonisolated enum Failure:Error {case failed(String)}
    nonisolated static func need(_ b:Bool,_ m:String)throws{if !b{throw Failure.failed(m)}}
    nonisolated static func exact(_ a:[V],_ b:[V])->Bool {a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}}
    nonisolated static func write<T:Encodable>(_ x:T,_ u:URL)throws{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];try e.encode(x).write(to:u,options:.atomic)}
    nonisolated static func bytes<T:Encodable>(_ x:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];return try e.encode(x)}
    nonisolated static func changed(_ plan:S.Plan,_ transform:(inout [String:Any])->Void)throws->S.Plan {
        var value=try JSONSerialization.jsonObject(with:bytes(plan))as! [String:Any];transform(&value)
        return try JSONDecoder().decode(S.Plan.self,from:JSONSerialization.data(withJSONObject:value,options:.sortedKeys))
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]),decoder=JSONDecoder()
        let fixture=root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-continuous-ease")
        let actual=fixture.appendingPathComponent("pencil"),baseline=fixture.appendingPathComponent("baseline")
        try SewingRegression.numericalChecks();try SewingRegression.planChecks(root:root,directory:out)
        for name in ["ordinary-plan.json","corner-plan.json","gathered-plan.json"] {
            try need(try Data(contentsOf:out.appendingPathComponent(name))==Data(contentsOf:baseline.appendingPathComponent(name)),"Existing ordinary/gathered/rightWrong/dart metadata JSON compatibility")
        }
        let oldProof=try decoder.decode(PriorProof.self,from:Data(contentsOf:actual.appendingPathComponent("validated-proof.json")))
        let priorQuality=oldProof.frames.last!.sewing
        try need(priorQuality.continuousBoundary==nil && !priorQuality.hasCompleteBoundaryClosureEvidence,"Legacy quality cannot acquire missing whole-seam proof")
        let priorKeys=Set((try JSONSerialization.jsonObject(with:bytes(priorQuality))as![String:Any]).keys)
        try need(priorKeys==Set(["anchorConstraintCount","maximumGapMeters","rmsGapMeters","maximumTargetResidualMeters","rmsTargetResidualMeters","rampFraction","measuresOnlyAnchorGaps"]),"Nil added field preserves legacy quality serialized schema")
        // One complete existing source-validator suite, sharing the real
        // factory rather than mocking its ownership/contact checks.
        try SewnInputRegression.main()
        var controlCount=4
        // Deliberately sparse data-only plan for a known8mm non-anchor bulge.
        // This is NOT passed off as a source-validated factory capability.
        let A=SewingRegression.rectangle("A"),B=SewingRegression.rectangle("B"),input=try SewingRegression.inputs([A,B],targets:[0.03,0.02])
        let ak=S.EdgeKey(panelID:"A",edgeIndex:0),bk=S.EdgeKey(panelID:"B",edgeIndex:0),stitch=S.SourceStitch(a:ak,b:bk,rightWrong:false)
        let hint=S.StitchHint(stitchIndex:0,seamID:"continuous",a:ak,b:bk,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.ordinary)
        let full=try SewingRegression.build(input,stitches:[stitch],hints:[hint])
        let sparse=try changed(full){value in
            let old=value["anchors"]as![[String:Any]],rows=value["constraints"]as![[String:Any]]
            var first=old.first!,last=old.last!;let ia=first["constraintIndex"]as!Int,ib=last["constraintIndex"]as!Int
            first["constraintIndex"]=0;last["constraintIndex"]=1
            value["anchors"]=[first,last];value["constraints"]=[rows[ia],rows[ib]]
        }
        var closed=input.positions
        for i in input.bindings[1].vertexIDs {closed[i].z=0}
        let path=full.allBoundaryPaths.first{$0.edge==ak}!,mid=path.vertexIDs[path.vertexIDs.count/2]
        var bulge=closed;bulge[mid].z=0.008
        let anchorsOnly=try S.inspect(positions:bulge,constraints:sparse.constraints)
        let entire=try S.inspect(positions:bulge,plan:sparse)
        try need(anchorsOnly.maximumGapMeters<1e-12 && entire.maximumMeasuredGapMeters>=0.008 && entire.maximumMeasuredGapMeters<0.008000000001,"Closed endpoints cannot hide8mm true source-polyline bulge")
        let reverseAdversary=try changed(sparse){value in
            var paths=value["allBoundaryPaths"]as![[String:Any]]
            for k in paths.indices {
                let e=paths[k]["edge"]as![String:Any]
                if (e["edgeIndex"]as!Int)==0 {
                    let ids=paths[k]["vertexIDs"]as![Int]
                    paths[k]["vertexIDs"]=[ids.first!,ids[ids.count/2],ids.last!]
                    paths[k]["sourceParameters"]=[0.0,0.5,1.0]
                    paths[k]["sourceArcFractions"]=(e["panelID"]as!String)=="A" ? [0.0,0.9,1.0]:[0.0,0.1,1.0]
                }
            };value["allBoundaryPaths"]=paths
        }
        var reversePose=closed
        for path in reverseAdversary.allBoundaryPaths where path.edge.edgeIndex==0 {
            let values=path.edge.panelID=="A" ? [0.0,0.5,1.0]:[1.0,0.5,0.0]
            for (i,id) in path.vertexIDs.enumerated(){reversePose[id] = .init(x:values[i],y:0,z:0)}
        }
        let reverseQuality=try S.inspect(positions:reversePose,plan:reverseAdversary)
        try need(reverseQuality.maximumMeasuredGapMeters>0,"Rounding reverse time to singleton must not erase true knot drift")
        try write(reverseAdversary,out.appendingPathComponent("reverse-near-knot-plan.json"));try write(reversePose,out.appendingPathComponent("reverse-near-knot-positions.json"));try write(reverseQuality,out.appendingPathComponent("reverse-near-knot-quality.json"));controlCount+=1
        let settled=try S.inspect(positions:closed,plan:full)
        try need(settled.hasCompleteBoundaryClosureEvidence && settled.maximumMeasuredGapMeters<1e-12,"Different source subdivision same line should bound closed")
        try write(entire,out.appendingPathComponent("eight-mm-bulge-quality.json"));try write(bulge,out.appendingPathComponent("eight-mm-bulge-positions.json"));try write(sparse,out.appendingPathComponent("eight-mm-bulge-plan.json"));controlCount+=2
        let nearInput=try SewingRegression.inputs([SewingRegression.rectangle("near-A",width:21),SewingRegression.rectangle("near-B")],targets:[0.03,0.03])
        let second=nearInput.sourceMeshes[1]
        var meshJSON=try JSONSerialization.jsonObject(with:bytes(second))as![String:Any]
        var boundaries=meshJSON["boundaries"]as![[String:Any]],edge0=boundaries[0],arcs=edge0["arcFractions"]as![Double]
        arcs[arcs.count/2]=arcs[arcs.count/2].nextUp;edge0["arcFractions"]=arcs;boundaries[0]=edge0;meshJSON["boundaries"]=boundaries
        let nearMesh=try decoder.decode(GarmentCodePanelMesher.Mesh.self,from:JSONSerialization.data(withJSONObject:meshJSON))
        let nearBinding=S.PanelBinding(mesh:nearMesh,vertexIDs:nearInput.bindings[1].vertexIDs,triangleIDs:nearInput.bindings[1].triangleIDs)
        let na=S.EdgeKey(panelID:"near-A",edgeIndex:0),nb=S.EdgeKey(panelID:"near-B",edgeIndex:0)
        let nearStitch=S.SourceStitch(a:na,b:nb,rightWrong:false),nearHash=try SewingRegression.sourceHash(nearInput.panels,[nearStitch])
        let nearPlan=try S.build(bindings:[nearInput.bindings[0],nearBinding],positions:nearInput.positions,sourceStitches:[nearStitch],actualSourceSHA256:nearHash,
            assembly:.init(sourceSHA256:nearHash,hints:[.init(stitchIndex:0,seamID:"near-ease",a:na,b:nb,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.eased(longerSide:.a,maximumLengthRatio:1.06))]))
        let reversedNear=1-arcs[arcs.count/2]
        try need(nearPlan.anchors.contains{$0.normalizedSeamFraction==0.5} && nearPlan.anchors.contains{$0.normalizedSeamFraction==reversedNear} && reversedNear != 0.5,"Every distinct normalized near knot retained")
        try need(nearPlan.constraints.allSatisfy{$0.origins.count==Set($0.origins).count} && nearPlan.deduplicatedCornerConstraints>0,"Exact duplicate Location provenance is a set without removing anchors")
        try write(nearPlan,out.appendingPathComponent("near-knot-origin-dedup-plan.json"));controlCount+=1
        let gather=try decoder.decode(S.Plan.self,from:Data(contentsOf:out.appendingPathComponent("gathered-plan.json")))
        let maxID=gather.allBoundaryPaths.flatMap(\.vertexIDs).max()!,gatherPositions=Array(repeating:V.zero,count:maxID+1)
        let gatheredQ=try S.inspect(positions:gatherPositions,plan:gather)
        try need(gatheredQ.continuousBoundary?.gatheredSeamsUnproven==1 && gatheredQ.continuousBoundary?.maximumGapUpperBoundMeters==nil && !gatheredQ.hasCompleteBoundaryClosureEvidence,"Unproved gathered seam is not zero-gap full closure")
        try write(gatheredQ,out.appendingPathComponent("gathered-excluded-quality.json"));controlCount+=1
        var limits=S.InspectionLimits();limits.maximumEvaluatedSourceKnots=2
        var budget=false;do{_=try S.inspect(positions:closed,plan:full,limits:limits)}catch S.SewingError.budgetExceeded{budget=true};try need(budget,"Whole union cannot be truncated to sample budget")
        limits=S.InspectionLimits();limits.maximumEstimatedWorkingBytes=1
        budget=false;do{_=try S.inspect(positions:closed,plan:full,limits:limits)}catch S.SewingError.budgetExceeded{budget=true};try need(budget,"Scratch budget cannot authorize partial report")
        var cancelled=false;do{_=try S.inspect(positions:closed,plan:full,isCancelled:{true})}catch is CancellationError{cancelled=true};try need(cancelled,"Initial cancel")
        let late=Hooks();late.limit=4
        cancelled=false;do{_=try S.inspect(positions:closed,plan:full,isCancelled:{late.call()})}catch is CancellationError{cancelled=true};try need(cancelled,"Late cancel no completed quality")
        let fpu=Hooks();fpu.flip=true;fpu.limit=4;var rounding=false
        do{_=try S.inspect(positions:closed,plan:full,isCancelled:{fpu.call()})}catch S.SewingError.precisionUnresolved{rounding=true}
        #if os(macOS)
        _ = Darwin.fesetround(FE_TONEAREST)
        #endif
        try need(rounding,"Callback cannot change rounding and publish quality")
        let counter=Hooks();counter.limit=Int.max
        _=try S.inspect(positions:closed,plan:full,isCancelled:{counter.call()})
        let finalFPU=Hooks();finalFPU.limit=counter.count;finalFPU.flip=true;rounding=false
        do{_=try S.inspect(positions:closed,plan:full,isCancelled:{finalFPU.call()})}catch S.SewingError.precisionUnresolved{rounding=true}
        #if os(macOS)
        _ = Darwin.fesetround(FE_TONEAREST)
        #endif
        try need(rounding,"Final callback may not publish under unsupported rounding");controlCount+=6
        // The actual paper source is regenerated, then the true factory checks
        // every source ownership, triangle, rest, mass and local contact span.
        let doc=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:actual.appendingPathComponent("complete-paper-source.json")))
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let parameters=try GarmentCodeJointParameters.restore(document:doc,catalog:catalog)
        let old=try decoder.decode(Initial.self,from:Data(contentsOf:actual.appendingPathComponent("complete-initial-input.json")))
        var settings=Sim.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyPoseSelection = .legacyTemplate;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let recipe=try GarmentCodeNativeAssembly.capture(document:doc,body:parameters.body,design:parameters.design,settings:settings,initialization:.rigidBodyAndClothPositiveClearance)
        let assembly=try GarmentCodeNativeAssembly.build(recipe:recipe),prepared=assembly.preparedInput,cloth=prepared.cloth,new=prepared.plan
        try need(prepared.sourceSHA256==old.sourceSHA256 && prepared.panelBindings.count==2 && new.constraints.count==142 && new.anchors.count==148 && !new.usesFiniteCoarseTacks && new.foldIntervals.isEmpty,"Actual complete Pencil source and dense ease rows")
        try need(exact(cloth.referencePositions,old.referencePositions) && cloth.referenceTriangles==old.referenceTriangles && cloth.triangleIndices==old.triangleIndices && cloth.referenceToSimulation==old.referenceToSimulation && exact(cloth.mannequinPositions,old.bodyPositions) && cloth.mannequinTriangleIndices==old.bodyTriangleIndices && cloth.pinned==old.pinMask && cloth.pinned.allSatisfy{!$0},"Original Pencil source rest topology/body/zero pins unchanged")
        try need(recipe.source.stitches.count==8 && recipe.source.stitches.filter{$0.a.panelID==$0.b.panelID}.count==4,"All actual four rear darts and four side seams retained")
        let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:cloth.referencePositions.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:cloth.referenceTriangles,arealDensity:0.18)
        try need(masses.massesKg.map(\.bitPattern)==old.massesKg.map(\.bitPattern),"All original physical masses bitwise unchanged")
        let topology=try GarmentCodeSewnDrape.contactTopology(vertexCount:cloth.positions.count,triangleIndices:cloth.triangleIndices,plan:new,referencePositions:cloth.referencePositions)
        let interval=new.ordinaryBoundaryIntervals.first{$0.stitchIndex==5}!,fa=interval.aSegment.adjacentTriangleID,fb=interval.bSegment.adjacentTriangleID
        let va=cloth.triangleIndices[(fa*3)..<(fa*3+3)].map(Int.init),vb=cloth.triangleIndices[(fb*3)..<(fb*3+3)].map(Int.init)
        try need(Set(va).isDisjoint(with:Set(vb)),"Actual eased panels retain independent source vertices")
        var crossing=cloth.positions
        let triA:[V]=[.init(x:0,y:0,z:0),.init(x:0.02,y:0,z:0),.init(x:0,y:0.02,z:0)]
        let triB:[V]=[.init(x:0.005,y:0.005,z:-0.01),.init(x:0.005,y:0.005,z:0.01),.init(x:0.015,y:0.005,z:0)]
        for (v,x) in zip(va,triA){crossing[v]=x};for (v,x) in zip(vb,triB){crossing[v]=x}
        let interior=V(x:0.01,y:0.005,z:0)
        try need(!topology.permitsSewnTouch(firstFace:fa,secondFace:fb,firstPoint:interior,secondPoint:interior,positions:crossing),"Dense eased contact rule must not exempt true interior crossing")
        let crossed=try GarmentCodeClothContact.inspect(positions:crossing,topology:topology,thickness:0.0005,maximumCandidatePairs:200_000)
        try need(crossed.intersectingTrianglePairs>0,"True crossing remains detected after dense source-local easing")
        for (v,x) in zip(vb,triA){crossing[v]=x}
        try need(!topology.permitsSewnTouch(firstFace:fa,secondFace:fb,firstPoint:.init(x:0.006,y:0.006,z:0),secondPoint:.init(x:0.006,y:0.006,z:0),positions:crossing),"Dense eased contact must not exempt coplanar interiors")
        let coplanar=try GarmentCodeClothContact.inspect(positions:crossing,topology:topology,thickness:0.0005,maximumCandidatePairs:200_000)
        try need(coplanar.intersectingTrianglePairs>0,"Coplanar overlap still active")
        try write(["properIntersectionCount":crossed.intersectingTrianglePairs,"coplanarIntersectionCount":coplanar.intersectingTrianglePairs,"actualEasedFaceA":fa,"actualEasedFaceB":fb],out.appendingPathComponent("actual-eased-contact-negative.json"));controlCount+=2
        let oldPose=try decoder.decode([V].self,from:Data(contentsOf:actual.appendingPathComponent("validated-output.json")).positionsData())
        let oldQuality=try S.inspect(positions:oldPose,plan:new)
        try need(oldQuality.hasCompleteBoundaryClosureEvidence && oldQuality.maximumMeasuredGapMeters>0.008,"Old numerical Pencil must fail full0.5mm closure gate")
        try write(new,out.appendingPathComponent("actual-pencil-new-plan.json"));try write(oldQuality,out.appendingPathComponent("actual-pencil-old-pose-new-quality.json"));try write(oldPose,out.appendingPathComponent("actual-pencil-old-pose.json"));controlCount+=2
        let source=try GarmentCodeSewnDrape.captureSource(document:doc)
        let missing=try changed(new){v in var spans=v["ordinaryBoundaryIntervals"]as![[String:Any]];let i=spans.firstIndex{($0["stitchIndex"]as?Int)==5}!;spans.remove(at:i);v["ordinaryBoundaryIntervals"]=spans}
        var rejected=false;do{_=try GarmentCodeSewnDrape.prepare(input:cloth,plan:missing,source:source,bindings:prepared.panelBindings)}catch{rejected=true};try need(rejected,"Real ownership rejects missing eased interval")
        let masks=try changed(new){v in var spans=v["ordinaryBoundaryIntervals"]as![[String:Any]];var first=spans[0],seg=first["aSegment"]as![String:Any];seg["adjacentTriangleID"]=1801;first["aSegment"]=seg;spans[0]=first;v["ordinaryBoundaryIntervals"]=spans}
        rejected=false;do{_=try GarmentCodeSewnDrape.prepare(input:cloth,plan:masks,source:source,bindings:prepared.panelBindings)}catch{rejected=true};try need(rejected,"Real ownership rejects expanded contact face")
        let legacy=try decoder.decode(S.Plan.self,from:Data(contentsOf:actual.appendingPathComponent("complete-sewing-plan.json")))
        rejected=false;do{_=try GarmentCodeSewnDrape.prepare(input:cloth,plan:legacy,source:source,bindings:prepared.panelBindings)}catch{rejected=true};try need(rejected,"Coarse old ease plan cannot acquire new continuous source capability")
        let duplicateOrigin=try changed(new){v in var rows=v["constraints"]as![[String:Any]],row=rows[0],origins=row["origins"]as![[String:Any]];origins.append(origins[0]);row["origins"]=origins;rows[0]=row;v["constraints"]=rows}
        rejected=false;do{_=try GarmentCodeSewnDrape.prepare(input:cloth,plan:duplicateOrigin,source:source,bindings:prepared.panelBindings)}catch{rejected=true};try need(rejected,"Full source validator must still reject genuinely duplicated Origin entries")
        controlCount+=1
        cancelled=false;do{_=try GarmentCodeSewnDrape.prepare(input:cloth,plan:new,source:source,bindings:prepared.panelBindings,isCancelled:{true})}catch is CancellationError{cancelled=true};try need(cancelled,"Source input cancelled without publishing")
        controlCount+=4
        var gatherDesign=parameters.design
        try need(gatherDesign.setValue(.string("Skirt2"),at:["meta","bottom"]) && gatherDesign.setValue(.string("StraightWB"),at:["meta","wb"]) && gatherDesign.setValue(.number(1.3),at:["skirt","ruffle"]),"Complete explicit native gather parameters")
        let gatherDoc=try GarmentCodeNativeGenerator.generate(body:parameters.body,design:gatherDesign)
        let gatherRecipe=try GarmentCodeNativeAssembly.capture(document:gatherDoc,body:parameters.body,design:gatherDesign,settings:settings,initialization:.nativeConstruction)
        let gatherAssembly=try GarmentCodeNativeAssembly.build(recipe:gatherRecipe),gplan=gatherAssembly.preparedInput.plan
        try need(gplan.usesFiniteCoarseTacks && !gplan.foldIntervals.isEmpty && gplan.foldIntervals.allSatisfy{if case .gathered=$0.intent{return !$0.untackedBoundaryVertexIDs.isEmpty};return false},"Real strong source factory retains gathered freedom without easing it away")
        let actualGatherQ=try S.inspect(positions:gatherAssembly.preparedInput.cloth.positions,plan:gplan)
        try need(!actualGatherQ.hasCompleteBoundaryClosureEvidence && actualGatherQ.continuousBoundary!.gatheredSeamsUnproven>0,"Actual gathered recipe cannot qualify as complete seam closure")
        try write(gplan,out.appendingPathComponent("actual-gathered-plan.json"));try write(actualGatherQ,out.appendingPathComponent("actual-gathered-quality.json"));controlCount+=1
        controlCount += try EasedBudgetFallbackRegression.run(root:root,out:out)
        let summary:[String:Any]=["passed":true,"newControls":controlCount,"originalScalarAndPlanRegressionExecuted":true,"ordinaryGatheredPlanBytesUnchanged":true,"actualPencilPrepared":true,"sourceSHA256":prepared.sourceSHA256,"originalSourceRestBodyAndMassBitwiseUnchanged":true,"zeroPins":true,"actualPanels":prepared.panelBindings.count,"actualStitches":recipe.source.stitches.count,"actualConstraints":new.constraints.count,"oldOutputFullGapUpperBoundMeters":oldQuality.maximumMeasuredGapMeters,"fullRClosureGateWouldRejectOldOutput":oldQuality.maximumMeasuredGapMeters>=0.0005,"gatheredRemainsDiagnosticNotFullClosure":!gatheredQ.hasCompleteBoundaryClosureEvidence,"physicsOrNewtonRun":false,"RValidatedProduced":false]
        try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys,.prettyPrinted]).write(to:out.appendingPathComponent("summary.json"),options:.atomic)
        print("CONTINUOUS_EASE_CONTROLS_PASS",controlCount,new.constraints.count,oldQuality.maximumMeasuredGapMeters)
    }
}
private extension Data {
    nonisolated func positionsData()throws->Data {
        nonisolated struct Output:Decodable {let positions:[GarmentCodeCircleDrape.Vector3]}
        return try JSONEncoder().encode(JSONDecoder().decode(Output.self,from:self).positions)
    }
}
