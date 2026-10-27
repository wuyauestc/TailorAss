import Foundation
import CryptoKit

/// Independent whole-[0,1] Euclidean distance-separation certificate.
/// It does NOT certify primitive nondegeneracy, exterior bootstrap or topology.
/// A caller must retain those original independent domain/adjacency checks.
public enum FeatureSeparationCertificate {
    public typealias Vector=SIMD3<Double>
    private typealias V=Vector
    public enum Kind:String,Codable,Sendable {case vertexFace,edgeEdge}
    public enum Status:String,Codable,Sendable {case separated,notCertified,budgetExceeded,invalid,cancelled,unsupportedRounding}
    public enum Reason:String,Codable,Sendable {case invalidInput,invalidLimits,nodeBudget,workingMemoryBudget,depthLimit,cancelled,unsupportedRounding,expansionOperationBudget,expansionCapacity}
    public struct Limits:Sendable {
        public var maximumDepth=12
        public var maximumNodes=8191
        public var maximumEstimatedWorkingBytes=1_048_576
        public var recordLeafCertificates=false
        /// Additional EFT work only after both original proofs fail. Never a
        /// replacement for the unchanged time-node/depth or memory limits.
        public var maximumExpansionOperations=1_048_576
        public init() {}
    }
    public struct Report:Codable,Sendable {
        public let status:Status
        public let motionSHA256:String
        public let minimumSeparationMeters:Double
        public let processedNodes:Int,certifiedIntervals:Int,maximumDepthReached:Int
        public let minimumCertifiedDistanceLowerBoundMeters:Double?
        public let firstUnresolvedInterval:[Double]?
        public let leafCertificates:[LeafCertificate]
        public let reason:Reason?
        /// Conservative bounded Swift-array estimate, not process RSS.
        public let maximumEstimatedWorkingBytes:Int
        public let peakPendingIntervals:Int
        public let fixedIntervalsCertified:Int
        public let movingNormalAttempts:Int,movingNormalIntervalsCertified:Int
        public let movingNormalCertificates:[MovingNormalCertificate]
        public let expansionAttempts:Int,expansionIntervalsCertified:Int,expansionOperations:Int,maximumExpansionWords:Int
        public let expansionUnavailableReason:ExpansionFailure?
        public let expansionCertificates:[ExpansionCertificate]
        public let criticalAttempts:Int,criticalIntervalsCertified:Int
        public let criticalCertificates:[CriticalCertificate]
        public let affineNormalAttempts:Int,affineNormalIntervalsCertified:Int
        public let affineNormalCertificates:[AffineNormalCertificate]
        public var distanceSeparatedForWholeMotion:Bool {status == .separated}
        public var provesDistanceSeparationOnly:Bool {true}
        public var requiresIndependentPrimitiveDomainCertificate:Bool {true}
        private enum CodingKeys:String,CodingKey {
            case status,motionSHA256,minimumSeparationMeters,processedNodes,certifiedIntervals,maximumDepthReached
            case minimumCertifiedDistanceLowerBoundMeters,firstUnresolvedInterval,leafCertificates,reason
            case maximumEstimatedWorkingBytes,peakPendingIntervals,fixedIntervalsCertified,movingNormalAttempts
            case movingNormalIntervalsCertified,movingNormalCertificates
            case expansionAttempts,expansionIntervalsCertified,expansionOperations,maximumExpansionWords
            case expansionUnavailableReason,expansionCertificates,criticalAttempts,criticalIntervalsCertified,criticalCertificates
            case affineNormalAttempts,affineNormalIntervalsCertified,affineNormalCertificates
        }
        public init(from decoder:Decoder)throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            status=try c.decode(Status.self,forKey:.status);motionSHA256=try c.decode(String.self,forKey:.motionSHA256)
            minimumSeparationMeters=try c.decode(Double.self,forKey:.minimumSeparationMeters)
            processedNodes=try c.decode(Int.self,forKey:.processedNodes)
            let total=try c.decode(Int.self,forKey:.certifiedIntervals)
            certifiedIntervals=total;maximumDepthReached=try c.decode(Int.self,forKey:.maximumDepthReached)
            minimumCertifiedDistanceLowerBoundMeters=try c.decodeIfPresent(Double.self,forKey:.minimumCertifiedDistanceLowerBoundMeters)
            firstUnresolvedInterval=try c.decodeIfPresent([Double].self,forKey:.firstUnresolvedInterval)
            leafCertificates=try c.decode([LeafCertificate].self,forKey:.leafCertificates)
            reason=try c.decodeIfPresent(Reason.self,forKey:.reason)
            maximumEstimatedWorkingBytes=try c.decode(Int.self,forKey:.maximumEstimatedWorkingBytes)
            peakPendingIntervals=try c.decode(Int.self,forKey:.peakPendingIntervals)
            let moving=try c.decodeIfPresent(Int.self,forKey:.movingNormalIntervalsCertified) ?? 0
            movingNormalIntervalsCertified=moving
            movingNormalAttempts=try c.decodeIfPresent(Int.self,forKey:.movingNormalAttempts) ?? 0
            let exact=try c.decodeIfPresent(Int.self,forKey:.expansionIntervalsCertified) ?? 0
            expansionIntervalsCertified=exact
            expansionAttempts=try c.decodeIfPresent(Int.self,forKey:.expansionAttempts) ?? 0
            expansionOperations=try c.decodeIfPresent(Int.self,forKey:.expansionOperations) ?? 0
            maximumExpansionWords=try c.decodeIfPresent(Int.self,forKey:.maximumExpansionWords) ?? 0
            expansionUnavailableReason=try c.decodeIfPresent(ExpansionFailure.self,forKey:.expansionUnavailableReason)
            expansionCertificates=try c.decodeIfPresent([ExpansionCertificate].self,forKey:.expansionCertificates) ?? []
            criticalAttempts=try c.decodeIfPresent(Int.self,forKey:.criticalAttempts) ?? 0
            let critical=try c.decodeIfPresent(Int.self,forKey:.criticalIntervalsCertified) ?? 0
            criticalIntervalsCertified=critical
            criticalCertificates=try c.decodeIfPresent([CriticalCertificate].self,forKey:.criticalCertificates) ?? []
            affineNormalAttempts=try c.decodeIfPresent(Int.self,forKey:.affineNormalAttempts) ?? 0
            let affine=try c.decodeIfPresent(Int.self,forKey:.affineNormalIntervalsCertified) ?? 0
            affineNormalIntervalsCertified=affine
            affineNormalCertificates=try c.decodeIfPresent([AffineNormalCertificate].self,forKey:.affineNormalCertificates) ?? []
            fixedIntervalsCertified=try c.decodeIfPresent(Int.self,forKey:.fixedIntervalsCertified) ?? total-moving-exact-critical-affine
            movingNormalCertificates=try c.decodeIfPresent([MovingNormalCertificate].self,forKey:.movingNormalCertificates) ?? []
        }
        fileprivate init(status:Status,motionSHA256:String,minimumSeparationMeters:Double,processedNodes:Int,
            certifiedIntervals:Int,maximumDepthReached:Int,minimumCertifiedDistanceLowerBoundMeters:Double?,
            firstUnresolvedInterval:[Double]?,leafCertificates:[LeafCertificate],reason:Reason?,
            maximumEstimatedWorkingBytes:Int,peakPendingIntervals:Int,fixedIntervalsCertified:Int,
            movingNormalAttempts:Int,movingNormalIntervalsCertified:Int,movingNormalCertificates:[MovingNormalCertificate],
            expansionAttempts:Int,expansionIntervalsCertified:Int,expansionOperations:Int,maximumExpansionWords:Int,
            expansionUnavailableReason:ExpansionFailure?,expansionCertificates:[ExpansionCertificate],
            criticalAttempts:Int,criticalIntervalsCertified:Int,criticalCertificates:[CriticalCertificate],
            affineNormalAttempts:Int,affineNormalIntervalsCertified:Int,affineNormalCertificates:[AffineNormalCertificate]) {
            self.status=status;self.motionSHA256=motionSHA256;self.minimumSeparationMeters=minimumSeparationMeters
            self.processedNodes=processedNodes;self.certifiedIntervals=certifiedIntervals;self.maximumDepthReached=maximumDepthReached
            self.minimumCertifiedDistanceLowerBoundMeters=minimumCertifiedDistanceLowerBoundMeters
            self.firstUnresolvedInterval=firstUnresolvedInterval;self.leafCertificates=leafCertificates;self.reason=reason
            self.maximumEstimatedWorkingBytes=maximumEstimatedWorkingBytes;self.peakPendingIntervals=peakPendingIntervals
            self.fixedIntervalsCertified=fixedIntervalsCertified;self.movingNormalAttempts=movingNormalAttempts
            self.movingNormalIntervalsCertified=movingNormalIntervalsCertified;self.movingNormalCertificates=movingNormalCertificates
            self.expansionAttempts=expansionAttempts;self.expansionIntervalsCertified=expansionIntervalsCertified
            self.expansionOperations=expansionOperations;self.maximumExpansionWords=maximumExpansionWords
            self.expansionUnavailableReason=expansionUnavailableReason;self.expansionCertificates=expansionCertificates
            self.criticalAttempts=criticalAttempts;self.criticalIntervalsCertified=criticalIntervalsCertified
            self.criticalCertificates=criticalCertificates
            self.affineNormalAttempts=affineNormalAttempts;self.affineNormalIntervalsCertified=affineNormalIntervalsCertified
            self.affineNormalCertificates=affineNormalCertificates
        }
    }
    /// Optional bounded diagnostic trace; no domain or advancement permission.
    public struct LeafCertificate:Codable,Sendable {
        public let startTime:Double,endTime:Double
        public let direction:Vector
        public let projectionLowerBound:Double
        public let directionNormUpperBound:Double
        public let requiredProductUpperBound:Double
        public let distanceLowerBoundMeters:Double
    }
    public struct ScalarBounds:Codable,Sendable {public let lower:Double,upper:Double}
    public struct VectorBounds:Codable,Sendable {public let x:ScalarBounds,y:ScalarBounds,z:ScalarBounds}
    /// Separate trace for n(t), not a reinterpretation of a fixed direction.
    /// All controls are Bernstein controls on THIS local time range [0,1].
    public struct MovingNormalCertificate:Codable,Sendable {
        public let startTime:Double,endTime:Double,kind:Kind
        public let projectionSign:Int
        public let normalBernsteinBounds:[VectorBounds]
        public let projectionBernsteinBounds:[ScalarBounds]
        public let absoluteProjectionLowerBound:Double
        public let normalNormUpperBound:Double,requiredProductUpperBound:Double
        public let distanceLowerBoundMeters:Double
    }
    /// Arbitrary affine normal proposal; every true vertex-pair projection
    /// is independently bounded. No orthogonality/closest-feature assumption.
    public enum AffineQuadraticProofKind:String,Codable,Sendable {case concaveOrLinear,endpointMinimum,positiveInteriorMinimum}
    public struct AffineProjectionCertificate:Codable,Sendable {
        public let firstVertex:Int,secondVertex:Int
        /// Scale TWO Bernstein coefficients and a,b,c power coefficients.
        public let scaledBernsteinBounds:[ScalarBounds],scaledPowerBounds:[ScalarBounds]
        public let proofKind:AffineQuadraticProofKind
        public let interiorNumeratorBounds:ScalarBounds?
        public let scaledProjectionLowerBound:Double
    }
    public struct AffineNormalCertificate:Codable,Sendable {
        public let startTime:Double,endTime:Double,kind:Kind,projectionScale:Int
        public let startDirection:Vector,endDirection:Vector
        public let projections:[AffineProjectionCertificate]
        public let scaledProjectionLowerBound:Double,normalNormUpperBound:Double
        public let requiredScaledProductUpperBound:Double,distanceLowerBoundMeters:Double
    }
    public enum ExpansionFailure:String,Codable,Sendable {case underflow,nonfinite,wordCapacity}
    /// Exact stored-binary controls start with scale THREE; bounded integer
    /// degree elevation multiplies the tracked common positive scale. This is
    /// neither a fixed-direction nor an ordinary interval-moving trace.
    public struct ExpansionCertificate:Codable,Sendable {
        public let startTime:Double,endTime:Double,kind:Kind,projectionScale:Int
        public let projectionDegree:Int
        public let projectionSign:Int
        public let scaledProjectionBernsteinBounds:[ScalarBounds]
        public let normalBernsteinBounds:[VectorBounds]
        public let absoluteScaledProjectionLowerBound:Double
        public let normalNormUpperBound:Double,requiredScaledProductUpperBound:Double
        public let distanceLowerBoundMeters:Double
        private enum CodingKeys:String,CodingKey {
            case startTime,endTime,kind,projectionScale,projectionDegree,projectionSign,scaledProjectionBernsteinBounds
            case normalBernsteinBounds,absoluteScaledProjectionLowerBound,normalNormUpperBound,requiredScaledProductUpperBound,distanceLowerBoundMeters
        }
        public init(from decoder:Decoder)throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            startTime=try c.decode(Double.self,forKey:.startTime);endTime=try c.decode(Double.self,forKey:.endTime)
            kind=try c.decode(Kind.self,forKey:.kind);projectionScale=try c.decode(Int.self,forKey:.projectionScale)
            scaledProjectionBernsteinBounds=try c.decode([ScalarBounds].self,forKey:.scaledProjectionBernsteinBounds)
            projectionDegree=try c.decodeIfPresent(Int.self,forKey:.projectionDegree) ?? scaledProjectionBernsteinBounds.count-1
            projectionSign=try c.decode(Int.self,forKey:.projectionSign)
            normalBernsteinBounds=try c.decode([VectorBounds].self,forKey:.normalBernsteinBounds)
            absoluteScaledProjectionLowerBound=try c.decode(Double.self,forKey:.absoluteScaledProjectionLowerBound)
            normalNormUpperBound=try c.decode(Double.self,forKey:.normalNormUpperBound)
            requiredScaledProductUpperBound=try c.decode(Double.self,forKey:.requiredScaledProductUpperBound)
            distanceLowerBoundMeters=try c.decode(Double.self,forKey:.distanceLowerBoundMeters)
        }
        fileprivate init(startTime:Double,endTime:Double,kind:Kind,projectionScale:Int,projectionDegree:Int,projectionSign:Int,
            scaledProjectionBernsteinBounds:[ScalarBounds],normalBernsteinBounds:[VectorBounds],
            absoluteScaledProjectionLowerBound:Double,normalNormUpperBound:Double,requiredScaledProductUpperBound:Double,distanceLowerBoundMeters:Double) {
            self.startTime=startTime;self.endTime=endTime;self.kind=kind;self.projectionScale=projectionScale;self.projectionDegree=projectionDegree
            self.projectionSign=projectionSign;self.scaledProjectionBernsteinBounds=scaledProjectionBernsteinBounds
            self.normalBernsteinBounds=normalBernsteinBounds;self.absoluteScaledProjectionLowerBound=absoluteScaledProjectionLowerBound
            self.normalNormUpperBound=normalNormUpperBound;self.requiredScaledProductUpperBound=requiredScaledProductUpperBound
            self.distanceLowerBoundMeters=distanceLowerBoundMeters
        }
    }
    /// A separate critical-value proof, NOT an all-positive Bernstein hull.
    /// Its polynomial is projectionSign * 2^binaryNormalizationExponent * 3g
    /// on this local [0,1]. It applies ONLY to a zero distance shell. Original
    /// normal/domain/full-feature checks remain independently necessary.
    public enum CriticalProofKind:String,Codable,Sendable {case monotoneCubic,positiveCubicMinimum,concaveOrLinear,positiveQuadraticMinimum}
    public struct CriticalCertificate:Codable,Sendable {
        public let startTime:Double,endTime:Double,kind:Kind
        public let proofKind:CriticalProofKind
        public let projectionScale:Int,projectionSign:Int,binaryNormalizationExponent:Int
        /// a,b,c,d in a*t^3+b*t^2+c*t+d, after exact signed binary scaling.
        public let normalizedPowerCoefficientBounds:[ScalarBounds]
        public let normalizedEndpointBounds:[ScalarBounds]
        public let derivativeDiscriminantBounds:ScalarBounds?
        public let cubicHBounds:ScalarBounds?,cubicDiscriminantBounds:ScalarBounds?
        public let quadraticNumeratorBounds:ScalarBounds?
        public let normalBernsteinBounds:[VectorBounds]
        public let absoluteNormalizedProjectionLowerBound:Double
        public let normalNormUpperBound:Double,distanceLowerBoundMeters:Double
    }
    // Exact nonoverlapping expansions of the stored binary64 inputs. This is
    // a filtered extra proof, not a new primitive domain or collision policy.
    enum ExpansionError:Error {case operations,capacity,underflow,nonfinite,cancelled,rounding}
    typealias E=[Double]
    typealias EV=[E]
    struct ExpansionWork {
        let maximumOperations:Int
        var operations=0,maximumWords=0
        mutating func tick(_ cancelled:()->Bool)throws {
            if cancelled(){throw ExpansionError.cancelled}
            guard nearestRounding() else{throw ExpansionError.rounding}
            guard operations<maximumOperations else{throw ExpansionError.operations}
            operations+=1
        }
        mutating func checked(_ a:E)throws->E {
            guard a.count<=64 else{throw ExpansionError.capacity}
            guard a.allSatisfy(\.isFinite) else{throw ExpansionError.nonfinite}
            maximumWords=max(maximumWords,a.count);return a
        }
        mutating func twoSum(_ a:Double,_ b:Double,_ cancelled:()->Bool)throws->(Double,Double) {
            try tick(cancelled)
            let s=a+b,bv=s-a,av=s-bv,br=b-bv,ar=a-av,e=ar+br
            guard [s,bv,av,br,ar,e].allSatisfy(\.isFinite) else{throw ExpansionError.nonfinite}
            return(s,e)
        }
        // The least set significand bit gives a sufficient, exact lattice
        // test: no bit in a*b may lie below the smallest binary64 subnormal.
        // Without it a rounded FMA residual would not be an exact EFT.
        static func lowBit(_ x:Double)->Int {
            let bits=x.bitPattern & 0x7fff_ffff_ffff_ffff
            let exponent=Int((bits>>52)&0x7ff),fraction=bits&0x000f_ffff_ffff_ffff
            let significand=exponent==0 ? fraction:fraction|(1<<52)
            return (exponent==0 ? -1074:exponent-1023-52)+significand.trailingZeroBitCount
        }
        mutating func twoProduct(_ a:Double,_ b:Double,_ cancelled:()->Bool)throws->(Double,Double) {
            try tick(cancelled)
            if a==0 || b==0 {return(0,0)}
            guard Self.lowBit(a)+Self.lowBit(b)>=(-1074) else{throw ExpansionError.underflow}
            let p=a*b,e=(-p).addingProduct(a,b)
            guard p.isFinite,e.isFinite else{throw ExpansionError.nonfinite}
            return(p,e)
        }
        mutating func grow(_ a:E,_ b:Double,_ cancelled:()->Bool)throws->E {
            if b==0{return a}
            var q=b,out:E=[];out.reserveCapacity(min(64,a.count+1))
            for v in a {
                let(s,e)=try twoSum(q,v,cancelled)
                if e != 0 {guard out.count<64 else{throw ExpansionError.capacity};out.append(e)}
                q=s
            }
            if q != 0 {guard out.count<64 else{throw ExpansionError.capacity};out.append(q)}
            return try checked(out)
        }
        mutating func sum(_ a:E,_ b:E,_ cancelled:()->Bool)throws->E {
            var out=a
            for v in b {out=try grow(out,v,cancelled)}
            return try checked(out)
        }
        mutating func subtract(_ a:E,_ b:E,_ cancelled:()->Bool)throws->E {
            try sum(a,b.map{-$0},cancelled)
        }
        mutating func product(_ a:E,_ b:E,_ cancelled:()->Bool)throws->E {
            var out:E=[]
            for x in a {for y in b {
                let(p,e)=try twoProduct(x,y,cancelled)
                out=try grow(out,e,cancelled);out=try grow(out,p,cancelled)
            }}
            return try checked(out)
        }
        mutating func scale(_ a:E,_ b:Double,_ cancelled:()->Bool)throws->E {
            try product(a,b==0 ? []:[b],cancelled)
        }
        mutating func vectorSum(_ a:EV,_ b:EV,_ cancelled:()->Bool)throws->EV {
            var out:EV=[]
            for i in 0..<3 {out.append(try sum(a[i],b[i],cancelled))}
            return out
        }
        mutating func cross(_ a:EV,_ b:EV,_ cancelled:()->Bool)throws->EV {
            var out:EV=[]
            for (i,j) in [(1,2),(2,0),(0,1)] {
                let p=try product(a[i],b[j],cancelled),q=try product(a[j],b[i],cancelled)
                out.append(try subtract(p,q,cancelled))
            }
            return out
        }
        mutating func dot(_ a:EV,_ b:EV,_ cancelled:()->Bool)throws->E {
            var out:E=[]
            for i in 0..<3 {let p=try product(a[i],b[i],cancelled);out=try sum(out,p,cancelled)}
            return out
        }
        /// Integer-scaled elevation represents nextDegree times the SAME
        /// polynomial. No division or new nonbinary interpolation factor.
        mutating func elevate(_ controls:[E],_ cancelled:()->Bool)throws->[E] {
            let nextDegree=controls.count
            guard (4...8).contains(nextDegree) else{throw ExpansionError.nonfinite}
            var result:[E]=[];result.reserveCapacity(nextDegree+1)
            result.append(try scale(controls[0],Double(nextDegree),cancelled))
            for k in 1..<nextDegree {
                let left=try scale(controls[k-1],Double(k),cancelled)
                let right=try scale(controls[k],Double(nextDegree-k),cancelled)
                result.append(try sum(left,right,cancelled))
            }
            result.append(try scale(controls[nextDegree-1],Double(nextDegree),cancelled))
            return result
        }
        mutating func split(_ controls:[E],_ cancelled:()->Bool)throws->([E],[E]) {
            var row=controls,left=[controls[0]],right=[controls[3]]
            for _ in 0..<3 {
                var next:[E]=[]
                for i in 0..<(row.count-1) {
                    let s=try sum(row[i],row[i+1],cancelled)
                    next.append(try scale(s,0.5,cancelled))
                }
                row=next;left.append(row[0]);right.append(row[row.count-1])
            }
            return(left,Array(right.reversed()))
        }
    }
    private static func exactRelative(_ points:[V],_ a:Int,_ b:Int,_ work:inout ExpansionWork,_ cancelled:()->Bool)throws->EV {
        var out:EV=[]
        for k in 0..<3 {
            let x=points[a][k],y=points[b][k]
            out.append(try work.subtract(x==0 ? []:[x],y==0 ? []:[y],cancelled))
        }
        return out
    }
    private static func exactProjectionPolynomial(_ kind:Kind,_ start:[V],_ end:[V],_ work:inout ExpansionWork,_ cancelled:()->Bool)throws->[E] {
        let indices=kind == .vertexFace ? [(2,1),(3,1),(0,1)]:[(1,0),(3,2),(0,2)]
        let u0=try exactRelative(start,indices[0].0,indices[0].1,&work,cancelled)
        let u1=try exactRelative(end,indices[0].0,indices[0].1,&work,cancelled)
        let v0=try exactRelative(start,indices[1].0,indices[1].1,&work,cancelled)
        let v1=try exactRelative(end,indices[1].0,indices[1].1,&work,cancelled)
        let w0=try exactRelative(start,indices[2].0,indices[2].1,&work,cancelled)
        let w1=try exactRelative(end,indices[2].0,indices[2].1,&work,cancelled)
        let n0=try work.cross(u0,v0,cancelled),n2=try work.cross(u1,v1,cancelled)
        let a=try work.cross(u0,v1,cancelled),b=try work.cross(u1,v0,cancelled)
        let mixed=try work.vectorSum(a,b,cancelled)
        let p0=try work.dot(w0,n0,cancelled),p3=try work.dot(w1,n2,cancelled)
        let a1=try work.dot(w0,mixed,cancelled),b1=try work.dot(w1,n0,cancelled)
        let a2=try work.dot(w0,n2,cancelled),b2=try work.dot(w1,mixed,cancelled)
        let g0=try work.scale(p0,3,cancelled),g1=try work.sum(a1,b1,cancelled)
        let g2=try work.sum(a2,b2,cancelled),g3=try work.scale(p3,3,cancelled)
        return[g0,g1,g2,g3]
    }
    private static func certifiedExpansion(_ kind:Kind,_ start:[V],_ end:[V],_ range:Range,_ floor:Double,
        _ global:[E],_ work:inout ExpansionWork,_ cancelled:()->Bool)throws->ExpansionCertificate? {
        var controls=global
        let divisor=1<<range.depth,index=Int(range.a*Double(divisor))
        guard Double(index)/Double(divisor)==range.a else{throw ExpansionError.nonfinite}
        for bit in (0..<range.depth).reversed() {
            let(left,right)=try work.split(controls,cancelled)
            controls=((index>>bit)&1)==0 ? left:right
        }
        // The original outward normal controls remain a valid norm bound;
        // only cancellation-sensitive projection coefficients use expansions.
        func point(_ i:Int,_ t:Double)->IV {let a=IV(start[i]);return a+(IV(end[i])-a)*I(t)}
        let a=start.indices.map{point($0,range.a)},b=start.indices.map{point($0,range.b)}
        let u0:IV,u1:IV,v0:IV,v1:IV
        if kind == .vertexFace {u0=a[2]-a[1];u1=b[2]-b[1];v0=a[3]-a[1];v1=b[3]-b[1]}
        else {u0=a[1]-a[0];u1=b[1]-b[0];v0=a[3]-a[2];v1=b[3]-b[2]}
        let normals=[u0.cross(v0),(u0.cross(v1)+u1.cross(v0))*I(0.5),u1.cross(v1)]
        guard normals.allSatisfy(\.finite) else{throw ExpansionError.nonfinite}
        func maximum(_ a:[I])->Double {a.reduce(0){max($0,max(abs($1.lo),abs($1.hi)))}}
        let nx=I(maximum(normals.map(\.x))),ny=I(maximum(normals.map(\.y))),nz=I(maximum(normals.map(\.z)))
        let n2=nx*nx+ny*ny+nz*nz
        guard n2.finite,n2.hi>0 else{return nil}
        let norm=sqrt(n2.hi).nextUp
        guard norm.isFinite else{return nil}
        func scalar(_ i:I)->ScalarBounds {.init(lower:i.lo,upper:i.hi)}
        func vector(_ v:IV)->VectorBounds {.init(x:scalar(v.x),y:scalar(v.y),z:scalar(v.z))}
        var degree=3,scale=3
        while true {
            if cancelled(){throw ExpansionError.cancelled}
            guard nearestRounding() else{throw ExpansionError.rounding}
            let bounds=controls.map{words->I in words.reduce(I(0)){$0+I($1)}}
            guard bounds.allSatisfy(\.finite) else{throw ExpansionError.nonfinite}
            let low=bounds.map(\.lo).min()!,high=bounds.map(\.hi).max()!
            let sign:Int,absoluteLower:Double
            if low>0 {sign=1;absoluteLower=low} else if high<0 {sign = -1;absoluteLower = -high} else{sign=0;absoluteLower=0}
            let denominator=(I(Double(scale))*I(norm)).hi,required=(I(floor)*I(denominator)).hi
            guard denominator.isFinite,required.isFinite else{throw ExpansionError.nonfinite}
            if sign != 0 && absoluteLower>required {
                return .init(startTime:range.a,endTime:range.b,kind:kind,projectionScale:scale,projectionDegree:degree,projectionSign:sign,
                    scaledProjectionBernsteinBounds:bounds.map(scalar),normalBernsteinBounds:normals.map(vector),
                    absoluteScaledProjectionLowerBound:absoluteLower,normalNormUpperBound:norm,
                    requiredScaledProductUpperBound:required,distanceLowerBoundMeters:max(0,(absoluteLower/denominator).nextDown))
            }
            guard degree<8 else{return nil}
            controls=try work.elevate(controls,cancelled)
            degree+=1;scale*=degree
        }
    }
    /// Bounded exact polynomial filter. No root approximation, epsilon, shell
    /// reduction or increased subdivision budget is used. At most 64 live
    /// 64-word arrays (including expression temporaries/COW capacity) fit the
    /// existing 128 KiB expansion scratch reservation; every EFT is charged.
    private static func certifiedCritical(_ kind:Kind,_ start:[V],_ end:[V],_ range:Range,
        _ global:[E],_ work:inout ExpansionWork,_ cancelled:()->Bool)throws->CriticalCertificate? {
        var controls=global
        let divisor=1<<range.depth,index=Int(range.a*Double(divisor))
        guard Double(index)/Double(divisor)==range.a else{throw ExpansionError.nonfinite}
        for bit in (0..<range.depth).reversed() {
            let(left,right)=try work.split(controls,cancelled)
            controls=((index>>bit)&1)==0 ? left:right
        }
        func interval(_ e:E)->I {e.reduce(I(0)){$0+I($1)}}
        func scalar(_ i:I)->ScalarBounds {.init(lower:i.lo,upper:i.hi)}
        func vector(_ v:IV)->VectorBounds {.init(x:scalar(v.x),y:scalar(v.y),z:scalar(v.z))}
        let first=interval(controls[0]),last=interval(controls[3])
        let sign:Int
        if first.lo>0 && last.lo>0 {sign=1}
        else if first.hi<0 && last.hi<0 {sign = -1}
        else{return nil}
        if sign<0 {controls=controls.map{$0.map{-$0}}}
        // Convert the SAME restricted cubic, retaining its original scale 3.
        let d0=controls[0]
        let c0=try work.scale(work.subtract(controls[1],controls[0],cancelled),3,cancelled)
        let b01=try work.subtract(controls[0],work.scale(controls[1],2,cancelled),cancelled)
        let b0=try work.scale(work.sum(b01,controls[2],cancelled),3,cancelled)
        let a01=try work.subtract(work.scale(controls[1],3,cancelled),controls[0],cancelled)
        let a02=try work.subtract(a01,work.scale(controls[2],3,cancelled),cancelled)
        let a0=try work.sum(a02,controls[3],cancelled)
        let raw=[a0,b0,c0,d0]
        let maximum=raw.flatMap{$0}.reduce(0){max($0,abs($1))}
        guard maximum>0,maximum.isFinite else{return nil}
        // Positive power-of-two normalization changes no sign. Restrict its
        // exponent to keep the scale and inverse finite; individual EFTs still
        // reject lost low bits, nonfinite products and the original word cap.
        let exponent=max(-512,min(512,-maximum.exponent))
        let scale=Double(sign:.plus,exponent:exponent,significand:1)
        var coefficients:[E]=[]
        for x in raw {coefficients.append(try work.scale(x,scale,cancelled))}
        let a=coefficients[0],b=coefficients[1],c=coefficients[2],d=coefficients[3]
        var endCoefficient=d
        for x in [a,b,c] {endCoefficient=try work.sum(endCoefficient,x,cancelled)}
        let bounds=coefficients.map(interval),endpoints=[interval(d),interval(endCoefficient)]
        guard bounds.allSatisfy(\.finite),endpoints.allSatisfy({$0.finite && $0.lo>0}) else{return nil}
        func exactSign(_ e:E)->Int {guard let x=e.last else{return 0};return x>0 ? 1:-1}
        var lower=min(endpoints[0].lo,endpoints[1].lo)
        var D:I?,H:I?,disc:I?,quadratic:I?
        let proofKind:CriticalProofKind
        if exactSign(a)==0 {
            if exactSign(b)<=0 {proofKind = .concaveOrLinear}
            else {
                let bd=try work.product(b,d,cancelled),cc=try work.product(c,c,cancelled)
                let numerator=try work.subtract(work.scale(bd,4,cancelled),cc,cancelled)
                let q=interval(numerator),denominator=(I(4)*bounds[1]).hi
                guard exactSign(numerator)>0,q.finite,q.lo>0,denominator.isFinite,denominator>0 else{return nil}
                let minimum=(q.lo/denominator).nextDown
                guard minimum.isFinite,minimum>0 else{return nil}
                lower=min(lower,minimum);quadratic=q;proofKind = .positiveQuadraticMinimum
            }
        } else {
            let bb=try work.product(b,b,cancelled),ac=try work.product(a,c,cancelled)
            let de=try work.subtract(bb,work.scale(ac,3,cancelled),cancelled)
            D=interval(de)
            if exactSign(de)<=0 {proofKind = .monotoneCubic}
            else {
                // H=2b^3-9abc+27a^2d and Disc degree FOUR, avoiding
                // cancellation in the degree-six H^2-4D^3 expression.
                let bbb=try work.product(bb,b,cancelled),aa=try work.product(a,a,cancelled)
                let abc=try work.product(ac,b,cancelled),aad=try work.product(aa,d,cancelled)
                let h1=try work.subtract(work.scale(bbb,2,cancelled),work.scale(abc,9,cancelled),cancelled)
                let he=try work.sum(h1,work.scale(aad,27,cancelled),cancelled)
                guard exactSign(he)>0 else{return nil}
                let abcd=try work.product(abc,d,cancelled),bbbd=try work.product(bbb,d,cancelled)
                let cc=try work.product(c,c,cancelled),bbcc=try work.product(bb,cc,cancelled)
                let accc=try work.product(ac,cc,cancelled),aadd=try work.product(aad,d,cancelled)
                var disce=try work.subtract(work.scale(abcd,18,cancelled),work.scale(bbbd,4,cancelled),cancelled)
                disce=try work.sum(disce,bbcc,cancelled)
                disce=try work.subtract(disce,work.scale(accc,4,cancelled),cancelled)
                disce=try work.subtract(disce,work.scale(aadd,27,cancelled),cancelled)
                guard exactSign(disce)<0 else{return nil}
                let di=interval(de),hi=interval(he),ci=interval(disce)
                guard di.finite,di.hi>0,hi.finite,hi.lo>0,ci.finite,ci.hi<0 else{return nil}
                let root=sqrt(di.hi).nextUp
                let denominator=(hi+I(2)*I(di.hi)*I(root)).hi
                guard root.isFinite,denominator.isFinite,denominator>0 else{return nil}
                // Rationalized true local minimum: -Disc/(H+2D*sqrt(D)).
                // Disc.upper<0 gives the correct POSITIVE numerator lower.
                let minimum=((-ci.hi)/denominator).nextDown
                guard minimum.isFinite,minimum>0 else{return nil}
                lower=min(lower,minimum);H=hi;disc=ci;proofKind = .positiveCubicMinimum
            }
        }
        // The same outward quadratic normal bound used by previous filters.
        func point(_ i:Int,_ t:Double)->IV {let a=IV(start[i]);return a+(IV(end[i])-a)*I(t)}
        let x=start.indices.map{point($0,range.a)},y=start.indices.map{point($0,range.b)}
        let u0:IV,u1:IV,v0:IV,v1:IV
        if kind == .vertexFace {u0=x[2]-x[1];u1=y[2]-y[1];v0=x[3]-x[1];v1=y[3]-y[1]}
        else {u0=x[1]-x[0];u1=y[1]-y[0];v0=x[3]-x[2];v1=y[3]-y[2]}
        let normals=[u0.cross(v0),(u0.cross(v1)+u1.cross(v0))*I(0.5),u1.cross(v1)]
        guard normals.allSatisfy(\.finite) else{throw ExpansionError.nonfinite}
        func maximumBound(_ a:[I])->Double {a.reduce(0){max($0,max(abs($1.lo),abs($1.hi)))}}
        let nx=I(maximumBound(normals.map(\.x))),ny=I(maximumBound(normals.map(\.y))),nz=I(maximumBound(normals.map(\.z)))
        let n2=nx*nx+ny*ny+nz*nz
        guard n2.finite,n2.hi>0 else{return nil}
        let norm=sqrt(n2.hi).nextUp
        let denominator=(I(scale)*I(3)*I(norm)).hi
        guard norm.isFinite,denominator.isFinite,denominator>0 else{return nil}
        let distance=(lower/denominator).nextDown
        guard distance.isFinite,distance>0 else{return nil}
        if cancelled(){throw ExpansionError.cancelled}
        guard nearestRounding() else{throw ExpansionError.rounding}
        return .init(startTime:range.a,endTime:range.b,kind:kind,proofKind:proofKind,
            projectionScale:3,projectionSign:sign,binaryNormalizationExponent:exponent,
            normalizedPowerCoefficientBounds:bounds.map(scalar),normalizedEndpointBounds:endpoints.map(scalar),
            derivativeDiscriminantBounds:D.map(scalar),cubicHBounds:H.map(scalar),cubicDiscriminantBounds:disc.map(scalar),
            quadraticNumeratorBounds:quadratic.map(scalar),normalBernsteinBounds:normals.map(vector),
            absoluteNormalizedProjectionLowerBound:lower,normalNormUpperBound:norm,distanceLowerBoundMeters:distance)
    }
    private struct I {
        let lo:Double,hi:Double
        init(_ x:Double){lo=x;hi=x}
        init(_ lo:Double,_ hi:Double){self.lo=lo;self.hi=hi}
        static func +(a:Self,b:Self)->Self {.init((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp)}
        static func -(a:Self,b:Self)->Self {.init((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp)}
        static func *(a:Self,b:Self)->Self {
            let p=a.lo*b.lo,q=a.lo*b.hi,r=a.hi*b.lo,s=a.hi*b.hi
            return .init(min(min(p,q),min(r,s)).nextDown,max(max(p,q),max(r,s)).nextUp)
        }
        var finite:Bool {lo.isFinite && hi.isFinite && lo<=hi}
    }
    private struct IV {
        let x:I,y:I,z:I
        init(_ v:V){x=I(v.x);y=I(v.y);z=I(v.z)}
        init(_ x:I,_ y:I,_ z:I){self.x=x;self.y=y;self.z=z}
        static func +(a:Self,b:Self)->Self {.init(a.x+b.x,a.y+b.y,a.z+b.z)}
        static func -(a:Self,b:Self)->Self {.init(a.x-b.x,a.y-b.y,a.z-b.z)}
        static func *(a:Self,b:I)->Self {.init(a.x*b,a.y*b,a.z*b)}
        func dot(_ b:Self)->I {x*b.x+y*b.y+z*b.z}
        func cross(_ b:Self)->Self {.init(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x)}
        var finite:Bool {x.finite && y.finite && z.finite}
    }
    private struct Range {let a:Double,b:Double;let depth:Int}
    public static func certify(kind:Kind,start:[Vector],end:[Vector],minimumSeparation:Double,limits:Limits=Limits(),
                        isCancelled:()->Bool={false})->Report {
        var nodes=0,leaves=0,depth=0,minimum:Double?,certificates:[LeafCertificate]=[]
        var fixedLeaves=0,movingAttempts=0,movingLeaves=0,movingCertificates:[MovingNormalCertificate]=[]
        var estimatedBytes=0,peakPending=0
        var exact=ExpansionWork(maximumOperations:limits.maximumExpansionOperations)
        var exactPolynomial:[[Double]]?,exactUnavailable:ExpansionFailure?
        var exactAttempts=0,exactLeaves=0,exactCertificates:[ExpansionCertificate]=[],exactReserved=false
        var criticalAttempts=0,criticalLeaves=0,criticalCertificates:[CriticalCertificate]=[]
        var affineAttempts=0,affineLeaves=0,affineCertificates:[AffineNormalCertificate]=[]
        let hash=start.count==4 && end.count==4 ? motionHash(kind,start,end,minimumSeparation):String(repeating:"0",count:64)
        func report(_ status:Status,_ r:Range?=nil,_ reason:Reason?=nil)->Report {
            .init(status:status,motionSHA256:hash,minimumSeparationMeters:minimumSeparation,
                  processedNodes:nodes,certifiedIntervals:leaves,maximumDepthReached:depth,
                  minimumCertifiedDistanceLowerBoundMeters:minimum,firstUnresolvedInterval:r.map{[$0.a,$0.b]},leafCertificates:certificates,
                  reason:reason,maximumEstimatedWorkingBytes:estimatedBytes,peakPendingIntervals:peakPending,
                  fixedIntervalsCertified:fixedLeaves,movingNormalAttempts:movingAttempts,
                  movingNormalIntervalsCertified:movingLeaves,movingNormalCertificates:movingCertificates,
                  expansionAttempts:exactAttempts,expansionIntervalsCertified:exactLeaves,expansionOperations:exact.operations,
                  maximumExpansionWords:exact.maximumWords,expansionUnavailableReason:exactUnavailable,
                  expansionCertificates:exactCertificates,criticalAttempts:criticalAttempts,criticalIntervalsCertified:criticalLeaves,
                  criticalCertificates:criticalCertificates,affineNormalAttempts:affineAttempts,
                  affineNormalIntervalsCertified:affineLeaves,affineNormalCertificates:affineCertificates)
        }
        if isCancelled(){return report(.cancelled,nil,.cancelled)}
        guard start.count==4,end.count==4,start.allSatisfy(valid),end.allSatisfy(valid),
              minimumSeparation.isFinite,(0...1).contains(minimumSeparation) else{return report(.invalid,nil,.invalidInput)}
        guard (0...16).contains(limits.maximumDepth),(0...65_535).contains(limits.maximumNodes),
              (4096...64*1_024*1_024).contains(limits.maximumEstimatedWorkingBytes),
              (0...1_048_576).contains(limits.maximumExpansionOperations) else{return report(.invalid,nil,.invalidLimits)}
        let maximumLeaves=min((limits.maximumNodes+1)/2,1<<limits.maximumDepth)
        // Bounded constant polynomial scratch is charged even with tracing off.
        estimatedBytes=8192+2*(limits.maximumDepth+2)*MemoryLayout<Range>.stride +
            (limits.recordLeafCertificates ? 2*maximumLeaves*MemoryLayout<LeafCertificate>.stride:0)
        let baseEstimatedBytes=estimatedBytes
        let exactScratchBytes=131_072
        let exactTraceBytes=MemoryLayout<ExpansionCertificate>.stride + 3*MemoryLayout<VectorBounds>.stride +
            9*MemoryLayout<ScalarBounds>.stride + 128
        let movingTraceBytes = MemoryLayout<MovingNormalCertificate>.stride + 3*MemoryLayout<VectorBounds>.stride +
            4*MemoryLayout<ScalarBounds>.stride + 128
        let criticalTraceBytes=MemoryLayout<CriticalCertificate>.stride + 3*MemoryLayout<VectorBounds>.stride +
            12*MemoryLayout<ScalarBounds>.stride + 256
        let affineTraceBytes=MemoryLayout<AffineNormalCertificate>.stride + 4*(MemoryLayout<AffineProjectionCertificate>.stride+7*MemoryLayout<ScalarBounds>.stride+128)+256
        func chargedBytes(_ movingCount:Int,_ exactCount:Int,_ reserved:Bool,_ criticalCount:Int)->Int {
            baseEstimatedBytes+2*movingCount*movingTraceBytes+2*exactCount*exactTraceBytes +
                2*criticalCount*criticalTraceBytes+2*affineCertificates.count*affineTraceBytes+(reserved ? exactScratchBytes:0)
        }
        guard estimatedBytes<=limits.maximumEstimatedWorkingBytes else{return report(.budgetExceeded,nil,.workingMemoryBudget)}
        guard nearestRounding() else{return report(.unsupportedRounding,nil,.unsupportedRounding)}
        if limits.recordLeafCertificates {certificates.reserveCapacity(maximumLeaves)}
        var stack=[Range(a:0,b:1,depth:0)]
        peakPending=1
        while let range=stack.popLast() {
            if isCancelled(){return report(.cancelled,range,.cancelled)}
            guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
            guard nodes<limits.maximumNodes else{return report(.budgetExceeded,range,.nodeBudget)}
            nodes+=1;depth=max(depth,range.depth)
            let mid=range.a+(range.b-range.a)*0.5
            var nodeProof:LeafCertificate?
            // Each is only a direction proposal. An endpoint proposal still
            // has to prove the SAME whole interval, never just that endpoint.
            for parameter in [mid,range.a,range.b] {
                if isCancelled(){return report(.cancelled,range,.cancelled)}
                guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                let positions=zip(start,end).map{$0+($1-$0)*parameter}
                let n:V
                if kind == .vertexFace {
                    n=positions[0]-onTriangle(positions[0],positions[1],positions[2],positions[3])
                } else {
                    let q=closestSegments(positions[0],positions[1],positions[2],positions[3]);n=q.0-q.1
                }
                if let proof=certifiedLowerBound(kind,start,end,n,range,minimumSeparation) {nodeProof=proof;break}
            }
            // A fixed triangle and the point trajectory are convex sets.
            // Their closest pair can occur at an INTERIOR trajectory time
            // against a triangle edge. Point/edge cross products propose
            // the corresponding separating axes without trusting a numeric
            // closest time. Both signs still prove the SAME whole interval.
            if nodeProof == nil,kind == .vertexFace,
               start[1]==end[1],start[2]==end[2],start[3]==end[3] {
                let trajectory=end[0]-start[0]
                for (i,j) in [(1,2),(2,3),(3,1)] {
                    let axis=cross(trajectory,start[j]-start[i])
                    for n in [axis,-axis] {
                        if isCancelled(){return report(.cancelled,range,.cancelled)}
                        guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                        if let proof=certifiedLowerBound(kind,start,end,n,range,minimumSeparation) {nodeProof=proof;break}
                    }
                    if nodeProof != nil {break}
                }
            }
            if let proof=nodeProof {
                leaves+=1;fixedLeaves+=1
                if limits.recordLeafCertificates {
                    guard certificates.count<maximumLeaves else{return report(.budgetExceeded,range,.workingMemoryBudget)}
                    certificates.append(proof)
                }
                minimum=min(minimum ?? proof.distanceLowerBoundMeters,proof.distanceLowerBoundMeters);continue
            }
            if isCancelled(){return report(.cancelled,range,.cancelled)}
            guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
            movingAttempts+=1
            if let proof=certifiedMovingNormal(kind,start,end,range,minimumSeparation) {
                if isCancelled(){return report(.cancelled,range,.cancelled)}
                guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                if limits.recordLeafCertificates {
                    let charged=chargedBytes(movingCertificates.count+1,exactCertificates.count,exactReserved,criticalCertificates.count)
                    guard movingCertificates.count<maximumLeaves,charged<=limits.maximumEstimatedWorkingBytes else {
                        return report(.budgetExceeded,range,.workingMemoryBudget)
                    }
                    estimatedBytes=max(estimatedBytes,charged);movingCertificates.append(proof)
                }
                leaves+=1;movingLeaves+=1
                minimum=min(minimum ?? proof.distanceLowerBoundMeters,proof.distanceLowerBoundMeters);continue
            }
            if exactUnavailable == nil {
                exactAttempts+=1
                if !exactReserved {
                    let charged=chargedBytes(movingCertificates.count,exactCertificates.count,true,criticalCertificates.count)
                    guard charged<=limits.maximumEstimatedWorkingBytes else{return report(.budgetExceeded,range,.workingMemoryBudget)}
                    estimatedBytes=max(estimatedBytes,charged);exactReserved=true
                }
                do {
                    if exactPolynomial == nil {exactPolynomial=try exactProjectionPolynomial(kind,start,end,&exact,isCancelled)}
                    if let proof=try certifiedExpansion(kind,start,end,range,minimumSeparation,exactPolynomial!,&exact,isCancelled) {
                        if isCancelled(){return report(.cancelled,range,.cancelled)}
                        guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                        if limits.recordLeafCertificates {
                            let charged=chargedBytes(movingCertificates.count,exactCertificates.count+1,true,criticalCertificates.count)
                            guard exactCertificates.count<maximumLeaves,charged<=limits.maximumEstimatedWorkingBytes else{return report(.budgetExceeded,range,.workingMemoryBudget)}
                            estimatedBytes=max(estimatedBytes,charged);exactCertificates.append(proof)
                        }
                        leaves+=1;exactLeaves+=1
                        minimum=min(minimum ?? proof.distanceLowerBoundMeters,proof.distanceLowerBoundMeters);continue
                    }
                    // A sign-only polynomial proof is valid for ZERO shell
                    // only. Positive shells retain the original norm test.
                    if minimumSeparation==0 {
                        criticalAttempts+=1
                        if let proof=try certifiedCritical(kind,start,end,range,exactPolynomial!,&exact,isCancelled) {
                            if isCancelled(){return report(.cancelled,range,.cancelled)}
                            guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                            if limits.recordLeafCertificates {
                                let charged=chargedBytes(movingCertificates.count,exactCertificates.count,true,criticalCertificates.count+1)
                                guard criticalCertificates.count<maximumLeaves,charged<=limits.maximumEstimatedWorkingBytes else{return report(.budgetExceeded,range,.workingMemoryBudget)}
                                estimatedBytes=max(estimatedBytes,charged);criticalCertificates.append(proof)
                            }
                            leaves+=1;criticalLeaves+=1
                            minimum=min(minimum ?? proof.distanceLowerBoundMeters,proof.distanceLowerBoundMeters);continue
                        }
                    }
                    affineAttempts+=1
                    if let proof=try certifiedAffineNormal(kind,start,end,range,minimumSeparation,&exact,&affineAttempts,isCancelled) {
                        if isCancelled(){return report(.cancelled,range,.cancelled)}
                        guard nearestRounding() else{return report(.unsupportedRounding,range,.unsupportedRounding)}
                        if limits.recordLeafCertificates {
                            let charged=chargedBytes(movingCertificates.count,exactCertificates.count,true,criticalCertificates.count)+2*affineTraceBytes
                            guard affineCertificates.count<maximumLeaves,charged<=limits.maximumEstimatedWorkingBytes else{return report(.budgetExceeded,range,.workingMemoryBudget)}
                            estimatedBytes=max(estimatedBytes,charged);affineCertificates.append(proof)
                        }
                        leaves+=1;affineLeaves+=1
                        minimum=min(minimum ?? proof.distanceLowerBoundMeters,proof.distanceLowerBoundMeters);continue
                    }
                } catch ExpansionError.cancelled {return report(.cancelled,range,.cancelled)}
                catch ExpansionError.rounding {return report(.unsupportedRounding,range,.unsupportedRounding)}
                catch ExpansionError.operations {return report(.budgetExceeded,range,.expansionOperationBudget)}
                catch ExpansionError.capacity {return report(.budgetExceeded,range,.expansionCapacity)}
                catch ExpansionError.underflow {exactUnavailable = .underflow}
                catch {exactUnavailable = .nonfinite}
            }
            guard range.depth<limits.maximumDepth,mid>range.a,mid<range.b else{return report(.notCertified,range,.depthLimit)}
            guard stack.count+2<=limits.maximumDepth+2 else{return report(.budgetExceeded,range,.workingMemoryBudget)}
            stack.append(.init(a:mid,b:range.b,depth:range.depth+1))
            stack.append(.init(a:range.a,b:mid,depth:range.depth+1))
            peakPending=max(peakPending,stack.count)
        }
        if isCancelled(){return report(.cancelled,nil,.cancelled)}
        guard nearestRounding() else{return report(.unsupportedRounding,nil,.unsupportedRounding)}
        return report(.separated)
    }
    /// n(s)=(1-s)*nA+s*nB is just a finite direction proposal. For each
    /// actual convex vertex pair, r(s).n(s) is a quadratic, not a sampled
    /// closest distance. Strict lower bounds for ALL pairs prove separation.
    /// Shares the original finite EFT/capacity/scratch, time-node and depth caps.
    private static func certifiedAffineNormal(_ kind:Kind,_ start:[V],_ end:[V],_ range:Range,_ floor:Double,
        _ work:inout ExpansionWork,_ proposalAttempts:inout Int,_ cancelled:()->Bool)throws->AffineNormalCertificate? {
        func proposed(_ t:Double)->V? {
            let p=zip(start,end).map{$0+($1-$0)*t},n:V
            if kind == .vertexFace {n=p[0]-onTriangle(p[0],p[1],p[2],p[3])}
            else {let q=closestSegments(p[0],p[1],p[2],p[3]);n=q.0-q.1}
            let scale=max(abs(n.x),abs(n.y),abs(n.z))
            guard scale.isFinite,scale>0 else{return nil}
            let result=n/scale
            return valid(result) ? result:nil
        }
        guard let na=proposed(range.a),let nb=proposed(range.b) else{return nil}
        func prove(_ na:V,_ nb:V,_ work:inout ExpansionWork)throws->AffineNormalCertificate? {
        if cancelled(){throw ExpansionError.cancelled};guard nearestRounding() else{throw ExpansionError.rounding}
        let normalA:EV=(0..<3).map{na[$0]==0 ? []:[na[$0]]},normalB:EV=(0..<3).map{nb[$0]==0 ? []:[nb[$0]]}
        let nx=I(max(abs(na.x),abs(nb.x))),ny=I(max(abs(na.y),abs(nb.y))),nz=I(max(abs(na.z),abs(nb.z)))
        let normSquared=nx*nx+ny*ny+nz*nz
        guard normSquared.finite,normSquared.hi>0 else{return nil}
        let normUpper=sqrt(normSquared.hi).nextUp,denominator=(I(2)*I(normUpper)).hi
        let required=(I(2)*I(floor)*I(normUpper)).hi
        guard normUpper.isFinite,denominator.isFinite,denominator>0,required.isFinite else{return nil}
        func interval(_ e:E)->I {e.reduce(I(0)){$0+I($1)}}
        func bounds(_ i:I)->ScalarBounds {.init(lower:i.lo,upper:i.hi)}
        func sign(_ e:E)->Int {guard let x=e.last else{return 0};return x>0 ? 1:-1}
        func relativeAt(_ i:Int,_ j:Int,_ t:Double)throws->EV {
            let r0=try exactRelative(start,i,j,&work,cancelled),r1=try exactRelative(end,i,j,&work,cancelled)
            var result:EV=[]
            for k in 0..<3 {let difference=try work.subtract(r1[k],r0[k],cancelled);result.append(try work.sum(r0[k],work.scale(difference,t,cancelled),cancelled))}
            return result
        }
        let first=kind == .vertexFace ? [0]:[0,1],second=kind == .vertexFace ? [1,2,3]:[2,3]
        var proofs:[AffineProjectionCertificate]=[],lower=Double.infinity
        for i in first {for j in second {
            let r0=try relativeAt(i,j,range.a),r1=try relativeAt(i,j,range.b)
            let b0=try work.scale(work.dot(r0,normalA,cancelled),2,cancelled)
            let b1=try work.sum(work.dot(r0,normalB,cancelled),work.dot(r1,normalA,cancelled),cancelled)
            let b2=try work.scale(work.dot(r1,normalB,cancelled),2,cancelled)
            let aa=try work.sum(work.subtract(b0,work.scale(b1,2,cancelled),cancelled),b2,cancelled)
            let bb=try work.scale(work.subtract(b1,b0,cancelled),2,cancelled),cc=b0
            let bernstein=[interval(b0),interval(b1),interval(b2)],power=[interval(aa),interval(bb),interval(cc)]
            guard bernstein.allSatisfy(\.finite),power.allSatisfy(\.finite),bernstein[0].lo>required,bernstein[2].lo>required else{return nil}
            var minimum=min(bernstein[0].lo,bernstein[2].lo),numerator:I?
            let proofKind:AffineQuadraticProofKind
            if sign(aa)<=0 {proofKind = .concaveOrLinear}
            else if sign(bb)>=0 {proofKind = .endpointMinimum}
            else {
                let derivativeAtEnd=try work.sum(bb,work.scale(aa,2,cancelled),cancelled)
                if sign(derivativeAtEnd)<=0 {proofKind = .endpointMinimum}
                else {
                    let ac=try work.product(aa,cc,cancelled),bs=try work.product(bb,bb,cancelled)
                    let num=try work.subtract(work.scale(ac,4,cancelled),bs,cancelled),ni=interval(num)
                    let di=(I(4)*power[0]).hi
                    guard sign(num)>0,ni.finite,ni.lo>0,di.isFinite,di>0 else{return nil}
                    let q=(ni.lo/di).nextDown
                    guard q.isFinite,q>required else{return nil}
                    minimum=min(minimum,q);numerator=ni;proofKind = .positiveInteriorMinimum
                }
            }
            guard minimum.isFinite,minimum>required else{return nil}
            lower=min(lower,minimum)
            proofs.append(.init(firstVertex:i,secondVertex:j,scaledBernsteinBounds:bernstein.map(bounds),scaledPowerBounds:power.map(bounds),
                proofKind:proofKind,interiorNumeratorBounds:numerator.map(bounds),scaledProjectionLowerBound:minimum))
        }}
        let distance=(lower/denominator).nextDown
        guard distance.isFinite,distance>floor else{return nil}
        if cancelled(){throw ExpansionError.cancelled};guard nearestRounding() else{throw ExpansionError.rounding}
        return .init(startTime:range.a,endTime:range.b,kind:kind,projectionScale:2,startDirection:na,endDirection:nb,projections:proofs,
            scaledProjectionLowerBound:lower,normalNormUpperBound:normUpper,requiredScaledProductUpperBound:required,distanceLowerBoundMeters:distance)
        }
        // Preserve the original separately normalized proposal as the fast path.
        if let first=try prove(na,nb,&work){return first}
        // A second arbitrary proposal preserves the two raw closest-vector
        // amplitudes. Closest remains untrusted: all four true projections
        // pass through the exact SAME quadratic/norm proof and original work.
        proposalAttempts+=1
        func raw(_ t:Double)->V {
            let p=zip(start,end).map{$0+($1-$0)*t}
            if kind == .vertexFace{return p[0]-onTriangle(p[0],p[1],p[2],p[3])}
            let q=closestSegments(p[0],p[1],p[2],p[3]);return q.0-q.1
        }
        let a=raw(range.a),b=raw(range.b)
        let common=max(max(abs(a.x),max(abs(a.y),abs(a.z))),max(abs(b.x),max(abs(b.y),abs(b.z))))
        guard valid(a),valid(b),common.isFinite,common>0 else{return nil}
        let ca=a/common,cb=b/common
        guard valid(ca),valid(cb) else{return nil}
        return try prove(ca,cb,&work)
    }
    /// A time-varying normal is perpendicular to BOTH edge directions for EE,
    /// or both triangle directions for VF. Every same-time convex feature pair
    /// therefore has the SAME projection g(t). Linear endpoints give quadratic
    /// n and cubic g; outward Bernstein controls cover every time, not samples.
    private static func certifiedMovingNormal(_ kind:Kind,_ start:[V],_ end:[V],_ range:Range,_ floor:Double)->MovingNormalCertificate? {
        func point(_ i:Int,_ t:Double)->IV {let a=IV(start[i]);return a+(IV(end[i])-a)*I(t)}
        let a=start.indices.map{point($0,range.a)},b=start.indices.map{point($0,range.b)}
        let u0:IV,u1:IV,v0:IV,v1:IV,w0:IV,w1:IV
        if kind == .vertexFace {
            u0=a[2]-a[1];u1=b[2]-b[1];v0=a[3]-a[1];v1=b[3]-b[1];w0=a[0]-a[1];w1=b[0]-b[1]
        } else {
            u0=a[1]-a[0];u1=b[1]-b[0];v0=a[3]-a[2];v1=b[3]-b[2];w0=a[0]-a[2];w1=b[0]-b[2]
        }
        let n0=u0.cross(v0),n1=(u0.cross(v1)+u1.cross(v0))*I(0.5),n2=u1.cross(v1)
        let third=I((1.0/3.0).nextDown,(1.0/3.0).nextUp)
        let g=[w0.dot(n0),(w0.dot(n1)*I(2)+w1.dot(n0))*third,
               (w0.dot(n2)+w1.dot(n1)*I(2))*third,w1.dot(n2)]
        let normals=[n0,n1,n2]
        guard normals.allSatisfy(\.finite),g.allSatisfy(\.finite) else{return nil}
        let low=g.map(\.lo).min()!,high=g.map(\.hi).max()!
        let sign:Int,absoluteLower:Double
        if low>0 {sign=1;absoluteLower=low} else if high<0 {sign = -1;absoluteLower = -high} else{return nil}
        func maximum(_ values:[I])->Double {values.reduce(0){max($0,max(abs($1.lo),abs($1.hi)))}}
        let x=I(maximum(normals.map(\.x))),y=I(maximum(normals.map(\.y))),z=I(maximum(normals.map(\.z)))
        let normSquared=x*x+y*y+z*z
        guard normSquared.finite,normSquared.hi>0 else{return nil}
        let normUpper=sqrt(normSquared.hi).nextUp,required=(I(floor)*I(normUpper)).hi
        guard normUpper.isFinite,required.isFinite,absoluteLower>required else{return nil}
        func bound(_ x:I)->ScalarBounds {.init(lower:x.lo,upper:x.hi)}
        func bounds(_ v:IV)->VectorBounds {.init(x:bound(v.x),y:bound(v.y),z:bound(v.z))}
        return .init(startTime:range.a,endTime:range.b,kind:kind,projectionSign:sign,
            normalBernsteinBounds:normals.map(bounds),projectionBernsteinBounds:g.map(bound),
            absoluteProjectionLowerBound:absoluteLower,normalNormUpperBound:normUpper,requiredProductUpperBound:required,
            distanceLowerBoundMeters:max(0,(absoluteLower/normUpper).nextDown))
    }
    /// For arbitrary convex feature points a(t)=sum alpha_i a_i(t) and
    /// b(t)=sum beta_j b_j(t), n.(a-b) is a convex combination of the pair
    /// projections n.(a_i-b_j). Each pair projection is linear in t.
    /// Enclosing ALL pair endpoints therefore covers every t and every
    /// barycentric feature location. Numeric closest only proposes n.
    private static func certifiedLowerBound(_ kind:Kind,_ start:[V],_ end:[V],_ n:V,_ range:Range,_ floor:Double)->LeafCertificate? {
        let scale=max(abs(n.x),abs(n.y),abs(n.z))
        guard scale.isFinite,scale>0 else{return nil}
        // Rescaling only chooses another finite direction; no correctness
        // statement relies on the nominal closest-point calculation.
        let direction=n/scale
        guard valid(direction),dot(direction,direction)>0 else{return nil}
        let ni=IV(direction),normSquare=ni.dot(ni)
        guard normSquare.finite,normSquare.hi>0 else{return nil}
        let normUpper=sqrt(normSquare.hi).nextUp,threshold=(I(floor)*I(normUpper)).hi
        guard normUpper.isFinite,threshold.isFinite else{return nil}
        let a=kind == .vertexFace ? [0]:[0,1],b=kind == .vertexFace ? [1,2,3]:[2,3]
        var lower=Double.infinity
        for i in a {for j in b {
            let d0=IV(start[i])-IV(start[j]),d1=IV(end[i])-IV(end[j])
            for t in [range.a,range.b] {
                let projection=ni.dot(d0+(d1-d0)*I(t))
                guard projection.finite else{return nil}
                lower=min(lower,projection.lo)
            }
        }}
        guard lower>threshold else{return nil}
        // Diagnostic lower bound only. Acceptance uses the strict interval
        // product comparison above, which also handles very small margins.
        return .init(startTime:range.a,endTime:range.b,direction:direction,projectionLowerBound:lower,
                     directionNormUpperBound:normUpper,requiredProductUpperBound:threshold,
                     distanceLowerBoundMeters:max(0,(lower/normUpper).nextDown))
    }
    private static func valid(_ v:V)->Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite && max(abs(v.x),abs(v.y),abs(v.z))<=1_000_000
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func cross(_ a:V,_ b:V)->V {
        V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
    }
    private static func segmentPoint(_ p:V,_ a:V,_ b:V)->V {
        let v=b-a,den=dot(v,v)
        let t=den>0 ? max(0,min(1,dot(p-a,v)/den)):0
        return a+v*t
    }
    private static func onTriangle(_ p:V,_ a:V,_ b:V,_ c:V)->V {
        let ab=b-a,ac=c-a,ap=p-a,d1=dot(ab,ap),d2=dot(ac,ap)
        if d1<=0 && d2<=0{return a}
        let bp=p-b,d3=dot(ab,bp),d4=dot(ac,bp)
        if d3>=0 && d4<=d3{return b}
        let vc=d1*d4-d3*d2
        if vc<=0 && d1>=0 && d3<=0 && d1-d3 != 0{return a+ab*(d1/(d1-d3))}
        let cp=p-c,d5=dot(ab,cp),d6=dot(ac,cp)
        if d6>=0 && d5<=d6{return c}
        let vb=d5*d2-d1*d6
        if vb<=0 && d2>=0 && d6<=0 && d2-d6 != 0{return a+ac*(d2/(d2-d6))}
        let va=d3*d6-d5*d4
        if va<=0 && d4-d3>=0 && d5-d6>=0 && (d4-d3)+(d5-d6) != 0{return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))}
        let denominator=va+vb+vc
        if denominator.isFinite,denominator != 0 {
            let q=a+ab*(vb/denominator)+ac*(vc/denominator)
            if valid(q){return q}
        }
        // Degeneracy is not accepted as a primitive domain. This fallback
        // merely proposes a finite direction; the support proof stays valid.
        return [segmentPoint(p,a,b),segmentPoint(p,b,c),segmentPoint(p,c,a)].min{dot($0-p,$0-p)<dot($1-p,$1-p)} ?? a
    }
    private static func closestSegments(_ a:V,_ b:V,_ c:V,_ d:V)->(V,V) {
        let u=b-a,v=d-c,w=a-c,aa=dot(u,u),bb=dot(u,v),cc=dot(v,v),dd=dot(u,w),ee=dot(v,w)
        if aa==0{return(a,segmentPoint(a,c,d))}
        if cc==0{return(segmentPoint(c,a,b),c)}
        let den=aa*cc-bb*bb
        var s=den>0 ? max(0,min(1,(bb*ee-cc*dd)/den)):0
        var t=(bb*s+ee)/cc
        if t<0 {t=0;s=max(0,min(1,-dd/aa))}
        else if t>1 {t=1;s=max(0,min(1,(bb-dd)/aa))}
        return(a+u*s,c+v*t)
    }
    private static func nearestRounding()->Bool {FloatingPointEnvironment.isNearestRounding}
    private static func motionHash(_ kind:Kind,_ start:[V],_ end:[V],_ floor:Double)->String {
        var bytes=Data(("continuous-feature-separation-v1:"+kind.rawValue+"\0").utf8)
        func add(_ x:UInt64){var y=x.littleEndian;withUnsafeBytes(of:&y){bytes.append(contentsOf:$0)}}
        add(floor.bitPattern);add(UInt64(start.count));add(UInt64(end.count))
        for p in start+end {add(p.x.bitPattern);add(p.y.bitPattern);add(p.z.bitPattern)}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
}


