import Foundation
import Darwin
#if canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Finite subdivision of the actual straight particle motion. Weyl bounds at
/// interval centres cover the entire interval, rather than relying on samples.
/// The source deformation coefficients are immutable binary64 values. Basic
/// arithmetic and sqrt bounds are widened with nextDown/nextUp under nearest
/// rounding; unresolved or exhausted work never returns a clear path.
nonisolated enum GarmentCodeMembranePath {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias M=GarmentCodeMembrane
    enum PathError:LocalizedError,Sendable {
        case invalid(String),unsupportedRounding
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "裁片形变路径无效："+s
            case .unsupportedRounding:return "当前浮点舍入环境不支持裁片路径检查。"
            }
        }
    }
    struct Limits:Sendable {
        // Actual full-source safe motions needed depth nine. Increase proof
        // refinement only; the principal domain and global node cap stay fixed.
        var maximumDepth=12
        var maximumIntervalNodes=262_144
    }
    enum Status:String,Codable,Sendable {case clear,outsideDomain,indeterminate,budgetExceeded}
    struct Report:Codable,Sendable {
        let status:Status
        let completedAllTriangles:Bool
        let trianglesExamined:Int
        let intervalNodes:Int
        let subdividedNodes:Int
        let maximumDepthReached:Int
        /// Bounds over certified leaves only; nil if there are no clear leaves.
        let minimumCertifiedPrincipalStretch:Double?
        let maximumCertifiedPrincipalStretch:Double?
        let unresolvedTriangleID:Int?
        let witnessParameter:Double?
    }
    struct Prepared:Sendable {
        let membrane:M.Prepared
        let limits:Limits
        init(membrane:M.Prepared,limits:Limits=Limits())throws {
            guard (0...12).contains(limits.maximumDepth),(1...1_048_576).contains(limits.maximumIntervalNodes) else {
                throw PathError.invalid("分段深度或节点预算无效。")
            }
            self.membrane=membrane;self.limits=limits
        }
        /// Certifies x(t)=(1-t)*x0+t*x1 for 0<=t<=1. It does not replace the
        /// per-Newton-step feasible limit, body/self CCD, or final strain gate.
        func certify(from x0:[V],to x1:[V],barrier:M.StrainBarrier,
                     isCancelled:@Sendable()->Bool={false})throws->Report {
            if isCancelled(){throw CancellationError()}
            guard nearestRounding() else {throw PathError.unsupportedRounding}
            guard x0.count==membrane.vertexCount,x1.count==x0.count,
                  x0.allSatisfy({$0.isFinite && $0.length<100}),x1.allSatisfy({$0.isFinite && $0.length<100}) else {
                throw PathError.invalid("需要两组完整、有限且使用米的实际端点坐标。")
            }
            var nodes=0,splits=0,depth=0,triangles=0,minimum=Double.infinity,maximum = -Double.infinity
            func report(_ status:Status,_ id:Int?=nil,_ witness:Double?=nil)->Report {
                .init(status:status,completedAllTriangles:status == .clear,trianglesExamined:triangles,
                      intervalNodes:nodes,subdividedNodes:splits,maximumDepthReached:depth,
                      minimumCertifiedPrincipalStretch:minimum.isFinite ? minimum:nil,
                      maximumCertifiedPrincipalStretch:maximum.isFinite ? maximum:nil,
                      unresolvedTriangleID:id,witnessParameter:witness)
            }
            for (id,t) in membrane.triangles.enumerated() {
                if id%64==0 && isCancelled(){throw CancellationError()};triangles+=1
                let f0=columns(x0,t),f1=columns(x1,t)
                guard f0.allSatisfy(\.finite),f1.allSatisfy(\.finite) else {return report(.indeterminate,id)}
                let delta=zip(f1,f0).map{$0-$1},slope=normUpper(delta)
                guard slope.isFinite else {return report(.indeterminate,id)}
                for (parameter,columns) in [(0.0,f0),(1.0,f1)] {
                    guard let s=spectrum(columns) else {return report(.indeterminate,id,parameter)}
                    if s.minimum.upper<=barrier.lowerLimit || s.maximum.lower>=barrier.upperLimit {
                        return report(.outsideDomain,id,parameter)
                    }
                }
                var pending=[Segment(lower:0,upper:1,depth:0)]
                while let segment=pending.popLast() {
                    if nodes%32==0 && isCancelled(){throw CancellationError()}
                    guard nodes<limits.maximumIntervalNodes else {return report(.budgetExceeded,id)}
                    nodes+=1;depth=max(depth,segment.depth)
                    let middle=(segment.lower+segment.upper)*0.5,half=(segment.upper-segment.lower)*0.5
                    let centre=zip(f0,delta).map{$0+$1*I(middle)}
                    guard let s=spectrum(centre) else {return report(.indeterminate,id,middle)}
                    if s.minimum.upper<=barrier.lowerLimit || s.maximum.lower>=barrier.upperLimit {
                        return report(.outsideDomain,id,middle)
                    }
                    let radius=(slope*half).nextUp
                    let low=(s.minimum.lower-radius).nextDown,high=(s.maximum.upper+radius).nextUp
                    if low>barrier.lowerLimit && high<barrier.upperLimit {
                        minimum=min(minimum,low);maximum=max(maximum,high);continue
                    }
                    guard segment.depth<limits.maximumDepth else {return report(.indeterminate,id,middle)}
                    splits+=1
                    // Depth-first storage never exceeds maximumDepth+1 items.
                    pending.append(.init(lower:middle,upper:segment.upper,depth:segment.depth+1))
                    pending.append(.init(lower:segment.lower,upper:middle,depth:segment.depth+1))
                }
            }
            if isCancelled(){throw CancellationError()}
            guard nearestRounding() else {throw PathError.unsupportedRounding}
            return report(.clear)
        }
    }
    private struct Segment {let lower:Double,upper:Double,depth:Int}
    private static func nearestRounding()->Bool {
        #if os(macOS)
        return fegetround()==FE_TONEAREST
        #elseif canImport(NativeClothCollision)
        return FloatingPointEnvironment.isNearestRounding
        #else
        return false
        #endif
    }
    private struct Spectrum {let minimum:I,maximum:I}
    private struct I {
        let lower:Double,upper:Double
        init(_ x:Double){lower=x;upper=x}
        init(_ lower:Double,_ upper:Double){self.lower=lower;self.upper=upper}
        var finite:Bool {lower.isFinite && upper.isFinite && lower<=upper}
        static func +(_ a:I,_ b:I)->I {.init((a.lower+b.lower).nextDown,(a.upper+b.upper).nextUp)}
        static func -(_ a:I,_ b:I)->I {.init((a.lower-b.upper).nextDown,(a.upper-b.lower).nextUp)}
        static func *(_ a:I,_ b:I)->I {
            let ll=a.lower*b.lower,lu=a.lower*b.upper,ul=a.upper*b.lower,uu=a.upper*b.upper
            return .init(min(min(ll,lu),min(ul,uu)).nextDown,max(max(ll,lu),max(ul,uu)).nextUp)
        }
        var squared:I {
            let lo=lower*lower,hi=upper*upper
            if lower<=0 && upper>=0 {return .init(0,max(lo,hi).nextUp)}
            return .init(max(0,min(lo,hi).nextDown),max(lo,hi).nextUp)
        }
        var squareRoot:I? {
            guard finite,upper>=0 else {return nil}
            return .init(max(0,sqrt(max(0,lower)).nextDown),sqrt(upper).nextUp)
        }
    }
    private static func coordinates(_ v:V)->[I] {[I(v.x),I(v.y),I(v.z)]}
    private static func columns(_ x:[V],_ t:M.Triangle)->[I] {
        let a=coordinates(x[t.a]),b=coordinates(x[t.b]),c=coordinates(x[t.c])
        let e=zip(b,a).map{$0-$1},f=zip(c,a).map{$0-$1}
        return zip(e,f).map{$0*I(t.du[1])+$1*I(t.du[2])} + zip(e,f).map{$0*I(t.dv[1])+$1*I(t.dv[2])}
    }
    private static func normUpper(_ values:[I])->Double {
        var sum=0.0
        for value in values {
            let largest=max(abs(value.lower),abs(value.upper))
            sum=(sum+(largest*largest).nextUp).nextUp
        }
        return sqrt(max(0,sum)).nextUp
    }
    /// Interval Gram eigenvalues: all arithmetic, including the sqrt, is
    /// widened. This bounds both singular values of every enclosed 3x2 F.
    private static func spectrum(_ f:[I])->Spectrum? {
        guard f.count==6,f.allSatisfy(\.finite) else {return nil}
        var a=I(0),b=I(0),c=I(0)
        for i in 0..<3 {a=a+f[i].squared;b=b+f[i]*f[3+i];c=c+f[3+i].squared}
        let trace=a+c
        guard let disc=((a-c).squared+b.squared*I(4)).squareRoot,
              let low=((trace-disc)*I(0.5)).squareRoot,let high=((trace+disc)*I(0.5)).squareRoot else {return nil}
        return Spectrum(minimum:low,maximum:high)
    }
}
