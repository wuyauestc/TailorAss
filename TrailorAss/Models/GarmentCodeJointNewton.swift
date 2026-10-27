import Foundation
import NativeClothCollision

/// Serial nonlinear objective solve. A converged mathematical subproblem is
/// not a garment: the caller still owns gravity/time integration, self force,
/// exterior bootstrap and the full final quality checks before showing output.
nonisolated enum GarmentCodeJointNewton {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias P=GarmentCodeJointPreconditioner
    typealias CP=GarmentCodeJointContactPreconditioner
    protocol EvaluationValue:Sendable {
        var energyJoules:Double {get}
        var gradientNewton:[V] {get}
    }
    protocol DeltaValue:Sendable {var energyJoules:Double {get}}
    protocol FrameOperator:Sendable {
        associatedtype Evaluation:EvaluationValue
        associatedtype Delta:DeltaValue
        var cloth:GarmentCodeJointObjective.Frame {get}
        func evaluate(positions:[V],isCancelled:@escaping @Sendable()->Bool)throws->Evaluation
        func hessianProduct(at:Evaluation,direction:[V],isCancelled:@escaping @Sendable()->Bool)throws->[V]
        func energyDelta(from:Evaluation,to:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->Delta
        func preconditionerBlocks(at:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->[CP.Block]
    }
    struct Limits:Sendable {
        // The complete sleeved source's assembly step 164 needs 71 iterations
        // with the original force, correction and path checks. Keep a bounded
        // work allowance; this does not relax any acceptance criterion.
        var maximumNewtonIterations=96
        var maximumCGIterations=400
        var maximumBacktracks=32
        var sourcePath=GarmentCodeMembranePath.Limits()
    }
    enum Status:String,Codable,Sendable {case converged,newtonBudget,lineSearchFailed,nonDescent,precisionUnresolved}
    enum TrajectoryMode:String,Codable,Sendable {
        /// One physical time step has the previous->final linear trajectory.
        case physicalLinearStep
        /// Quasi-static assembly follows every accepted optimization segment.
        /// No gravity/time trajectory may silently select this mode.
        case configurationPolyline
    }
    enum LinearReason:String,Codable,Sendable {case converged,budget,trustBoundary,nonpositiveCurvature,preconditionedGradient,representableCoordinate,representableCoupledCoordinates}
    enum DirectionKind:String,Codable,Sendable {
        case conjugateGradient,preconditionedGradientForNonDescent,preconditionedGradientAfterLineSearch,representableCoordinate,representableCoupledCoordinates
    }
    enum SolverError:LocalizedError,Sendable {
        case invalid,invalidPreconditioner,nonfinite
        var errorDescription:String? {
            switch self {
            case .invalid:return "联立求解的输入或工作预算无效。"
            case .invalidPreconditioner:return "联立求解的预条件器不是有限正定的当前状态。"
            case .nonfinite:return "联立求解产生了无法表示的方向或导数。"
            }
        }
    }
    struct LinearReport:Codable,Sendable {
        let iterations:Int
        let trueRelativeResidual:Double
        let converged:Bool
        let reason:LinearReason
    }
    struct Iteration:Codable,Sendable {
        let index:Int,backtracks:Int
        let alpha:Double,energyDeltaEstimateJoules:Double,armijoIncrementJoules:Double
        let gradientInfinityNewton:Double
        let linear:LinearReport
        let sourcePath:GarmentCodeMembranePath.Report
        /// Explicit local numerical line proof. Optional only for decoding
        /// historical reports that relied on the conservative Weyl proposal.
        let localSourcePath:GarmentCodeMembranePath.Report?
        let preconditioner:CP.Report?
        /// Optional only to decode historical traces. New records identify the
        /// accepted direction; a P direction is never labelled converged CG.
        let directionKind:DirectionKind?
        let precedingCG:LinearReport?
        let precedingP:LinearReport?
    }
    struct CoordinateSearch:Codable,Sendable {
        let iteration:Int,preselectedCandidates:Int,evaluatedCandidates:Int,preconditionerProducts:Int
        let trigger:String
        let termination:String?
        let currentPInfinityMeters:Double,maximumCoordinateSpacingMeters:Double
        let acceptedDOF:Int?,acceptedProposalRank:Int?
        /// Existing certified candidate used for an energy comparison only.
        /// Nil for the original failed-CG/failed-P fallback.
        let normalCandidateEnergyDeltaJoules:Double?
        let normalCandidateDirectionKind:DirectionKind?
        let unresolvedCandidateEvaluations:Int?
        /// Bounded eligible force-threshold coverage inside the SAME64 slots.
        /// Nil only for historical reports before this selection rule.
        var forceResidualPriorityCandidates:Int?=nil
        /// Current-P diagonal lookups replace full basis-vector P products.
        /// Optional for historical traces before direct diagonal access.
        var preconditionerDiagonalQueries:Int?=nil
        /// Proposal construction only; separate from CG and residual products.
        var coupledHessianBasisProducts:Int?=nil
        var coupledPreselectedCandidates:Int?=nil
        var coupledGeneratedCandidates:Int?=nil
        var coupledTargetDOF:Int?=nil
        var coupledChargedTemporaryBytes:Int?=nil
        var coupledBudgetLimited:Bool?=nil
        var acceptedDOFs:[Int]?=nil
    }
    struct Report:Codable,Sendable {
        let status:Status
        let trajectoryMode:TrajectoryMode
        let initialGradientInfinityNewton:Double
        let finalGradientInfinityNewton:Double
        let finalGradientRelativeToInitial:Double
        /// Scale-aware numerical correction, not a certified position error.
        let finalPreconditionedGradientInfinityMeters:Double?
        let finalPreconditionerRelativeResidual:Double?
        let stoppingCriterion:String
        let history:[Iteration]
        let failureDetail:String?
        /// Optional only for historical reports. This is a bounded numerical
        /// proposal search, never a feasibility or convergence certificate.
        let coordinateSearches:[CoordinateSearch]?
        /// KKT only; the caller cannot infer complete physical acceptance.
        var converged:Bool {status == .converged}
    }
    struct Result<E:EvaluationValue>:Sendable {
        let positions:[V]
        let evaluation:E
        let report:Report
        let lastRejectedCandidate:[V]?
        let acceptedTrajectory:[AcceptedSegment]
    }
    struct AcceptedSegment:Sendable {
        let previous:[V],accepted:[V]
        let sourceMotion:GarmentCodeMembranePath.Report
        fileprivate init(previous:[V],accepted:[V],sourceMotion:GarmentCodeMembranePath.Report) {
            self.previous=previous;self.accepted=accepted;self.sourceMotion=sourceMotion
        }
    }
    struct CoordinatePool:Sendable {
        let proposals:[CoordinateProposal]
        let forceResidualPriorityCandidates:Int
        let forceResidualPriorityDOFs:[Int]
    }
    /// A work trigger, never an acceptance condition. A tiny certified normal
    /// move can leave EVERY force-violating coordinate unchanged even when a
    /// different low-force coordinate makes the global current-P radius large.
    /// Only exact unchanged violating coordinates and no actual force-norm
    /// improvement qualify; all energy/path/KKT gates are still required.
    static func roundedForceStall(positions:[V],gradient:[V],candidate:[V],candidateGradient:[V])->Bool {
        guard positions.count==gradient.count,positions.count==candidate.count,
              positions.count==candidateGradient.count,!positions.isEmpty,
              positions.allSatisfy(\.isFinite),candidate.allSatisfy(\.isFinite),
              gradient.allSatisfy(\.isFinite),candidateGradient.allSatisfy(\.isFinite),
              infinity(gradient)>=1e-6,infinity(candidateGradient)>=infinity(gradient) else{return false}
        var violating=false
        for i in positions.indices {
            let a=positions[i],b=candidate[i],g=gradient[i]
            for (x,y,f) in [(a.x,b.x,g.x),(a.y,b.y,g.y),(a.z,b.z,g.z)] where abs(f)>=1e-6 {
                violating=true
                if x.bitPattern != y.bitPattern{return false}
            }
        }
        return violating
    }
    /// Candidate selection only. Up to16 of the existing64 slots cover the
    /// largest ELIGIBLE components that violate the unchanged force criterion.
    /// The rest retain actual single-ULP work ordering. No surrogate score,
    /// priority or force value authorizes an energy/path/KKT acceptance.
    static func coordinateProposalPool(positions:[V],gradient:[V],travel:[Double],
        isCancelled:@Sendable()->Bool={false})throws->CoordinatePool {
        guard positions.count==gradient.count,positions.count==travel.count,
              travel.allSatisfy({$0.isFinite && $0>=0}),positions.allSatisfy(\.isFinite),gradient.allSatisfy(\.isFinite) else {
            throw SolverError.invalid
        }
        if isCancelled(){throw CancellationError()}
        func force(_ p:CoordinateProposal)->Double {
            let v=gradient[p.vertex];return abs([v.x,v.y,v.z][p.axis])
        }
        func betterForce(_ a:CoordinateProposal,_ b:CoordinateProposal)->Bool {
            let x=force(a),y=force(b);return x==y ? a.dof<b.dof:x>y
        }
        func betterWork(_ a:CoordinateProposal,_ b:CoordinateProposal)->Bool {
            a.slope==b.slope ? a.dof<b.dof:a.slope<b.slope
        }
        func proposal(_ vertex:Int,_ axis:Int)throws->CoordinateProposal? {
            let point=positions[vertex],f=gradient[vertex],value=[point.x,point.y,point.z][axis],g=[f.x,f.y,f.z][axis]
            if g==0{return nil}
            let next=g>0 ? value.nextDown:value.nextUp,delta=next-value,slope=g*delta
            guard next.isFinite,delta.isFinite,slope.isFinite else{throw SolverError.nonfinite}
            guard delta != 0,slope<0,abs(delta)<=0.02,abs(delta)<=max(0,0.5-travel[vertex]) else{return nil}
            return .init(dof:3*vertex+axis,vertex:vertex,axis:axis,value:next,delta:delta,slope:slope)
        }
        func insert(_ p:CoordinateProposal,_ pool:inout [CoordinateProposal],_ limit:Int,
                    _ better:(CoordinateProposal,CoordinateProposal)->Bool) {
            guard limit>0 else{return}
            if pool.count==limit && !better(p,pool.last!){return}
            var low=0,high=pool.count
            while low<high {let m=(low+high)/2;if better(p,pool[m]){high=m}else{low=m+1}}
            pool.insert(p,at:low);if pool.count>limit {pool.removeLast()}
        }
        var priority:[CoordinateProposal]=[]
        for vertex in positions.indices {
            if vertex%128==0 && isCancelled(){throw CancellationError()}
            let f=gradient[vertex]
            for axis in 0..<3 where abs([f.x,f.y,f.z][axis])>=1e-6 {
                if let p=try proposal(vertex,axis){insert(p,&priority,16,betterForce)}
            }
        }
        var work:[CoordinateProposal]=[]
        let remaining=64-priority.count
        for vertex in positions.indices {
            if vertex%128==0 && isCancelled(){throw CancellationError()}
            for axis in 0..<3 {
                if priority.contains(where:{$0.dof==3*vertex+axis}){continue}
                if let p=try proposal(vertex,axis){insert(p,&work,remaining,betterWork)}
            }
        }
        // Retain the previous product order whenever the force-covered DOFs
        // were already in the old pool. The true P score is computed later.
        let result=(priority+work).sorted(by:betterWork)
        if isCancelled(){throw CancellationError()}
        return .init(proposals:result,forceResidualPriorityCandidates:priority.count,forceResidualPriorityDOFs:priority.map(\.dof))
    }
    private struct CG {let vector:[V],report:LinearReport}
    struct CoordinateProposal:Sendable {
        let dof:Int,vertex:Int,axis:Int,value:Double,delta:Double,slope:Double
        var score=0.0
    }

    /// Initial positions are the previously accepted state. Static assembly
    /// follows its recorded configuration segments; physical mode also checks
    /// the whole previous->candidate time step. Unconfirmed motion is rejected.
    static func solve<F:FrameOperator>(frame:F,initialPositions:[V],preconditioner:P.Workspace,
        limits:Limits=Limits(),trajectoryMode:TrajectoryMode = .physicalLinearStep,
        pathGuard:(_ previous:[V],_ candidate:[V])throws->Bool,
        isCancelled:@escaping @Sendable()->Bool={false})throws->Result<F.Evaluation> {
        guard (1...96).contains(limits.maximumNewtonIterations),(1...400).contains(limits.maximumCGIterations),
              (1...32).contains(limits.maximumBacktracks),initialPositions.count==frame.cloth.prepared.massesKg.count else {throw SolverError.invalid}
        if isCancelled(){throw CancellationError()}
        let factor=CP.Workspace(base:preconditioner)
        let sourcePath=try GarmentCodeMembranePath.Prepared(membrane:frame.cloth.prepared.membrane,limits:limits.sourcePath)
        func checked(_ e:F.Evaluation)throws->F.Evaluation {
            guard e.energyJoules.isFinite,e.gradientNewton.count==initialPositions.count,e.gradientNewton.allSatisfy(\.isFinite) else {
                throw SolverError.nonfinite
            };return e
        }
        var x=initialPositions,e=try checked(frame.evaluate(positions:initialPositions,isCancelled:isCancelled))
        let g0=infinity(e.gradientNewton)
        var history:[Iteration]=[],travel=Array(repeating:0.0,count:x.count),rejected:[V]?,scaledGradient:Double?,scaledSolveResidual:Double?
        var trajectory:[AcceptedSegment]=[]
        var coordinateSearches:[CoordinateSearch]=[]
        func result(_ status:Status,_ detail:String?=nil)->Result<F.Evaluation> {
            let gradient=infinity(e.gradientNewton)
            return .init(positions:x,evaluation:e,report:.init(status:status,trajectoryMode:trajectoryMode,initialGradientInfinityNewton:g0,
                finalGradientInfinityNewton:gradient,finalGradientRelativeToInitial:relative(gradient,g0),
                finalPreconditionedGradientInfinityMeters:scaledGradient,finalPreconditionerRelativeResidual:scaledSolveResidual,
                stoppingCriterion:"forceBelow1e-6N_and_currentPCorrectionBelow1e-7m_with_relativePzResidualBelow1e-6",
                history:history,failureDetail:detail,coordinateSearches:coordinateSearches),lastRejectedCandidate:rejected,acceptedTrajectory:trajectory)
        }
        for iteration in 0...limits.maximumNewtonIterations {
            if isCancelled(){throw CancellationError()}
            let g=infinity(e.gradientNewton)
            if g==0 {scaledGradient=0;scaledSolveResidual=0;return result(.converged)}
            if iteration==limits.maximumNewtonIterations && g>=1e-6 {return result(.newtonBudget)}
            let blocks=try frame.preconditionerBlocks(at:e,isCancelled:isCancelled)
            let generation=try factor.update(frame:frame.cloth,positions:x,blocks:blocks,isCancelled:isCancelled)
            // A relative-to-initial force condition becomes meaningless under
            // soft loading: the real .001 N control stalled at 1.41e-13 N.
            // Keep the original absolute force bound, and also require a
            // small actual current-P correction before accepting stationarity.
            // Relative reduction remains in the report for convergence studies.
            if g<1e-6 {
                let correction=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:generation,isCancelled:isCancelled)
                scaledGradient=infinity(correction)
                scaledSolveResidual=factor.latestSolveRelativeResidual
                if scaledGradient!<1e-7,let residual=scaledSolveResidual,residual.isFinite,residual<1e-6 {return result(.converged)}
            } else {scaledGradient=nil;scaledSolveResidual=nil}
            if iteration==limits.maximumNewtonIterations {return result(.newtonBudget)}
            let cg=try conjugateGradient(frame:frame,at:e,workspace:factor,generation:generation,
                maximumIterations:limits.maximumCGIterations,isCancelled:isCancelled)
            var p=cg.vector,slope=dot(e.gradientNewton,p)
            var directionKind=DirectionKind.conjugateGradient,linear=cg.report
            func gradientDirectionReport(_ direction:[V])throws->LinearReport {
                let hp=try frame.hessianProduct(at:e,direction:direction,isCancelled:isCancelled)
                guard hp.count==e.gradientNewton.count,hp.allSatisfy(\.isFinite) else {throw SolverError.nonfinite}
                let residual=norm(zip(hp,e.gradientNewton).map{$0+$1})/max(norm(e.gradientNewton),Double.leastNormalMagnitude)
                guard residual.isFinite else {throw SolverError.nonfinite}
                return .init(iterations:0,trueRelativeResidual:residual,converged:false,reason:.preconditionedGradient)
            }
            if !slope.isFinite || slope>=0 {
                p=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:generation,isCancelled:isCancelled)
                slope=dot(e.gradientNewton,p)
                directionKind = .preconditionedGradientForNonDescent
                linear=try gradientDirectionReport(p)
            }
            guard slope.isFinite else {throw SolverError.nonfinite}
            if slope>=0 {return result(.nonDescent)}
            // Weyl/Frobenius bounds are sufficient but can reduce a nearly
            // isometric move to tiny steps near a stretch limit. Propose the
            // bounded full step and certify its actual source path below.
            // This changes the proposal, never the domain or acceptance gates.
            var accepted=false
            var pending:(positions:[V],evaluation:F.Evaluation,iteration:Iteration)?
            var pendingP:[V]?
            var pendingForceStall=false
            func coordinateSpacing()throws->Double {
                var spacing=0.0
                for i in x.indices {
                    if i%128==0 && isCancelled(){throw CancellationError()}
                    for value in [x[i].x,x[i].y,x[i].z] {
                        let up=value.nextUp-value,down=value-value.nextDown
                        guard up.isFinite,down.isFinite,up>0,down>0 else {throw SolverError.nonfinite}
                        spacing=max(spacing,up,down)
                    }
                }
                return spacing
            }
            func commit(_ positions:[V],_ evaluation:F.Evaluation,_ record:Iteration) {
                for i in x.indices {travel[i]+=(positions[i]-x[i]).length}
                history.append(record)
                if trajectoryMode == .configurationPolyline {trajectory.append(.init(previous:x,accepted:positions,sourceMotion:record.sourcePath))}
                x=positions;e=evaluation;scaledGradient=nil;scaledSolveResidual=nil;rejected=nil;accepted=true
            }
            var searchedCG=false,searchedPostP=false,sawRoundedNoOp=false
            // At most two directions, each with the original bounded search.
            // A descent CG direction can still fail every actual rounded
            // candidate. Then try the current SPD P-gradient, retaining the
            // exact same objective, Armijo, source and collision gates.
            for directionAttempt in 0..<2 {
                if isCancelled(){throw CancellationError()}
                if directionAttempt==1 {
                    // The existing non-descent fallback already tried P.
                    // Repeating that identical direction would add no option.
                    if directionKind != .conjugateGradient {break}
                    p=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:generation,isCancelled:isCancelled)
                    slope=dot(e.gradientNewton,p)
                    guard slope.isFinite else {throw SolverError.nonfinite}
                    if slope>=0 {break}
                    directionKind = .preconditionedGradientAfterLineSearch
                    linear=try gradientDirectionReport(p)
                }
                var alpha=1.0
                if directionKind == .conjugateGradient {searchedCG=true}
                if directionKind == .preconditionedGradientAfterLineSearch {searchedPostP=true}
                for i in p.indices where p[i].length>0 {
                    alpha=min(alpha,0.02/p[i].length,max(0,0.5-travel[i])/p[i].length)
                }
                for backtrack in 0..<limits.maximumBacktracks {
                    if isCancelled(){throw CancellationError()}
                    if alpha<=Double.ulpOfOne {break}
                    let trial=zip(x,p).map{$0+$1*alpha};rejected=trial
                    // A rounded no-op is not an accepted optimization segment,
                    // even if a scalar product/Armijo bound underflows to zero.
                    if trial==x {sawRoundedNoOp=true;alpha *= 0.5;continue}
                    let te:F.Evaluation
                    do {te=try checked(frame.evaluate(positions:trial,isCancelled:isCancelled))}
                    catch {
                        if domainRejection(error){alpha *= 0.5;continue}
                        throw error
                    }
                    let delta:Double
                    do {delta=try frame.energyDelta(from:e,to:te,isCancelled:isCancelled).energyJoules}
                    catch GarmentCodeElasticEnergyDelta.DeltaError.precisionUnresolved {return result(.precisionUnresolved,"elasticEnergyDeltaUnresolved")}
                    guard delta.isFinite else {throw SolverError.nonfinite}
                    let armijo=1e-4*alpha*slope
                    if delta<0 && armijo<0 && delta<=armijo {
                        let localSource=try sourcePath.certify(from:x,to:trial,barrier:frame.cloth.prepared.strainBarrier,isCancelled:isCancelled)
                        var source=localSource
                        if localSource.status == .clear && localSource.completedAllTriangles &&
                            trajectoryMode == .physicalLinearStep && x != initialPositions {
                            source=try sourcePath.certify(from:initialPositions,to:trial,barrier:frame.cloth.prepared.strainBarrier,isCancelled:isCancelled)
                        }
                        if localSource.status == .clear && localSource.completedAllTriangles && source.status == .clear && source.completedAllTriangles {
                            let localClear=try pathGuard(x,trial)
                            var wholeClear=localClear
                            if localClear && trajectoryMode == .physicalLinearStep && x != initialPositions {
                                wholeClear=try pathGuard(initialPositions,trial)
                            }
                            if localClear && wholeClear {
                                let record=Iteration(index:iteration+1,backtracks:backtrack,alpha:alpha,energyDeltaEstimateJoules:delta,
                                    armijoIncrementJoules:armijo,gradientInfinityNewton:infinity(te.gradientNewton),linear:linear,
                                    sourcePath:source,localSourcePath:localSource,preconditioner:factor.report,
                                    directionKind:directionKind,precedingCG:directionKind == .conjugateGradient ? nil:cg.report,precedingP:nil)
                                let spacing=try coordinateSpacing(),actual=zip(trial,x).map{$0-$1}
                                // Near representational resolution a backtracked vector can
                                // move only low-impact coordinates while its stiff components
                                // round away. Keep this already-certified step, and compare
                                // it with the same bounded coordinate proposals below.
                                if infinity(actual)<=32*spacing {
                                    let correction=try factor.solve(rhs:e.gradientNewton.map{$0 * -1},generation:generation,isCancelled:isCancelled)
                                    let stalled=roundedForceStall(positions:x,gradient:e.gradientNewton,candidate:trial,candidateGradient:te.gradientNewton)
                                    if infinity(correction)<=32*spacing || stalled {
                                        pendingForceStall=stalled
                                        pending=(trial,te,record);pendingP=correction;break
                                    }
                                }
                                commit(trial,te,record);break
                            }
                        }
                    }
                    alpha *= 0.5
                }
                if accepted || pending != nil {break}
            }
            if pending != nil || (!accepted && searchedCG && searchedPostP && sawRoundedNoOp) {
                let spacing=try coordinateSpacing(),coordinateP=pendingP ?? p
                let numericalRadius=32*spacing,pInfinity=infinity(coordinateP)
                let trigger=pendingForceStall ? "certified_normal_within_32_spacings_leaves_every_violating_force_DOF_unchanged_and_force_norm_not_improved"
                    : (pending == nil ? "CG_and_P_search_failed_with_rounded_noop_and_P_within_32_max_coordinate_spacings"
                    : "certified_normal_step_and_current_P_within_32_max_coordinate_spacings")
                let precedingP=pending == nil ? linear : try gradientDirectionReport(coordinateP)
                guard numericalRadius.isFinite,pInfinity.isFinite else {throw SolverError.nonfinite}
                // This scale test controls extra numerical work only. It
                // changes neither an energy/path gate nor the KKT precision.
                if pInfinity<=numericalRadius || pendingForceStall {
                    let pool=try coordinateProposalPool(positions:x,gradient:e.gradientNewton,travel:travel,isCancelled:isCancelled)
                    var proposals=pool.proposals
                    let forcePriorityCount=pool.forceResidualPriorityCandidates
                    // The bounded pool covers force violations plus actual ULP work,
                    // then is ordered by a current-P scalar Taylor prediction.
                    // This score is never substituted for the real objective.
                    for i in proposals.indices {
                        if isCancelled(){throw CancellationError()}
                        let diagonal=try factor.diagonal(at:proposals[i].dof,generation:generation)
                        guard diagonal.isFinite,diagonal>0 else {throw SolverError.invalidPreconditioner}
                        let delta=proposals[i].delta
                        proposals[i].score=proposals[i].slope+0.5*diagonal*delta*delta
                        guard proposals[i].score.isFinite else {throw SolverError.nonfinite}
                    }
                    proposals.sort{$0.score==$1.score ? $0.dof<$1.dof:$0.score<$1.score}
                    let coupled=try GarmentCodeCoupledCoordinateProposals.build(positions:x,gradient:e.gradientNewton,travel:travel,
                        hessianColumn:{ dof in
                            var unit=Array(repeating:V.zero,count:x.count),components=[0.0,0.0,0.0]
                            components[dof%3]=1
                            unit[dof/3] = V(x:components[0],y:components[1],z:components[2])
                            return try frame.hessianProduct(at:e,direction:unit,isCancelled:isCancelled)
                        },isCancelled:isCancelled)
                    // Coupled proposals share the SAME64 actual evaluations.
                    // Keep every force-priority single; fill the remaining
                    // single slots using the original current-P ordering.
                    let priority=Set(pool.forceResidualPriorityDOFs),singleLimit=64-coupled.proposals.count
                    let singleIDs=priority.union(proposals.filter{!priority.contains($0.dof)}.prefix(singleLimit-priority.count).map(\.dof))
                    let singles=proposals.filter{singleIDs.contains($0.dof)}
                    let candidates:[(target:Int,changes:[GarmentCodeCoupledCoordinateProposals.Change],coupled:Bool)] =
                        coupled.proposals.map{($0.targetDOF,$0.changes,true)} + singles.map{($0.dof,[.init(dof:$0.dof,value:$0.value,delta:$0.delta)],false)}
                    var evaluated=0,unresolved=0,acceptedDOF:Int?,acceptedRank:Int?,acceptedDOFs:[Int]?
                    func searchRecord(_ termination:String)->CoordinateSearch {
                        .init(iteration:iteration+1,preselectedCandidates:candidates.count,evaluatedCandidates:evaluated,
                            preconditionerProducts:0,trigger:trigger,termination:termination,
                            currentPInfinityMeters:pInfinity,maximumCoordinateSpacingMeters:spacing,
                            acceptedDOF:acceptedDOF,acceptedProposalRank:acceptedRank,
                            normalCandidateEnergyDeltaJoules:pending?.iteration.energyDeltaEstimateJoules,
                            normalCandidateDirectionKind:pending?.iteration.directionKind,unresolvedCandidateEvaluations:unresolved,
                            forceResidualPriorityCandidates:forcePriorityCount,preconditionerDiagonalQueries:proposals.count,
                            coupledHessianBasisProducts:coupled.statistics.rawBasisProducts,
                            coupledPreselectedCandidates:coupled.proposals.count,coupledGeneratedCandidates:coupled.statistics.generatedCandidates,
                            coupledTargetDOF:coupled.statistics.targetDOF,coupledChargedTemporaryBytes:coupled.statistics.chargedTemporaryBytes,
                            coupledBudgetLimited:coupled.statistics.budgetLimited,acceptedDOFs:acceptedDOFs)
                    }
                    for (rank,proposal) in candidates.enumerated() {
                        if isCancelled(){throw CancellationError()}
                        var trial=x
                        for change in proposal.changes {
                            let vertex=change.dof/3,axis=change.dof%3
                            var values=[trial[vertex].x,trial[vertex].y,trial[vertex].z];values[axis]=change.value
                            trial[vertex]=V(x:values[0],y:values[1],z:values[2])
                        }
                        rejected=trial
                        let actual=zip(trial,x).map{$0-$1}
                        let slope=dot(e.gradientNewton,actual)
                        guard slope.isFinite,actual.allSatisfy(\.isFinite) else {throw SolverError.nonfinite}
                        guard trial != x,slope<0 else {continue}
                        evaluated+=1
                        let te:F.Evaluation
                        do {te=try checked(frame.evaluate(positions:trial,isCancelled:isCancelled))}
                        catch {if domainRejection(error){continue};throw error}
                        let delta:Double
                        do {delta=try frame.energyDelta(from:e,to:te,isCancelled:isCancelled).energyJoules}
                        catch GarmentCodeElasticEnergyDelta.DeltaError.precisionUnresolved {
                            unresolved+=1
                            // Unknown alternatives are discarded. A separately
                            // certified normal candidate is still safe to retain;
                            // report this as one search, not repeated 64-product runs.
                            if pending != nil {continue}
                            coordinateSearches.append(searchRecord("precisionUnresolved"))
                            return result(.precisionUnresolved,"elasticEnergyDeltaUnresolved")
                        }
                        guard delta.isFinite else {throw SolverError.nonfinite}
                        let armijo=1e-4*slope
                        guard delta<0,armijo<0,delta<=armijo else {continue}
                        // A comparison candidate must beat the already certified
                        // normal step using the same actual stable delta estimator.
                        if let pending,delta>=pending.iteration.energyDeltaEstimateJoules {continue}
                        let localSource=try sourcePath.certify(from:x,to:trial,barrier:frame.cloth.prepared.strainBarrier,isCancelled:isCancelled)
                        var source=localSource
                        if localSource.status == .clear && localSource.completedAllTriangles && trajectoryMode == .physicalLinearStep && x != initialPositions {
                            source=try sourcePath.certify(from:initialPositions,to:trial,barrier:frame.cloth.prepared.strainBarrier,isCancelled:isCancelled)
                        }
                        guard localSource.status == .clear,localSource.completedAllTriangles,source.status == .clear,source.completedAllTriangles else {continue}
                        let localClear=try pathGuard(x,trial)
                        var wholeClear=localClear
                        if localClear && trajectoryMode == .physicalLinearStep && x != initialPositions {wholeClear=try pathGuard(initialPositions,trial)}
                        guard localClear,wholeClear else {continue}
                        let actualLinear=try gradientDirectionReport(actual)
                        let coordinateLinear=LinearReport(iterations:0,trueRelativeResidual:actualLinear.trueRelativeResidual,
                            converged:false,reason:proposal.coupled ? .representableCoupledCoordinates:.representableCoordinate)
                        if isCancelled(){throw CancellationError()}
                        commit(trial,te,.init(index:iteration+1,backtracks:0,alpha:1,energyDeltaEstimateJoules:delta,
                            armijoIncrementJoules:armijo,gradientInfinityNewton:infinity(te.gradientNewton),linear:coordinateLinear,
                            sourcePath:source,localSourcePath:localSource,preconditioner:factor.report,
                            directionKind:proposal.coupled ? .representableCoupledCoordinates:.representableCoordinate,precedingCG:cg.report,precedingP:precedingP))
                        acceptedDOF=proposal.target;acceptedRank=rank+1;acceptedDOFs=proposal.changes.map(\.dof);break
                    }
                    coordinateSearches.append(searchRecord(accepted ? "accepted":(pending == nil ? "candidatesExhausted":"normalCandidateRetained")))
                }
            }
            if !accepted,let pending {
                if isCancelled(){throw CancellationError()}
                commit(pending.positions,pending.evaluation,pending.iteration)
            }
            if !accepted {return result(.lineSearchFailed)}
        }
        return result(.newtonBudget)
    }
    private static func conjugateGradient<F:FrameOperator>(frame:F,at e:F.Evaluation,workspace:CP.Workspace,generation:UInt64,
        maximumIterations:Int,isCancelled:@escaping @Sendable()->Bool)throws->CG {
        let rhs=e.gradientNewton.map{$0 * -1},rhsNorm=norm(rhs),trust=0.02*sqrt(Double(rhs.count))
        var p=Array(repeating:V.zero,count:rhs.count),r=rhs
        func inverse(_ b:[V])throws->[V] {
            try workspace.solve(rhs:b,generation:generation,isCancelled:isCancelled)
        }
        func product(_ direction:[V])throws->[V] {
            let h=try frame.hessianProduct(at:e,direction:direction,isCancelled:isCancelled)
            guard h.count==rhs.count,h.allSatisfy(\.isFinite) else {throw SolverError.nonfinite};return h
        }
        func finish(_ reason:LinearReason,_ iterations:Int)throws->CG {
            let hp=try product(p)
            let residual=norm(zip(rhs,hp).map{$0-$1})/max(rhsNorm,Double.leastNormalMagnitude)
            guard residual.isFinite else {throw SolverError.nonfinite}
            return .init(vector:p,report:.init(iterations:iterations,trueRelativeResidual:residual,
                converged:reason == .converged && residual<1e-9,reason:reason))
        }
        if rhsNorm==0 {return try finish(.converged,0)}
        var z=try inverse(r),d=z,rz=dot(r,z)
        guard rz.isFinite,rz>0 else {throw SolverError.invalidPreconditioner}
        func boundary(_ direction:[V])throws->[V] {
            let a=dot(direction,direction),b=2*dot(p,direction),c=dot(p,p)-trust*trust
            guard a.isFinite,a>0,b.isFinite,c.isFinite else {throw SolverError.nonfinite}
            let t=(-b+sqrt(max(0,b*b-4*a*c)))/(2*a)
            guard t.isFinite,t>=0 else {throw SolverError.nonfinite}
            return zip(p,direction).map{$0+$1*t}
        }
        for iteration in 0..<maximumIterations {
            if isCancelled(){throw CancellationError()}
            let hd=try product(d),curvature=dot(d,hd)
            guard curvature.isFinite else {throw SolverError.nonfinite}
            if curvature<=0 {p=try boundary(d);return try finish(.nonpositiveCurvature,iteration+1)}
            let step=rz/curvature,next=zip(p,d).map{$0+$1*step}
            if norm(next)>=trust {p=try boundary(d);return try finish(.trustBoundary,iteration+1)}
            p=next;r=zip(r,hd).map{$0-$1*step}
            var residual=norm(r)/rhsNorm
            if residual<1e-9 || (iteration+1)%40==0 {
                let hp=try product(p)
                r=zip(rhs,hp).map{$0-$1};residual=norm(r)/rhsNorm
            }
            if residual<1e-9 {return try finish(.converged,iteration+1)}
            z=try inverse(r)
            let nextRz=dot(r,z)
            guard nextRz.isFinite,nextRz>0,rz>0 else {throw SolverError.invalidPreconditioner}
            let beta=nextRz/rz;d=zip(z,d).map{$0+$1*beta};rz=nextRz
        }
        return try finish(.budget,maximumIterations)
    }
    private static func domainRejection(_ error:Error)->Bool {
        if let e=error as? GarmentCodeMembrane.MembraneError {
            switch e {case .collapsedTriangle,.strainLimitExceeded:return true;default:return false}
        }
        if let e=error as? GarmentCodeHingeBending.HingeError {
            switch e {case .degenerateCurrentHinge,.principalAngleCut:return true;default:return false}
        }
        if let e=error as? BodyContactPotential.Failure {
            switch e {case .infeasible,.degenerate:return true;default:return false}
        }
        if let e=error as? ClothContactPotential.Failure {
            switch e {case .infeasible,.degenerate:return true;default:return false}
        }
        return false
    }
    private static func relative(_ a:Double,_ b:Double)->Double {b==0 ? (a==0 ? 0:Double.greatestFiniteMagnitude):a/b}
    private static func infinity(_ x:[V])->Double {x.reduce(0){max($0,abs($1.x),abs($1.y),abs($1.z))}}
    private static func dot(_ a:[V],_ b:[V])->Double {
        var s=0.0,c=0.0
        for (a,b) in zip(a,b) {
            for x in [a.x*b.x,a.y*b.y,a.z*b.z] {let t=s+x;c += abs(s)>=abs(x) ? (s-t)+x:(x-t)+s;s=t}
        }
        return s+c
    }
    private static func norm(_ x:[V])->Double {sqrt(max(0,dot(x,x)))}
}

extension GarmentCodeJointBodyObjective.Evaluation:GarmentCodeJointNewton.EvaluationValue {}
extension GarmentCodeJointBodyObjective.EnergyDelta:GarmentCodeJointNewton.DeltaValue {}
extension GarmentCodeJointBodyObjective.Frame:GarmentCodeJointNewton.FrameOperator {}

extension GarmentCodeJointNewton.FrameOperator {
    nonisolated func preconditionerBlocks(at:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->[GarmentCodeJointNewton.CP.Block] {
        if isCancelled(){throw CancellationError()};return []
    }
}
extension GarmentCodeJointBodyObjective.Frame {
    nonisolated func preconditionerBlocks(at e:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->[GarmentCodeJointNewton.CP.Block] {
        try GarmentCodeJointNewton.CP.blocks(body:bodyPreconditioner(at:e,isCancelled:isCancelled))
    }
}


/// Pure bounded proposal data. The owner must supply the raw Hessian of the
/// SAME frame/evaluation and must enforce the existing roundoff trigger. No
/// score, returned gradient prediction or helper completion authorizes a step.
nonisolated enum GarmentCodeCoupledCoordinateProposals {
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error,Sendable {case invalidInput,invalidHessianProduct}
    struct Limits:Sendable {
        var maximumPartners=16
        var maximumBasisProducts=17
        var maximumProposals=8
        var maximumTemporaryBytes=32*1_024*1_024
    }
    struct Change:Codable,Sendable {
        let dof:Int,value:Double,delta:Double
    }
    struct Proposal:Codable,Sendable {
        let targetDOF:Int
        let changes:[Change]
        let predictedGradientInfinityNewton:Double,predictedEnergyDeltaJoules:Double
    }
    struct Statistics:Codable,Sendable {
        let targetDOF:Int?,forceViolations:Int
        let rawBasisProducts:Int,availablePartners:Int,generatedCandidates:Int,selectedCandidates:Int
        /// Conservative charged payload; not an allocator/RSS measurement.
        let chargedTemporaryBytes:Int
        let budgetLimited:Bool
    }
    struct Build:Sendable {let proposals:[Proposal],statistics:Statistics}
    static func build(positions x:[V],gradient:[V],travel:[Double],limits:Limits = .init(),
        hessianColumn:(_ dof:Int)throws->[V],isCancelled:()->Bool={false})throws->Build {
        guard !x.isEmpty,x.count<=20_000,x.count==gradient.count,x.count==travel.count,
              x.allSatisfy({$0.isFinite && $0.length<100}),gradient.allSatisfy(\.isFinite),travel.allSatisfy({$0.isFinite && $0>=0}),
              (2...16).contains(limits.maximumPartners),(1...17).contains(limits.maximumBasisProducts),
              (1...8).contains(limits.maximumProposals),(1...64*1_024*1_024).contains(limits.maximumTemporaryBytes) else{throw Failure.invalidInput}
        if isCancelled(){throw CancellationError()}
        let n=3*x.count
        guard 4*n*8+64*1024<=limits.maximumTemporaryBytes else {
            return .init(proposals:[],statistics:.init(targetDOF:nil,forceViolations:0,rawBasisProducts:0,availablePartners:0,generatedCandidates:0,selectedCandidates:0,chargedTemporaryBytes:0,budgetLimited:true))
        }
        let flat=x.flatMap{[$0.x,$0.y,$0.z]},g=gradient.flatMap{[$0.x,$0.y,$0.z]}
        var target:Int?,violations=0
        for i in 0..<n {
            if i%128==0 && isCancelled(){throw CancellationError()}
            if abs(g[i])<1e-6{continue};violations+=1
            let next=g[i]>0 ? flat[i].nextDown:flat[i].nextUp,delta=next-flat[i]
            if !next.isFinite || !delta.isFinite || delta==0 || !(g[i]*delta<0) || abs(delta)>min(0.02,max(0,0.5-travel[i/3])){continue}
            if target==nil || abs(g[i])>abs(g[target!]) || (abs(g[i])==abs(g[target!]) && i<target!){target=i}
        }
        var columns:[Int:[Double]]=[:],raw=0,generated=0,budgetLimited=false,charged=4*n*8
        func result(_ proposals:[Proposal],_ partners:Int)->Build {
            .init(proposals:proposals,statistics:.init(targetDOF:target,forceViolations:violations,
                rawBasisProducts:raw,availablePartners:partners,generatedCandidates:generated,
                selectedCandidates:proposals.count,chargedTemporaryBytes:charged,budgetLimited:budgetLimited))
        }
        guard let i=target else{return result([],0)}
        func pull(_ index:Int)throws->[Double]? {
            if let existing=columns[index]{return existing}
            if isCancelled(){throw CancellationError()}
            let bytes=4*n*8+2*(columns.count+1)*n*8+64*1024
            guard raw<limits.maximumBasisProducts,bytes<=limits.maximumTemporaryBytes else{budgetLimited=true;return nil}
            let product=try hessianColumn(index)
            raw+=1
            guard product.count==x.count,product.allSatisfy(\.isFinite)else{throw Failure.invalidHessianProduct}
            let c=product.flatMap{[$0.x,$0.y,$0.z]};columns[index]=c;charged=max(charged,bytes)
            if isCancelled(){throw CancellationError()}
            return c
        }
        guard let h=try pull(i),h[i]>0 else{return result([],0)}
        let ranked=(0..<n).filter{$0 != i && h[$0] != 0}.sorted{
            let a=abs(h[$0])*flat[$0].ulp,b=abs(h[$1])*flat[$1].ulp
            return a==b ? $0<$1:a>b
        }
        var partners:[Int]=[]
        for j in ranked.prefix(limits.maximumPartners) {
            guard try pull(j) != nil else{break};partners.append(j)
        }
        guard partners.count>=2 else{return result([],partners.count)}
        var best:[Proposal]=[]
        func better(_ a:Proposal,_ b:Proposal)->Bool {
            if a.predictedGradientInfinityNewton != b.predictedGradientInfinityNewton{return a.predictedGradientInfinityNewton<b.predictedGradientInfinityNewton}
            if a.predictedEnergyDeltaJoules != b.predictedEnergyDeltaJoules{return a.predictedEnergyDeltaJoules<b.predictedEnergyDeltaJoules}
            for (x,y)in zip(a.changes,b.changes) {
                if x.dof != y.dof{return x.dof<y.dof}
                if x.value != y.value{return x.value<y.value}
                if x.value.bitPattern != y.value.bitPattern{return x.value.bitPattern<y.value.bitPattern}
            }
            return false
        }
        for a in partners.indices {for b in partners.indices where b>a {
            if isCancelled(){throw CancellationError()}
            let j=partners[a],k=partners[b],cj=columns[j]!,ck=columns[k]!,hjj=cj[j],hkk=ck[k]
            // Numerical symmetrization is ONLY for the proposal's small model.
            let hij=0.5*h[j]+0.5*cj[i],hik=0.5*h[k]+0.5*ck[i],hjk=0.5*cj[k]+0.5*ck[j],det=hjj*hkk-hjk*hjk
            if !det.isFinite || det<=0 || hjj<=0 || hkk<=0{continue}
            for ti in [flat[i].nextDown,flat[i].nextUp] {
                let di=ti-flat[i],rj = -(g[j]+hij*di),rk = -(g[k]+hik*di)
                let dj0=(rj*hkk-rk*hjk)/det,dk0=(rk*hjj-rj*hjk)/det,nj=flat[j]+dj0,nk=flat[k]+dk0
                if !nj.isFinite || !nk.isFinite{continue}
                for tj in [nj.nextDown,nj,nj.nextUp] {for tk in [nk.nextDown,nk,nk.nextUp] {
                    if generated%32==0 && isCancelled(){throw CancellationError()}
                    let dj=tj-flat[j],dk=tk-flat[k]
                    if dj==0 || dk==0{continue}
                    let changes=[Change(dof:i,value:ti,delta:di),.init(dof:j,value:tj,delta:dj),.init(dof:k,value:tk,delta:dk)].sorted{$0.dof<$1.dof}
                    var byVertex:[Int:Double]=[:]
                    for c in changes{byVertex[c.dof/3,default:0]+=c.delta*c.delta}
                    if byVertex.contains(where:{!$0.value.isFinite || travel[$0.key]>=0.5 || sqrt($0.value)>min(0.02,max(0,0.5-travel[$0.key]))}){continue}
                    let predicted=(0..<n).reduce(0.0){max($0,abs(g[$1]+h[$1]*di+cj[$1]*dj+ck[$1]*dk))}
                    let de=g[i]*di+g[j]*dj+g[k]*dk+0.5*h[i]*di*di+hij*di*dj+hik*di*dk+0.5*hjj*dj*dj+hjk*dj*dk+0.5*hkk*dk*dk
                    if !predicted.isFinite || !de.isFinite{continue}
                    generated+=1
                    if best.contains(where:{a in zip(a.changes,changes).allSatisfy{$0.dof==$1.dof && $0.value.bitPattern==$1.value.bitPattern}}){continue}
                    let p=Proposal(targetDOF:i,changes:changes,predictedGradientInfinityNewton:predicted,predictedEnergyDeltaJoules:de)
                    if best.count==limits.maximumProposals && !better(p,best.last!){continue}
                    var low=0,high=best.count
                    while low<high{let m=(low+high)/2;if better(p,best[m]){high=m}else{low=m+1}}
                    best.insert(p,at:low);if best.count>limits.maximumProposals{best.removeLast()}
                }}
            }
        }}
        if isCancelled(){throw CancellationError()}
        return result(best,partners.count)
    }
}
