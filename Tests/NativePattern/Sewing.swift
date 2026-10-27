import Foundation
import CryptoKit

/// Independent numerical sewing checks and fixture-backed, non-welded seam
/// plans. Passing anchor checks is not a full garment-drape certificate.
#if !CONTINUOUS_EASE_REGRESSION
@main
#endif
@MainActor
struct SewingRegression {
    typealias S=GarmentCodeSewing
    typealias V=S.Vector3
    enum Failure:Error {case check(String)}
    nonisolated struct SourceSnapshot:Encodable {let panels:[GarmentCodePanelGeometry];let stitches:[S.SourceStitch]}
    static func v(_ x:Double,_ y:Double=0,_ z:Double=0)->V {.init(x:x,y:y,z:z)}
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws {if !value(){throw Failure.check(message)}}
    static func near(_ a:Double,_ b:Double,_ message:String,tolerance:Double=1e-11)throws {try require(abs(a-b)<=tolerance,"\(message): \(a) != \(b)")}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func encode<T:Encodable>(_ value:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted];return try e.encode(value)}
    static func sourceHash(_ panels:[GarmentCodePanelGeometry],_ stitches:[S.SourceStitch])throws->String {
        let data=try encode(SourceSnapshot(panels:panels.sorted{$0.id<$1.id},stitches:stitches))
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    static func vertexConstraint(_ a:Int=0,_ b:Int=1,gap:Double=0.01,direction:V = .zero)throws->S.Constraint {
        try .init(a:.init(vertexID:a),b:.init(vertexID:b),initialGapMeters:gap,initialDirection:direction)
    }
    @discardableResult static func project(_ positions:inout[V],_ constraints:[S.Constraint],_ weights:[Double],_ state:inout S.State,
                                          ramp:Double=1,compliance:Double=0,meanMass:Double=1,dt:Double=0.1,cap:Double=0.1,single:Double=0.02)throws->S.ProjectionStatistics {
        try S.project(positions:&positions,constraints:constraints,normalizedInverseMass:weights,state:&state,
                      timeStep:dt,physicalCompliance:compliance,meanParticleMassKg:meanMass,rampFraction:ramp,
                      maximumVertexCorrectionPerFrameMeters:cap,maximumSingleVertexCorrectionMeters:single)
    }
    static func numericalChecks()throws {
        let c=try vertexConstraint()
        var p=[v(0),v(0.01)],state=try S.State(constraintCount:1,vertexCount:2)
        _=try project(&p,[c],[1,3],&state)
        try near(p[0].x,0.0025,"Inverse-mass one endpoint")
        try near(p[1].x,0.0025,"Inverse-mass three endpoint")
        try near(p[0].x+(p[1].x-0.01)/3,0,"Sewing must conserve the unpinned mass-weighted center")

        let canonical=try S.Attachment(vertexIDs:[2,1,2,9],weights:[0.2,0.3,0.5,0])
        try require(canonical.vertexIDs==[1,2],"Repeated attachment IDs were not combined and sorted")
        try near(canonical.weights[0],0.3,"Combined first weight");try near(canonical.weights[1],0.7,"Combined second weight")
        let normalized=try S.Attachment(vertexIDs:[0,1],weights:[0.5,0.50000000005])
        try require(normalized.weights.reduce(0,+)==1,"Near-unit barycentric weights must be normalized exactly")
        let bary=try S.Constraint(a:.init(vertexIDs:[0,1],weights:[0.25,0.75]),b:.init(vertexID:2),initialGapMeters:0.01)
        let original=[v(0,-0.03),v(0,0.01),v(0.01)]
        p=original;state=try .init(constraintCount:1,vertexCount:3)
        _=try project(&p,[bary],[1,2,4],&state)
        let denominator=0.25*0.25+2*0.75*0.75+4,lambda = -0.01/denominator
        try near(p[0].x,-lambda*0.25,"Barycentric gradient for first endpoint")
        try near(p[1].x,-lambda*2*0.75,"Barycentric gradient for second endpoint")
        try near(p[2].x,0.01+lambda*4,"Barycentric opposite endpoint")
        let baryGap=try (bary.a.point(in:p)-bary.b.point(in:p)).length
        try near(baryGap,0,"Weighted barycentric anchors did not meet")
        p=original;state=try .init(constraintCount:1,vertexCount:3)
        _=try project(&p,[bary],[0,1,0],&state)
        try require(p[0]==original[0] && p[2]==original[2],"Partial barycentric pins moved")
        try near(p[1].x,0.01/0.75,"Free barycentric endpoint must carry the whole correction")
        p=[v(0),v(0.01)];state=try .init(constraintCount:1,vertexCount:2)
        let fixed=try project(&p,[c],[0,0],&state)
        try require(p==[v(0),v(0.01)] && fixed.unresolvedPinnedConstraints==1,"Incompatible pinned anchors were hidden or moved")
        let fixedQuality=try S.inspect(positions:p,constraints:[c])
        try near(fixedQuality.maximumGapMeters,0.01,"Pinned actual gap reporting")

        // Compare physical inverse masses to a common normalized scale. Both
        // the denominator and alpha must scale, so the resulting motion agrees.
        var physical=[v(0),v(0.01)],normalizedPositions=physical
        var physicalState=try S.State(constraintCount:1,vertexCount:2),normalizedState=physicalState
        _=try project(&physical,[c],[10,5],&physicalState,compliance:0.002,meanMass:1)
        _=try project(&normalizedPositions,[c],[1.5,0.75],&normalizedState,compliance:0.002,meanMass:0.15)
        try require(zip(physical,normalizedPositions).allSatisfy{($0-$1).length<1e-12},"Mass normalization changed physical compliance")
        try near(normalizedState.lambdas[0]*0.15,physicalState.lambdas[0],"Normalized XPBD lambda")
        let alpha=0.002/(0.1*0.1),expectedGap=0.01*alpha/(15+alpha)
        try near((physical[0]-physical[1]).length,expectedGap,"Analytic compliant distance solution")
        let first=physical
        _=try project(&physical,[c],[10,5],&physicalState,compliance:0.002)
        try require(zip(first,physical).allSatisfy{($0-$1).length<1e-12},"Repeated within-frame XPBD passes discarded their accumulated lambda")

        let rampConstraint=try vertexConstraint(gap:0.04,direction:v(-1))
        p=[v(0),v(0.04)];state=try .init(constraintCount:1,vertexCount:2)
        _=try project(&p,[rampConstraint],[1,1],&state,ramp:0.25)
        let rampQuality=try S.inspect(positions:p,constraints:[rampConstraint],rampFraction:0.25)
        try near(rampQuality.maximumGapMeters,0.03,"A partially gathered seam is still open")
        try near(rampQuality.maximumTargetResidualMeters,0,"Ramp target residual")
        try require(rampQuality.measuresOnlyAnchorGaps,"Anchor gaps were called a continuous-seam certificate")
        let prior=p
        var rejected=false
        do {_=try project(&p,[rampConstraint],[1,1],&state,ramp:1)} catch S.SewingError.invalid {rejected=true}
        try require(rejected && p==prior,"Changing ramp reused a previous frame's multipliers")
        state.resetForFrame();_=try project(&p,[rampConstraint],[1,1],&state)
        try near((p[0]-p[1]).length,0,"Final ramp closure")

        p=[v(0),v(0)];state=try .init(constraintCount:1,vertexCount:2)
        let unknown=try vertexConstraint(gap:0.01)
        let unknownStats=try project(&p,[unknown],[1,1],&state,ramp:0)
        try require(unknownStats.unresolvedDirectionConstraints==1 && p==[v(0),v(0)],"A missing positive-target direction was guessed")
        let directed=try vertexConstraint(gap:0.01,direction:v(1))
        state=try .init(constraintCount:1,vertexCount:2);_=try project(&p,[directed],[1,1],&state,ramp:0)
        try near((p[0]-p[1]).length,0.01,"Explicit zero-gap fallback direction")
        let closed=try vertexConstraint(gap:0)
        p=[v(0),v(0)];state=try .init(constraintCount:1,vertexCount:2)
        _=try project(&p,[closed],[1,1],&state)
        try require(p.allSatisfy(\.isFinite) && p==[v(0),v(0)],"Coincident closed anchors generated a direction or NaN")

        let budgetConstraint=try vertexConstraint(gap:0.1,direction:v(-1))
        p=[v(0),v(0.1)];state=try .init(constraintCount:1,vertexCount:2)
        for _ in 0..<20 {_=try project(&p,[budgetConstraint],[1,3],&state,cap:0.003)}
        try near(p[0].x,0.001,"Common motion clamp must retain inverse mass ratio")
        try near(p[1].x,0.097,"Frame motion budget cannot reset on every pass")
        try near(state.accumulatedCorrectionsMeters.max()!,0.003,"Total per-frame correction budget")
        state.resetForFrame();_=try project(&p,[budgetConstraint],[1,3],&state,cap:0.003)
        try near(p[1].x,0.094,"A new frame must restore the motion budget")
        p=[v(0),v(0.01),v(-0.01)];state=try .init(constraintCount:2,vertexCount:3)
        let opposing=[try vertexConstraint(0,1),try vertexConstraint(0,2)]
        _=try project(&p,opposing,[1,0,0],&state,cap:0.005)
        try near(p[0].x,0.005,"Opposing constraints spent a vertex path budget twice")
        try near(state.accumulatedCorrectionsMeters[0],0.005,"Motion budget measures path length, not net displacement")

        // A larger iteration-path allowance is distinct from one large jump.
        // Measure actual endpoints after each call, rather than trusting only
        // the statistics or the cap configuration.
        let longConstraint=try vertexConstraint(gap:0.4,direction:v(-1))
        p=[v(0),v(0.4)];state=try .init(constraintCount:1,vertexCount:2)
        var accumulatedPath=0.0
        for _ in 0..<20 {
            let before=p,stats=try project(&p,[longConstraint],[1,3],&state,cap:0.15,single:0.02)
            let actual=max((p[0]-before[0]).length,(p[1]-before[1]).length)
            accumulatedPath += (p[1]-before[1]).length
            try require(actual<=0.02+1e-12 && stats.maximumSingleCorrectionMeters<=0.02+1e-12,"A larger cumulative path permitted a greater-than-20 mm correction")
            try near(p[0].x+(p[1].x-0.4)/3,0,"Single/frame cap common scaling changed the mass-weighted center")
        }
        try near(p[0].x,0.05,"150 mm path budget must preserve the 1:3 inverse-mass ratio")
        try near(p[1].x,0.25,"150 mm total frame path must stop further endpoint travel")
        try near(accumulatedPath,0.15,"Actual total endpoint path")
        try near(state.accumulatedCorrectionsMeters[1],0.15,"Recorded total endpoint path")
        try require(accumulatedPath>0.1 && (p[0]-p[1]).length>0.19,"Long-path fixture did not exercise >100 mm cumulative travel and an honestly unresolved gap")
        state.resetForFrame();let beforeResetStep=p
        _=try project(&p,[longConstraint],[1,3],&state,cap:0.15,single:0.02)
        try near((p[1]-beforeResetStep[1]).length,0.02,"Reset restores frame travel but retains the single-correction cap")
        for invalid in [0.0,-0.1,0.500001,Double.nan] {
            var positions=[v(0),v(0.4)],invalidState=try S.State(constraintCount:1,vertexCount:2),rejected=false
            do{_=try project(&positions,[longConstraint],[1,3],&invalidState,cap:invalid)}catch S.SewingError.invalid{rejected=true}
            try require(rejected && positions==[v(0),v(0.4)] && invalidState.rampFraction==nil,"Invalid total path budget changed the frame or was accepted")
        }
        for invalid in [0.0,-0.1,0.100001,Double.nan] {
            var positions=[v(0),v(0.4)],invalidState=try S.State(constraintCount:1,vertexCount:2),rejected=false
            do{_=try project(&positions,[longConstraint],[1,3],&invalidState,cap:0.15,single:invalid)}catch S.SewingError.invalid{rejected=true}
            try require(rejected && positions==[v(0),v(0.4)] && invalidState.rampFraction==nil,"Invalid single-correction budget changed the frame or was accepted")
        }

        p=[v(0),v(0.01)];state=try .init(constraintCount:1,vertexCount:2)
        var cancelled=false
        do {_=try S.project(positions:&p,constraints:[c],normalizedInverseMass:[1,1],state:&state,timeStep:0.1,physicalCompliance:0,meanParticleMassKg:1,rampFraction:1,isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled && p==[v(0),v(0.01)] && state.rampFraction==nil,"Pre-cancelled sewing changed a frame")
        cancelled=false
        do {_=try S.inspect(positions:p,constraints:[c],isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled,"Cancelled sewing quality returned a result")
        for item in [([0,1],[0.2,0.2]),([0,1],[-0.5,1.5]),([0,1,2],[0.2,0.3,0.5])] {
            rejected=false
            do {_=try S.Attachment(vertexIDs:item.0,weights:item.1)} catch S.SewingError.invalid {rejected=true}
            try require(rejected,"Invalid sewing attachment was silently repaired")
        }
        log("PASS scalar XPBD: weighted/barycentric anchors, pins, compliance scaling, lambdas, ramp semantics, directions, frame budgets and cancellation")
    }

    static func rectangle(_ name:String,width:Double=20,height:Double=10)->GarmentCodePanelGeometry {
        let p=[GarmentCodePoint(x:0,y:0),.init(x:width,y:0),.init(x:width,y:height),.init(x:0,y:height)]
        return .init(id:name,edges:p.indices.map{.init(id:"\(name)-e\($0)",start:p[$0],end:p[($0+1)%4],curvature:nil,label:nil)})
    }
    struct Inputs {
        let panels:[GarmentCodePanelGeometry]
        let bindings:[S.PanelBinding]
        let positions:[V]
        let sourceMeshes:[GarmentCodePanelMesher.Mesh]
    }
    static func inputs(_ panels:[GarmentCodePanelGeometry],targets:[Double],mirrorSecond:Bool=true,
                       boundarySpacing:[String:[Int:Double]]=[:])throws->Inputs {
        var bindings:[S.PanelBinding]=[],positions:[V]=[],meshes:[GarmentCodePanelMesher.Mesh]=[],triOffset=0
        for (i,panel) in panels.enumerated() {
            let mesh=try GarmentCodePanelMesher.prepare(panel:panel,targetEdgeMeters:targets[i],
                maximumBoundarySpacingMeters:boundarySpacing[panel.id] ?? [:])
            let binding=try S.PanelBinding(mesh:mesh,vertexOffset:positions.count,triangleOffset:triOffset)
            bindings.append(binding);meshes.append(mesh);triOffset += mesh.triangleIndices.count/3
            positions += mesh.flatPositions.map {p in
                i==1 && mirrorSecond ? v(0.2-p.x,-p.y,0.01) : v(p.x,p.y,Double(i)*0.01)
            }
        }
        return .init(panels:panels,bindings:bindings,positions:positions,sourceMeshes:meshes)
    }
    static func build(_ input:Inputs,stitches:[S.SourceStitch],hints:[S.StitchHint],hash:String?=nil,limits:S.BuildLimits = .init())throws->S.Plan {
        let actual=try hash ?? sourceHash(input.panels,stitches)
        return try S.build(bindings:input.bindings,positions:input.positions,sourceStitches:stitches,actualSourceSHA256:actual,
                           assembly:.init(sourceSHA256:actual,hints:hints),limits:limits)
    }
    static func globalTriangles(_ input:Inputs)->[UInt32] {
        input.bindings.flatMap {binding in binding.mesh.triangleIndices.map {UInt32(binding.vertexIDs[Int($0)])}}
    }
    static func planChecks(root:URL,directory:URL)throws {
        let a=rectangle("A"),b=rectangle("B"),input=try inputs([a,b],targets:[0.03,0.02])
        let ak=S.EdgeKey(panelID:"A",edgeIndex:0),bk=S.EdgeKey(panelID:"B",edgeIndex:0)
        let stitch=S.SourceStitch(a:ak,b:bk,rightWrong:false)
        let hint=S.StitchHint(stitchIndex:0,seamID:"ordinary",a:ak,b:bk,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.ordinary,maximumTackSpacingMeters:0.04)
        let plan=try build(input,stitches:[stitch],hints:[hint])
        let sourceBytes=try encode(SourceSnapshot(panels:input.panels,stitches:[stitch]))
        try require(plan.constraints.count==plan.anchors.count && plan.foldIntervals.isEmpty,"Ordinary matching edges acquired folds or a hidden weld")
        try require(!plan.usesFiniteCoarseTacks,"An ordinary continuous matched seam was labeled as sparse gather/ease tacks")
        try require(plan.ordinaryBoundaryIntervals.count==plan.anchors.count-1,"Ordinary contact spans do not cover every union-of-knot interval")
        for f in input.sourceMeshes[0].boundaries[0].arcFractions {
            try require(plan.anchors.contains{abs($0.normalizedSeamFraction-f)<1e-11},"An original A boundary knot was omitted")
        }
        for f in input.sourceMeshes[1].boundaries[0].arcFractions {
            try require(plan.anchors.contains{abs($0.normalizedSeamFraction-(1-f))<1e-11},"A differently subdivided B boundary knot was omitted")
        }
        try require(plan.anchors.contains{$0.a.attachment.vertexIDs.count==2},"Unequal boundary subdivision never produced a true barycentric attachment")
        for anchor in plan.anchors {
            try near(anchor.a.sourceArcFraction,anchor.normalizedSeamFraction,"Explicit A source direction")
            try near(anchor.b.sourceArcFraction,1-anchor.normalizedSeamFraction,"Explicit reverse B source direction")
            try require(anchor.a.edge==ak && anchor.b.edge==bk,"Source-side correspondence was reordered")
            try near((try anchor.a.attachment.point(in:input.positions)-anchor.b.attachment.point(in:input.positions)).length,0.01,"Matched world-space source locations")
        }
        let rwStitch=S.SourceStitch(a:ak,b:bk,rightWrong:true)
        let rwHint=S.StitchHint(stitchIndex:0,seamID:"ordinary",a:ak,b:bk,aDirection:.forward,bDirection:.reverse,rightWrong:true,intent:.ordinary,maximumTackSpacingMeters:0.04)
        let rw=try build(input,stitches:[rwStitch],hints:[rwHint])
        try require(plan.anchors.map(\.a.attachment)==rw.anchors.map(\.a.attachment) && plan.anchors.map(\.b.attachment)==rw.anchors.map(\.b.attachment),"rightWrong incorrectly reversed the source path")
        try require(rw.constraints.flatMap(\.origins).allSatisfy(\.rightWrong) && rw.contactNeighborhoods.allSatisfy(\.rightWrong),"Facing metadata was lost")

        let a1=S.EdgeKey(panelID:"A",edgeIndex:1),b1=S.EdgeKey(panelID:"B",edgeIndex:1)
        let cornerStitches=[S.SourceStitch(a:ak,b:bk,rightWrong:false),.init(a:b1,b:a1,rightWrong:false)]
        let cornerHints=[S.StitchHint(stitchIndex:0,seamID:"bottom",a:ak,b:bk,aDirection:.forward,bDirection:.forward,rightWrong:false,intent:.ordinary),
                         .init(stitchIndex:1,seamID:"side-reversed",a:b1,b:a1,aDirection:.forward,bDirection:.forward,rightWrong:false,intent:.ordinary)]
        let corner=try build(input,stitches:cornerStitches,hints:cornerHints)
        try require(corner.deduplicatedCornerConstraints>=1 && corner.constraints.contains{$0.origins.count>=2},"Shared corner constraints were duplicated instead of retaining both source origins")
        try require(corner.constraints.flatMap(\.origins).contains(where:\.reversedRelativeToConstraint),"Corner dedup lost original A/B order")
        for neighborhood in corner.contactNeighborhoods {
            for pair in neighborhood.adjacentTrianglePairs {
                try require(neighborhood.a.boundarySegments.contains{$0.adjacentTriangleID==pair.a} && neighborhood.b.boundarySegments.contains{$0.adjacentTriangleID==pair.b},"Triangle pair numerical sorting lost source-side correspondence")
            }
        }
        let squareInput=try inputs([rectangle("dart",height:20)],targets:[0.03])
        let d0=S.EdgeKey(panelID:"dart",edgeIndex:0),d1=S.EdgeKey(panelID:"dart",edgeIndex:1)
        let dart=try build(squareInput,stitches:[.init(a:d0,b:d1,rightWrong:false)],hints:[.init(stitchIndex:0,seamID:"dart-tip",a:d0,b:d1,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.ordinary)])
        try require(dart.sharedTopologicalCornerAnchors==1 && dart.anchors.contains{$0.constraintIndex==nil},"An already shared same-panel corner acquired a duplicate particle or constraint")
        _=try GarmentCodeSewnDrape.contactTopology(vertexCount:input.positions.count,triangleIndices:globalTriangles(input),plan:plan)
        _=try GarmentCodeSewnDrape.contactTopology(vertexCount:squareInput.positions.count,triangleIndices:globalTriangles(squareInput),plan:dart)

        let wbDoc=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/waistband-straight.json")))
        let skirtDoc=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-two-panel.json")))
        let wb=try wbDoc.geometryPanels()["wb_front"]!,skirt=try skirtDoc.geometryPanels()["skirt_front"]!
        let gatheredInput=try inputs([skirt,wb],targets:[0.03,0.03],mirrorSecond:false)
        let long=S.EdgeKey(panelID:skirt.id,edgeIndex:2),short=S.EdgeKey(panelID:wb.id,edgeIndex:2)
        let gatherStitch=S.SourceStitch(a:long,b:short,rightWrong:false)
        let gatherHint=S.StitchHint(stitchIndex:0,seamID:"waist-gather",a:long,b:short,aDirection:.forward,bDirection:.reverse,rightWrong:false,
                                    intent:.gathered(longerSide:.a,maximumLengthRatio:1.31),maximumTackSpacingMeters:0.10,minimumFreeBoundaryNodes:1)
        let gathered=try build(gatheredInput,stitches:[gatherStitch],hints:[gatherHint])
        try require(gathered.usesFiniteCoarseTacks,"A gathered seam omitted its finite-tack limitation")
        let attached=Set(gathered.constraints.flatMap{$0.a.vertexIDs+$0.b.vertexIDs})
        try require(!gathered.foldIntervals.isEmpty && gathered.ordinaryBoundaryIntervals.isEmpty,"A gathered seam was represented as a continuous matched strip")
        for fold in gathered.foldIntervals {
            try require(fold.longerEdge==long && fold.untackedBoundaryVertexIDs.count>=fold.minimumFreeBoundaryNodes,"Long gathered edge lost actual free folding degrees of freedom")
            try require(fold.untackedBoundaryVertexIDs.allSatisfy{!attached.contains($0)},"An allegedly free gathered node participates in a sewing attachment")
        }
        let paths=gathered.allBoundaryPaths.filter{$0.edge==long || $0.edge==short}
        let ratio=paths.first{$0.edge==long}!.sourceLengthMeters/paths.first{$0.edge==short}!.sourceLengthMeters
        try near(ratio,1.3,"Official waistband/skirt source excess was altered")
        let beforeGather=try encode(SourceSnapshot(panels:gatheredInput.panels,stitches:[gatherStitch]))
        var rejected=false
        do {_=try build(gatheredInput,stitches:[gatherStitch],hints:[.init(stitchIndex:0,seamID:"wrong-ordinary",a:long,b:short,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.ordinary)])} catch S.SewingError.invalid {rejected=true}
        try require(rejected,"An unequal ordinary seam was silently shortened or treated as a gather")
        let coarse=try inputs([skirt,wb],targets:[0.1,0.1],mirrorSecond:false)
        let denseHint=S.StitchHint(stitchIndex:0,seamID:"undersampled",a:long,b:short,aDirection:.forward,bDirection:.reverse,rightWrong:false,
                                  intent:.gathered(longerSide:.a,maximumLengthRatio:1.31),maximumTackSpacingMeters:0.02,minimumFreeBoundaryNodes:1)
        var requests:[S.RefinementRequest]=[]
        do {_=try build(coarse,stitches:[gatherStitch],hints:[denseHint])} catch S.SewingError.refinementNeeded(let value) {requests=value}
        try require(!requests.isEmpty && requests.allSatisfy{$0.edge==long && $0.existingFreeBoundaryNodes<$0.minimumFreeBoundaryNodes && $0.requiredMaximumBoundarySpacingMeters>0},"Undersampled gathers did not return an explicit source-edge refinement request")
        var spacing:[Int:Double]=[:]
        for request in requests {
            spacing[request.edge.edgeIndex]=min(spacing[request.edge.edgeIndex] ?? .infinity,request.requiredMaximumBoundarySpacingMeters)
        }
        let refined=try inputs([skirt,wb],targets:[0.1,0.1],mirrorSecond:false,boundarySpacing:[skirt.id:spacing])
        let refinedPlan=try build(refined,stitches:[gatherStitch],hints:[denseHint])
        let refinedAttached=Set(refinedPlan.constraints.flatMap{$0.a.vertexIDs+$0.b.vertexIDs})
        try require(!refinedPlan.foldIntervals.isEmpty && refinedPlan.foldIntervals.allSatisfy{fold in
            fold.untackedBoundaryVertexIDs.count>=fold.minimumFreeBoundaryNodes &&
            fold.untackedBoundaryVertexIDs.allSatisfy{!refinedAttached.contains($0)}
        },"Actual source-edge remeshing did not retain the requested free gathered nodes")
        let refinedSource=try encode(SourceSnapshot(panels:refined.panels,stitches:[gatherStitch]))
        try require(refinedSource==beforeGather,
                    "Refinement changed the original source paper instead of adding freedom")
        for i in wb.edges.indices {
            try require(refined.sourceMeshes[1].boundaries[i].sourceParameters==coarse.sourceMeshes[1].boundaries[i].sourceParameters,
                        "Refining skirt gather unnecessarily refined the separate waistband")
        }
        log("PASS actual gathered seam refinement: explicit request -> local source remesh -> free untacked fold nodes, original source unchanged")
        let easeInput=try inputs([rectangle("ease-long",width:21),rectangle("ease-short")],targets:[0.03,0.03])
        let ea=S.EdgeKey(panelID:"ease-long",edgeIndex:0),eb=S.EdgeKey(panelID:"ease-short",edgeIndex:0)
        let eased=try build(easeInput,stitches:[.init(a:ea,b:eb,rightWrong:false)],hints:[.init(stitchIndex:0,seamID:"ease",a:ea,b:eb,aDirection:.forward,bDirection:.reverse,rightWrong:false,intent:.eased(longerSide:.a,maximumLengthRatio:1.06),maximumTackSpacingMeters:0.10)])
        try require(eased.foldIntervals.isEmpty && !eased.usesFiniteCoarseTacks && !eased.ordinaryBoundaryIntervals.isEmpty,"Explicit ease must retain full continuous source correspondence")
        let afterGather=try encode(SourceSnapshot(panels:gatheredInput.panels,stitches:[gatherStitch]))
        let afterOrdinary=try encode(SourceSnapshot(panels:input.panels,stitches:[stitch]))
        try require(beforeGather==afterGather && sourceBytes==afterOrdinary,"Building sewing plans modified source geometry")

        let hash=try sourceHash(input.panels,[stitch])
        let reorderedHash=try sourceHash(Array(input.panels.reversed()),[stitch])
        try require(hash==reorderedHash && hash.count==64 && hash==hash.lowercased(),"Canonical source hashing depends on panel ordering")
        rejected=false
        do {_=try S.build(bindings:input.bindings,positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:String(repeating:"b",count:64),hints:[hint]))} catch S.SewingError.invalid {rejected=true}
        try require(rejected,"A stale source hash was accepted")
        rejected=false
        do {_=try build(input,stitches:[stitch],hints:[hint],hash:hash.uppercased())} catch S.SewingError.invalid {rejected=true}
        try require(rejected,"A noncanonical source hash was accepted")
        var welded=input.bindings[1].vertexIDs;welded[0]=input.bindings[0].vertexIDs[0]
        let badBinding=S.PanelBinding(mesh:input.sourceMeshes[1],vertexIDs:welded,triangleIDs:input.bindings[1].triangleIDs)
        rejected=false
        do {_=try S.build(bindings:[input.bindings[0],badBinding],positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:[hint]))} catch S.SewingError.invalid {rejected=true}
        try require(rejected,"Pre-welded panel IDs were accepted as separate source degrees of freedom")
        var limits=S.BuildLimits();limits.maximumConstraints=1
        var budget=false
        do {_=try build(input,stitches:[stitch],hints:[hint],limits:limits)} catch S.SewingError.budgetExceeded {budget=true}
        try require(budget,"Sewing constraint exhaustion silently dropped anchors")
        var cancelled=false
        do {_=try S.build(bindings:input.bindings,positions:input.positions,sourceStitches:[stitch],actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:[hint]),isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled,"Cancelled sewing-plan construction returned a plan")
        for (name,value) in [("ordinary",plan),("corner",corner),("gathered",gathered),("eased",eased)] {
            try encode(value).write(to:directory.appendingPathComponent(name+"-plan.json"),options:.atomic)
        }
        log("PASS builders: union knots, explicit directions/facing, corner dedup, original source-side contacts, sparse fixture gathers and continuous ease, refinement/hash/weld/budget/cancel contracts")
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_SEWING_OUTPUT_DIR"] ?? "/private/tmp/TailorAssSewing")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try numericalChecks();try planChecks(root:root,directory:directory)
        let summary:[String:Any]=["passed":true,"sourceUnchanged":true,"weldedVertices":false,"scope":"Independent scalar XPBD and immutable runtime seam plans, including continuous ordinary/eased and sparse gathered boundaries. Anchor gaps do not certify every point of a continuous seam or full garment drape."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("sewing-summary.json"),options:.atomic)
        print("PASS: independent sewing projection, immutable source correspondence, continuous ease and sparse gather DOFs, contact metadata and explicit failures")
    }
}
