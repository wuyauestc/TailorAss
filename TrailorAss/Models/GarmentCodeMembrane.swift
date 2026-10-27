import Foundation

/// Immutable per-triangle material coordinates for the joint cloth solver.
/// F = Ds * inverse(Dm), in metres, measures the whole 2D metric. Edge length
/// bounds alone can miss principal stretch on thin/oblique source triangles.
/// No mesh, source length, mass or pinned state is modified by this module.
nonisolated enum GarmentCodeMembrane {
    typealias V=GarmentCodeCircleDrape.Vector3
    enum MembraneError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,collapsedTriangle(Int),strainLimitExceeded(Int)
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "布片面内度量无效："+s
            case .budgetExceeded:return "布片面内度量超出顶点或三角面预算。"
            case let .collapsedTriangle(id):return "布片三角面 \(id) 已退化，不能继续求解。"
            case let .strainLimitExceeded(id):return "布片三角面 \(id) 已超出面内主伸长的可行范围。"
            }
        }
    }
    struct Triangle:Sendable {
        let a:Int,b:Int,c:Int
        let referenceAreaSquareMeters:Double
        // Derivatives of the linear source shape functions wrt material u,v.
        let du:SIMD3<Double>
        let dv:SIMD3<Double>
    }
    struct Deformation:Codable,Sendable {
        let materialU:V,materialV:V
        let minimumPrincipalStretch:Double
        let maximumPrincipalStretch:Double
        let areaRatio:Double
        let materialShear:Double
        var maximumAbsolutePrincipalStrain:Double {
            max(abs(minimumPrincipalStretch-1),abs(maximumPrincipalStretch-1))
        }
    }
    struct Quality:Codable,Sendable {
        let triangleCount:Int
        let minimumPrincipalStretch:Double
        let maximumPrincipalStretch:Double
        let maximumAbsolutePrincipalStrain:Double
        let minimumAreaRatio:Double
        let maximumAbsoluteMaterialShear:Double
        let degenerateTriangles:Int
        let referenceAreaSquareMeters:Double
        let actualAreaSquareMeters:Double
        let worstPrincipalStrainTriangle:Int
    }
    /// Experimental isotropic plane material: both coefficients are N/m.
    /// The caller must choose them explicitly; there is no measured-fabric claim.
    struct Material:Sendable {
        let shearStiffnessNewtonPerMeter:Double
        let areaStiffnessNewtonPerMeter:Double
        init(shearStiffnessNewtonPerMeter:Double,areaStiffnessNewtonPerMeter:Double)throws {
            guard shearStiffnessNewtonPerMeter.isFinite,shearStiffnessNewtonPerMeter>0,
                  shearStiffnessNewtonPerMeter<=1e12,areaStiffnessNewtonPerMeter.isFinite,
                  (0...1e12).contains(areaStiffnessNewtonPerMeter) else {
                throw MembraneError.invalid("面内材料系数必须有限，剪切刚度为正且面积刚度非负。")
            }
            self.shearStiffnessNewtonPerMeter=shearStiffnessNewtonPerMeter
            self.areaStiffnessNewtonPerMeter=areaStiffnessNewtonPerMeter
        }
    }
    /// A numerical feasibility barrier, separate from measured elasticity.
    /// Its open interval applies to both principal stretches. Choosing .93/1.07
    /// leaves a margin inside the existing 8% final source-edge acceptance.
    struct StrainBarrier:Sendable {
        let lowerLimit:Double,lowerActivation:Double,upperActivation:Double,upperLimit:Double
        let stiffnessNewtonPerMeter:Double
        init(lowerLimit:Double,lowerActivation:Double,upperActivation:Double,upperLimit:Double,
             stiffnessNewtonPerMeter:Double)throws {
            guard [lowerLimit,lowerActivation,upperActivation,upperLimit,stiffnessNewtonPerMeter].allSatisfy(\.isFinite),
                  lowerLimit>0,lowerLimit<lowerActivation,lowerActivation<1,upperActivation>1,
                  upperActivation<upperLimit,upperLimit<=2,stiffnessNewtonPerMeter>0,stiffnessNewtonPerMeter<=1e12 else {
                throw MembraneError.invalid("主伸长限制需包含无应变状态，激活值位于严格上下界之间。")
            }
            self.lowerLimit=lowerLimit;self.lowerActivation=lowerActivation
            self.upperActivation=upperActivation;self.upperLimit=upperLimit
            self.stiffnessNewtonPerMeter=stiffnessNewtonPerMeter
        }
        fileprivate func scalar(_ stretch:Double,triangleID:Int)throws->(energy:Double,first:Double,second:Double) {
            guard stretch>lowerLimit,stretch<upperLimit else {throw MembraneError.strainLimitExceeded(triangleID)}
            let delta:Double,width:Double,sign:Double
            if stretch>upperActivation {delta=stretch-upperActivation;width=upperLimit-upperActivation;sign=1}
            else if stretch<lowerActivation {delta=lowerActivation-stretch;width=lowerActivation-lowerLimit;sign = -1}
            else {return (0,0,0)}
            let remaining=width-delta
            guard remaining>0 else {throw MembraneError.strainLimitExceeded(triangleID)}
            let logarithm=log1p(-delta/width),k=stiffnessNewtonPerMeter
            return (-k*delta*delta*logarithm,
                    sign*k*(-2*delta*logarithm+delta*delta/remaining),
                    k*(-2*logarithm+4*delta/remaining+delta*delta/(remaining*remaining)))
        }
        /// Stable secant of b', used only by the PSD numerical proxy. The
        /// energy/gradient/raw Hessian routines above and below are unchanged.
        fileprivate func firstDividedDifference(_ lo:Double,_ hi:Double,_ low:(energy:Double,first:Double,second:Double),
                                               _ high:(energy:Double,first:Double,second:Double))->Double {
            if hi==lo {return low.second}
            let d0:Double,d1:Double,width:Double
            if lo>upperActivation {d0=lo-upperActivation;d1=hi-upperActivation;width=upperLimit-upperActivation}
            else if hi<lowerActivation {d0=lowerActivation-hi;d1=lowerActivation-lo;width=lowerActivation-lowerLimit}
            else {return (high.first-low.first)/(hi-lo)}
            let gap=d1-d0,r0=width-d0,r1=width-d1
            if gap==0 {return 0.5*(low.second+high.second)}
            // Both terms are nonnegative. log1p retains a small relative gap;
            // the direct positive ratio avoids rounding its argument to -1.
            let ratio=gap/r0,logRatio=ratio<0.5 ? log1p(-ratio):log(r1/r0)
            let logTerm = -2*(log1p(-d1/width)+d0*(logRatio/gap))
            let rational=(d0*(width+r0)+gap*r0)/(r0*r1)
            return stiffnessNewtonPerMeter*(logTerm+rational)
        }
    }
    struct BarrierPreconditionerLimits:Sendable {
        var maximumBlocks=40_000
        var maximumStagedBytes=64*1_024*1_024
    }
    struct BarrierPreconditionerBlock:Sendable {
        let triangleID:Int,vertexIDs:[Int]
        /// A Dᵀ H_F⁺ D, full symmetric row-major 9×9, in N/m. The positive
        /// part is taken in 3×2 deformation space before the source pullback.
        let hessian:[Double]
        fileprivate init(triangleID:Int,vertexIDs:[Int],hessian:[Double]) {
            self.triangleID=triangleID;self.vertexIDs=vertexIDs;self.hessian=hessian
        }
    }
    struct BarrierPreconditioner:Sendable {
        let blocks:[BarrierPreconditionerBlock]
        let chargedStagedBytes:Int,maximumDensityCurvatureNewtonPerMeter:Double
        fileprivate init(blocks:[BarrierPreconditionerBlock],chargedStagedBytes:Int,maximumDensityCurvatureNewtonPerMeter:Double) {
            self.blocks=blocks;self.chargedStagedBytes=chargedStagedBytes
            self.maximumDensityCurvatureNewtonPerMeter=maximumDensityCurvatureNewtonPerMeter
        }
    }
    struct EnergyEvaluation:Sendable {
        let energyJoules:Double
        /// dE/dx, in N. The internal force is its negative.
        let gradientNewton:[V]
    }
    struct Prepared:Sendable {
        let vertexCount:Int
        let triangles:[Triangle]
        let referenceAreaSquareMeters:Double
        init(referencePositions:[V],triangleIndices:[UInt32],
             isCancelled:@Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            guard referencePositions.count<=20_000,triangleIndices.count<=120_000 else {throw MembraneError.budgetExceeded}
            guard referencePositions.count>=3,!triangleIndices.isEmpty,triangleIndices.count%3==0,
                  referencePositions.allSatisfy({$0.isFinite && $0.length<100 && abs($0.z)<1e-12}),
                  triangleIndices.allSatisfy({Int($0)<referencePositions.count}) else {throw MembraneError.invalid("需要完整、有限且以米表示的原始二维三角网格。")}
            var prepared:[Triangle]=[];prepared.reserveCapacity(triangleIndices.count/3)
            var used=Array(repeating:false,count:referencePositions.count),area=0.0
            for offset in stride(from:0,to:triangleIndices.count,by:3) {
                if offset%384==0 && isCancelled(){throw CancellationError()}
                let a=Int(triangleIndices[offset]),b=Int(triangleIndices[offset+1]),c=Int(triangleIndices[offset+2])
                let u=referencePositions[b]-referencePositions[a],v=referencePositions[c]-referencePositions[a]
                let determinant=u.x*v.y-v.x*u.y
                guard a != b,b != c,c != a,determinant.isFinite,determinant>1e-14 else {
                    throw MembraneError.invalid("原始三角面必须保持已验证的正向面积，不能翻转或退化。")
                }
                let m00=v.y/determinant,m01 = -v.x/determinant,m10 = -u.y/determinant,m11=u.x/determinant
                let du=SIMD3<Double>(-m00-m10,m00,m10),dv=SIMD3<Double>(-m01-m11,m01,m11)
                guard [du.x,du.y,du.z,dv.x,dv.y,dv.z].allSatisfy(\.isFinite) else {throw MembraneError.invalid("源度量逆矩阵不可分辨。")}
                let triangleArea=determinant/2
                prepared.append(.init(a:a,b:b,c:c,referenceAreaSquareMeters:triangleArea,du:du,dv:dv))
                used[a]=true;used[b]=true;used[c]=true;area += triangleArea
            }
            guard used.allSatisfy({$0}),area.isFinite else {throw MembraneError.invalid("源顶点必须全部属于真实三角面。")}
            vertexCount=referencePositions.count;triangles=prepared;referenceAreaSquareMeters=area
        }
        private func validate(_ positions:[V])throws {
            guard positions.count==vertexCount,positions.allSatisfy({$0.isFinite && $0.length<100}) else {
                throw MembraneError.invalid("实际坐标必须完整、有限并使用米。")
            }
        }
        func deformation(positions:[V],triangleID:Int)throws->Deformation {
            try validate(positions)
            guard triangles.indices.contains(triangleID) else {throw MembraneError.invalid("三角面编号越界。")}
            return try uncheckedDeformation(positions:positions,triangle:triangles[triangleID])
        }
        private func uncheckedDeformation(positions:[V],triangle:Triangle)throws->Deformation {
            // Differences avoid cancellation of absolute world translations.
            let u=positions[triangle.b]-positions[triangle.a],v=positions[triangle.c]-positions[triangle.a]
            let fu=u*triangle.du.y+v*triangle.du.z,fv=u*triangle.dv.y+v*triangle.dv.z
            let a=dot(fu,fu),b=dot(fu,fv),c=dot(fv,fv),areaRatio=fu.cross(fv).length
            let largest=sqrt(max(0,0.5*(a+c+hypot(a-c,2*b))))
            // Product of singular values is |Fu x Fv|; this form avoids the
            // catastrophic trace - discriminant cancellation near collapse.
            let smallest=largest>0 ? areaRatio/largest : 0
            guard [a,b,c,areaRatio,largest,smallest].allSatisfy(\.isFinite) else {throw MembraneError.invalid("实际变形度量溢出。")}
            return .init(materialU:fu,materialV:fv,minimumPrincipalStretch:smallest,
                         maximumPrincipalStretch:largest,areaRatio:areaRatio,materialShear:b)
        }
        /// 3x2 compressible Neo-Hookean membrane with the immutable source area:
        /// A * [mu/2*(tr(C)-2) - mu*log(J) + lambda/2*log(J)^2],
        /// C=F^T F and J=|Fu x Fv|. No out-of-plane spring is added here.
        /// This elastic energy alone is not a strict 8% strain/contact barrier.
        func neoHookean(positions:[V],material:Material,
                        isCancelled:@Sendable()->Bool={false})throws->EnergyEvaluation {
            if isCancelled(){throw CancellationError()};try validate(positions)
            var energy=0.0,gradient=Array(repeating:V.zero,count:vertexCount)
            let mu=material.shearStiffnessNewtonPerMeter,lambda=material.areaStiffnessNewtonPerMeter
            for (id,t) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t)
                guard f.areaRatio>1e-10 else {throw MembraneError.collapsedTriangle(id)}
                let u=f.materialU,v=f.materialV,a=dot(u,u),b=dot(u,v),c=dot(v,v)
                let inv=1/(f.areaRatio*f.areaRatio),logJ=log1p(f.areaRatio-1)
                let hu=(u*c-v*b)*inv,hv=(v*a-u*b)*inv,beta=lambda*logJ-mu
                let pu=u*mu+hu*beta,pv=v*mu+hv*beta,A=t.referenceAreaSquareMeters
                // Algebraically identical nonnegative density avoids subtracting
                // O(1) quantities to recover O(strain^2) near a rigid state.
                let deltaJ=f.areaRatio-1,gap=f.maximumPrincipalStretch-f.minimumPrincipalStretch
                let volumeEnergy:Double
                if abs(deltaJ)<1e-4 {
                    volumeEnergy=deltaJ*deltaJ*(0.5+deltaJ*(-1.0/3+deltaJ*(0.25+deltaJ*(-0.2+deltaJ/6))))
                }else{volumeEnergy=deltaJ-logJ}
                energy += A*(0.5*mu*gap*gap+mu*volumeEnergy+0.5*lambda*logJ*logJ)
                for (i,w) in [(t.a,0),(t.b,1),(t.c,2)] {
                    gradient[i]=gradient[i]+(pu*t.du[w]+pv*t.dv[w])*A
                }
            }
            guard energy.isFinite,gradient.allSatisfy(\.isFinite) else {throw MembraneError.invalid("膜能量或梯度溢出。")}
            if isCancelled(){throw CancellationError()}
            return .init(energyJoules:energy,gradientNewton:gradient)
        }
        /// Exact energy Hessian times an arbitrary displacement. It can be
        /// indefinite under compression: callers must not pretend it is an SPD
        /// matrix or accept an unconverged Newton direction as a cloth result.
        func neoHookeanHessianProduct(positions:[V],direction:[V],material:Material,
                        isCancelled:@Sendable()->Bool={false})throws->[V] {
            if isCancelled(){throw CancellationError()};try validate(positions)
            guard direction.count==vertexCount,direction.allSatisfy(\.isFinite) else {throw MembraneError.invalid("膜能量方向向量无效。")}
            var result=Array(repeating:V.zero,count:vertexCount)
            let mu=material.shearStiffnessNewtonPerMeter,lambda=material.areaStiffnessNewtonPerMeter
            for (id,t) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t)
                guard f.areaRatio>1e-10 else {throw MembraneError.collapsedTriangle(id)}
                let u=f.materialU,v=f.materialV,a=dot(u,u),b=dot(u,v),c=dot(v,v),inv=1/(f.areaRatio*f.areaRatio)
                let m00=c*inv,m01 = -b*inv,m11=a*inv,hu=u*m00+v*m01,hv=u*m01+v*m11
                let db=direction[t.b]-direction[t.a],dc=direction[t.c]-direction[t.a]
                let du=db*t.du.y+dc*t.du.z,dv=db*t.dv.y+dc*t.dv.z
                let d00=2*dot(u,du),d01=dot(u,dv)+dot(v,du),d11=2*dot(v,dv)
                let dhu=du*m00+dv*m01-hu*(d00*m00+d01*m01)-hv*(d01*m00+d11*m01)
                let dhv=du*m01+dv*m11-hu*(d00*m01+d01*m11)-hv*(d01*m01+d11*m11)
                let dlogJ=dot(hu,du)+dot(hv,dv),beta=lambda*log1p(f.areaRatio-1)-mu
                let dpu=du*mu+hu*(lambda*dlogJ)+dhu*beta
                let dpv=dv*mu+hv*(lambda*dlogJ)+dhv*beta
                for (i,w) in [(t.a,0),(t.b,1),(t.c,2)] {
                    result[i]=result[i]+(dpu*t.du[w]+dpv*t.dv[w])*t.referenceAreaSquareMeters
                }
            }
            guard result.allSatisfy(\.isFinite) else {throw MembraneError.invalid("膜能量 Hessian 方向积溢出。")}
            if isCancelled(){throw CancellationError()}
            return result
        }
        /// C2-at-activation logarithmic barriers for the two singular values.
        /// No energy or derivative is clamped to turn an infeasible state valid.
        func principalBarrier(positions:[V],barrier:StrainBarrier,
                              isCancelled:@Sendable()->Bool={false})throws->EnergyEvaluation {
            if isCancelled(){throw CancellationError()};try validate(positions)
            var energy=0.0,gradient=Array(repeating:V.zero,count:vertexCount)
            for (id,t) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t)
                let low=try barrier.scalar(f.minimumPrincipalStretch,triangleID:id)
                let high=try barrier.scalar(f.maximumPrincipalStretch,triangleID:id)
                let angle=0.5*atan2(2*dot(f.materialU,f.materialV),dot(f.materialU,f.materialU)-dot(f.materialV,f.materialV))
                let co=cos(angle),si=sin(angle)
                let lowF=f.materialU*(-si)+f.materialV*co,highF=f.materialU*co+f.materialV*si
                let pl=lowF*(low.first/f.minimumPrincipalStretch),ph=highF*(high.first/f.maximumPrincipalStretch)
                let pu=pl*(-si)+ph*co,pv=pl*co+ph*si,A=t.referenceAreaSquareMeters
                energy += A*(low.energy+high.energy)
                for (i,w) in [(t.a,0),(t.b,1),(t.c,2)] {gradient[i]=gradient[i]+(pu*t.du[w]+pv*t.dv[w])*A}
            }
            guard energy.isFinite,gradient.allSatisfy(\.isFinite) else {throw MembraneError.invalid("主伸长限制能量或梯度溢出。")}
            if isCancelled(){throw CancellationError()}
            return .init(energyJoules:energy,gradientNewton:gradient)
        }
        /// Exact spectral Hessian product, including repeated singular values.
        /// Like the elastic Hessian, this is not silently replaced with an SPD
        /// approximation. A joint Newton solver must handle negative curvature.
        func principalBarrierHessianProduct(positions:[V],direction:[V],barrier:StrainBarrier,
                              isCancelled:@Sendable()->Bool={false})throws->[V] {
            if isCancelled(){throw CancellationError()};try validate(positions)
            guard direction.count==vertexCount,direction.allSatisfy(\.isFinite) else {throw MembraneError.invalid("主伸长限制的方向向量无效。")}
            var result=Array(repeating:V.zero,count:vertexCount)
            for (id,t) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t)
                let sl=f.minimumPrincipalStretch,sh=f.maximumPrincipalStretch
                let low=try barrier.scalar(sl,triangleID:id),high=try barrier.scalar(sh,triangleID:id)
                let angle=0.5*atan2(2*dot(f.materialU,f.materialV),dot(f.materialU,f.materialU)-dot(f.materialV,f.materialV))
                let co=cos(angle),si=sin(angle)
                let fl=f.materialU*(-si)+f.materialV*co,fh=f.materialU*co+f.materialV*si
                let db=direction[t.b]-direction[t.a],dc=direction[t.c]-direction[t.a]
                let du=db*t.du.y+dc*t.du.z,dv=db*t.dv.y+dc*t.dv.z
                let dl=du*(-si)+dv*co,dh=du*co+dv*si
                let gl=low.first/sl,gh=high.first/sh
                let dgl=0.5*(low.second/sl-low.first/(sl*sl))/sl
                let dgh=0.5*(high.second/sh-high.first/(sh*sh))/sh
                let off:Double
                // The divided difference has an analytic repeated-eigenvalue
                // limit. At indistinguishable binary64 stretches subtraction
                // of two nearly equal gradients would lose that curvature.
                if abs(sh-sl)<=64*Double.ulpOfOne*max(1,sh,sl) {off=0.5*(dgl+dgh)}
                else {off=(gh-gl)/((sh-sl)*(sh+sl))}
                let cross=off*(dot(fl,dh)+dot(fh,dl))
                let dpl=dl*gl+fl*(dgl*2*dot(fl,dl))+fh*cross
                let dph=dh*gh+fh*(dgh*2*dot(fh,dh))+fl*cross
                let pu=dpl*(-si)+dph*co,pv=dpl*co+dph*si
                for (i,w) in [(t.a,0),(t.b,1),(t.c,2)] {result[i]=result[i]+(pu*t.du[w]+pv*t.dv[w])*t.referenceAreaSquareMeters}
            }
            guard result.allSatisfy(\.isFinite) else {throw MembraneError.invalid("主伸长限制 Hessian 方向积溢出。")}
            if isCancelled(){throw CancellationError()}
            return result
        }
        /// Pure numerical PSD proxy for the existing principal barrier. Six
        /// orthogonal density modes cover both stretches, symmetric shear,
        /// in-plane rotation and two normal modes. Negative density modes are
        /// omitted ONLY here; no true energy, force or raw Hv is changed.
        func principalBarrierPreconditioner(positions:[V],barrier:StrainBarrier,
                              limits:BarrierPreconditionerLimits=BarrierPreconditionerLimits(),
                              isCancelled:@Sendable()->Bool={false})throws->BarrierPreconditioner {
            if isCancelled(){throw CancellationError()};try validate(positions)
            guard (1...40_000).contains(limits.maximumBlocks),(1...128*1_024*1_024).contains(limits.maximumStagedBytes) else {
                throw MembraneError.invalid("主伸长预条件块预算无效。")
            }
            var blocks:[BarrierPreconditionerBlock]=[],bytes=0,largest=0.0
            // Includes conservative array-element/capacity and backing-array
            // allowances. This is a charged staging budget, not an RSS claim.
            let charge=2*MemoryLayout<BarrierPreconditionerBlock>.stride+84*MemoryLayout<Double>.stride+64
            for (id,t) in triangles.enumerated() {
                if id%64==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t),sl=f.minimumPrincipalStretch,sh=f.maximumPrincipalStretch
                let low=try barrier.scalar(sl,triangleID:id),high=try barrier.scalar(sh,triangleID:id)
                if low.first==0 && low.second==0 && high.first==0 && high.second==0 {continue}
                guard blocks.count<limits.maximumBlocks,charge<=limits.maximumStagedBytes-bytes else {throw MembraneError.budgetExceeded}
                let a=dot(f.materialU,f.materialU),b=dot(f.materialU,f.materialV),c=dot(f.materialV,f.materialV)
                let angle=0.5*atan2(2*b,a-c),co=cos(angle),si=sin(angle)
                let ul=(f.materialU*(-si)+f.materialV*co)/sl,uh=(f.materialU*co+f.materialV*si)/sh,n=ul.cross(uh)
                let shear=barrier.firstDividedDifference(sl,sh,low,high),rotation=(low.first+high.first)/(sl+sh)
                let coefficients=[low.second,high.second,shear,rotation,low.first/sl,high.first/sh]
                guard coefficients.allSatisfy(\.isFinite) else {throw MembraneError.invalid("主伸长预条件谱系数溢出。")}
                largest=max(largest,coefficients.max() ?? 0)
                var matrix=Array(repeating:0.0,count:81)
                func rank(_ u:V,_ v:V,_ coefficient:Double) {
                    if coefficient<=0 {return}
                    let q=(0..<3).flatMap{i->[Double] in let a=u*t.du[i]+v*t.dv[i];return [a.x,a.y,a.z]}
                    let weight=t.referenceAreaSquareMeters*coefficient
                    for i in 0..<9 {for j in 0...i {
                        let value=weight*q[i]*q[j];matrix[i*9+j]+=value
                        if i != j {matrix[j*9+i]+=value}
                    }}
                }
                let s=1/sqrt(2.0)
                rank(ul*(-si),ul*co,low.second);rank(uh*co,uh*si,high.second)
                rank((ul*co+uh*(-si))*s,(ul*si+uh*co)*s,shear)
                rank((ul*co-uh*(-si))*s,(ul*si-uh*co)*s,rotation)
                rank(n*(-si),n*co,low.first/sl);rank(n*co,n*si,high.first/sh)
                guard matrix.allSatisfy(\.isFinite) else {throw MembraneError.invalid("主伸长预条件块溢出。")}
                bytes+=charge;blocks.append(.init(triangleID:id,vertexIDs:[t.a,t.b,t.c],hessian:matrix))
            }
            if isCancelled(){throw CancellationError()}
            return .init(blocks:blocks,chargedStagedBytes:bytes,maximumDensityCurvatureNewtonPerMeter:largest)
        }
        /// Weyl's singular-value perturbation bound with the Frobenius norm
        /// bounds the whole linear path. The joint solver must still evaluate
        /// the actual candidate and retain final source/contact acceptance.
        func principalBarrierStepLimit(positions:[V],direction:[V],barrier:StrainBarrier,
                              safetyFactor:Double=0.9,isCancelled:@Sendable()->Bool={false})throws->Double {
            if isCancelled(){throw CancellationError()};try validate(positions)
            guard direction.count==vertexCount,direction.allSatisfy(\.isFinite),safetyFactor.isFinite,
                  safetyFactor>0,safetyFactor<1 else {throw MembraneError.invalid("主伸长限制的步长参数无效。")}
            var step=1.0
            for (id,t) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:t)
                _=try barrier.scalar(f.minimumPrincipalStretch,triangleID:id)
                _=try barrier.scalar(f.maximumPrincipalStretch,triangleID:id)
                let db=direction[t.b]-direction[t.a],dc=direction[t.c]-direction[t.a]
                let du=db*t.du.y+dc*t.du.z,dv=db*t.dv.y+dc*t.dv.z
                let norm=sqrt(du.lengthSquared+dv.lengthSquared).nextUp
                guard norm.isFinite else {throw MembraneError.invalid("主伸长方向范数溢出。")}
                if norm<=Double.leastNormalMagnitude {continue}
                let reserve=64*Double.ulpOfOne*max(1,f.maximumPrincipalStretch)
                let slack=min(f.minimumPrincipalStretch-barrier.lowerLimit,barrier.upperLimit-f.maximumPrincipalStretch)-reserve
                guard slack>0 else {return 0}
                step=min(step,max(0,safetyFactor*slack/norm))
            }
            if isCancelled(){throw CancellationError()}
            return step
        }
        func inspect(positions:[V],isCancelled:@Sendable()->Bool={false})throws->Quality {
            if isCancelled(){throw CancellationError()};try validate(positions)
            var minimum=Double.infinity,maximum=0.0,strain=0.0,minArea=Double.infinity,shear=0.0,degenerate=0,area=0.0,worst=0
            for (id,triangle) in triangles.enumerated() {
                if id%128==0 && isCancelled(){throw CancellationError()}
                let f=try uncheckedDeformation(positions:positions,triangle:triangle)
                minimum=min(minimum,f.minimumPrincipalStretch);maximum=max(maximum,f.maximumPrincipalStretch)
                if f.maximumAbsolutePrincipalStrain>strain {strain=f.maximumAbsolutePrincipalStrain;worst=id}
                minArea=min(minArea,f.areaRatio);shear=max(shear,abs(f.materialShear))
                if f.areaRatio<=1e-10 {degenerate += 1}
                area += f.areaRatio*triangle.referenceAreaSquareMeters
            }
            return .init(triangleCount:triangles.count,minimumPrincipalStretch:minimum,maximumPrincipalStretch:maximum,
                maximumAbsolutePrincipalStrain:strain,minimumAreaRatio:minArea,maximumAbsoluteMaterialShear:shear,
                degenerateTriangles:degenerate,referenceAreaSquareMeters:referenceAreaSquareMeters,
                actualAreaSquareMeters:area,worstPrincipalStrainTriangle:worst)
        }
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
}
