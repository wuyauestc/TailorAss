import Foundation

/// Immutable exact elastic Hessian at ONE actual Newton point. It changes no
/// source metric, material, gradient, branch domain, pins or solver equation.
/// Rebuild at every new x; never reuse it for a trial with different positions.
nonisolated enum GarmentCodeElasticLinearization {
    typealias M=GarmentCodeMembrane
    typealias H=GarmentCodeHingeBending
    typealias V=M.V
    enum LinearizationError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded
        var errorDescription:String? {
            switch self {case let .invalid(s):return "弹性线性化无效："+s
            case .budgetExceeded:return "弹性线性化缓存超出预算。"}
        }
    }
    struct Limits:Sendable {var maximumEstimatedCachedBytes=64*1_024*1_024}
    struct Statistics:Sendable {
        let vertices:Int,triangles:Int,hinges:Int,activeBarrierTriangles:Int
        let bendingEnabled:Bool
        /// Conservative array/capacity estimate, not measured process RSS.
        let maximumEstimatedCachedBytes:Int
    }
    /// Validate the immutable shared source ONCE, outside a Newton loop.
    /// The topology/metric check is the existing stable-delta source check;
    /// canonical provenance remains the caller's verified-source responsibility.
    struct Source:Sendable {
        /// Runtime binding only: copied values retain the token; rebuilt sources
        /// receive a new one. Never part of canonical source JSON or provenance.
        let identity:UUID
        let membrane:M.Prepared,bending:H.Prepared?
        init(membrane:M.Prepared,bending:H.Prepared?=nil,isCancelled:@Sendable()->Bool={false})throws {
            _ = try GarmentCodeElasticEnergyDelta.Prepared(membrane:membrane,bending:bending,isCancelled:isCancelled)
            self.identity=UUID();self.membrane=membrane;self.bending=bending
        }
    }
    struct Prepared:Sendable {
        let source:Source,positions:[V],material:M.Material,barrier:M.StrainBarrier,bendingMaterial:H.Material?
        let statistics:Statistics
        private let membraneCache:MembraneCache,hingeCache:HingeCache?
        /// Convenience path includes a fresh source validation. Consumers with
        /// repeated Newton points should retain Source and use the next init.
        init(membrane:M.Prepared,bending:H.Prepared?=nil,positions:[V],material:M.Material,
             barrier:M.StrainBarrier,bendingMaterial:H.Material?=nil,limits:Limits=Limits(),
             isCancelled:@Sendable()->Bool={false})throws {
            try self.init(source:Source(membrane:membrane,bending:bending,isCancelled:isCancelled),positions:positions,
                          material:material,barrier:barrier,bendingMaterial:bendingMaterial,limits:limits,isCancelled:isCancelled)
        }
        init(source:Source,positions:[V],material:M.Material,barrier:M.StrainBarrier,bendingMaterial:H.Material?=nil,
             limits:Limits=Limits(),isCancelled:@Sendable()->Bool={false})throws {
            try cancel(isCancelled)
            guard (1...256*1_024*1_024).contains(limits.maximumEstimatedCachedBytes),
                  (source.bending==nil)==(bendingMaterial==nil) else {throw LinearizationError.invalid("缓存预算或弯曲材料与源不匹配。")}
            let n=source.membrane.vertexCount,t=source.membrane.triangles.count
            let enabled=(bendingMaterial?.bendingStiffnessNewtonMeter ?? 0)>0
            let h=enabled ? (source.bending?.hinges.count ?? 0):0
            // Reserve/check BEFORE variable-sized cached states. Factors of two
            // allow array capacity/allocator rounding and retained CoW snapshots.
            let bytes=4_096+2*n*MemoryLayout<V>.stride+2*t*(MemoryLayout<MembraneCache.NHState>.stride+MemoryLayout<MembraneCache.BarrierState>.stride)+2*h*MemoryLayout<HingeCache.State>.stride
            guard bytes<=limits.maximumEstimatedCachedBytes else {throw LinearizationError.budgetExceeded}
            let m=try MembraneCache(source.membrane,positions,material,barrier,isCancelled)
            let b:HingeCache?
            if enabled,let original=source.bending,let bendingMaterial {b=try HingeCache(original,positions,bendingMaterial,isCancelled)}
            else {b=nil} // Same explicit kb==0 skip as the joint objective.
            try cancel(isCancelled)
            self.source=source;self.positions=positions;self.material=material;self.barrier=barrier;self.bendingMaterial=bendingMaterial
            membraneCache=m;hingeCache=b
            statistics=Statistics(vertices:n,triangles:t,hinges:h,activeBarrierTriangles:m.active.count,bendingEnabled:enabled,maximumEstimatedCachedBytes:bytes)
        }
        private func validate(_ d:[V],_ isCancelled:@Sendable()->Bool)throws {
            try cancel(isCancelled)
            guard d.count==source.membrane.vertexCount else {throw LinearizationError.invalid("方向向量数量不一致。")}
            for i in d.indices {
                if i%128==0 {try cancel(isCancelled)}
                guard d[i].isFinite else {throw LinearizationError.invalid("方向向量含非有限值。")}
            }
        }
        func neoHookeanHessianProduct(direction:[V],isCancelled:@Sendable()->Bool={false})throws->[V] {
            try validate(direction,isCancelled);return try membraneCache.neoHookean(direction,isCancelled)
        }
        func principalBarrierHessianProduct(direction:[V],isCancelled:@Sendable()->Bool={false})throws->[V] {
            try validate(direction,isCancelled);return try membraneCache.principal(direction,isCancelled)
        }
        func bendingHessianProduct(direction:[V],isCancelled:@Sendable()->Bool={false})throws->[V] {
            try validate(direction,isCancelled)
            if let hingeCache {return try hingeCache.product(direction,isCancelled)}
            try cancel(isCancelled);return Array(repeating:.zero,count:direction.count)
        }
        /// Exact raw (NH + principal barrier) + bending, in that order. No PSD
        /// projection or frozen-gradient/Gauss-Newton substitution is made.
        func hessianProduct(direction:[V],isCancelled:@Sendable()->Bool={false})throws->[V] {
            try validate(direction,isCancelled)
            var out=try membraneCache.neoHookean(direction,isCancelled)
            let b=try membraneCache.principal(direction,isCancelled)
            for i in out.indices {if i%128==0 {try cancel(isCancelled)};out[i]=out[i]+b[i]}
            if let hingeCache {
                let h=try hingeCache.product(direction,isCancelled)
                for i in out.indices {if i%128==0 {try cancel(isCancelled)};out[i]=out[i]+h[i]}
            }
            guard out.allSatisfy(\.isFinite) else {throw LinearizationError.invalid("Hessian方向积溢出。")}
            try cancel(isCancelled);return out
        }
    }
    private static func cancel(_ f:@Sendable()->Bool)throws {if f(){throw CancellationError()}}
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
private struct MembraneCache:Sendable {
    struct NHState:Sendable {let u:V,v:V,hu:V,hv:V;let m00:Double,m01:Double,m11:Double,beta:Double}
    struct BarrierState:Sendable {let triangleID:Int;let fl:V,fh:V;let co:Double,si:Double,gl:Double,gh:Double,dgl:Double,dgh:Double,off:Double}
    let prepared:M.Prepared,material:M.Material,barrier:M.StrainBarrier
    let nh:[NHState],active:[BarrierState]
    init(_ p:M.Prepared,_ x:[V],_ material:M.Material,_ barrier:M.StrainBarrier,_ isCancelled:@Sendable()->Bool)throws {
        try cancel(isCancelled)
        guard x.count==p.vertexCount,x.allSatisfy({$0.isFinite && $0.length<100}) else {throw M.MembraneError.invalid("cache coordinates")}
        var nh:[NHState]=[],active:[BarrierState]=[];nh.reserveCapacity(p.triangles.count);active.reserveCapacity(p.triangles.count)
        let mu=material.shearStiffnessNewtonPerMeter,lambda=material.areaStiffnessNewtonPerMeter
        for (id,t) in p.triangles.enumerated() {
            if id%128==0 {try cancel(isCancelled)}
            let db=x[t.b]-x[t.a],dc=x[t.c]-x[t.a],u=db*t.du.y+dc*t.du.z,v=db*t.dv.y+dc*t.dv.z
            let a=dot(u,u),b=dot(u,v),c=dot(v,v),J=u.cross(v).length
            let sh=sqrt(max(0,0.5*(a+c+hypot(a-c,2*b)))),sl=sh>0 ? J/sh:0
            guard [a,b,c,J,sh,sl].allSatisfy(\.isFinite),J>1e-10 else {throw M.MembraneError.collapsedTriangle(id)}
            let inv=1/(J*J),m00=c*inv,m01 = -b*inv,m11=a*inv,hu=u*m00+v*m01,hv=u*m01+v*m11
            nh.append(.init(u:u,v:v,hu:hu,hv:hv,m00:m00,m01:m01,m11:m11,beta:lambda*log1p(J-1)-mu))
            let low=try Self.scalar(sl,barrier,id),high=try Self.scalar(sh,barrier,id)
            // Strictly inactive scalar barriers have zero first AND second
            // derivatives. This is not a material/domain clamp or approximation.
            if low.0==0 && low.1==0 && high.0==0 && high.1==0 {continue}
            let angle=0.5*atan2(2*b,a-c),co=cos(angle),si=sin(angle)
            let fl=u*(-si)+v*co,fh=u*co+v*si,gl=low.0/sl,gh=high.0/sh
            let dgl=0.5*(low.1/sl-low.0/(sl*sl))/sl,dgh=0.5*(high.1/sh-high.0/(sh*sh))/sh
            let off:Double
            if abs(sh-sl)<=64*Double.ulpOfOne*max(1,sh,sl) {off=0.5*(dgl+dgh)}
            else {off=(gh-gl)/((sh-sl)*(sh+sl))}
            active.append(.init(triangleID:id,fl:fl,fh:fh,co:co,si:si,gl:gl,gh:gh,dgl:dgl,dgh:dgh,off:off))
        }
        try cancel(isCancelled)
        self.prepared=p;self.material=material;self.barrier=barrier;self.nh=nh;self.active=active
    }
    static func scalar(_ s:Double,_ b:M.StrainBarrier,_ id:Int)throws->(Double,Double) {
        guard s>b.lowerLimit,s<b.upperLimit else {throw M.MembraneError.strainLimitExceeded(id)}
        let delta:Double,width:Double,sign:Double
        if s>b.upperActivation {delta=s-b.upperActivation;width=b.upperLimit-b.upperActivation;sign=1}
        else if s<b.lowerActivation {delta=b.lowerActivation-s;width=b.lowerActivation-b.lowerLimit;sign = -1}
        else {return(0,0)}
        let rem=width-delta,l=log1p(-delta/width),k=b.stiffnessNewtonPerMeter
        guard rem>0 else {throw M.MembraneError.strainLimitExceeded(id)}
        return(sign*k*(-2*delta*l+delta*delta/rem),k*(-2*l+4*delta/rem+delta*delta/(rem*rem)))
    }
    func neoHookean(_ d:[V],_ isCancelled:@Sendable()->Bool)throws->[V] {
        try cancel(isCancelled);var out=Array(repeating:V.zero,count:d.count)
        let mu=material.shearStiffnessNewtonPerMeter,lambda=material.areaStiffnessNewtonPerMeter
        for (id,t) in prepared.triangles.enumerated() {
            if id%128==0 {try cancel(isCancelled)}
            let s=nh[id],u=s.u,v=s.v,hu=s.hu,hv=s.hv,m00=s.m00,m01=s.m01,m11=s.m11
            let db=d[t.b]-d[t.a],dc=d[t.c]-d[t.a],du=db*t.du.y+dc*t.du.z,dv=db*t.dv.y+dc*t.dv.z
            let d00=2*dot(u,du),d01=dot(u,dv)+dot(v,du),d11=2*dot(v,dv)
            let dhu=du*m00+dv*m01-hu*(d00*m00+d01*m01)-hv*(d01*m00+d11*m01)
            let dhv=du*m01+dv*m11-hu*(d00*m01+d01*m11)-hv*(d01*m01+d11*m11)
            let dlogJ=dot(hu,du)+dot(hv,dv),dpu=du*mu+hu*(lambda*dlogJ)+dhu*s.beta,dpv=dv*mu+hv*(lambda*dlogJ)+dhv*s.beta
            for(i,w) in [(t.a,0),(t.b,1),(t.c,2)] {out[i]=out[i]+(dpu*t.du[w]+dpv*t.dv[w])*t.referenceAreaSquareMeters}
        }
        guard out.allSatisfy(\.isFinite) else {throw M.MembraneError.invalid("cache NH overflow")};try cancel(isCancelled);return out
    }
    func principal(_ d:[V],_ isCancelled:@Sendable()->Bool)throws->[V] {
        try cancel(isCancelled);var out=Array(repeating:V.zero,count:d.count)
        for (index,s) in active.enumerated() {
            if index%128==0 {try cancel(isCancelled)}
            let t=prepared.triangles[s.triangleID],fl=s.fl,fh=s.fh,co=s.co,si=s.si
            let db=d[t.b]-d[t.a],dc=d[t.c]-d[t.a],du=db*t.du.y+dc*t.du.z,dv=db*t.dv.y+dc*t.dv.z
            let dl=du*(-si)+dv*co,dh=du*co+dv*si,cross=s.off*(dot(fl,dh)+dot(fh,dl))
            let dpl=dl*s.gl+fl*(s.dgl*2*dot(fl,dl))+fh*cross,dph=dh*s.gh+fh*(s.dgh*2*dot(fh,dh))+fl*cross
            let pu=dpl*(-si)+dph*co,pv=dpl*co+dph*si
            for(i,w) in [(t.a,0),(t.b,1),(t.c,2)] {out[i]=out[i]+(pu*t.du[w]+pv*t.dv[w])*t.referenceAreaSquareMeters}
        }
        guard out.allSatisfy(\.isFinite) else {throw M.MembraneError.invalid("cache barrier overflow")};try cancel(isCancelled);return out
    }
}
private struct HingeCache:Sendable {
    struct State:Sendable {
        let theta:Double,q0:V,q1:V,q2:V,q3:V,e:V,v:V,w:V,length:Double,n1:V,n2:V,a:Double,b:Double
    }
    let prepared:H.Prepared,material:H.Material,states:[State]
    init(_ p:H.Prepared,_ x:[V],_ material:H.Material,_ isCancelled:@Sendable()->Bool)throws {
        try cancel(isCancelled)
        // Honor the original Prepared's private, potentially stricter domain
        // limits. This one validation/evaluation is charged to linearization,
        // never replaced with guessed default limits or a relaxed angle band.
        _ = try p.evaluate(positions:x,material:material,isCancelled:isCancelled)
        guard x.count==p.vertexCount,x.allSatisfy({$0.isFinite && $0.length<100}) else {throw H.HingeError.invalid("cache coordinates")}
        var states:[State]=[];states.reserveCapacity(p.hinges.count)
        for(id,h) in p.hinges.enumerated() {
            if id%128==0 {try cancel(isCancelled)}
            let ids=h.vertexIDs,p0=x[ids[0]],e=x[ids[1]]-p0,v=x[ids[2]]-p0,w=x[ids[3]]-p0,L=e.length,n1=e.cross(v),n2=w.cross(e),s1=n1.length,s2=n2.length
            guard L.isFinite,L>0,s1.isFinite,s2.isFinite,
                  s1>0,s2>0 else {throw H.HingeError.degenerateCurrentHinge(id)}
            let theta=atan2(dot(e/L,(n1/s1).cross(n2/s2)),dot(n1/s1,n2/s2))
            guard theta.isFinite else {throw H.HingeError.principalAngleCut(id)}
            let q2=n1*(-L/(s1*s1)),q3=n2*(-L/(s2*s2)),a=dot(e,v)/(L*L),b=dot(e,w)/(L*L)
            let q0=q2*(-(1-a))+q3*(-(1-b)),q1=q2*(-a)+q3*(-b)
            guard [q0,q1,q2,q3].allSatisfy(\.isFinite) else {throw H.HingeError.invalid("cache angle gradient")}
            states.append(.init(theta:theta,q0:q0,q1:q1,q2:q2,q3:q3,e:e,v:v,w:w,length:L,n1:n1,n2:n2,a:a,b:b))
        }
        try cancel(isCancelled)
        self.prepared=p;self.material=material;self.states=states
    }
    func product(_ d:[V],_ isCancelled:@Sendable()->Bool)throws->[V] {
        try cancel(isCancelled)
        var out=Array(repeating:V.zero,count:d.count)
        for(id,h) in prepared.hinges.enumerated() {
            if id%128==0 {try cancel(isCancelled)}
            let s=states[id],ids=h.vertexIDs,d0=d[ids[0]],d1=d[ids[1]],d2=d[ids[2]],d3=d[ids[3]]
            var dt=0.0;dt+=dot(s.q0,d0);dt+=dot(s.q1,d1);dt+=dot(s.q2,d2);dt+=dot(s.q3,d3)
            let de=d1-d0,dv=d2-d0,dw=d3-d0,dL=dot(s.e,de)/s.length
            let dn1=de.cross(s.v)+s.e.cross(dv),dn2=dw.cross(s.e)+s.w.cross(de),s1=s.n1.lengthSquared,s2=s.n2.lengthSquared
            let dq2=(s.n1*dL+dn1*s.length)*(-1/s1)+s.n1*(s.length*2*dot(s.n1,dn1)/(s1*s1))
            let dq3=(s.n2*dL+dn2*s.length)*(-1/s2)+s.n2*(s.length*2*dot(s.n2,dn2)/(s2*s2))
            let common=2*dot(s.e,de)/(s.length*s.length)
            let da=(dot(de,s.v)+dot(s.e,dv))/(s.length*s.length)-s.a*common,db=(dot(de,s.w)+dot(s.e,dw))/(s.length*s.length)-s.b*common
            let dq0=s.q2*da-dq2*(1-s.a)+s.q3*db-dq3*(1-s.b),dq1=s.q2*(-da)-dq2*s.a+s.q3*(-db)-dq3*s.b
            let c=2*material.bendingStiffnessNewtonMeter*h.sourceWeight
            out[ids[0]]=out[ids[0]]+(s.q0*dt+dq0*s.theta)*c
            out[ids[1]]=out[ids[1]]+(s.q1*dt+dq1*s.theta)*c
            out[ids[2]]=out[ids[2]]+(s.q2*dt+dq2*s.theta)*c
            out[ids[3]]=out[ids[3]]+(s.q3*dt+dq3*s.theta)*c
        }
        guard out.allSatisfy(\.isFinite) else {throw H.HingeError.invalid("cache H overflow")};try cancel(isCancelled);return out
    }
}
}
