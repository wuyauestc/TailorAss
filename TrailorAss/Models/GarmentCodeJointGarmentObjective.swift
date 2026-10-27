import Foundation
import NativeClothCollision

/// Joint source elasticity/bending/sewing, complete body contact and complete
/// all-moving cloth self contact. This is an objective, not a garment result;
/// valid bootstrap, body/self CCD and final quality checks remain mandatory.
nonisolated enum GarmentCodeJointGarmentObjective {
    typealias J=GarmentCodeJointObjective
    typealias T=GarmentCodeJointBodyObjective
    typealias V=J.V
    typealias S=ClothContactPotential
    typealias D=ContactEnergyDelta
    enum ObjectiveError:LocalizedError,Sendable {
        case invalid,foreignEvaluation,nonfinite
        var errorDescription:String? {
            switch self {
            case .invalid:return "布片自接触的完整源或真实导数配置无效。"
            case .foreignEvaluation:return "布片自接触导数与当前求解步不一致。"
            case .nonfinite:return "整衣联立能量或导数无法用有限数表示。"
            }
        }
    }
    struct Evaluation:Sendable {
        let body:T.Evaluation
        let selfContact:S.Evaluation
        let energyJoules:Double
        let gradientNewton:[V]
        fileprivate let contactSnapshot:D.Snapshot
        fileprivate let positions:[V],frameIdentity:UUID
    }
    struct EnergyDelta:Sendable {
        let energyJoules:Double
        let body:T.EnergyDelta
        /// Accumulated rounded signed local values, not an analytic IPC
        /// increment or a guaranteed sign at arbitrary stationary states.
        let selfRoundedBlockDeltaJoules:Double
        let selfAbsoluteStoredEnergyScaleJoules:Double
        /// Selected contact increments. Legacy rounded fields above remain
        /// available for comparison; explicit fallbacks retain all signed leaves.
        let contactIncrement:D.Report
        let isDoubleEstimate:Bool
    }
    struct Prepared:Sendable {
        let body:T.Prepared
        let selfContact:S.Prepared
        let parameters:S.Parameters
        fileprivate let deltaOwner:D.Prepared
        init(body:T.Prepared,parameters:S.Parameters,limits:S.Limits=S.Limits(),
             isCancelled:@escaping @Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            guard parameters.hessianMode == .exact,parameters.stiffnessPascals.isFinite,parameters.stiffnessPascals>0,
                  parameters.minimumDistanceMeters.isFinite,parameters.minimumDistanceMeters>=0,
                  parameters.activationGapMeters.isFinite,parameters.activationGapMeters>0,
                  (parameters.minimumDistanceMeters+parameters.activationGapMeters).isFinite else {throw ObjectiveError.invalid}
            selfContact=try checked {try S.Prepared(restPositions:body.body.clothRestPositions,
                triangleIndices:body.clothTriangleIndices,limits:limits,isCancelled:isCancelled)}
            deltaOwner=try checkedDelta {try D.Prepared(restPositions:body.body.clothRestPositions,
                fixedPositions:body.body.body.bodyPositions,
                bodyParameters:.init(stiffnessPascals:body.parameters.stiffnessPascals,
                    minimumDistanceMeters:body.parameters.minimumDistanceMeters,activationGapMeters:body.parameters.activationGapMeters),
                clothParameters:.init(stiffnessPascals:parameters.stiffnessPascals,
                    minimumDistanceMeters:parameters.minimumDistanceMeters,activationGapMeters:parameters.activationGapMeters),
                isCancelled:isCancelled)}
            self.body=body;self.parameters=parameters
            if isCancelled(){throw CancellationError()}
        }
        init(input:GarmentCodeJointInput.Prepared,bodyParameters:T.B.Parameters,selfParameters:S.Parameters,
             bodyLimits:T.B.Limits=T.B.Limits(),selfLimits:S.Limits=S.Limits(),
             isCancelled:@escaping @Sendable()->Bool={false})throws {
            try self.init(body:T.Prepared(input:input,parameters:bodyParameters,limits:bodyLimits,isCancelled:isCancelled),
                          parameters:selfParameters,limits:selfLimits,isCancelled:isCancelled)
        }
        func frame(predictor:[V],timeStepSeconds:Double,sewingRamp:Double,
                   sewingSchedule:J.SewingSchedule = .distanceTarget)throws->Frame {
            Frame(body:try body.frame(predictor:predictor,timeStepSeconds:timeStepSeconds,sewingRamp:sewingRamp,sewingSchedule:sewingSchedule),
                  prepared:self,identity:UUID())
        }
    }
    struct Frame:Sendable {
        let body:T.Frame
        let prepared:Prepared
        fileprivate let identity:UUID
        var cloth:J.Frame {body.cloth}
        func evaluate(positions:[V],isCancelled:@escaping @Sendable()->Bool={false})throws->Evaluation {
            let b=try body.evaluate(positions:positions,isCancelled:isCancelled)
            let s=try checked {try prepared.selfContact.evaluate(positions:positions.map(nativeVector),parameters:prepared.parameters,isCancelled:isCancelled)}
            guard s.gradientNewtons.count==b.gradientNewton.count else {throw ObjectiveError.invalid}
            let gradient=zip(b.gradientNewton,s.gradientNewtons).map{$0+appVector($1)},energy=b.energyJoules+s.energyJoules
            guard energy.isFinite,gradient.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            let snapshot=try checkedDelta {try prepared.deltaOwner.capture(positions:positions.map(nativeVector),
                bodyLeaves:b.body.localBlocks.map{D.Leaf(bodyBlock:$0)},clothLeaves:s.localBlocks.map{D.Leaf(clothBlock:$0)},
                isCancelled:isCancelled)}
            if isCancelled(){throw CancellationError()}
            return .init(body:b,selfContact:s,energyJoules:energy,gradientNewton:gradient,contactSnapshot:snapshot,
                         positions:positions,frameIdentity:identity)
        }
        func hessianProduct(at e:Evaluation,direction:[V],isCancelled:@escaping @Sendable()->Bool={false})throws->[V] {
            guard e.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let b=try body.hessianProduct(at:e.body,direction:direction,isCancelled:isCancelled)
            let s=try checked {try e.selfContact.hessianProduct(direction:direction.map(nativeVector),isCancelled:isCancelled)}
            let result=zip(b,s).map{$0+appVector($1)}
            guard result.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            if isCancelled(){throw CancellationError()};return result
        }
        func selfPreconditioner(at e:Evaluation,isCancelled:@escaping @Sendable()->Bool={false})throws->S.Evaluation {
            guard e.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let p=prepared.parameters
            return try checked {try prepared.selfContact.evaluate(positions:e.positions.map(nativeVector),
                parameters:.init(stiffnessPascals:p.stiffnessPascals,minimumDistanceMeters:p.minimumDistanceMeters,
                    activationGapMeters:p.activationGapMeters,hessianMode:.clampPositiveSemidefinite),isCancelled:isCancelled)}
        }
        func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool={false})throws->EnergyDelta {
            guard a.frameIdentity==identity,b.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let bodyDelta=try body.energyDelta(from:a.body,to:b.body,isCancelled:isCancelled)
            var s=Sum(),scale=Sum()
            for (sign,blocks) in [(1.0,b.selfContact.localBlocks),(-1.0,a.selfContact.localBlocks)] {
                for (i,block) in blocks.enumerated() {
                    if i%32==0 && isCancelled(){throw CancellationError()}
                    s.add(sign*block.energyJoules);scale.add(abs(block.energyJoules))
                }
            }
            let c=bodyDelta.cloth
            let computedIncrement=try checkedDelta {try prepared.deltaOwner.difference(from:a.contactSnapshot,to:b.contactSnapshot,isCancelled:isCancelled)}
            // A structural/type transition keeps the exact existing force-owner
            // rounded sum. The selected report and actual total use those bits.
            let increment=try computedIncrement.selectingOriginalRoundedFallbacks(body:bodyDelta.bodyRoundedBlockDeltaJoules,cloth:s.value)
            var total=Sum()
            for x in [c.nonelastic.inertiaJoules,c.nonelastic.sewingJoules,c.elastic.neoHookeanDeltaJoules,
                      c.elastic.principalBarrierDeltaJoules,c.elastic.hingeDeltaJoules,
                      increment.body.deltaJoules,increment.cloth.deltaJoules] {total.add(x)}
            guard total.value.isFinite,s.value.isFinite,scale.value.isFinite else {throw ObjectiveError.nonfinite}
            if isCancelled(){throw CancellationError()}
            return .init(energyJoules:total.value,body:bodyDelta,selfRoundedBlockDeltaJoules:s.value,
                         selfAbsoluteStoredEnergyScaleJoules:scale.value,contactIncrement:increment,isDoubleEstimate:true)
        }
    }
    private struct Sum {
        private var sum=0.0,correction=0.0
        mutating func add(_ x:Double){let t=sum+x;correction += abs(sum)>=abs(x) ? (sum-t)+x:(x-t)+sum;sum=t}
        var value:Double {sum+correction}
    }
    private static func nativeVector(_ v:V)->SIMD3<Double>{SIMD3(v.x,v.y,v.z)}
    private static func appVector(_ v:SIMD3<Double>)->V{V(x:v.x,y:v.y,z:v.z)}
    private static func checked<A>(_ work:()throws->A)throws->A {
        do {return try work()}catch S.Failure.cancelled {throw CancellationError()}
    }
    private static func checkedDelta<A>(_ work:()throws->A)throws->A {
        do {return try work()}catch D.Failure.cancelled {throw CancellationError()}
    }
}

extension GarmentCodeJointGarmentObjective.Evaluation:GarmentCodeJointNewton.EvaluationValue {}
extension GarmentCodeJointGarmentObjective.EnergyDelta:GarmentCodeJointNewton.DeltaValue {}
extension GarmentCodeJointGarmentObjective.Frame:GarmentCodeJointNewton.FrameOperator {
    nonisolated func preconditionerBlocks(at e:Evaluation,isCancelled:@escaping @Sendable()->Bool)throws->[GarmentCodeJointNewton.CP.Block] {
        try body.preconditionerBlocks(at:e.body,isCancelled:isCancelled) +
            GarmentCodeJointNewton.CP.blocks(cloth:selfPreconditioner(at:e,isCancelled:isCancelled))
    }
}
