import Foundation

nonisolated private final class StrainLimitCancellationCounter: @unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    private let cancelAt:Int
    init(cancelAt:Int) {self.cancelAt=cancelAt}
    func check()->Bool {
        lock.lock();defer {lock.unlock()}
        count += 1
        return count>=cancelAt
    }
    var calls:Int {lock.lock();defer {lock.unlock()};return count}
}

@main
@MainActor
struct StrainLimitRegression {
    typealias Kernel=GarmentCodeCircleDrape
    typealias Limiter=Kernel.SourceStrainLimiter
    typealias Vector=Kernel.Vector3
    enum Failure:Error {case check(String)}
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws {
        if !value(){throw Failure.check(message)}
    }
    static func close(_ a:Double,_ b:Double,_ tolerance:Double=1e-12)->Bool {abs(a-b)<=tolerance}
    static func vector(_ x:Double,_ y:Double=0,_ z:Double=0)->Vector {.init(x:x,y:y,z:z)}
    static func invalid(_ tag:String,_ operation:()throws->Void)throws {
        do {try operation()} catch let error as Limiter.LimiterError {
            if case .invalid = error {return}
            throw Failure.check("\(tag): wrong typed error \(error)")
        }
        throw Failure.check("\(tag): invalid input was accepted")
    }
    static func budget(_ tag:String,_ operation:()throws->Void)throws {
        do {try operation()} catch let error as Limiter.LimiterError {
            if case .budgetExceeded = error {return}
            throw Failure.check("\(tag): wrong typed error \(error)")
        }
        throw Failure.check("\(tag): budget was ignored")
    }
    static func sendable<T:Sendable>(_ value:T) {}
    static func center(_ p:[Vector],weights:[Double])->Vector {
        var sum=Vector.zero,total=0.0
        for i in p.indices {let mass=1/weights[i];sum=sum+p[i]*mass;total += mass}
        return sum/total
    }
    static func main()throws {
        let spring=Kernel.Spring(a:0,b:1,length:1)
        let limiter=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,3],
            maximumSingleVertexCorrectionMeters:2)
        sendable(limiter)
        for (tag,start,expectedA,expectedB,expectedLength) in [
            ("stretch",2.0,0.2375,1.2875,1.05),
            ("compression",0.4,-0.1375,0.8125,0.95)] {
            var p=[vector(0),vector(start)]
            let before=center(p,weights:[1,3])
            let statistics=try limiter.project(positions:&p)
            try require(close(p[0].x,expectedA) && close(p[1].x,expectedB),"\(tag): independent analytic 1:3 displacement is wrong")
            try require(close((p[1]-p[0]).length,expectedLength),"\(tag): actual positions missed the source interval")
            try require((center(p,weights:[1,3])-before).length<1e-12,"\(tag): mass-weighted center moved")
            try require(statistics.projectedConstraints==1 && statistics.cappedCorrections==0 && statistics.examinedConstraints==1,"\(tag): incorrect contact statistics")
        }
        var capped=[vector(0),vector(2)]
        let cappedBefore=center(capped,weights:[1,3])
        let cappedLimiter=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,3])
        let capStatistics=try cappedLimiter.project(positions:&capped)
        try require(close(capped[0].x,0.02/3) && close(capped[1].x,1.98),"20 mm actual-vertex cap changed the 1:3 correction ratio")
        try require(close(capStatistics.maximumSingleVertexCorrectionMeters,0.02) && capStatistics.cappedCorrections==1,"Correction cap was not reported precisely")
        try require((center(capped,weights:[1,3])-cappedBefore).length<1e-12,"Capped projection moved the mass center")
        try require((capped[1]-capped[0]).length>1.05,"Cap silently certified an unresolved edge")

        var pinned=[vector(0),vector(2)]
        let pinLimiter=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[0,3],maximumSingleVertexCorrectionMeters:2)
        _=try pinLimiter.project(positions:&pinned)
        try require(pinned[0]==vector(0) && close(pinned[1].x,1.05),"Zero-weight pin moved or free endpoint missed the target")
        var conflict=[vector(0),vector(2)],unchangedConflict=conflict
        let fixed=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[0,0])
        let conflictStatistics=try fixed.project(positions:&conflict)
        try require(conflict==unchangedConflict && conflictStatistics.unresolvedPinnedConstraints==1 && conflictStatistics.projectedConstraints==0,"Fully pinned violation was hidden or moved")

        for length in [0.95,0.98,1,1.02,1.05] {
            var p=[vector(0),vector(length)],original=p
            let statistics=try limiter.project(positions:&p)
            try require(p==original && statistics.projectedConstraints==0,"A source edge inside the interval moved")
        }
        var rigid=[vector(0),vector(1.3)]
        let zeroLimit=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumAbsoluteStrain:0,maximumSingleVertexCorrectionMeters:2)
        _=try zeroLimit.project(positions:&rigid)
        try require(close((rigid[1]-rigid[0]).length,1),"Zero is a valid inextensible limit")

        let network=[Kernel.Spring(a:0,b:1,length:1),Kernel.Spring(a:1,b:2,length:sqrt(2)),Kernel.Spring(a:2,b:0,length:1)]
        let beforeGraph=network.map {[$0.a.double,$0.b.double,$0.length,$0.isShear ? 1 : 0]}
        let networkLimiter=try Limiter(vertexCount:3,springs:network,normalizedInverseMass:[0,1,3])
        var networkPositions=[vector(0),vector(1.4),vector(0,1.4)]
        for pass in 0..<500 {_=try networkLimiter.project(positions:&networkPositions,reverseOrder:pass%2==1)}
        let actualMaximum=network.map {abs((networkPositions[$0.a]-networkPositions[$0.b]).length/$0.length-1)}.max()!
        try require(actualMaximum<=0.05+1e-10 && networkPositions[0]==vector(0),"Alternating real-position projections did not satisfy a feasible source graph")
        try require(network.map {[$0.a.double,$0.b.double,$0.length,$0.isShear ? 1 : 0]}==beforeGraph,"Limiter modified source spring records")

        var collapsed=[vector(1),vector(1)],collapsedBefore=collapsed
        let collapsedStatistics=try cappedLimiter.project(positions:&collapsed)
        try require(collapsed==collapsedBefore && collapsed.allSatisfy(\.isFinite) && collapsedStatistics.collapsedConstraints==1 && collapsedStatistics.projectedConstraints==0,"Collapsed direction fabricated a finite-looking repair")
        let collapsedFixed=try fixed.project(positions:&collapsed)
        try require(collapsedFixed.collapsedConstraints==1 && collapsedFixed.unresolvedPinnedConstraints==1,"Collapsed pinned conflict was not explicit")

        // A single correction cap is deliberately not a total pass budget.
        let star=try Limiter(vertexCount:3,springs:[.init(a:0,b:1,length:0.1),.init(a:0,b:2,length:0.1)],normalizedInverseMass:[1,0,0])
        var starPositions=[vector(0),vector(1),vector(2)]
        let starStatistics=try star.project(positions:&starPositions)
        try require(close(starPositions[0].x,0.04) && close(starStatistics.maximumSingleVertexCorrectionMeters,0.02),"Single-edge correction cap was confused with pass displacement")

        for bad in [-0.01,0.400001,Double.nan,Double.infinity] {
            try invalid("strain limit") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumAbsoluteStrain:bad)}
        }
        _=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumAbsoluteStrain:0.4)
        for bad in [0.0,-0.02,Double.nan,Double.infinity,11] {
            try invalid("correction cap") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumSingleVertexCorrectionMeters:bad)}
        }
        for weights in [[1],[-1,1],[Double.nan,1],[Double.infinity,1],[1e13,1]] {
            try invalid("mass validation") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:weights)}
        }
        for graph in [[Kernel.Spring](),[.init(a:0,b:0,length:1)],[.init(a:0,b:2,length:1)],
                      [.init(a:-1,b:1,length:1)],[.init(a:0,b:1,length:0)],[.init(a:0,b:1,length:Double.nan)],
                      [.init(a:0,b:1,length:Double.infinity)],[spring,.init(a:1,b:0,length:1)]] {
            try invalid("source graph") {_=try Limiter(vertexCount:2,springs:graph,normalizedInverseMass:[1,1])}
        }
        try invalid("empty vertices") {_=try Limiter(vertexCount:0,springs:[spring],normalizedInverseMass:[])}
        try invalid("invalid vertex budget") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumVertices:0)}
        try invalid("invalid edge budget") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumConstraints:0)}
        try budget("vertex count") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumVertices:1)}
        try budget("edge count") {_=try Limiter(vertexCount:3,springs:Array(network.prefix(2)),normalizedInverseMass:[1,1,1],maximumConstraints:1)}
        try invalid("invalid position bound") {_=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,1],maximumPositionMagnitudeMeters:0)}
        var wrongCount=[vector(0)]
        try invalid("position count") {_=try limiter.project(positions:&wrongCount)}
        var nonfinite=[vector(Double.nan),vector(1)]
        try invalid("nonfinite positions") {_=try limiter.project(positions:&nonfinite)}
        try require(nonfinite[0].x.isNaN && nonfinite[1]==vector(1),"Invalid pass partially replaced its input")
        var excessive=[vector(6),vector(1)]
        try invalid("coordinate bound") {_=try limiter.project(positions:&excessive)}
        let escapes=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1,0],maximumSingleVertexCorrectionMeters:2)
        var boundary=[vector(4.99),vector(4.989)],boundaryBefore=boundary
        try invalid("postprojection bound") {_=try escapes.project(positions:&boundary)}
        try require(boundary==boundaryBefore,"Failed postprojection bounds check was not transactional")
        var tiny=[vector(0),vector(2)]
        let tinyLimiter=try Limiter(vertexCount:2,springs:[spring],normalizedInverseMass:[1e-310,3e-310])
        _=try tinyLimiter.project(positions:&tiny)
        try require(tiny.allSatisfy(\.isFinite) && close(tiny[0].x,0.02/3) && close(tiny[1].x,1.98),"Finite tiny weights produced overflow or changed their ratio")

        var cancelledPositions=[vector(0),vector(2)],cancelledBefore=cancelledPositions
        var cancelled=false
        do {_=try limiter.project(positions:&cancelledPositions,isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled && cancelledPositions==cancelledBefore,"Pre-cancelled projection changed positions")
        let chain=(0..<130).map {Kernel.Spring(a:$0,b:$0+1,length:0.02)}
        let chainLimiter=try Limiter(vertexCount:131,springs:chain,normalizedInverseMass:Array(repeating:1,count:131))
        var chainPositions=(0..<131).map {vector(Double($0)*0.03)},chainBefore=chainPositions
        let counter=StrainLimitCancellationCounter(cancelAt:3)
        cancelled=false
        do {_=try chainLimiter.project(positions:&chainPositions,isCancelled:{counter.check()})} catch is CancellationError {cancelled=true}
        try require(cancelled && counter.calls==3 && chainPositions==chainBefore,"Periodic cancellation missed the 64-constraint interval or leaked partial positions")
        print("PASS source strain limiter: independent weighted stretch/compression, center/pins/cap, alternating source graph, immutable rest metrics, typed validation/budgets, collapsed direction, transactional periodic cancellation")
    }
}

private extension Int {var double:Double {Double(self)}}
