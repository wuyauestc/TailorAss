import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#endif

/// Preparation/metadata controls only. No Session, Newton, output or final
/// qualification is created. Fixture paper and parameters are immutable.
@MainActor enum EasedBudgetFallbackRegression {
    typealias S=GarmentCodeSewing
    typealias V=S.Vector3
    typealias M=GarmentCodePanelMesher
    typealias Sim=GarmentCodeJointSimulation
    nonisolated struct Entry:Decodable,Sendable {
        let caseID:String,sourceSHA256:String,patternFile:String,paperJSONBytesSHA256:String
        let parameterFile:String,parameterJSONBytesSHA256:String
    }
    nonisolated struct Manifest:Decodable,Sendable {let cases:[Entry]}
    nonisolated struct Row:Codable,Sendable {
        let sourceSHA256:String,caseID:String,planFile:String,positionsFile:String,qualityFile:String
        let panels:Int,stitches:Int,sourceVertices:Int,sourceTriangles:Int,constraints:Int
        let primaryOverBudgetEasedSeams:Int,maximumAnchorIntervals:Int
        let zeroPins:Bool,initialBodyCrossings:Int,initialSelfCrossings:Int
    }
    nonisolated static func need(_ ok:Bool,_ text:String)throws {if !ok{throw ContinuousEaseRegression.Failure.failed(text)}}
    nonisolated static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func synthetic(out:URL)throws {
        let directory=out.appendingPathComponent("budget-fallback-controls")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let input=try SewingRegression.inputs([SewingRegression.rectangle("budget-A"),SewingRegression.rectangle("budget-B")],targets:[0.03,0.03],mirrorSecond:false)
        let a=S.EdgeKey(panelID:"budget-A",edgeIndex:0),b=S.EdgeKey(panelID:"budget-B",edgeIndex:0)
        let stitch=S.SourceStitch(a:a,b:b,rightWrong:true)
        let hint=S.StitchHint(stitchIndex:0,seamID:"fallback",a:a,b:b,aDirection:.forward,bDirection:.forward,rightWrong:true,intent:.eased(longerSide:.a,maximumLengthRatio:1.01),maximumTackSpacingMeters:0.04)
        var limit=S.BuildLimits();limit.maximumAnchorIntervalsPerStitch=10
        let plan=try SewingRegression.build(input,stitches:[stitch],hints:[hint],limits:limit)
        let raw=Set(plan.allBoundaryPaths.filter{$0.edge.edgeIndex==0}.flatMap(\.sourceArcFractions))
        try need(plan.anchors.count==raw.count && plan.anchors.count-1<=10,"Fallback must retain source union without redundant uniform tacks")
        try need(plan.anchors.map(\.normalizedSeamFraction)==raw.sorted(),"No source knot may be removed")
        try ContinuousEaseRegression.write(plan,directory.appendingPathComponent("synthetic-fallback-plan.json"))
        var tooSmall=limit;tooSmall.maximumAnchorIntervalsPerStitch=6
        var refused=false;do{_=try SewingRegression.build(input,stitches:[stitch],hints:[hint],limits:tooSmall)}catch S.SewingError.budgetExceeded(let why){refused=why.contains("实际源节点本身")};try need(refused,"Real source knots over cap must remain rejected at the actual-source guard")
        let ordinary=S.StitchHint(stitchIndex:0,seamID:"unchanged-ordinary",a:a,b:b,aDirection:.forward,bDirection:.forward,rightWrong:true,intent:.ordinary,maximumTackSpacingMeters:0.04)
        refused=false;do{_=try SewingRegression.build(input,stitches:[stitch],hints:[ordinary],limits:limit)}catch S.SewingError.budgetExceeded{refused=true};try need(refused,"Ordinary must never enter eased fallback")
        let hash=try SewingRegression.sourceHash(input.panels,[stitch])
        refused=false;do{_=try S.build(bindings:input.bindings,positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:[hint]),limits:limit,isCancelled:{true})}catch is CancellationError{refused=true};try need(refused,"Cancellation cannot publish plan")
        let sparseArcs:[Double]=[0,0.01,0.02,0.03,0.04,0.05,0.06,0.1,1]
        let modified=input.bindings.map {binding->S.PanelBinding in
            let m=binding.mesh
            let bs=m.boundaries.map {z->M.Boundary in
                if z.edgeIndex != 0{return z}
                precondition(z.arcFractions.count==sparseArcs.count)
                return .init(edgeIndex:z.edgeIndex,edgeID:z.edgeID,vertexIDs:z.vertexIDs,sourceParameters:z.sourceParameters,arcFractions:sparseArcs,sourceLengthMeters:z.sourceLengthMeters)
            }
            let n=M.Mesh(panelID:m.panelID,flatPositions:m.flatPositions,triangleIndices:m.triangleIndices,boundaries:bs,sourceClockwise:m.sourceClockwise,sourceSignedAreaSquareMeters:m.sourceSignedAreaSquareMeters,flattenedAreaSquareMeters:m.flattenedAreaSquareMeters,maximumBoundaryDeviationMeters:m.maximumBoundaryDeviationMeters,arcLengthIntegrationToleranceMeters:m.arcLengthIntegrationToleranceMeters,quality:m.quality,boundaryRecovery:m.boundaryRecovery)
            return .init(mesh:n,vertexIDs:binding.vertexIDs,triangleIDs:binding.triangleIDs)
        }
        var sparseLimit=limit;sparseLimit.maximumAnchorIntervalsPerStitch=11
        let sparseHint=S.StitchHint(stitchIndex:0,seamID:"sparse-gap",a:a,b:b,aDirection:.forward,bDirection:.forward,rightWrong:true,intent:.eased(longerSide:.a,maximumLengthRatio:1.01),maximumTackSpacingMeters:0.046)
        let split=try S.build(bindings:modified,positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:[sparseHint]),limits:sparseLimit)
        try need(Set(sparseArcs).isSubset(of:Set(split.anchors.map(\.normalizedSeamFraction))) && split.anchors.count==12,"Long source interval must be subdivided without losing any source knot")
        try ContinuousEaseRegression.write(split,directory.appendingPathComponent("sparse-source-gap-plan.json"))
        #if os(macOS)
        _ = Darwin.fesetround(FE_UPWARD)
        var precision=false
        do{_=try S.build(bindings:input.bindings,positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:[hint]),limits:limit)}catch S.SewingError.precisionUnresolved{precision=true}
        _ = Darwin.fesetround(FE_TONEAREST)
        try need(precision,"Fallback outward spacing proof requires nearest rounding")
        #endif
        print("BUDGET_CONTROLS_PASS numerical/plan baseline, true-source guard, long-interval subdivision, ordinary exclusion, cancellation and RNE")
    }
    static func run(root:URL,out:URL)throws->Int {
        try synthetic(out:out)
        let fixture=root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-continuous-ease/budget-inputs")
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:fixture.appendingPathComponent("manifest.json")))
        try need(manifest.cases.count==10 && Set(manifest.cases.map(\.sourceSHA256)).count==10,"All ten immutable original budget sources required")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let materials=Sim.Materials(membrane:try .init(shearStiffnessNewtonPerMeter:310,areaStiffnessNewtonPerMeter:170),
            strainBarrier:try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11),
            bending:try .init(bendingStiffnessNewtonMeter:2e-4),sewingComplianceMetersPerNewton:1e-8,
            bodyContact:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            selfContact:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        var settings=Sim.K.Settings();settings.targetEdgeMeters=0.04;settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyPoseSelection = .legacyTemplate
        settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        var rows:[Row]=[]
        for entry in manifest.cases {
            let data=try Data(contentsOf:fixture.appendingPathComponent(entry.patternFile))
            try need(hash(data)==entry.paperJSONBytesSHA256 && hash(try Data(contentsOf:fixture.appendingPathComponent(entry.parameterFile)))==entry.parameterJSONBytesSHA256,"Budget fixture original source bytes")
            let document=try GarmentCodePatternFile.validatedImport(from:data)
            let parameters=try GarmentCodeJointParameters.restore(document:document,catalog:catalog)
            let recipe=try Sim.capture(document:document,body:parameters.body,design:parameters.design,sourceSettings:settings,materials:materials)
            let p=try Sim.prepare(recipe:recipe)
            let receipt=try GarmentCodeJointResult.prepare(document:document,simulation:p)
            let source=p.input.source,cloth=source.cloth,plan=source.plan
            try need(p.sourceSHA256==entry.sourceSHA256 && receipt.simulation.sourceSHA256==entry.sourceSHA256,"Native regeneration and complete prepared source SHA")
            try need(source.panelBindings.count==document.pattern.panels.count && source.plan.allBoundaryPaths.count==document.pattern.panels.values.reduce(0){$0+$1.edges.count},"All original panels and edges retained")
            try need(cloth.pinned.allSatisfy{!$0} && p.initialBodySurface.intersectingTrianglePairs==0 && p.initialSelfSurface.intersectingTrianglePairs==0,"Real prepare preserves zero pins and safe initial surfaces")
            let grouped=Dictionary(grouping:plan.constraints.flatMap(\.origins),by:\.stitchIndex)
            try need(grouped.count==document.pattern.stitches.count,"Every actual source stitch retained")
            let paths=Dictionary(uniqueKeysWithValues:plan.allBoundaryPaths.map{($0.edge,$0)})
            var recovered=0,maximum=0
            for index in grouped.keys.sorted() {
                let origin=grouped[index]!.first!,a=paths[origin.a.edge]!,b=paths[origin.b.edge]!
                let anchors=plan.anchors.filter{$0.stitchIndex==index}.map(\.normalizedSeamFraction)
                maximum=max(maximum,anchors.count-1)
                try need(anchors.count-1<=256,"Seam interval limit may not increase")
                if case .eased=origin.intent {
                    let knots=a.sourceArcFractions.map{origin.aDirection == .forward ? $0:1-$0}+b.sourceArcFractions.map{origin.bDirection == .forward ? $0:1-$0}
                    let intervals=max(1,Int(ceil(min(a.sourceLengthMeters,b.sourceLengthMeters)/0.06)))
                    let uniform=(0...intervals).map{Double($0)/Double(intervals)}
                    if Set(knots+uniform).count-1>256{recovered += 1}
                    try need(Set(knots).isSubset(of:Set(anchors)),"Every actual eased mapped source knot must remain represented")
                }
            }
            try need(recovered>0,"Each regression fixture must exercise original over-cap primary list")
            let q=try S.inspect(positions:cloth.positions,plan:plan)
            try need(q.continuousBoundary?.completedAllContinuousSeams==true,"Complete continuous source inspection cannot be truncated")
            let stem="budget-"+entry.sourceSHA256
            let pn=stem+"-plan.json",xn=stem+"-positions.json",qn=stem+"-quality.json"
            try ContinuousEaseRegression.write(plan,out.appendingPathComponent(pn));try ContinuousEaseRegression.write(cloth.positions,out.appendingPathComponent(xn));try ContinuousEaseRegression.write(q,out.appendingPathComponent(qn))
            rows.append(.init(sourceSHA256:entry.sourceSHA256,caseID:entry.caseID,planFile:pn,positionsFile:xn,qualityFile:qn,panels:source.panelBindings.count,stitches:grouped.count,sourceVertices:cloth.positions.count,sourceTriangles:cloth.triangleIndices.count/3,constraints:plan.constraints.count,primaryOverBudgetEasedSeams:recovered,maximumAnchorIntervals:maximum,zeroPins:true,initialBodyCrossings:0,initialSelfCrossings:0))
        }
        try ContinuousEaseRegression.write(rows,out.appendingPathComponent("budget-preparation-summary.json"))
        print("EASED_BUDGET_FULL_PREPARATION_PASS",rows.count,"No Newton or garment simulation")
        return 6+rows.count
    }
}
