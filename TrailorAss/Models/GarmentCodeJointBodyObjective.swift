import Foundation
import NativeClothCollision

/// The actual joint cloth objective plus the complete signed IPC body force.
/// It keeps the raw physical Hessian separate from the body PSD surrogate.
/// A time-step solver must additionally handle cloth self-contact, a valid
/// exterior initial state, continuous motion and the final garment gates.
nonisolated enum GarmentCodeJointBodyObjective {
    typealias J=GarmentCodeJointObjective
    typealias V=J.V
    typealias B=BodyContactPotential
    enum ObjectiveError:LocalizedError,Sendable {
        case invalid(String),foreignEvaluation,nonfinite
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "布料人体联立能量无效："+s
            case .foreignEvaluation:return "人体接触导数与当前求解步不一致。"
            case .nonfinite:return "布料人体联立能量或导数无法用有限数表示。"
            }
        }
    }
    struct Evaluation:Sendable {
        let cloth:J.Evaluation
        let body:B.Evaluation
        let energyJoules:Double
        let gradientNewton:[V]
        fileprivate let elasticLinearization:J.L.Prepared
        /// The exact iterate is retained with its body Hessian. Callers cannot
        /// accidentally evaluate the cloth Hessian at a different candidate.
        fileprivate let positions:[V]
        fileprivate let frameIdentity:UUID
    }
    struct EnergyDelta:Sendable {
        let energyJoules:Double
        let cloth:J.EnergyDelta
        /// Difference of the stored signed local body energies, accumulated
        /// before total-energy rounding. This is not an analytic IPC increment
        /// or a guaranteed sign near floating-point cancellation.
        let bodyRoundedBlockDeltaJoules:Double
        let bodyAbsoluteStoredEnergyScaleJoules:Double
        let isDoubleEstimate:Bool
    }
    struct Prepared:Sendable {
        let cloth:J.Prepared
        let body:B.Prepared
        let parameters:B.Parameters
        let clothTriangleIndices:[UInt32]
        /// Low-level component constructor. The full App solver uses the
        /// verified JointInput overload below, rather than raw imported meshes.
        init(cloth:J.Prepared,referencePositions:[V],clothTriangleIndices:[UInt32],
             bodyPositions:[V],bodyTriangleIndices:[UInt32],parameters:B.Parameters,
             limits:B.Limits=B.Limits(),isCancelled:@escaping @Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            guard referencePositions.count==cloth.massesKg.count,
                  clothTriangleIndices.count==cloth.membrane.triangles.count*3,
                  parameters.hessianMode == .exact,parameters.stiffnessPascals.isFinite,parameters.stiffnessPascals>0,
                  parameters.minimumDistanceMeters.isFinite,parameters.minimumDistanceMeters>=0,
                  parameters.activationGapMeters.isFinite,parameters.activationGapMeters>0,
                  (parameters.minimumDistanceMeters+parameters.activationGapMeters).isFinite else {
                throw ObjectiveError.invalid("原始源顶点需完整对应，真实目标必须使用精确接触Hessian。")
            }
            let referenceTriangles=cloth.membrane.triangles.flatMap{[UInt32($0.a),UInt32($0.b),UInt32($0.c)]}
            let reference=try J.M.Prepared(referencePositions:referencePositions,triangleIndices:referenceTriangles,isCancelled:isCancelled)
            for (i,pair) in zip(reference.triangles,cloth.membrane.triangles).enumerated() {
                if i%128==0 && isCancelled(){throw CancellationError()}
                let (a,b)=pair,ids=Set(clothTriangleIndices[(3*i)..<(3*i+3)].map(Int.init))
                guard a.du==b.du,a.dv==b.dv,a.referenceAreaSquareMeters==b.referenceAreaSquareMeters,
                      ids==Set([b.a,b.b,b.c]) else {throw ObjectiveError.invalid("接触表面和膜必须保留同一份完整源网格与原始面积。")}
            }
            // Both body force and path guard share this exact immutable BVH.
            let native=try checked {try ContinuousBodyContact.Prepared(bodyPositions:bodyPositions.map(nativeVector),triangleIndices:bodyTriangleIndices,isCancelled:isCancelled)}
            body=try checked {try B.Prepared(clothRestPositions:referencePositions.map(nativeVector),clothTriangleIndices:clothTriangleIndices,
                                              body:native,limits:limits,isCancelled:isCancelled)}
            self.cloth=cloth;self.parameters=parameters;self.clothTriangleIndices=clothTriangleIndices
            if isCancelled(){throw CancellationError()}
        }
        init(input:GarmentCodeJointInput.Prepared,parameters:B.Parameters,limits:B.Limits=B.Limits(),
             isCancelled:@escaping @Sendable()->Bool={false})throws {
            let source=input.source.cloth
            try self.init(cloth:input.objective,referencePositions:source.referencePositions,
                clothTriangleIndices:source.triangleIndices,bodyPositions:source.mannequinPositions,
                bodyTriangleIndices:source.mannequinTriangleIndices,parameters:parameters,limits:limits,isCancelled:isCancelled)
        }
        func frame(predictor:[V],timeStepSeconds:Double,sewingRamp:Double,
                   sewingSchedule:J.SewingSchedule = .distanceTarget)throws->Frame {
            Frame(cloth:try cloth.frame(predictor:predictor,timeStepSeconds:timeStepSeconds,sewingRamp:sewingRamp,sewingSchedule:sewingSchedule),
                  prepared:self,identity:UUID())
        }
        /// All cloth/body features move continuously with the same .5mm (or
        /// explicitly supplied) minimum as the barrier's open domain. This is
        /// still only body CCD; unsigned force alone proves no exterior state.
        func bodyMotion(from x:[V],to y:[V],isCancelled:@escaping @Sendable()->Bool={false})throws->ContinuousBodyContact.Report {
            if isCancelled(){throw CancellationError()}
            let options=ContinuousBodyContact.Options(minimumSeparation:parameters.minimumDistanceMeters,
                distanceTolerance:1e-8,maximumIterationsPerFeature:10_000,safetyFactor:0.9)
            let report=body.body.guardMotion(previous:x.map(nativeVector),candidate:y.map(nativeVector),
                clothTriangleIndices:clothTriangleIndices,options:options,isCancelled:isCancelled)
            if isCancelled() || report.status == .cancelled {throw CancellationError()}
            return report
        }
    }
    struct Frame:Sendable {
        let cloth:J.Frame
        let prepared:Prepared
        fileprivate let identity:UUID
        func evaluate(positions:[V],isCancelled:@escaping @Sendable()->Bool={false})throws->Evaluation {
            let c=try cloth.evaluate(positions:positions,isCancelled:isCancelled)
            let linearization=try cloth.linearize(positions:positions,isCancelled:isCancelled)
            let b=try checked {try prepared.body.evaluate(clothPositions:positions.map(nativeVector),parameters:prepared.parameters,isCancelled:isCancelled)}
            guard c.gradientNewton.count==b.clothGradientNewtons.count else {throw ObjectiveError.invalid("人体力缺少完整裁片自由度。")}
            let gradient=zip(c.gradientNewton,b.clothGradientNewtons).map{$0+appVector($1)},energy=c.energyJoules+b.energyJoules
            guard energy.isFinite,gradient.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            if isCancelled(){throw CancellationError()}
            return Evaluation(cloth:c,body:b,energyJoules:energy,gradientNewton:gradient,elasticLinearization:linearization,positions:positions,frameIdentity:identity)
        }
        func hessianProduct(at evaluation:Evaluation,direction:[V],isCancelled:@escaping @Sendable()->Bool={false})throws->[V] {
            guard evaluation.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let c=try cloth.hessianProduct(positions:evaluation.positions,direction:direction,linearization:evaluation.elasticLinearization,isCancelled:isCancelled)
            let b=try checked {try evaluation.body.hessianProduct(direction:direction.map(nativeVector),isCancelled:isCancelled)}
            let result=zip(c,b).map{$0+appVector($1)}
            guard result.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            if isCancelled(){throw CancellationError()};return result
        }
        /// This does not change evaluate/Hv. Complete signed local blocks are
        /// projected BEFORE eliminating fixed body rows, inside the IPC port.
        func bodyPreconditioner(at evaluation:Evaluation,isCancelled:@escaping @Sendable()->Bool={false})throws->B.Evaluation {
            guard evaluation.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let p=prepared.parameters
            let parameters=B.Parameters(stiffnessPascals:p.stiffnessPascals,minimumDistanceMeters:p.minimumDistanceMeters,
                activationGapMeters:p.activationGapMeters,hessianMode:.clampPositiveSemidefinite)
            return try checked {try prepared.body.evaluate(clothPositions:evaluation.positions.map(nativeVector),parameters:parameters,isCancelled:isCancelled)}
        }
        func energyDelta(from a:Evaluation,to b:Evaluation,isCancelled:@escaping @Sendable()->Bool={false})throws->EnergyDelta {
            guard a.frameIdentity==identity,b.frameIdentity==identity else {throw ObjectiveError.foreignEvaluation}
            let c=try cloth.energyDelta(from:a.positions,to:b.positions,isCancelled:isCancelled)
            var body=Sum(),scale=Sum()
            for (sign,blocks) in [(1.0,b.body.localBlocks),(-1.0,a.body.localBlocks)] {
                for (i,block) in blocks.enumerated() {
                    if i%32==0 && isCancelled(){throw CancellationError()}
                    body.add(sign*block.energyJoules);scale.add(abs(block.energyJoules))
                }
            }
            var total=Sum()
            for e in [c.nonelastic.inertiaJoules,c.nonelastic.sewingJoules,c.elastic.neoHookeanDeltaJoules,
                      c.elastic.principalBarrierDeltaJoules,c.elastic.hingeDeltaJoules,body.value] {total.add(e)}
            guard total.value.isFinite,body.value.isFinite,scale.value.isFinite else {throw ObjectiveError.nonfinite}
            if isCancelled(){throw CancellationError()}
            return .init(energyJoules:total.value,cloth:c,bodyRoundedBlockDeltaJoules:body.value,
                         bodyAbsoluteStoredEnergyScaleJoules:scale.value,isDoubleEstimate:true)
        }
    }
    private struct Sum {
        private var sum=0.0,correction=0.0
        mutating func add(_ x:Double) {
            let next=sum+x;correction += abs(sum)>=abs(x) ? (sum-next)+x:(x-next)+sum;sum=next
        }
        var value:Double {sum+correction}
    }
    private static func nativeVector(_ v:V)->SIMD3<Double> {SIMD3(v.x,v.y,v.z)}
    private static func appVector(_ v:SIMD3<Double>)->V {V(x:v.x,y:v.y,z:v.z)}
    private static func checked<T>(_ work:()throws->T)throws->T {
        do{return try work()}
        catch B.Failure.cancelled {throw CancellationError()}
        catch ContinuousBodyContact.Failure.cancelled {throw CancellationError()}
    }
}
