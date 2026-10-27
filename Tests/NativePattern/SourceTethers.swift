import Foundation

@main @MainActor
struct SourceTethersRegression {
    typealias T = GarmentCodeSourceTethers
    typealias K = GarmentCodeCircleDrape
    typealias S = GarmentCodeSewing
    typealias V = K.Vector3
    enum Failure: Error {case check(String)}
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {throw Failure.check(message)}
    }
    static func rejected(_ name: String, _ work: () throws -> Void) throws {
        do {try work()} catch {print("PASS reject \(name): \(error)");return}
        throw Failure.check("accepted invalid \(name)")
    }
    static func point(_ x: Double, _ y: Double = 0) -> V {.init(x:x,y:y,z:0)}
    static func springs(_ p: [V], _ edges: [(Int,Int)]) -> [K.Spring] {
        edges.map{.init(a:$0.0,b:$0.1,length:(p[$0.0]-p[$0.1]).length)}
    }
    static func raw(_ p: [V], _ edges: [(Int,Int)], _ pins: [Bool], _ constraints: [S.Constraint] = [],
                    limits: T.Limits = .init(), cancelled: @Sendable () -> Bool = {false}) throws -> T.Plan {
        try T.prepareRawGraph(referencePositions:p,sourceEdges:springs(p,edges),pinned:pins,
                              inverseMasses:pins.map{$0 ? 0:1},constraints:constraints,limits:limits,isCancelled:cancelled)
    }
    static func bound(_ plan: T.Plan, _ vertex: Int) -> Double {plan.tethers.first{$0.vertexID==vertex}!.pathUpperBoundMeters}
    final class Counter: @unchecked Sendable {
        private let lock=NSLock();private var count=0
        func cancel() -> Bool {lock.lock();defer{lock.unlock()};count += 1;return count>=3}
    }
    static func main() throws {
        let chain=[point(0),point(1),point(2),point(3)]
        let plan=try raw(chain,[(0,1),(1,2),(2,3)],[true,false,false,false])
        try require(plan.provenance == .rawGraphOnly,"raw graph misrepresented as paper-verified")
        try require(abs(bound(plan,3)-3.24)<1e-12 && plan.tethers.allSatisfy{$0.pinID==0},"analytic shortest source chain")
        var folded=[point(0),point(1.061),point(1.061,1.061),point(0,1.061)],before=folded
        let valid=try T.project(positions:&folded,plan:plan,seamRampFraction:1)
        try require(folded==before && valid.projectedVertices==0,"legal 6.1% stretched/folded source must be unchanged")
        var stretched=chain;stretched[3]=point(4)
        let s=try T.project(positions:&stretched,plan:plan,seamRampFraction:1)
        try require(abs(stretched[3].x-3.98)<1e-12 && stretched[0]==chain[0] && s.cappedCorrections==1 && s.maximumSingleVertexCorrectionMeters<=0.02,"20mm cap or fixed pin violated")
        var unconstrained=[point(0),point(0.3,0.4),point(0.2,0.3),point(0.1,0.2)];before=unconstrained
        _=try T.project(positions:&unconstrained,plan:plan,seamRampFraction:1)
        try require(unconstrained==before,"free folding DOFs were pinned to a template")
        print("PASS analytic chain, 6.1% legal source, free folding, original pin and 20mm cap")

        let panel=[point(0),point(1),point(10),point(12),point(20),point(21)]
        let a=try S.Attachment(vertexIDs:[0,1],weights:[0.25,0.75])
        let b=try S.Attachment(vertexIDs:[2,3],weights:[0.5,0.5])
        let seam=try S.Constraint(a:a,b:b,initialGapMeters:10)
        let cross=try raw(panel,[(0,1),(2,3),(4,5)],[true,false,false,false,false,false],[seam,seam])
        try require(cross.virtualAttachmentCount==2,"canonical barycentric attachment was duplicated")
        try require(abs(bound(cross,2)-(0.75*1.08+0.0005+1.08))<1e-12,"barycentric source segment or seam slack incorrect")
        try require(cross.unreachableVertexIDs==[4,5] && cross.unreachableComponentCount==1,"unsewn component hidden or pinned")
        var legal=[point(0),point(1.06),point(-0.2646),point(1.8554),point(50),point(51)];before=legal
        let legalStats=try T.project(positions:&legal,plan:cross,seamRampFraction:1)
        try require(legal==before && legalStats.projectedVertices==0 && legalStats.unreachableVertices==2,"valid <8% edges / .4mm seam pose changed")
        let noPins=try raw(panel,[(0,1),(2,3),(4,5)],Array(repeating:false,count:6),[seam])
        try require(noPins.tethers.isEmpty && noPins.unreachableVertexIDs.count==6 && noPins.unreachableComponentCount==2,"no-pin graph must report, not add pins")
        print("PASS cross-panel canonical barycentric graph, .5mm seam slack, legal .4mm seam, unreachable components")

        // A finite tack at the first node does not shortcut the untacked cloth.
        let gathered=[point(0),point(5),point(6),point(7),point(8),point(9)]
        let tack=try S.Constraint(a:S.Attachment(vertexID:0),b:S.Attachment(vertexID:1),initialGapMeters:5)
        let finite=try raw(gathered,[(1,2),(2,3),(3,4),(4,5)],[true,false,false,false,false,false],[tack])
        try require(abs(bound(finite,5)-(4*1.08+0.0005))<1e-12,"untacked fold boundary was shortcut or source shortened")
        let tied=try raw(chain,[(0,1),(1,2),(2,3)],[true,false,false,true])
        try require(tied.tethers.first{$0.vertexID==1}?.pinID==0 && tied.tethers.first{$0.vertexID==2}?.pinID==3,"nearest actual pin ownership")
        print("PASS finite tacks retain source paths and multi-source actual-pin ownership")

        // The selected full-ramp shortest path crosses exactly these two real
        // seams; each contributes its own true initial gap during the ramp.
        let rampSource=[point(0),point(1),point(10),point(11),point(20)]
        let rampSeams=try [(1,2),(3,4)].map {
            try S.Constraint(a:S.Attachment(vertexID:$0.0),b:S.Attachment(vertexID:$0.1),initialGapMeters:9)
        }
        let rampPlan=try raw(rampSource,[(0,1),(2,3)],[true,false,false,false,false],rampSeams)
        let endTether=rampPlan.tethers.first{$0.vertexID==4}!
        try require(abs(endTether.initialSewingGapSumMeters-18)<1e-12 && abs(endTether.pathUpperBoundMeters-2.161)<1e-12,"path initial seam gaps must add on the selected real path")
        for ramp in [0.0,0.5,1.0] {
            let target=9*(1-ramp),second=1.06+target+0.0004,third=second+1.06,fourth=third+target+0.0004
            var pose=[point(0),point(1.06),point(second),point(third),point(fourth)]
            let before=pose,stats=try T.project(positions:&pose,plan:rampPlan,seamRampFraction:ramp,mode:.followSewingRamp)
            try require(pose==before && stats.projectedVertices==0,"ramp target-feasible state changed at \(ramp)")
            try require(abs(endTether.upperBoundMeters(seamRampFraction:ramp)-(2.161+(1-ramp)*18))<1e-12,"ramp-aware triangle bound differs from actual targets")
        }
        var early=rampSource
        let earlyStats=try T.project(positions:&early,plan:rampPlan,seamRampFraction:0,mode:.followSewingRamp)
        try require(early==rampSource && earlyStats.projectedVertices==0,"initial source-valid placement changed")
        var atHalf=[point(0),point(1),point(5.5),point(6.5),point(12)]
        let halfStats=try T.project(positions:&atHalf,plan:rampPlan,seamRampFraction:0.5,mode:.followSewingRamp)
        try require(halfStats.projectedVertices==1 && abs(atHalf[4].x-11.98)<1e-12,"ramp bound must actually tighten and retain 20mm cap")
        print("PASS fixed-path initial seam gap sum, ramp-aware valid start/half/full poses, gradual upper bound and cap")

        try rejected("early sewing ramp") {var p=chain;_=try T.project(positions:&p,plan:plan,seamRampFraction:0.99)}
        try rejected("NaN ramp") {var p=chain;_=try T.project(positions:&p,plan:plan,seamRampFraction:.nan)}
        for bad in [-0.01,1.01,Double.infinity,Double.nan] {
            try rejected("invalid following ramp \(bad)") {var p=chain;_=try T.project(positions:&p,plan:plan,seamRampFraction:bad,mode:.followSewingRamp)}
        }
        try rejected("oversized single correction") {var p=chain;_=try T.project(positions:&p,plan:plan,seamRampFraction:1,maximumSingleVertexCorrectionMeters:0.021)}
        try rejected("duplicate source edge") {_=try raw(chain,[(0,1),(1,0)],[true,false,false,false])}
        try rejected("non-source bary edge") {
            let c=try S.Constraint(a:S.Attachment(vertexIDs:[0,2],weights:[0.5,0.5]),b:S.Attachment(vertexID:3),initialGapMeters:1)
            _=try raw(chain,[(0,1),(1,2),(2,3)],[true,false,false,false],[c])
        }
        try rejected("changed rest metric") {
            _=try T.prepareRawGraph(referencePositions:chain,sourceEdges:[.init(a:0,b:1,length:0.9)],pinned:[true,false,false,false],inverseMasses:[0,1,1,1],constraints:[])
        }
        try rejected("invalid original mass") {
            _=try T.prepareRawGraph(referencePositions:chain,sourceEdges:[],pinned:[true,false,false,false],inverseMasses:[1,1,1,1],constraints:[])
        }
        try rejected("nonfinite source") {_=try raw([point(.nan),point(1)],[(0,1)],[true,false])}
        var tiny=T.Limits();tiny.maximumGraphEdges=1
        try rejected("graph edge budget") {_=try raw(chain,[(0,1),(1,2)],[true,false,false,false],limits:tiny)}
        tiny=T.Limits();tiny.maximumDijkstraVisits=1
        try rejected("Dijkstra work budget") {_=try raw(chain,[(0,1),(1,2)],[true,false,false,false],limits:tiny)}
        try rejected("prepare cancellation") {_=try raw(chain,[(0,1)],[true,false,false,false],cancelled:{true})}
        var many=(0..<300).map{point(Double($0)*0.01)},manyPins=Array(repeating:false,count:300);manyPins[0]=true
        let manyPlan=try raw(many,(0..<299).map{($0,$0+1)},manyPins),counter=Counter()
        many[1]=point(0.1);let unchanged=many
        try rejected("transactional mid-project cancellation") {_=try T.project(positions:&many,plan:manyPlan,seamRampFraction:1,isCancelled:{counter.cancel()})}
        try require(many==unchanged,"cancellation partially mutated positions")

        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        var design=GarmentCodeDesignParameters(catalog:catalog)
        _=design.setValue(.null,at:["meta","upper"]);_=design.setValue(.null,at:["meta","bottom"]);_=design.setValue(.string("StraightWB"),at:["meta","wb"])
        let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        var settings=K.Settings();settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let input=try GarmentCodeWaistbandAssembly.prepare(document:document,body:body,settings:settings)
        let original=input.cloth.positions,flat=input.cloth.referencePositions,masses=input.cloth.inverseMasses
        let actual=try T.prepare(input:input)
        try require(actual.provenance == .verifiedSourceSHA256(input.sourceSHA256) && actual.unreachableVertexIDs.isEmpty,"verified input source/pin graph incorrect")
        var projected=original
        let actualStats=try T.project(positions:&projected,plan:actual,seamRampFraction:1)
        try require(input.cloth.positions==original && input.cloth.referencePositions==flat && input.cloth.inverseMasses==masses,"source/positions/mass mutated")
        try require(original.indices.filter{input.cloth.pinned[$0]}.allSatisfy{original[$0]==projected[$0]},"actual source pins moved")
        try require(actualStats.maximumSingleVertexCorrectionMeters<=0.02,"actual graph projection exceeded cap")
        print("PASS actual PreparedInput provenance, \(actual.graphNodeCount) nodes, \(actual.tethers.count) tethers, source/masses/pins unchanged")
        print("PASS SourceTethers: source-derived redundant upper bounds only; no physical convergence claim")
    }
}
