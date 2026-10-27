import Foundation

@main @MainActor
struct SewnPointBlockRegression {
    typealias B=GarmentCodeSewnPointBlock
    typealias S=GarmentCodeSewing
    typealias V=B.Vector3
    enum Failure:Error {case check(String)}
    static var checks:[String]=[],metrics:[String:Double]=[:]
    static var caseStatistics:[String:Any]=[:]
    static func v(_ x:Double,_ y:Double=0,_ z:Double=0)->V{.init(x:x,y:y,z:z)}
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws{if !value(){throw Failure.check(message)}}
    static func passed(_ message:String){checks.append(message);print("PASS "+message)}
    static func record(_ label:String,_ stats:B.Statistics)throws{
        caseStatistics[label]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(stats))
    }
    static func a(_ id:Int)throws->S.Attachment{try .init(vertexID:id)}
    static func c(_ x:Int,_ y:Int)throws->S.Constraint{try .init(a:a(x),b:a(y),initialGapMeters:0)}
    static func prepared(_ constraints:[S.Constraint],_ weights:[Double],compliance:Double=0,
                         limits:B.Limits = .init())throws->B.Prepared{
        try .init(vertexCount:weights.count,constraints:constraints,normalizedInverseMass:weights,
            physicalCompliance:compliance,meanParticleMassKg:0.001,timeStepSeconds:1.0/120,limits:limits)
    }
    static func solve(_ p:[V],_ q:B.Prepared,frame:Double=10,single:Double=10)throws->([V],B.FrameState,[Double],B.Statistics){
        var p=p,state=q.makeFrameState(),travel=Array(repeating:0.0,count:p.count)
        let result=try B.project(positions:&p,prepared:q,state:&state,frameTravelMeters:&travel,
            maximumFrameTravelMeters:frame,maximumSingleProjectionMeters:single)
        return (p,state,travel,result)
    }
    static func near(_ a:V,_ b:V,_ tolerance:Double=1e-10)->Bool{(a-b).length<tolerance}
    static func analyticalChecks()throws{
        let constraint=try c(0,1),q=try prepared([constraint],[1,4])
        let result=try solve([v(0),v(5)],q)
        try require(near(result.0[0],v(1)) && near(result.0[1],v(1)),"Unequal inverse masses did not conserve the analytic mass-weighted centre")
        try require(result.3.allLinearSystemsConverged && result.3.maximumActualGapMeters<1e-11,"Single hard coincidence failed its exact residual")
        let soft=try prepared([constraint],[1,4],compliance:1e-4),softResult=try solve([v(0),v(5)],soft)
        let expected=5/(5+soft.alpha)
        try require(abs(soft.alpha-1e-4*0.001/pow(1.0/120,2))<1e-15 && near(softResult.0[0],v(expected)) && near(softResult.0[1],v(5-4*expected)),"XPBD alpha or signed mass coefficients disagree with analytic compliance")
        var again=softResult.0,state=softResult.1,travel=softResult.2
        _=try B.project(positions:&again,prepared:soft,state:&state,frameTravelMeters:&travel,maximumFrameTravelMeters:10,maximumSingleProjectionMeters:10)
        try require(zip(again,softResult.0).allSatisfy{near($0,$1)},"Within-frame Cartesian lambda was not retained")
        try require(soft.makeFrameState().cartesianLambda.allSatisfy{$0 == .zero},"Fresh frame retained an earlier multiplier")
        let pinned=try solve([v(0),v(5)],prepared([constraint],[0,4]))
        try require(pinned.0[0]==v(0) && near(pinned.0[1],v(0)),"A pinned DOF moved or its free mate did not close")
        passed("Analytic unequal masses, pins, signed coefficients, physical alpha and per-frame Cartesian lambda")

        let shared=try S.Constraint(a:a(0),b:.init(vertexIDs:[1,2],weights:[0.5,0.5]),initialGapMeters:0)
        let rows=try [shared,c(1,2)],joint=try prepared(rows,[1,2,4]),jointResult=try solve([v(0),v(2),v(5)],joint)
        let centre=v((0+2/2.0+5/4.0)/(1+1/2.0+1/4.0))
        try require(joint.blockCount==1 && jointResult.0.allSatisfy{near($0,centre)},"Shared barycentric attachment rows were projected independently or with wrong coefficients")
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(rows);_=try solve([v(0),v(2),v(5)],joint)
        let after=try encoder.encode(rows)
        try require(before == after,"Block preparation/project changed original attachment coefficients or constraints")
        passed("Simultaneous shared barycentric rows preserve the original mass metric and input plan")
    }
    static func rankAndCGChecks()throws{
        let rows=try [c(0,1),c(1,2),c(2,0)],q=try prepared(rows,[1,2,4])
        let result=try solve([v(0),v(2),v(5)],q)
        try require(q.alpha==0 && q.matrixFreeBlockCount==1 && result.3.blocks[0].denseRankFallback,
            "Redundant zero-compliance cycle was regularized or treated as a positive-definite factor")
        try require(result.3.allLinearSystemsConverged && result.3.maximumActualGapMeters<1e-10,"Consistent PSD cycle did not converge honestly")
        let centre=v((2/2.0+5/4.0)/(1+1/2.0+1/4.0))
        try require(result.0.allSatisfy{near($0,centre)},"Redundant cycle changed physical mass weighting")
        try record("zeroAlphaRedundantCycle",result.3)
        let fixed=try prepared([c(0,1)],[0,0]),fixedResult=try solve([v(0),v(1)],fixed)
        try require(fixedResult.0==[v(0),v(1)] && !fixedResult.3.allLinearSystemsConverged && fixedResult.3.unconvergedConstraintIndices==[0] && fixedResult.3.unresolvedPinnedConstraintIndices==[0] && fixedResult.3.maximumActualGapMeters==1,
            "An all-pinned inconsistent hard row was moved or silently marked solved")
        try record("allPinnedHardRow",fixedResult.3)
        let compliantFixed=try solve([v(0),v(1)],prepared([c(0,1)],[0,0],compliance:1e-4))
        try require(compliantFixed.0==[v(0),v(1)] && compliantFixed.3.unresolvedPinnedConstraintIndices==[0] && compliantFixed.3.maximumActualGapMeters==1,
            "Compliant multiplier convergence concealed the actual all-pinned gap")
        let impossibleRows=try [c(0,1),c(0,2)]
        let impossible=try solve([v(0),v(1),v(2)],prepared(impossibleRows,[1,0,0]))
        try require(!impossible.3.allLinearSystemsConverged && impossible.0==[v(0),v(1),v(2)] && impossible.3.unconvergedConstraintIndices==[0,1],
            "Rank-deficient inconsistent pinned targets applied a misleading partial block solve")
        passed("Zero-alpha redundant PSD cycle, rank-deficient inconsistent rows and all-pinned residuals remain explicit")

        var limits=B.Limits();limits.maximumDenseBlockRows=0
        let p=(0..<20).map{v(Double($0)*0.1,sin(Double($0))*0.1,cos(Double($0))*0.1)}
        let chain=try (0..<19).map{try c($0,$0+1)}
        let cg=try solve(p,prepared(chain,Array(repeating:1,count:20),limits:limits))
        try require(cg.3.allLinearSystemsConverged && cg.3.maximumActualGapMeters<1e-9 && cg.3.matrixFreeBlockCount==1,"Forced matrix-free diagonally preconditioned CG failed")
        limits.maximumCGIterationsPerBlock=1
        let budget=try solve(p,prepared(chain,Array(repeating:1,count:20),limits:limits))
        try require(!budget.3.allLinearSystemsConverged && budget.0==p && budget.1.cartesianLambda.allSatisfy{$0 == .zero} && budget.2.allSatisfy{$0==0} && budget.3.blocks[0].failureReason=="cgIterationBudgetExceeded", "CG budget exhaustion changed state or silently claimed convergence")
        try record("cgBudgetExhausted",budget.3)
        passed("Large-block matrix-free CG converges with a sufficient budget and reports an unapplied budget-limited block")
    }
    static func covarianceAndBudgetChecks()throws{
        let rows=try [c(0,1),c(1,2),c(2,0)],p=[v(0.1,0.4,-0.2),v(0.7,-0.1,0.3),v(-0.2,0.5,0.8)]
        func rotate(_ p:V)->V{
            let axis=v(1,2,3)/sqrt(14),angle=0.73
            let dot=axis.x*p.x+axis.y*p.y+axis.z*p.z
            return p*cos(angle)+axis.cross(p)*sin(angle)+axis*(dot*(1-cos(angle)))
        }
        let q=try prepared(rows,[1,2,4]),one=try solve(p,q),rotated=try solve(p.map(rotate),q)
        try require(zip(one.0.map(rotate),rotated.0).allSatisfy{near($0,$1)} && zip(one.1.cartesianLambda.map(rotate),rotated.1.cartesianLambda).allSatisfy{near($0,$1)},"Cartesian block solve changed under a rigid frame rotation")
        passed("Cartesian positions and multipliers transform covariantly under a non-axis-aligned rotation")

        // One positive-mass component uses a very small remaining budget.
        // A second component shares only the fixed vertex; it keeps its own
        // full correction. There is no whole-document minimum scale.
        let independent=try prepared([c(0,1),c(2,1)],[1,0,1])
        var positions=[v(1),v(0),v(-1)],state=independent.makeFrameState(),travel=[0.4999,0,0]
        let stats=try B.project(positions:&positions,prepared:independent,state:&state,frameTravelMeters:&travel)
        try require(stats.blockCount==2 && abs((positions[0]-v(1)).length-0.0001)<1e-12 && abs((positions[2]-v(-1)).length-0.02)<1e-12 && positions[1]==v(0),"Independent blocks starved each other or a shared pinned vertex joined them")
        let shared=try prepared([c(0,1)],[1,4])
        var pair=[v(0),v(5)],sharedState=shared.makeFrameState(),pairTravel=[0.0,0.0]
        let capped=try B.project(positions:&pair,prepared:shared,state:&sharedState,frameTravelMeters:&pairTravel)
        try require(abs(pair[0].x-0.005)<1e-12 && abs(pair[1].x-4.98)<1e-12 && abs(sharedState.cartesianLambda[0].x-0.005)<1e-12 && capped.blocks[0].appliedScale<1,
            "A block cap scaled particle motion and Cartesian lambda inconsistently")
        try require(travel.max()!<=0.5+1e-12 && pairTravel.max()!<=0.02+1e-12,"Motion caps exceeded their original path or single-pass budget")
        pair=[v(0),v(5)];sharedState=shared.makeFrameState();pairTravel=[0.4999,0]
        _=try B.project(positions:&pair,prepared:shared,state:&sharedState,frameTravelMeters:&pairTravel)
        try require(abs(pair[0].x-0.0001)<1e-12 && abs(pair[1].x-4.9996)<1e-12 && abs(pairTravel[1]-0.0004)<1e-12,
            "One particle's remaining path budget did not scale its entire positive-mass block together")
        passed("Common per-block scale preserves signed mass ratios and lambda; independent blocks do not starve under path/single caps")
    }
    nonisolated final class Counter:@unchecked Sendable{
        let lock=NSLock();var value=0
        func cancelled()->Bool{lock.lock();defer{lock.unlock()};value+=1;return value>3}
    }
    static func cancellationAndValidationChecks()throws{
        let q=try prepared([c(0,1),c(2,1)],[1,0,1])
        var p=[v(1),v(0),v(-1)],state=q.makeFrameState(),travel=[0.0,0,0]
        let original=p,originalLambda=state.cartesianLambda,originalTravel=travel,counter=Counter()
        var cancelled=false
        do{_=try B.project(positions:&p,prepared:q,state:&state,frameTravelMeters:&travel,isCancelled:{counter.cancelled()})}catch is CancellationError{cancelled=true}
        try require(cancelled && p==original && state.cartesianLambda==originalLambda && travel==originalTravel,"Cancellation after a tentative earlier block leaked positions/lambda/travel")
        func rejection(_ prepared:B.Prepared,_ ramp:Double=1)throws{
            var rejected=false
            do{_=try B.project(positions:&p,prepared:prepared,state:&state,frameTravelMeters:&travel,rampFraction:ramp)}catch B.BlockError.invalid{rejected=true}
            try require(rejected && p==original && state.cartesianLambda==originalLambda && travel==originalTravel,"Invalid frame/input was accepted or changed state")
        }
        try rejection(q,0.999);try rejection(prepared([c(0,1),c(2,1)],[1,0,1]))
        var badMass=false
        do{_=try prepared([c(0,1)],[1,.nan])}catch B.BlockError.invalid{badMass=true}
        try require(badMass,"Invalid source inverse mass was accepted")
        var badIndex=false
        do{_=try prepared([c(0,4)],[1,1])}catch B.BlockError.invalid{badIndex=true}
        try require(badIndex,"Out-of-bounds attachment index was accepted")
        var limited=B.Limits();limited.maximumConstraints=1
        var budget=false
        do{_=try prepared([c(0,1),c(1,2)],[1,1,1],limits:limited)}catch B.BlockError.budgetExceeded{budget=true}
        try require(budget,"Oversize source constraint input silently truncated a component")
        var prepareCancelled=false
        do{_=try B.Prepared(vertexCount:2,constraints:[c(0,1)],normalizedInverseMass:[1,1],physicalCompliance:0,meanParticleMassKg:0.001,timeStepSeconds:1.0/120,isCancelled:{true})}catch is CancellationError{prepareCancelled=true}
        try require(prepareCancelled,"Preparation ignored immediate cancellation")
        passed("Preparation/input refusal and mid-projection cancellation publish no positions, multipliers or path-state changes")
    }

    /// Independent pivoted Gaussian elimination, rather than the production
    /// Cholesky/PCG implementations, checks the actual 69-row source plan.
    static func oracle(_ p:[V],constraints:[S.Constraint],weights:[Double],alpha:Double)throws->[V]{
        let n=constraints.count
        var rows:[[Int:Double]]=[]
        for c in constraints {
            var row:[Int:Double]=[:]
            for (id,w) in zip(c.a.vertexIDs,c.a.weights){row[id,default:0]+=w}
            for (id,w) in zip(c.b.vertexIDs,c.b.weights){row[id,default:0]-=w}
            rows.append(row)
        }
        var matrix=Array(repeating:Array(repeating:0.0,count:n),count:n)
        var rhs=rows.map{row in row.keys.sorted().reduce(V.zero){$0-p[$1]*row[$1]!}}
        for i in 0..<n {for j in 0..<n {
            matrix[i][j]=rows[i].keys.sorted().reduce(0.0){$0+weights[$1]*rows[i][$1]!*(rows[j][$1] ?? 0)}+(i==j ? alpha:0)
        }}
        for i in 0..<n {
            let pivot=(i..<n).max{abs(matrix[$0][i])<abs(matrix[$1][i])}!
            try require(abs(matrix[pivot][i])>1e-20,"Independent real-plan oracle is singular")
            if pivot != i {matrix.swapAt(i,pivot);rhs.swapAt(i,pivot)}
            for j in (i+1)..<n {
                let ratio=matrix[j][i]/matrix[i][i]
                for k in i..<n {matrix[j][k]-=ratio*matrix[i][k]}
                rhs[j]=rhs[j]-rhs[i]*ratio
            }
        }
        var delta=Array(repeating:V.zero,count:n)
        for i in (0..<n).reversed(){var value=rhs[i];for j in (i+1)..<n{value=value-delta[j]*matrix[i][j]};delta[i]=value/matrix[i][i]}
        var result=p
        for (row,d) in zip(rows,delta){for id in row.keys.sorted(){result[id]=result[id]+d*(weights[id]*row[id]!)}}
        return result
    }
    struct Reference:Decodable {
        let positions:[V],triangleIndices:[UInt32],pinned:[Bool],sourceToSimulation:[Int]
    }
    static func realPlanCheck()throws->Bool{
        guard let path=ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_POINT_BLOCK_FIXTURE"] else {
            print("SKIP optional real Integrated3 fixture: no supplied directory");return false
        }
        let directory=URL(fileURLWithPath:path),decoder=JSONDecoder()
        let planData=try Data(contentsOf:directory.appendingPathComponent("straight-default-plan.json"))
        let plan=try decoder.decode(S.Plan.self,from:planData)
        let ref=try decoder.decode(Reference.self,from:Data(contentsOf:directory.appendingPathComponent("straight-default-reference.json")))
        // The persisted numerical fixture keeps the exact original cloth
        // positions. Rendering-only body arrays are unnecessary for this
        // linear projection oracle and are deliberately not required.
        struct PositionSnapshot:Decodable {let positions:[V]}
        let output=try decoder.decode(PositionSnapshot.self,from:Data(contentsOf:directory.appendingPathComponent("straight-default-mesh.json")))
        let masses=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:ref.positions.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:ref.triangleIndices,
            referenceToSimulation:ref.sourceToSimulation,simulationVertexCount:output.positions.count,arealDensity:0.18)
        let weights=masses.normalizedInverseMasses.enumerated().map{ref.pinned[$0.offset] ? 0:$0.element}
        let q=try B.Prepared(vertexCount:output.positions.count,constraints:plan.constraints,normalizedInverseMass:weights,
            physicalCompliance:1e-8,meanParticleMassKg:masses.meanMassKg,timeStepSeconds:1.0/240)
        let result=try solve(output.positions,q,frame:0.5,single:0.02)
        let expected=try oracle(output.positions,constraints:plan.constraints,weights:weights,alpha:q.alpha)
        let deviation=zip(result.0,expected).map{($0-$1).length}.max()!
        let before=try S.inspect(positions:output.positions,constraints:plan.constraints)
        let after=try S.inspect(positions:result.0,constraints:plan.constraints)
        try require(plan.constraints.count==69 && result.3.allLinearSystemsConverged && after.maximumGapMeters<1e-7 && deviation<1e-8,
            "Actual Integrated3 plan disagrees with an independent simultaneous solve")
        try require(result.0.indices.allSatisfy{!ref.pinned[$0] || result.0[$0]==output.positions[$0]} && result.3.maximumAppliedCorrectionMeters<=0.02+1e-12,
            "Actual plan moved a fixed source point or exceeded its original motion cap")
        let planAfter=try Data(contentsOf:directory.appendingPathComponent("straight-default-plan.json"))
        try require(planData==planAfter,"Actual source plan fixture was rewritten")
        metrics["realPlanConstraintCount"]=Double(plan.constraints.count)
        metrics["realGapBeforeMeters"]=before.maximumGapMeters;metrics["realGapAfterMeters"]=after.maximumGapMeters
        metrics["realIndependentOracleMaximumPositionDifferenceMeters"]=deviation
        metrics["realAlpha"]=q.alpha
        try record("actualIntegrated3Plan",result.3)
        passed("Actual 69-row Integrated3 plan uses unchanged source masses/pins and matches independent pivoted Gaussian elimination")
        return true
    }
    static func main()throws{
        try analyticalChecks();try rankAndCGChecks();try covarianceAndBudgetChecks();try cancellationAndValidationChecks()
        let real=try realPlanCheck()
        let summary:[String:Any]=["kind":"final_point_coincidence_cartesian_block_regression","passed":true,
            "checks":checks,"metrics":metrics,"caseStatistics":caseStatistics,"realIntegrated3FixtureVerified":real,
            "fullPhysicsAcceptanceClaimed":false,"originalScalarDefaultModified":false]
        if let path=ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_POINT_BLOCK_OUTPUT"]{
            try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("sewn-point-block-summary.json"))
        }
        print("PASS point-coincidence block foundation; no full-physics or App acceptance claim")
    }
}
