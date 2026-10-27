import Foundation

/// One implicit cloth objective in SI units. This component evaluates forces;
/// it neither projects positions nor certifies a complete garment. Body/self
/// contact must be added by the solver before accepting a physical time step.
nonisolated enum GarmentCodeJointObjective {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias M=GarmentCodeMembrane
    typealias H=GarmentCodeHingeBending
    typealias D=GarmentCodeElasticEnergyDelta
    typealias L=GarmentCodeElasticLinearization
    enum ObjectiveError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,nonsmoothSewing(Int),nonfinite
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "布料联立能量无效："+s
            case .budgetExceeded:return "布料联立能量超出工作预算。"
            case let .nonsmoothSewing(i):return "接缝 \(i) 的两端已重合，但本步目标间距仍非零。"
            case .nonfinite:return "布料联立能量或导数无法用有限数表示。"
            }
        }
    }
    struct SewingRow:Sendable {
        let vertexIDs:[Int]
        let coefficients:[Double]
        let initialGapMeters:Double
    }
    enum SewingSchedule: Sendable, Equatable {
        /// Historical scalar rest-gap ramp; retained for exact controls.
        case distanceTarget
        /// A solver homotopy. The target is always zero; only its coefficient
        /// grows. At r=1 the original final objective is exactly recovered.
        case quadraticStiffness(initialNewtonPerMeter: Double)
    }
    struct Evaluation:Sendable {
        let energyJoules:Double
        let inertiaJoules:Double
        let membraneJoules:Double
        let strainBarrierJoules:Double
        let bendingJoules:Double
        let sewingJoules:Double
        /// dPhi/dx in N. This is the exact declared objective's gradient.
        let gradientNewton:[V]
        let maximumSewingGapMeters:Double
        let maximumSewingTargetResidualMeters:Double
    }
    struct NonelasticDelta:Sendable {
        let inertiaJoules:Double
        let sewingJoules:Double
        var energyJoules:Double {inertiaJoules+sewingJoules}
    }
    struct EnergyDelta:Sendable {
        let energyJoules:Double
        let elastic:D.Evaluation
        let nonelastic:NonelasticDelta
        /// Floating-point estimate of the same objective, not a sign proof.
        let isDoubleEstimate:Bool
    }
    /// A low-level energy component, not a replacement for PreparedInput's
    /// source/provenance/body checks. Masses must be the original area masses;
    /// no fixed particles or normalized inverse masses are introduced here.
    struct Prepared:Sendable {
        let membrane:M.Prepared
        let bending:H.Prepared
        let elasticEnergyDelta:D.Prepared
        let linearizationSource:L.Source
        let massesKg:[Double]
        let sewingRows:[SewingRow]
        let material:M.Material
        let strainBarrier:M.StrainBarrier
        let bendingMaterial:H.Material
        let sewingStiffnessNewtonPerMeter:Double

        init(referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[H.PanelGroup],
             massesKg:[Double],stitches:[GarmentCodeSewing.Constraint],material:M.Material,
             strainBarrier:M.StrainBarrier,bendingMaterial:H.Material,
             sewingComplianceMetersPerNewton:Double,
             isCancelled:@Sendable()->Bool={false})throws {
            try checkCancellation(isCancelled)
            guard referencePositions.count<=20_000,stitches.count<=4096 else {throw ObjectiveError.budgetExceeded}
            guard massesKg.count==referencePositions.count,
                  massesKg.allSatisfy({$0.isFinite && $0>0 && $0<=100}),
                  sewingComplianceMetersPerNewton.isFinite,sewingComplianceMetersPerNewton>0,
                  sewingComplianceMetersPerNewton<=1e4,
                  (1/sewingComplianceMetersPerNewton).isFinite,
                  1/sewingComplianceMetersPerNewton<=1e16 else {
                throw ObjectiveError.invalid("需要原始正质量与有限正缝合顺应度；零顺应度不能用小正数代替。")
            }
            let m=try M.Prepared(referencePositions:referencePositions,triangleIndices:referenceTriangles,isCancelled:isCancelled)
            let h=try H.Prepared(referencePositions:referencePositions,referenceTriangles:referenceTriangles,
                                 panelGroups:panelGroups,isCancelled:isCancelled)
            membrane=m;bending=h
            // A zero coefficient disables this component. Its identically
            // zero force/Hv needs no principal-angle branch evaluation.
            elasticEnergyDelta=try D.Prepared(membrane:m,bending:bendingMaterial.bendingStiffnessNewtonMeter>0 ? h:nil,isCancelled:isCancelled)
            linearizationSource=try L.Source(membrane:m,bending:bendingMaterial.bendingStiffnessNewtonMeter>0 ? h:nil,isCancelled:isCancelled)
            var rows:[SewingRow]=[];rows.reserveCapacity(stitches.count)
            for (index,stitch) in stitches.enumerated() {
                if index%64==0 {try checkCancellation(isCancelled)}
                var values:[Int:Double]=[:]
                for (id,w) in zip(stitch.a.vertexIDs,stitch.a.weights) {values[id,default:0]+=w}
                for (id,w) in zip(stitch.b.vertexIDs,stitch.b.weights) {values[id,default:0]-=w}
                let ids=values.keys.filter{values[$0] != 0}.sorted(),coefficients=ids.map{values[$0]!}
                guard ids.allSatisfy({referencePositions.indices.contains($0)}),ids.count<=4,
                      coefficients.allSatisfy(\.isFinite),abs(coefficients.reduce(0,+))<=1e-12,
                      stitch.initialGapMeters.isFinite,(0...100).contains(stitch.initialGapMeters),
                      stitch.finalGapMeters==0,!ids.isEmpty || stitch.initialGapMeters==0 else {
                    throw ObjectiveError.invalid("真实接缝的附着点、初始间距或零终态间距无效。")
                }
                rows.append(.init(vertexIDs:ids,coefficients:coefficients,initialGapMeters:stitch.initialGapMeters))
            }
            self.massesKg=massesKg;sewingRows=rows;self.material=material
            self.strainBarrier=strainBarrier;self.bendingMaterial=bendingMaterial
            sewingStiffnessNewtonPerMeter=1/sewingComplianceMetersPerNewton
            try checkCancellation(isCancelled)
        }
        func frame(predictor:[V],timeStepSeconds:Double,sewingRamp:Double,
                   sewingSchedule:SewingSchedule = .distanceTarget)throws->Frame {
            guard predictor.count==massesKg.count,predictor.allSatisfy({$0.isFinite && $0.length<100}),
                  timeStepSeconds.isFinite,(1e-5...1).contains(timeStepSeconds),
                  sewingRamp.isFinite,(0...1).contains(sewingRamp) else {
                throw ObjectiveError.invalid("预测位置、时间步长或缝合收紧比例无效。")
            }
            let k:Double
            switch sewingSchedule {
            case .distanceTarget:k=sewingStiffnessNewtonPerMeter
            case let .quadraticStiffness(initial):
                guard initial.isFinite,initial>0,initial<=sewingStiffnessNewtonPerMeter else {
                    throw ObjectiveError.invalid("缝合刚度延续需要不超过原终态刚度的有限正起始值。")
                }
                if sewingRamp==1 {k=sewingStiffnessNewtonPerMeter}
                else if sewingRamp==0 {k=initial}
                else {k=exp(log(initial)+sewingRamp*(log(sewingStiffnessNewtonPerMeter)-log(initial)))}
            }
            guard k.isFinite,k>0 else {throw ObjectiveError.nonfinite}
            return Frame(prepared:self,predictor:predictor,timeStepSeconds:timeStepSeconds,sewingRamp:sewingRamp,
                         sewingSchedule:sewingSchedule,sewingStiffnessNewtonPerMeter:k)
        }
    }
    struct Frame:Sendable {
        let prepared:Prepared
        let predictor:[V]
        let timeStepSeconds:Double
        let sewingRamp:Double
        let sewingSchedule:SewingSchedule
        let sewingStiffnessNewtonPerMeter:Double
        func sewingTargetMeters(_ row:SewingRow)->Double {
            switch sewingSchedule {case .distanceTarget:return (1-sewingRamp)*row.initialGapMeters;case .quadraticStiffness:return 0}
        }
        private var inverseTimeStepSquared:Double {1/(timeStepSeconds*timeStepSeconds)}
        private func validate(_ x:[V])throws {
            guard x.count==predictor.count,x.allSatisfy({$0.isFinite && $0.length<100}) else {
                throw ObjectiveError.invalid("当前坐标必须与完整源顶点一一对应且有限。")
            }
        }
        func evaluate(positions x:[V],isCancelled:@Sendable()->Bool={false})throws->Evaluation {
            try checkCancellation(isCancelled);try validate(x)
            let m=try prepared.membrane.neoHookean(positions:x,material:prepared.material,isCancelled:isCancelled)
            let b=try prepared.membrane.principalBarrier(positions:x,barrier:prepared.strainBarrier,isCancelled:isCancelled)
            let h=try prepared.bendingMaterial.bendingStiffnessNewtonMeter>0
                ? prepared.bending.evaluate(positions:x,material:prepared.bendingMaterial,isCancelled:isCancelled):nil
            var g=zip(m.gradientNewton,b.gradientNewton).map{$0+$1}
            if let h {for i in g.indices {g[i]=g[i]+h.gradientNewton[i]}}
            let bendingEnergy=h?.energyJoules ?? 0
            var inertia=Sum(),sewing=Sum(),maximumGap=0.0,maximumResidual=0.0
            for i in x.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let d=x[i]-predictor[i],weight=prepared.massesKg[i]*inverseTimeStepSquared
                inertia.add(0.5*weight*d.lengthSquared);g[i]=g[i]+d*weight
            }
            let k=sewingStiffnessNewtonPerMeter
            for (index,row) in prepared.sewingRows.enumerated() {
                if index%64==0 {try checkCancellation(isCancelled)}
                let d=pointDifference(x,row),length=d.length,target=sewingTargetMeters(row),residual=length-target
                maximumGap=max(maximumGap,length);maximumResidual=max(maximumResidual,abs(residual))
                sewing.add(0.5*k*residual*residual)
                let force:V
                if target==0 {force=d*k}
                else {
                    guard length>0 else {throw ObjectiveError.nonsmoothSewing(index)}
                    force=d*(k*residual/length)
                }
                for (i,c) in zip(row.vertexIDs,row.coefficients) {g[i]=g[i]+force*c}
            }
            var total=Sum();for e in [inertia.value,sewing.value,m.energyJoules,b.energyJoules,bendingEnergy] {total.add(e)}
            guard total.value.isFinite,g.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            try checkCancellation(isCancelled)
            return .init(energyJoules:total.value,inertiaJoules:inertia.value,membraneJoules:m.energyJoules,
                         strainBarrierJoules:b.energyJoules,bendingJoules:bendingEnergy,sewingJoules:sewing.value,
                         gradientNewton:g,maximumSewingGapMeters:maximumGap,maximumSewingTargetResidualMeters:maximumResidual)
        }
        /// Exact Hessian-vector product. Negative radial-sewing or bending
        /// curvature is preserved; any PSD surrogate belongs to preconditioning.
        func linearize(positions:[V],isCancelled:@Sendable()->Bool={false})throws->L.Prepared {
            try L.Prepared(source:prepared.linearizationSource,positions:positions,material:prepared.material,
                barrier:prepared.strainBarrier,bendingMaterial:prepared.bendingMaterial.bendingStiffnessNewtonMeter>0 ? prepared.bendingMaterial:nil,
                isCancelled:isCancelled)
        }
        func hessianProduct(positions x:[V],direction p:[V],linearization:L.Prepared?=nil,
                            isCancelled:@Sendable()->Bool={false})throws->[V] {
            try checkCancellation(isCancelled);try validate(x)
            guard p.count==x.count,p.allSatisfy(\.isFinite) else {throw ObjectiveError.invalid("方向向量与完整源顶点不匹配。")}
            var result:[V]
            if let cache=linearization {
                let a=cache.barrier,b=prepared.strainBarrier
                guard cache.source.identity==prepared.linearizationSource.identity,cache.positions==x,
                      cache.material.shearStiffnessNewtonPerMeter==prepared.material.shearStiffnessNewtonPerMeter,
                      cache.material.areaStiffnessNewtonPerMeter==prepared.material.areaStiffnessNewtonPerMeter,
                      a.lowerLimit==b.lowerLimit,a.lowerActivation==b.lowerActivation,a.upperActivation==b.upperActivation,
                      a.upperLimit==b.upperLimit,a.stiffnessNewtonPerMeter==b.stiffnessNewtonPerMeter,
                      (cache.bendingMaterial?.bendingStiffnessNewtonMeter ?? 0)==prepared.bendingMaterial.bendingStiffnessNewtonMeter else {
                    throw ObjectiveError.invalid("弹性导数缓存必须属于同一源、实际位置和材料。")
                }
                result=try cache.hessianProduct(direction:p,isCancelled:isCancelled)
            } else {
                let m=try prepared.membrane.neoHookeanHessianProduct(positions:x,direction:p,material:prepared.material,isCancelled:isCancelled)
                let b=try prepared.membrane.principalBarrierHessianProduct(positions:x,direction:p,barrier:prepared.strainBarrier,isCancelled:isCancelled)
                result=zip(m,b).map{$0+$1}
                if prepared.bendingMaterial.bendingStiffnessNewtonMeter>0 {
                    let h=try prepared.bending.hessianProduct(positions:x,direction:p,material:prepared.bendingMaterial,mode:.exact,isCancelled:isCancelled)
                    for i in result.indices {result[i]=result[i]+h[i]}
                }
            }
            for i in x.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                result[i]=result[i]+p[i]*(prepared.massesKg[i]*inverseTimeStepSquared)
            }
            let k=sewingStiffnessNewtonPerMeter
            for (index,row) in prepared.sewingRows.enumerated() {
                if index%64==0 {try checkCancellation(isCancelled)}
                let d=pointDifference(x,row),q=pointDifference(p,row),length=d.length,target=sewingTargetMeters(row)
                let value:V
                if target==0 {value=q*k}
                else {
                    guard length>0 else {throw ObjectiveError.nonsmoothSewing(index)}
                    let n=d/length,radial=n*dot(n,q)
                    value=(radial+(q-radial)*(1-target/length))*k
                }
                for (i,c) in zip(row.vertexIDs,row.coefficients) {result[i]=result[i]+value*c}
            }
            guard result.allSatisfy(\.isFinite) else {throw ObjectiveError.nonfinite}
            try checkCancellation(isCancelled);return result
        }
        /// Stable differences for the quadratic inertia and radial sewing
        /// terms, using the two actual stored position arrays. Add the elastic
        /// difference separately; subtracting two rounded total energies loses
        /// tiny descent steps. This Double estimate is not an interval proof.
        func nonelasticEnergyDelta(from x:[V],to y:[V],isCancelled:@Sendable()->Bool={false})throws->NonelasticDelta {
            try checkCancellation(isCancelled);try validate(x);try validate(y)
            let step=zip(y,x).map{$0-$1};var inertia=Sum(),sewing=Sum()
            for i in x.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let d=x[i]-predictor[i],p=step[i]
                inertia.add(prepared.massesKg[i]*inverseTimeStepSquared*(dot(d,p)+0.5*p.lengthSquared))
            }
            for (index,row) in prepared.sewingRows.enumerated() {
                if index%64==0 {try checkCancellation(isCancelled)}
                let d=pointDifference(x,row),p=pointDifference(step,row),old=d.length,new=pointDifference(y,row).length
                if case .quadraticStiffness = sewingSchedule {
                    sewing.add(sewingStiffnessNewtonPerMeter*(dot(d,p)+0.5*p.lengthSquared));continue
                }
                let target=sewingTargetMeters(row),deltaLength:Double
                if old+new==0 {
                    guard target==0 else {throw ObjectiveError.nonsmoothSewing(index)}
                    deltaLength=0
                } else {deltaLength=(2*dot(d,p)+p.lengthSquared)/(old+new)}
                sewing.add(sewingStiffnessNewtonPerMeter*((old-target)*deltaLength+0.5*deltaLength*deltaLength))
            }
            guard inertia.value.isFinite,sewing.value.isFinite else {throw ObjectiveError.nonfinite}
            try checkCancellation(isCancelled);return .init(inertiaJoules:inertia.value,sewingJoules:sewing.value)
        }
        func energyDelta(from x:[V],to y:[V],isCancelled:@Sendable()->Bool={false})throws->EnergyDelta {
            let nonelastic=try nonelasticEnergyDelta(from:x,to:y,isCancelled:isCancelled)
            let elastic=try prepared.elasticEnergyDelta.evaluate(from:x,to:y,material:prepared.material,
                barrier:prepared.strainBarrier,bendingMaterial:prepared.bendingMaterial.bendingStiffnessNewtonMeter>0 ? prepared.bendingMaterial:nil,isCancelled:isCancelled)
            var total=Sum()
            for value in [nonelastic.inertiaJoules,nonelastic.sewingJoules,elastic.neoHookeanDeltaJoules,
                          elastic.principalBarrierDeltaJoules,elastic.hingeDeltaJoules] {total.add(value)}
            guard total.value.isFinite else {throw ObjectiveError.nonfinite}
            try checkCancellation(isCancelled)
            return .init(energyJoules:total.value,elastic:elastic,nonelastic:nonelastic,isDoubleEstimate:true)
        }
    }
    private static func pointDifference(_ x:[V],_ row:SewingRow)->V {
        return zip(row.vertexIDs,row.coefficients).reduce(V.zero){$0+x[$1.0]*$1.1}
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func checkCancellation(_ f:@Sendable()->Bool)throws {if f(){throw CancellationError()}}
    private struct Sum {
        private var sum=0.0,correction=0.0
        mutating func add(_ x:Double) {
            let next=sum+x
            correction += abs(sum)>=abs(x) ? (sum-next)+x:(x-next)+sum
            sum=next
        }
        var value:Double {sum+correction}
    }
}
