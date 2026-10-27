import Foundation

/// Data-only adversarial controls for the independent result boundary. These
/// do not construct a Session, PhysicalSubstep or Validated result.
nonisolated enum JointPhysicalLeafValidationChecks {
    typealias R=GarmentCodeJointResult
    typealias V=R.V
    enum Failure:Error {case failed(String)}
    static func run()throws->Int {
        let settings=R.S.Settings(),index=481,initial=[V.zero],initialVelocity=[V.zero]
        func leaf(_ position:[V],_ velocity:[V],_ start:Int,_ end:Int,_ denominator:Int)->R.PhysicalKinematics {
            let dt=settings.timeStepSeconds*Double(end-start)/Double(denominator)
            let gravity=min(1,max(0,(Double(index-settings.staticAssemblySteps-1)+Double(end)/Double(denominator))/Double(settings.gravityRampSteps)))
            let damping=exp(-settings.velocityDampingPerSecond*dt),a=V(x:0,y:-settings.gravityMetersPerSecondSquared*gravity,z:0)
            let predictor=zip(position,velocity).map{$0+$1*(damping*dt)+a*(dt*dt)}
            return .init(previousPositions:position,previousVelocities:velocity,acceptedPositions:predictor,
                acceptedVelocities:zip(predictor,position).map{($0-$1)/dt},predictor:predictor,
                startTick:start,endTick:end,ticksPerMacroStep:denominator,timeStepSeconds:dt,sewingRamp:1,gravityFraction:gravity)
        }
        func edit(_ l:R.PhysicalKinematics,start:Int?=nil,end:Int?=nil,ticks:Int?=nil,dt:Double?=nil,gravity:Double?=nil,
                  previous:[V]?=nil,previousVelocity:[V]?=nil,acceptedVelocity:[V]?=nil,predictor:[V]?=nil)->R.PhysicalKinematics {
            .init(previousPositions:previous ?? l.previousPositions,previousVelocities:previousVelocity ?? l.previousVelocities,
                acceptedPositions:l.acceptedPositions,acceptedVelocities:acceptedVelocity ?? l.acceptedVelocities,predictor:predictor ?? l.predictor,
                startTick:start ?? l.startTick,endTick:end ?? l.endTick,ticksPerMacroStep:ticks ?? l.ticksPerMacroStep,
                timeStepSeconds:dt ?? l.timeStepSeconds,sewingRamp:l.sewingRamp,gravityFraction:gravity ?? l.gravityFraction)
        }
        let first=leaf(initial,initialVelocity,0,1,2),last=leaf(first.acceptedPositions,first.acceptedVelocities,1,2,2)
        let chain=[first,last]
        func check(_ xs:[R.PhysicalKinematics],depth:Int=1,velocity:[V]?=nil,predictor:[V]?=nil,cancel:@Sendable()->Bool={false})throws {
            try R.checkedPhysicalSubstepKinematics(previousPositions:initial,previousVelocities:initialVelocity,
                acceptedPositions:last.acceptedPositions,acceptedVelocities:velocity ?? last.acceptedVelocities,
                finalPredictor:predictor ?? last.predictor,macroStep:index,settings:settings,maximumSubdivisionDepth:depth,
                leaves:xs,isCancelled:cancel)
        }
        var count=0
        try check(chain);count+=1
        for depth in 0...4 {
            let one=leaf(initial,initialVelocity,0,1<<depth,1<<depth)
            try R.checkedPhysicalSubstepKinematics(previousPositions:initial,previousVelocities:initialVelocity,
                acceptedPositions:one.acceptedPositions,acceptedVelocities:one.acceptedVelocities,finalPredictor:one.predictor,
                macroStep:index,settings:settings,maximumSubdivisionDepth:depth,leaves:[one]);count+=1
        }
        func partition(_ spans:[(Int,Int)],ticks:Int)->[R.PhysicalKinematics] {
            var position=initial,velocity=initialVelocity,result:[R.PhysicalKinematics]=[]
            for (start,end) in spans {let next=leaf(position,velocity,start,end,ticks);result.append(next);position=next.acceptedPositions;velocity=next.acceptedVelocities}
            return result
        }
        func audit(_ xs:[R.PhysicalKinematics],depth:Int)throws->Int {
            guard let end=xs.last else {throw Failure.failed("Test partition must not be empty")}
            return try R.checkedPhysicalSubstepKinematics(previousPositions:initial,previousVelocities:initialVelocity,
                acceptedPositions:end.acceptedPositions,acceptedVelocities:end.acceptedVelocities,finalPredictor:end.predictor,
                macroStep:index,settings:settings,maximumSubdivisionDepth:depth,leaves:xs)
        }
        let mixed=partition([(0,2),(2,4),(4,6),(6,7),(7,8)],ticks:8)
        guard try audit(mixed,depth:3)==3 else {throw Failure.failed("Actual mixed depth must be3")};count+=1
        let uniform=partition((0..<8).map{($0,$0+1)},ticks:8)
        guard try audit(uniform,depth:3)==3 else {throw Failure.failed("Eight true eighths")};count+=1
        let quarters=partition([(0,2),(2,4),(4,6),(6,8)],ticks:8)
        guard try audit(quarters,depth:3)==2 else {throw Failure.failed("Configured3 is not actual2")};count+=1
        func reject(_ name:String,_ body:()throws->Void)throws {
            do {try body()} catch {count+=1;return}
            throw Failure.failed("Physical leaf validator accepted "+name)
        }
        try reject("leaf budget"){_ = try audit(Array(repeating:mixed[0],count:9),depth:3)}
        try reject("non-dyadic width"){_ = try audit(partition([(0,3),(3,8)],ticks:8),depth:3)}
        try reject("misaligned dyadic width"){_ = try audit(partition([(0,1),(1,3),(3,4),(4,8)],ticks:8),depth:3)}
        try reject("mixed gap"){_ = try audit([mixed[0],edit(mixed[1],start:3)]+Array(mixed.dropFirst(2)),depth:3)}
        try reject("mixed stale predictor"){_ = try audit(Array(mixed.dropLast())+[edit(mixed.last!,predictor:mixed[0].predictor)],depth:3)}
        try reject("mixed wrong velocity"){_ = try audit(Array(mixed.dropLast())+[edit(mixed.last!,acceptedVelocity:initialVelocity)],depth:3)}
        try reject("empty partition"){try check([])}
        try reject("gap"){try check([first,edit(last,start:2)])}
        try reject("overlap"){try check([first,edit(last,start:0)])}
        try reject("wrong denominator"){try check([edit(first,ticks:3),last])}
        try reject("wrong dt"){try check([edit(first,dt:settings.timeStepSeconds),last])}
        try reject("wrong load"){try check([edit(first,gravity:last.gravityFraction),last])}
        try reject("wrong source order"){try check([last,first])}
        try reject("stale predictor"){try check([edit(first,predictor:initial),last])}
        try reject("wrong leaf velocity"){try check([edit(first,acceptedVelocity:initialVelocity),last])}
        try reject("macro average velocity"){try check(chain,velocity:zip(last.acceptedPositions,initial).map{($0-$1)/settings.timeStepSeconds})}
        try reject("wrong final predictor"){try check(chain,predictor:first.predictor)}
        var signedZero=last.previousPositions;signedZero[0].x = -0.0
        try reject("signed-zero broken position chain"){try check([first,edit(last,previous:signedZero)])}
        var nonfinite=last.previousVelocities;nonfinite[0].z = .nan
        try reject("nonfinite velocity"){try check([first,edit(last,previousVelocity:nonfinite)])}
        try reject("fraction integer overflow"){try check([edit(first,start:Int.min),last])}
        try reject("unapproved depth"){try check(chain,depth:5)}
        do {try check(chain,cancel:{true});throw Failure.failed("Cancellation not thrown")}
        catch is CancellationError {count+=1}
        typealias Span=R.S.PhysicalSeedSpan
        typealias Node=R.S.PhysicalAttemptLedger
        func span(_ a:Int,_ b:Int,_ d:Int=8)->Span {.init(startTick:a,endTick:b,ticksPerMacroStep:d)}
        let leafSpans=[span(0,2),span(2,4),span(4,6),span(6,7),span(7,8)]
        func node(_ seed:Int,_ parent:Int?,_ a:Int,_ b:Int,_ accepted:Bool,_ d:Int=8)->Node {
            .init(seedIndex:seed,parentAttemptIndex:parent,startTick:a,endTick:b,ticksPerMacroStep:d,
                accepted:accepted,rejectionReason:accepted ? nil:"actualFailure",computationSeconds:0.25)
        }
        let rootNodes=[node(0,nil,0,8,false),node(0,0,0,4,false),node(0,1,0,2,true),node(0,1,2,4,true),
            node(0,0,4,8,false),node(0,4,4,6,true),node(0,4,6,8,false),node(0,6,6,7,true),node(0,6,7,8,true)]
        let halfNodes=[node(0,nil,0,4,false),node(0,0,0,2,true),node(0,0,2,4,true),node(1,nil,4,8,false),
            node(1,3,4,6,true),node(1,3,6,8,false),node(1,5,6,7,true),node(1,5,7,8,true)]
        let reusedNodes=leafSpans.enumerated().map{node($0.offset,nil,$0.element.startTick,$0.element.endTick,true)}
        func forest(_ seeds:[Span],_ ls:[Span],_ nodes:[Node],depth:Int=3,attempts:Int?=nil,budget:Int=15,
                    cancel:@Sendable()->Bool={false})throws->R.PhysicalSeedForestProof {
            try R.checkedPhysicalSeedForest(seeds:seeds,leaves:ls,maximumDepth:depth,
                reportedAttempts:attempts ?? nodes.count,ledger:nodes,maximumAttempts:budget,isCancelled:cancel)
        }
        let fromRoot=try forest([span(0,8)],leafSpans,rootNodes)
        guard fromRoot.attemptCount==9,fromRoot.acceptedAttemptIndices==[2,3,5,7,8],
              fromRoot.leafSeedIndices==[0,0,0,0,0],fromRoot.actualMaximumDepth==3 else {throw Failure.failed("Root forest ledger")};count+=1
        // Actual historical922 contained two halves, not the five later923
        // leaves. Reusing those roots skips exactly the root attempt, not more.
        let fromHalves=try forest([span(0,4),span(4,8)],leafSpans,halfNodes)
        guard fromHalves.attemptCount==8,fromHalves.acceptedAttemptIndices==[1,2,4,6,7],
              fromHalves.leafSeedIndices==[0,0,1,1,1] else {throw Failure.failed("Historical two-root forest")};count+=1
        let reused=try forest(leafSpans,leafSpans,reusedNodes)
        guard reused.attemptCount==5,reused.acceptedAttemptIndices==Array(0..<5),reused.leafSeedIndices==Array(0..<5) else {throw Failure.failed("Committed partition reuse")};count+=1
        for depth in 0...4 {
            let end=1<<depth
            let one=try forest([span(0,end,end)],[span(0,end,end)],[node(0,nil,0,end,true,end)],depth:depth)
            guard one.actualMaximumDepth==0 else {throw Failure.failed("Root alone must have actual depth0")};count+=1
        }
        func change(_ x:Node,seed:Int?=nil,parent:Int??=nil,accepted:Bool?=nil,reason:String??=nil,seconds:Double?=nil)->Node {
            .init(seedIndex:seed ?? x.seedIndex,parentAttemptIndex:parent ?? x.parentAttemptIndex,
                startTick:x.startTick,endTick:x.endTick,ticksPerMacroStep:x.ticksPerMacroStep,
                accepted:accepted ?? x.accepted,rejectionReason:reason ?? x.rejectionReason,computationSeconds:seconds ?? x.computationSeconds)
        }
        try reject("forest missing roots"){_ = try forest([],leafSpans,rootNodes)}
        try reject("forest non-dyadic roots"){_ = try forest([span(0,3),span(3,8)],leafSpans,halfNodes)}
        try reject("forest root gap"){_ = try forest([span(0,2),span(4,8)],leafSpans,halfNodes)}
        try reject("forest leaf crosses seed"){_ = try forest([span(0,4),span(4,8)],[span(0,8)],rootNodes)}
        try reject("forest ghost failed parent"){_ = try forest(leafSpans,leafSpans,rootNodes)}
        try reject("forest omitted failed parent"){_ = try forest([span(0,8)],leafSpans,reusedNodes)}
        try reject("forest wrong count"){_ = try forest([span(0,8)],leafSpans,rootNodes,attempts:8)}
        try reject("forest wrong root owner"){_ = try forest([span(0,8)],leafSpans,[change(rootNodes[0],seed:1)]+Array(rootNodes.dropFirst()))}
        try reject("forest wrong parent"){_ = try forest([span(0,8)],leafSpans,Array(rootNodes.prefix(2))+[change(rootNodes[2],parent:.some(0))]+Array(rootNodes.dropFirst(3)))}
        try reject("forest missing parent"){_ = try forest([span(0,8)],leafSpans,Array(rootNodes.prefix(2))+[change(rootNodes[2],parent:.some(nil))]+Array(rootNodes.dropFirst(3)))}
        try reject("forest accepts failed node"){_ = try forest([span(0,8)],leafSpans,[change(rootNodes[0],accepted:true,reason:.some(nil))]+Array(rootNodes.dropFirst()))}
        try reject("forest failed reason missing"){_ = try forest([span(0,8)],leafSpans,[change(rootNodes[0],reason:.some(nil))]+Array(rootNodes.dropFirst()))}
        try reject("forest successful reason present"){_ = try forest(leafSpans,leafSpans,[change(reusedNodes[0],reason:.some("failure"))]+Array(reusedNodes.dropFirst()))}
        try reject("forest node NaN time"){_ = try forest([span(0,8)],leafSpans,[change(rootNodes[0],seconds:.nan)]+Array(rootNodes.dropFirst()))}
        try reject("forest node negative time"){_ = try forest([span(0,8)],leafSpans,[change(rootNodes[0],seconds:-1)]+Array(rootNodes.dropFirst()))}
        var swapped=rootNodes;swapped.swapAt(2,3)
        try reject("forest swapped DFS children"){_ = try forest([span(0,8)],leafSpans,swapped)}
        try reject("forest denominator mismatch"){_ = try forest([span(0,8,16)],leafSpans,rootNodes)}
        try reject("forest malicious endpoint"){_ = try forest([span(Int.min,8)],leafSpans,rootNodes)}
        try reject("forest unsupported depth"){_ = try forest([span(0,8)],leafSpans,rootNodes,depth:5)}
        let fineSpans=[(0,2),(2,3),(3,4),(4,6),(6,8),(8,10),(10,12),(12,14),(14,16)]
        let fine=partition(fineSpans,ticks:16)
        guard try audit(fine,depth:4)==4 else {throw Failure.failed("Nine physical leaves may use fourth-level resolution")};count+=1
        let fineSeeds=[span(0,4,16)]+stride(from:4,to:16,by:2).map{span($0,$0+2,16)}
        let fineLeaves=fineSpans.map{span($0.0,$0.1,16)}
        let fineNodes=[node(0,nil,0,4,false,16),node(0,0,0,2,true,16),node(0,0,2,4,false,16),
            node(0,2,2,3,true,16),node(0,2,3,4,true,16)] +
            Array(fineSeeds.dropFirst()).enumerated().map{node($0.offset+1,nil,$0.element.startTick,$0.element.endTick,true,16)}
        let fineForest=try forest(fineSeeds,fineLeaves,fineNodes,depth:4)
        guard fineForest.leafCount==9,fineForest.attemptCount==11,fineForest.actualMaximumDepth==4 else {throw Failure.failed("Resolution must be independent of the 15-attempt budget")};count+=1
        try reject("fine forest over lower budget"){_ = try forest(fineSeeds,fineLeaves,fineNodes,depth:4,budget:10)}
        try reject("zero attempt budget"){_ = try forest(fineSeeds,fineLeaves,fineNodes,depth:4,budget:0)}
        try reject("unapproved attempt budget"){_ = try forest(fineSeeds,fineLeaves,fineNodes,depth:4,budget:16)}
        let fifteen=[span(0,2,16)]+(2..<16).map{span($0,$0+1,16)}
        let fifteenNodes=fifteen.enumerated().map{node($0.offset,nil,$0.element.startTick,$0.element.endTick,true,16)}
        guard try forest(fifteen,fifteen,fifteenNodes,depth:4).attemptCount==15 else {throw Failure.failed("Exact fixed attempt budget")};count+=1
        let sixteen=(0..<16).map{span($0,$0+1,16)}
        let sixteenNodes=sixteen.enumerated().map{node($0.offset,nil,$0.element.startTick,$0.element.endTick,true,16)}
        try reject("sixteen successful roots exceed real budget"){_ = try forest(sixteen,sixteen,sixteenNodes,depth:4)}
        do {_ = try forest([span(0,8)],leafSpans,rootNodes,cancel:{true});throw Failure.failed("Forest cancellation not thrown")}
        catch is CancellationError {count+=1}
        return count
    }
}
