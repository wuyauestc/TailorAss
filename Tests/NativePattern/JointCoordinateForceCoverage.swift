import Foundation

/// Mathematical candidate-selection controls, not a garment or fit capability.
@main enum JointCoordinateForceCoverage {
    typealias N=GarmentCodeJointNewton
    typealias V=N.V
    enum Failure:Error {case failed(String)}
    static func check(_ b:Bool,_ m:String)throws {if !b{throw Failure.failed(m)}}
    static func component(_ v:V,_ j:Int)->Double {[v.x,v.y,v.z][j]}
    static func main()throws {
        let out=URL(fileURLWithPath:CommandLine.arguments[1])
        // A real quadratic counterexample: the continuous optimum of the two
        // stiff coupled z coordinates is .3 ULP in each coordinate, while one
        // single-coordinate ULP decreases Phi. Large-spacing distractors have
        // greater |g*ULP| but every individual step increases this same Phi.
        var x:[V]=[],g:[V]=[]
        for i in 0..<36 {x.append(.init(x:1+Double(i%6)*0.05,y:1+Double(i/6)*0.05,z:0.02));g.append(.init(x:5e-7,y:5e-7,z:0))}
        let k=6e11,spacing=x[0].z-x[0].z.nextDown,specialForce=0.57*k*spacing
        g[0].z=specialForce;g[1].z=specialForce
        try check(specialForce>1e-6,"The force threshold is actually violated")
        var old:[(dof:Int,slope:Double,delta:Double)]=[]
        for v in x.indices {for axis in 0..<3 {
            let f=component(g[v],axis),value=component(x[v],axis);if f==0{continue}
            let d=value.nextDown-value;old.append((3*v+axis,f*d,d))
        }}
        old.sort{$0.slope==$1.slope ? $0.dof<$1.dof:$0.slope<$1.slope}
        let original=Array(old.prefix(64))
        try check(original.allSatisfy{$0.dof != 2 && $0.dof != 5},"Old work-only pool misses both stiff-force coordinates")
        func diagonal(_ dof:Int,_ d:Double)->Double {
            (dof==2 || dof==5) ? k:component(g[dof/3],dof%3)/(0.3*abs(d))
        }
        try check(original.allSatisfy{$0.slope+0.5*diagonal($0.dof,$0.delta)*$0.delta*$0.delta>0},"Every original pool move raises the analytical quadratic")
        let pool=try N.coordinateProposalPool(positions:x,gradient:g,travel:Array(repeating:0,count:x.count))
        try check(pool.proposals.count==64 && pool.forceResidualPriorityCandidates==2,"Same64 slots cover both actual force violations")
        try check(Set(pool.proposals.map(\.dof)).count==64,"No duplicate products/candidates")
        guard let q=pool.proposals.first(where:{$0.dof==2})else{throw Failure.failed("Force coordinate omitted")}
        let delta=q.slope+0.5*k*q.delta*q.delta
        try check(delta<0 && delta<=1e-4*q.slope,"Covered move strictly satisfies unchanged actual Armijo")
        let own=specialForce+k*q.delta,other=specialForce+0.9*k*q.delta
        let after=max(5e-7,abs(own),abs(other))
        try check(after<1e-6,"Analytical post-move force meets original threshold")
        // Coverage never invents a movement after a particle exhausts its
        // original .5m solver travel, even if its residual force is enormous.
        let exhausted=try N.coordinateProposalPool(positions:x,gradient:g,travel:Array(repeating:0.5,count:x.count))
        try check(exhausted.proposals.isEmpty && exhausted.forceResidualPriorityCandidates==0,"Original path caps remain eligibility gates")
        var tieX=Array(repeating:V(x:1.2,y:1.3,z:1.4),count:40),tieG=Array(repeating:V.zero,count:40)
        for v in tieG.indices {tieG[v] = .init(x:2e-6,y:2e-6,z:2e-6)}
        let tied=try N.coordinateProposalPool(positions:tieX,gradient:tieG,travel:Array(repeating:0,count:40))
        try check(tied.proposals.count==64 && tied.forceResidualPriorityCandidates==16,"Priority is bounded at16 inside64")
        try check(Set(0..<16).isSubset(of:Set(tied.proposals.map(\.dof))),"Force ties use deterministic smallestDOF coverage")
        // When the force set was already inside the old pool, preserve the
        // original work/product ordering exactly, not just its membership.
        for v in tieG.indices {tieG[v] = .init(x:Double(3*v+1)*1e-6,y:Double(3*v+2)*1e-6,z:Double(3*v+3)*1e-6)}
        var reference:[(Int,Double)]=[]
        for v in tieX.indices {for axis in 0..<3 {let z=component(tieX[v],axis);reference.append((3*v+axis,component(tieG[v],axis)*(z.nextDown-z)))}}
        reference.sort{$0.1==$1.1 ? $0.0<$1.0:$0.1<$1.1}
        let unchanged=try N.coordinateProposalPool(positions:tieX,gradient:tieG,travel:Array(repeating:0,count:40))
        try check(unchanged.proposals.map(\.dof)==reference.prefix(64).map(\.0),"Already-covered work order remains unchanged")
        // A signed-zero slope from subnormal multiplication cannot become a
        // valid proposal solely because its raw force is prioritized.
        let underflow=try N.coordinateProposalPool(positions:[.zero],gradient:[V(x:1e-6,y:0,z:0)],travel:[0])
        try check(underflow.proposals.isEmpty,"Underflowed work never grants eligibility")
        var cancelled=false
        do {_ = try N.coordinateProposalPool(positions:x,gradient:g,travel:Array(repeating:0,count:x.count),isCancelled:{true})}catch is CancellationError{cancelled=true}
        try check(cancelled,"Synchronous cancellation is explicit")
        tieX[0].x = .nan;var invalid=false
        do {_ = try N.coordinateProposalPool(positions:tieX,gradient:tieG,travel:Array(repeating:0,count:40))}catch{invalid=true}
        try check(invalid,"Nonfinite input is rejected")
        // A certified tiny update of only a low-force coordinate cannot
        // make representational progress on any violating coordinate.
        let stalledX=[V(x:1,y:1,z:1)],stalledG=[V(x:2e-6,y:1.5e-6,z:1e-8)]
        let tiny=[V(x:1,y:1,z:Double(1).nextUp)]
        try check(N.roundedForceStall(positions:stalledX,gradient:stalledG,candidate:tiny,candidateGradient:stalledG),"Exact frozen violating coordinates qualify as work only")
        try check(!N.roundedForceStall(positions:stalledX,gradient:stalledG,candidate:[V(x:Double(1).nextUp,y:1,z:1)],candidateGradient:stalledG),"Any moved violating coordinate prevents this trigger")
        try check(!N.roundedForceStall(positions:stalledX,gradient:stalledG,candidate:tiny,candidateGradient:[V(x:1.9e-6,y:1.5e-6,z:1e-8)]),"Real force improvement retains the original radius trigger")
        try check(!N.roundedForceStall(positions:stalledX,gradient:[.zero],candidate:tiny,candidateGradient:[.zero]),"No violating force cannot qualify")
        try check(!N.roundedForceStall(positions:stalledX,gradient:stalledG,candidate:[],candidateGradient:stalledG),"Mismatched state never qualifies")
        try check(!N.roundedForceStall(positions:stalledX,gradient:stalledG,candidate:tiny,candidateGradient:[V(x:.nan,y:0,z:0)]),"Nonfinite force never qualifies")
        try JointCoupledProposalBoundaryChecks.run()
        let report:[String:Any]=["passed":true,"analyticalQuadraticOriginalPoolAllRise":true,"analyticalNewCoveredMoveStrictlyDescends":true,
            "postForceInfinity":after,"originalForceInfinity":specialForce,"deltaPhi":delta,"candidateSlots":pool.proposals.count,
            "forcePrioritySlots":pool.forceResidualPriorityCandidates,"priorityCap":16,"preservesAlreadyCoveredWorkOrder":true,
            "pathCapUnderflowCancellationAndInvalidControlsPassed":true,"coupledProposalBoundaryControlsPassed":true,"completeGarmentAccepted":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out)
        print("FORCE_COVERAGE_CONTROLS_PASS")
    }
}

nonisolated enum JointCoupledProposalBoundaryChecks {
    typealias H=GarmentCodeCoupledCoordinateProposals
    typealias V=H.V
    enum Bad:Error{case check(String)}
    static func check(_ b:Bool,_ s:String)throws{if !b{throw Bad.check(s)}}
    static func run()throws {
        let x=Array(repeating:V(x:0.25,y:0.25,z:0.25),count:3),g=[V(x:1.1e-6,y:0,z:0),V(x:0,y:0,z:0),V(x:0,y:0,z:0)],travel=Array(repeating:0.0,count:3)
        func col(_ i:Int)->[V] {
            var a=Array(repeating:0.0,count:9);a[i]=i<3 ? (i==0 ? 2e11+1:1e11+1):1
            if i==0{a[1] = -1e11;a[2] = -1e11}
            if i==1 || i==2{a[0] = -1e11}
            return stride(from:0,to:9,by:3).map{V(x:a[$0],y:a[$0+1],z:a[$0+2])}
        }
        var calls=0
        let built=try H.build(positions:x,gradient:g,travel:travel,hessianColumn:{calls+=1;return col($0)})
        try check(calls==3 && built.statistics.rawBasisProducts==3 && built.statistics.availablePartners==2 && built.proposals.count<=8 && !built.proposals.isEmpty,"Honest bounded basis/proposal counts")
        for p in built.proposals{try check(p.targetDOF==0 && p.changes.count==3 && Set(p.changes.map(\.dof)).count==3 && p.changes.allSatisfy{$0.value.isFinite && $0.delta != 0},"No fabricated or duplicate changes")}
        let again=try H.build(positions:x,gradient:g,travel:travel,hessianColumn:col)
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys];try check(try enc.encode(built.proposals)==enc.encode(again.proposals),"Pure matrix repeat ordering")
        var limit=H.Limits();limit.maximumBasisProducts=1;calls=0
        let budget=try H.build(positions:x,gradient:g,travel:travel,limits:limit,hessianColumn:{calls+=1;return col($0)})
        try check(calls==1 && budget.statistics.rawBasisProducts==1 && budget.statistics.budgetLimited && budget.proposals.isEmpty,"Column cap enforced before callback")
        limit=H.Limits();limit.maximumTemporaryBytes=1;calls=0
        let memory=try H.build(positions:x,gradient:g,travel:travel,limits:limit,hessianColumn:{calls+=1;return col($0)})
        try check(calls==0 && memory.statistics.chargedTemporaryBytes==0 && memory.statistics.budgetLimited,"Scratch cap enforced before allocation/product")
        var seen=false
        do {_ = try H.build(positions:x,gradient:g,travel:travel,hessianColumn:col,isCancelled:{true})}catch is CancellationError{seen=true}
        try check(seen,"Entry cancellation")
        var cancel=false;seen=false
        do {_ = try H.build(positions:x,gradient:g,travel:travel,hessianColumn:{cancel=true;return col($0)},isCancelled:{cancel})}catch is CancellationError{seen=true}
        try check(seen,"After-product cancellation publishes no result")
        seen=false
        do {_ = try H.build(positions:x,gradient:g,travel:travel,hessianColumn:{_ in []})}catch H.Failure.invalidHessianProduct{seen=true}
        try check(seen,"Foreign product dimensions")
        seen=false;var bad=x;bad[0]=V(x:Double.nan,y:0,z:0)
        do {_ = try H.build(positions:bad,gradient:g,travel:travel,hessianColumn:col)}catch H.Failure.invalidInput{seen=true}
        try check(seen,"Nonfinite positions")
        let capped=try H.build(positions:x,gradient:g,travel:Array(repeating:0.5,count:3),hessianColumn:col)
        try check(capped.statistics.rawBasisProducts==0 && capped.proposals.isEmpty,"Exact spent travel cannot move any nonzero delta")
        let noForce=try H.build(positions:x,gradient:Array(repeating:V(x:0,y:0,z:0),count:3),travel:travel,hessianColumn:col)
        try check(noForce.statistics.rawBasisProducts==0 && noForce.proposals.isEmpty,"No force target")
        print("PASS helper10 bounded data/cancellation/nonfinite/repeat/travel controls; no physics or acceptance")
    }
}
