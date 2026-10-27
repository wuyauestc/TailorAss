import Foundation
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Stable differences of the same analytic elastic energies evaluated by the
/// membrane and hinge modules. These are Double estimates, not certified sign
/// intervals. No energy acceptance tolerance, projection or dynamics is added.
nonisolated enum GarmentCodeElasticEnergyDelta {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias M=GarmentCodeMembrane
    typealias H=GarmentCodeHingeBending
    enum DeltaError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,precisionUnresolved
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "弹性能量增量无效："+s
            case .budgetExceeded:return "弹性能量增量超出工作预算。"
            case .precisionUnresolved:return "当前能量增量的数值精度不足，不能判定变化。"
            }
        }
    }
    struct Limits:Sendable {
        var maximumVertices=20_000,maximumTriangles=40_000,maximumHinges=60_000
    }
    struct Evaluation:Sendable {
        let neoHookeanDeltaJoules:Double
        let principalBarrierDeltaJoules:Double
        let hingeDeltaJoules:Double
        let totalDeltaJoules:Double
        let sumAbsoluteElementDeltaJoules:Double
        let unchangedCoordinates:Bool
        /// The value remains a numerical estimate, even after the explicit
        /// underflow/cancellation guards. No universal sign guarantee is made.
        let isDoubleEstimate:Bool
    }
    struct Prepared:Sendable {
        let membrane:M.Prepared
        let bending:H.Prepared?
        private let limits:Limits
        /// Both inputs must belong to the caller's same verified source. The
        /// topology and stored source measures are checked again here; this
        /// arithmetic module does not independently certify a canonical SHA.
        init(membrane:M.Prepared,bending:H.Prepared?=nil,limits:Limits=Limits(),
             isCancelled:@Sendable()->Bool={false})throws {
            try cancel(isCancelled)
            guard (1...20_000).contains(limits.maximumVertices),(1...40_000).contains(limits.maximumTriangles),
                  (1...60_000).contains(limits.maximumHinges) else {throw DeltaError.invalid("工作预算无效。")}
            guard membrane.vertexCount<=limits.maximumVertices,membrane.triangles.count<=limits.maximumTriangles,
                  (bending?.hinges.count ?? 0)<=limits.maximumHinges else {throw DeltaError.budgetExceeded}
            if let bending {
                guard bending.vertexCount==membrane.vertexCount,bending.triangleCount==membrane.triangles.count else {throw DeltaError.invalid("膜与弯曲必须使用同一份源网格。")}
                var edges:[Edge:Int]=[:]
                for (id,t) in membrane.triangles.enumerated() {
                    if id%128==0 {try cancel(isCancelled)}
                    for (a,b) in [(t.a,t.b),(t.b,t.c),(t.c,t.a)] {edges[Edge(a,b),default:0]+=1}
                }
                guard edges.values.allSatisfy({$0<=2}),edges.values.filter({$0==2}).count==bending.hinges.count else {throw DeltaError.invalid("膜与弯曲的完整内部边不一致。")}
                var seen=Set<Edge>()
                for (id,h) in bending.hinges.enumerated() {
                    if id%128==0 {try cancel(isCancelled)}
                    guard h.vertexIDs.count==4,h.sourceTriangleIDs.count==2,
                          h.sourceTriangleIDs.allSatisfy({membrane.triangles.indices.contains($0)}),
                          seen.insert(Edge(h.vertexIDs[0],h.vertexIDs[1])).inserted,
                          edges[Edge(h.vertexIDs[0],h.vertexIDs[1])]==2 else {throw DeltaError.invalid("弯曲源索引与膜拓扑不一致。")}
                    let a=membrane.triangles[h.sourceTriangleIDs[0]],b=membrane.triangles[h.sourceTriangleIDs[1]],ids=h.vertexIDs
                    guard cyclic([a.a,a.b,a.c],[ids[0],ids[1],ids[2]]),cyclic([b.a,b.b,b.c],[ids[1],ids[0],ids[3]]) else {throw DeltaError.invalid("弯曲的源面方向与膜不一致。")}
                    let area=a.referenceAreaSquareMeters+b.referenceAreaSquareMeters
                    let length=try sourceEdgeLength(ids[0],ids[1],triangle:a)
                    guard abs(area-h.sourceAdjacentAreaSquareMeters)<=128*Double.ulpOfOne*max(area,h.sourceAdjacentAreaSquareMeters),
                          abs(length-h.sourceEdgeLengthMeters)<=1e-10*max(length,h.sourceEdgeLengthMeters) else {throw DeltaError.invalid("膜与弯曲的原始面积或边长不一致。")}
                }
            }
            try cancel(isCancelled);self.membrane=membrane;self.bending=bending;self.limits=limits
        }
        /// x1 must be the actual rounded candidate, not an intended alpha*d.
        /// On a numerical/domain failure the caller must stop/reject; there is
        /// no fallback to subtracting two rounded total elastic energies.
        func evaluate(from x0:[V],to x1:[V],material:M.Material,barrier:M.StrainBarrier?=nil,
                      bendingMaterial:H.Material?=nil,isCancelled:@Sendable()->Bool={false})throws->Evaluation {
            try cancel(isCancelled,requiresNearest:barrier != nil)
            guard x0.count==membrane.vertexCount,x1.count==x0.count,
                  (bending==nil)==(bendingMaterial==nil) else {throw DeltaError.invalid("实际坐标或弯曲材料与准备数据不一致。")}
            guard x0.count<=limits.maximumVertices,membrane.triangles.count<=limits.maximumTriangles,
                  (bending?.hinges.count ?? 0)<=limits.maximumHinges else {throw DeltaError.budgetExceeded}
            var step:[V]=[];step.reserveCapacity(x0.count);var largest=0.0
            for i in x0.indices {
                if i%128==0 {try cancel(isCancelled,requiresNearest:barrier != nil)}
                guard x0[i].isFinite,x1[i].isFinite,x0[i].length<100,x1[i].length<100 else {throw DeltaError.invalid("坐标必须完整、有限并使用米。")}
                let d=x1[i]-x0[i];step.append(d);largest=max(largest,max(abs(d.x),abs(d.y),abs(d.z)))
            }
            // An exponent-range guard, not an energy/slack tolerance.
            if largest>0 && largest<Double.leastNormalMagnitude.squareRoot(){throw DeltaError.precisionUnresolved}
            var nh=Sum(),bp=Sum(),hb=Sum(),absolute=Sum(),arithmetic=Sum()
            for (id,t) in membrane.triangles.enumerated() {
                if id%128==0 {try cancel(isCancelled,requiresNearest:barrier != nil)}
                let (u,v)=columns(x0,t),(du,dv)=columns(step,t),(u1,v1)=columns(x1,t)
                let n=u.cross(v),n1=u1.cross(v1),nn=n.lengthSquared
                guard n.length>1e-10,n1.length>1e-10 else {throw DeltaError.invalid("膜三角面退化。")}
                let dn=u.cross(dv)+du.cross(v)+du.cross(dv)
                let fraction=(2*dot(n,dn)+dn.lengthSquared)/nn
                guard fraction.isFinite,fraction > -1 else {throw DeltaError.invalid("膜面积增量越过有效域。")}
                let dl=0.5*log1p(fraction),dt=sum([2*dot(u,du),du.lengthSquared,2*dot(v,dv),dv.lengthSquared])
                let pieces=[0.5*material.shearStiffnessNewtonPerMeter*dt,-material.shearStiffnessNewtonPerMeter*dl,
                            material.areaStiffnessNewtonPerMeter*log(n.length)*dl,0.5*material.areaStiffnessNewtonPerMeter*dl*dl]
                let change=t.referenceAreaSquareMeters*sum(pieces)
                nh.add(change);absolute.add(abs(change));arithmetic.add(t.referenceAreaSquareMeters*sum(pieces.map(abs)))
                if let barrier {
                    let change=try barrierIncrement(x0,x1,t,barrier)
                    let value=t.referenceAreaSquareMeters*change.value
                    bp.add(value);absolute.add(abs(value));arithmetic.add(t.referenceAreaSquareMeters*change.scale)
                }
            }
            if let bending,let bendingMaterial {
                for (id,h) in bending.hinges.enumerated() {
                    if id%128==0 {try cancel(isCancelled,requiresNearest:barrier != nil)}
                    let change=try hingeIncrement(x0,x1,step,h,bendingMaterial.bendingStiffnessNewtonMeter)
                    hb.add(change.value);absolute.add(abs(change.value));arithmetic.add(change.scale)
                }
            }
            let values=[nh.value,bp.value,hb.value],total=sum(values)
            guard values.allSatisfy(\.isFinite),total.isFinite,absolute.value.isFinite,arithmetic.value.isFinite else {throw DeltaError.precisionUnresolved}
            // A conservative cancellation alarm, not a certified error bound.
            // It deliberately cannot promise to catch every nearly stationary
            // case; callers retain their real gradient/KKT/line-search checks.
            if largest>0 && arithmetic.value>0 && abs(total)<=32*Double.ulpOfOne*arithmetic.value {throw DeltaError.precisionUnresolved}
            try cancel(isCancelled,requiresNearest:barrier != nil)
            return .init(neoHookeanDeltaJoules:values[0],principalBarrierDeltaJoules:values[1],hingeDeltaJoules:values[2],
                         totalDeltaJoules:total,sumAbsoluteElementDeltaJoules:absolute.value,unchangedCoordinates:largest==0,isDoubleEstimate:true)
        }
    }
    private struct Sum {var s=0.0,c=0.0;mutating func add(_ x:Double){let t=s+x;if abs(s)>=abs(x){c+=(s-t)+x}else{c+=(x-t)+s};s=t};var value:Double{s+c}}
    private struct Edge:Hashable {let a:Int,b:Int;init(_ x:Int,_ y:Int){a=min(x,y);b=max(x,y)}}
    private struct Spectrum {let low:Double,high:Double,a:Double,b:Double,c:Double,disc:Double}
    private static func cancel(_ f:@Sendable()->Bool,requiresNearest:Bool=false)throws {
        if requiresNearest && !barrierNearestRounding(){throw DeltaError.precisionUnresolved}
        let stop=f()
        if stop{throw CancellationError()}
        if requiresNearest && !barrierNearestRounding(){throw DeltaError.precisionUnresolved}
    }
    private static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    private static func sum(_ values:[Double])->Double{var s=Sum();for x in values{s.add(x)};return s.value}
    private static func cyclic(_ a:[Int],_ b:[Int])->Bool{(0..<3).contains{offset in (0..<3).allSatisfy{a[$0]==b[($0+offset)%3]}}}
    private static func columns(_ x:[V],_ t:M.Triangle)->(V,V){let b=x[t.b]-x[t.a],c=x[t.c]-x[t.a];return(b*t.du.y+c*t.du.z,b*t.dv.y+c*t.dv.z)}
    private static func sourceEdgeLength(_ first:Int,_ second:Int,triangle t:M.Triangle)throws->Double {
        let determinant=t.du.y*t.dv.z-t.dv.y*t.du.z
        guard determinant.isFinite,determinant>0 else {throw DeltaError.invalid("源形函数不可分辨。")}
        func p(_ id:Int)->V {
            if id==t.a{return .zero}
            if id==t.b{return .init(x:t.dv.z/determinant,y:-t.du.z/determinant,z:0)}
            return .init(x:-t.dv.y/determinant,y:t.du.y/determinant,z:0)
        }
        return(p(first)-p(second)).length
    }
    /// Both C roots are well-conditioned only in this barrier's legal range.
    /// General near-collapse inspection keeps its existing J/high algorithm.
    private static func spectrum(_ u:V,_ v:V)throws->Spectrum {
        let a=dot(u,u),b=dot(u,v),c=dot(v,v),d=hypot(a-c,2*b),lo=0.5*(a+c-d),hi=0.5*(a+c+d)
        guard lo>0,hi>0,[a,b,c,d,lo,hi].allSatisfy(\.isFinite) else {throw DeltaError.invalid("主伸长谱越过有效域。")}
        return .init(low:sqrt(lo),high:sqrt(hi),a:a,b:b,c:c,disc:d)
    }
    private static func validate(_ s:Spectrum,_ barrier:M.StrainBarrier)throws {
        guard s.low>barrier.lowerLimit,s.high<barrier.upperLimit else {throw DeltaError.invalid("实际候选主伸长越过严格屏障界限。")}
    }
    /// Bounded two-word arithmetic for barrier base values. This is still an
    /// estimate, not an interval/sign certificate. NaN propagates an unsupported
    /// exponent/domain until the caller rejects it as precisionUnresolved.
    private struct DD {
        var h:Double,l:Double
        init(_ x:Double){h=x;l=0;if !Self.range(x){h = .nan}}
        private init(_ h:Double,_ l:Double){self.h=h;self.l=l}
        static let zero=DD(0)
        static var invalid:DD {DD(.nan,0)}
        static func range(_ x:Double)->Bool {x.isFinite && (x==0 || (abs(x)>=1e-240 && abs(x)<=1e240))}
        static func twoSum(_ a:Double,_ b:Double)->(Double,Double) {let s=a+b,v=s-a;return(s,(a-(s-v))+(b-v))}
        static func norm(_ a:Double,_ b:Double)->DD {let(s,e)=twoSum(a,b);return range(s) && range(e) ? DD(s,e):.invalid}
        static prefix func -(_ a:DD)->DD {DD(-a.h,-a.l)}
        static func +(_ a:DD,_ b:DD)->DD {
            let(s,e)=twoSum(a.h,b.h), (t,f)=twoSum(a.l,b.l), (u,g)=twoSum(e,t), (v,k)=twoSum(s,u)
            return norm(v,(g+f)+k)
        }
        static func -(_ a:DD,_ b:DD)->DD {a + (-b)}
        static func product(_ a:Double,_ b:Double)->Double {
            if a==0 || b==0{return 0};let p=a*b
            return range(a) && range(b) && range(p) && p != 0 ? p:.nan
        }
        static func *(_ a:DD,_ b:DD)->DD {
            let p=product(a.h,b.h),error=(-p).addingProduct(a.h,b.h)
            let c=product(a.h,b.l),d=product(a.l,b.h),e=product(a.l,b.l)
            return norm(p,((error+c)+d)+e)
        }
        static func /(_ a:DD,_ b:DD)->DD {
            guard a.finite,b.finite,b.h != 0 else{return .invalid}
            let q=DD(a.h/b.h),r=a-b*q,q2=DD(r.h/b.h),first=q+q2,last=a-b*first
            return first+DD(last.h/b.h)
        }
        var finite:Bool {Self.range(h) && Self.range(l)}
        var value:Double {h+l}
        var positive:Bool {h>0 || (h==0 && l>0)}
        var negative:Bool {h<0 || (h==0 && l<0)}
        var isZero:Bool {h==0 && l==0}
        var absolute:DD {negative ? -self:self}
        func greater(_ b:DD)->Bool {h>b.h || (h==b.h && l>b.l)}
        func squareRoot()->DD {
            if isZero{return .zero};guard finite,positive else{return .invalid}
            let first=DD(sqrt(h)),second=(first+self/first)*DD(0.5)
            return (second+self/second)*DD(0.5)
        }
        func logarithm()->DD {
            guard finite,positive,h>0 else{return .invalid}
            return DD(log(h))+DD(log1p((DD(l)/DD(h)).value))
        }
        func logOnePlus()->DD {
            guard finite,(DD(1)+self).positive,1+h>0 else{return .invalid}
            let low=DD(l)/(DD(1)+DD(h))
            return DD(log1p(h))+DD(log1p(low.value))
        }
    }
    private struct DV {
        let x:DD,y:DD,z:DD
        init(_ p:V){x=DD(p.x);y=DD(p.y);z=DD(p.z)}
        init(_ x:DD,_ y:DD,_ z:DD){self.x=x;self.y=y;self.z=z}
        static func +(_ a:DV,_ b:DV)->DV {DV(a.x+b.x,a.y+b.y,a.z+b.z)}
        static func -(_ a:DV,_ b:DV)->DV {DV(a.x-b.x,a.y-b.y,a.z-b.z)}
        static func *(_ a:DV,_ s:DD)->DV {DV(a.x*s,a.y*s,a.z*s)}
        func dot(_ b:DV)->DD {x*b.x+y*b.y+z*b.z}
    }
    private struct DSpectrum {let low:DD,high:DD,a:DD,b:DD,c:DD,disc:DD}
    private static func dSpectrum(_ u:DV,_ v:DV)throws->DSpectrum {
        let a=u.dot(u),b=u.dot(v),c=v.dot(v),h=a-c,j=b*DD(2),d=(h*h+j*j).squareRoot()
        let low=((a+c-d)*DD(0.5)).squareRoot(),high=((a+c+d)*DD(0.5)).squareRoot()
        guard [a,b,c,d,low,high].allSatisfy(\.finite),low.positive,high.positive else{throw DeltaError.precisionUnresolved}
        return .init(low:low,high:high,a:a,b:b,c:c,disc:d)
    }
    private static func barrierNearestRounding()->Bool {
#if os(macOS)
        Darwin.fegetround()==Darwin.FE_TONEAREST
#elseif canImport(NativeClothCollision)
        FloatingPointEnvironment.isNearestRounding
#else
        false
#endif
    }
    private static func dColumns(_ a:DV,_ b:DV,_ c:DV,_ t:M.Triangle)->(DV,DV) {
        let e=b-a,f=c-a;return(e*DD(t.du.y)+f*DD(t.du.z),e*DD(t.dv.y)+f*DD(t.dv.z))
    }
    private static func barrierIncrement(_ x0:[V],_ x1:[V],_ t:M.Triangle,_ barrier:M.StrainBarrier)throws->(value:Double,scale:Double) {
        guard barrierNearestRounding() else{throw DeltaError.precisionUnresolved}
        let a=DV(x0[t.a]),b=DV(x0[t.b]),c=DV(x0[t.c]),aa=DV(x1[t.a]),bb=DV(x1[t.b]),cc=DV(x1[t.c])
        let(u,v)=dColumns(a,b,c,t),(du,dv)=dColumns(aa-a,bb-b,cc-c,t),(u1,v1)=dColumns(aa,bb,cc,t)
        let s=try dSpectrum(u,v),end=try dSpectrum(u1,v1),lower=DD(barrier.lowerLimit),upper=DD(barrier.upperLimit)
        guard s.low.greater(lower),upper.greater(s.high),end.low.greater(lower),upper.greater(end.high) else{throw DeltaError.invalid("实际候选主伸长越过严格屏障界限。")}
        let da=DD(2)*u.dot(du)+du.dot(du),dc=DD(2)*v.dot(dv)+dv.dot(dv),db=u.dot(dv)+v.dot(du)+du.dot(dv)
        let h=s.a-s.c,j=DD(2)*s.b,dh=da-dc,dj=DD(2)*db,d1=((h+dh)*(h+dh)+(j+dj)*(j+dj)).squareRoot()
        let denominator=s.disc+d1,dd:DD
        if denominator.isZero {dd = .zero}
        else {dd=(DD(2)*h*dh+dh*dh+DD(2)*j*dj+dj*dj)/denominator}
        let dt=da+dc,ll=(dt-dd)*DD(0.5),lh=(dt+dd)*DD(0.5)
        let dsLow=ll/((s.low*s.low+ll).squareRoot()+s.low),dsHigh=lh/((s.high*s.high+lh).squareRoot()+s.high)
        var value=DD.zero,scale=DD.zero
        for(base,ds)in[(s.low,dsLow),(s.high,dsHigh)] {
            guard [base,ds].allSatisfy(\.finite) else{throw DeltaError.precisionUnresolved}
            guard (base+ds).greater(lower),upper.greater(base+ds) else{throw DeltaError.invalid("主伸长增量越过严格屏障界限。")}
            for(activation,width,sign)in[(barrier.upperActivation,barrier.upperLimit-barrier.upperActivation,1.0),(barrier.lowerActivation,barrier.lowerActivation-barrier.lowerLimit,-1.0)] {
                let raw=DD(sign)*(base-DD(activation)),dr=DD(sign)*ds,yy=raw+dr
                guard raw.finite,dr.finite,yy.finite else{throw DeltaError.precisionUnresolved}
                let x=raw.positive ? raw:DD.zero,y=yy.positive ? yy:DD.zero
                if x.isZero && y.isZero{continue}
                let dx=x.positive && y.positive ? dr:(x.isZero ? y:-x),w=DD(width),r=w-x,r1=w-y
                guard r.positive,r1.positive else{throw DeltaError.invalid("主伸长标量屏障越界。")}
                let ell=(-x/w).logOnePlus(),de=(r*DD(0.5)).greater(dx.absolute) ? (-dx/r).logOnePlus():(r1/r).logarithm()
                let one=dx*(DD(2)*x+dx)*ell,two=y*y*de,k=DD(barrier.stiffnessNewtonPerMeter)
                value=value-k*(one+two);scale=scale+k*(one.absolute+two.absolute)
            }
        }
        guard barrierNearestRounding(),value.finite,scale.finite,value.value.isFinite,scale.value.isFinite else{throw DeltaError.precisionUnresolved}
        return(value.value,scale.value)
    }
    private static func hingeIncrement(_ x:[V],_ end:[V],_ step:[V],_ h:H.Hinge,_ kb:Double)throws->(value:Double,scale:Double) {
        let ids=h.vertexIDs,a=ids[0],b=ids[1],c=ids[2],d=ids[3]
        let e=x[b]-x[a],v=x[c]-x[a],w=x[d]-x[a],de=step[b]-step[a],dv=step[c]-step[a],dw=step[d]-step[a]
        let n1=e.cross(v),n2=w.cross(e),dn1=e.cross(dv)+de.cross(v)+de.cross(dv),dn2=w.cross(de)+dw.cross(e)+dw.cross(de),l=e.length,l1=(e+de).length
        let ee=end[b]-end[a],vv=end[c]-end[a],ww=end[d]-end[a],endN1=ee.cross(vv),endN2=ww.cross(ee)
        guard min(l,l1,ee.length)>h.sourceEdgeLengthMeters*1e-8,
              min(n1.length,endN1.length)>h.sourceFirstCrossNormSquareMeters*1e-8,
              min(n2.length,endN2.length)>h.sourceSecondCrossNormSquareMeters*1e-8 else {throw DeltaError.invalid("弯曲铰链退化。")}
        let q=n1.cross(n2),dq=n1.cross(dn2)+dn1.cross(n2)+dn1.cross(dn2),s=dot(e,q)/l,co=dot(n1,n2)
        let dl=(2*dot(e,de)+de.lengthSquared)/(l+l1),dt=sum([dot(e,dq),dot(de,q),dot(de,dq)])
        let ds=sum([dt,-s*dl])/(l+dl),dc=sum([dot(n1,dn2),dot(dn1,n2),dot(dn1,dn2)])
        let magnitude=max(abs(s),abs(co),abs(ds),abs(dc))
        guard magnitude.isFinite,magnitude>0 else {throw DeltaError.precisionUnresolved}
        let ss=s/magnitude,cc=co/magnitude,dss=ds/magnitude,dcc=dc/magnitude
        let theta=atan2(ss,cc),delta=atan2(sum([dss*cc,-dcc*ss]),sum([cc*cc,ss*ss,cc*dcc,ss*dss]))
        let candidateTheta=atan2(dot(ee,endN1.cross(endN2))/ee.length,dot(endN1,endN2))
        guard [theta,delta,candidateTheta].allSatisfy(\.isFinite),Double.pi-abs(theta)>1e-6,
              Double.pi-abs(candidateTheta)>1e-6,Double.pi-abs(theta+delta)>1e-6 else {throw DeltaError.invalid("弯曲增量越过正负 π 分支。")}
        let aTerm=2*theta*delta,bTerm=delta*delta,coefficient=kb*h.sourceWeight
        return(coefficient*sum([aTerm,bTerm]),coefficient*(abs(aTerm)+abs(bTerm)))
    }
}
