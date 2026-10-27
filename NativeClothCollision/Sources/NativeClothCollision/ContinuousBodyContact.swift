/// A conservative path guard against an immutable, exact triangle body surface.
/// It does not implement cloth self-contact, sewing exceptions, elasticity or a physics solver.
public enum ContinuousBodyContact {
    public typealias Vector = SIMD3<Double>
    public enum Status: String, Sendable {
        case clear, limited, blockedInitialContact, uncertain, invalid, cancelled, budgetExceeded
    }
    public enum FeatureKind: String, Sendable { case clothVertexBodyFace, bodyVertexClothFace, edgeEdge }
    public enum Failure: Error, Sendable, Equatable {
        case invalid(String), budgetExceeded(String), cancelled
    }
    public struct Limits: Sendable {
        public var maximumBodyVertices = 200_000
        public var maximumBodyTriangles = 400_000
        public var maximumClothVertices = 200_000
        public var maximumClothTriangles = 400_000
        public var maximumBVHNodes = 1_000_000
        public var maximumBuildWork = 100_000_000
        public var maximumBVHVisits = 20_000_000
        public var maximumTrianglePairs = 500_000
        public var maximumFeatureQueries = 1_000_000
        /// Whole-query budget for independent Euclidean certificates after a
        /// native coordinate-box conservative hit. No native predicate changes.
        public var maximumEuclideanCertificateNodes = 262_144
        public var maximumEstimatedBytes = 256 * 1_024 * 1_024
        public init() {}
    }
    public struct Options: Sendable {
        public var minimumSeparation: Double
        public var distanceTolerance: Double
        public var maximumIterationsPerFeature: Int64
        public var safetyFactor: Double
        public var limits: Limits
        public init(minimumSeparation: Double = 0, distanceTolerance: Double = 1e-8,
                    maximumIterationsPerFeature: Int64 = 10_000,
                    safetyFactor: Double = 0.9, limits: Limits = .init()) {
            self.minimumSeparation = minimumSeparation
            self.distanceTolerance = distanceTolerance
            self.maximumIterationsPerFeature = maximumIterationsPerFeature
            self.safetyFactor = safetyFactor
            self.limits = limits
        }
    }
    public struct Statistics: Sendable {
        public internal(set) var bodyTriangles = 0
        public internal(set) var clothTriangles = 0
        public internal(set) var bvhNodeVisits = 0
        public internal(set) var trianglePairs = 0
        public internal(set) var uniqueClothVertexBodyFace = 0
        public internal(set) var uniqueBodyVertexClothFace = 0
        public internal(set) var uniqueEdgeEdge = 0
        public internal(set) var evaluatedFeatures = 0
        public internal(set) var nativeQueries = 0
        public internal(set) var euclideanCertificateAttempts = 0
        public internal(set) var euclideanCertifiedFeatures = 0
        public internal(set) var euclideanCertificateNodes = 0
        public internal(set) var euclideanCertifiedAfterPrecisionLimit = 0
        public internal(set) var estimatedWorkingBytes = 0
        public internal(set) var completedAllFeatures = false
    }
    public struct Witness: Sendable {
        public let kind: FeatureKind
        public let clothVertexIDs: [UInt32]
        public let bodyVertexIDs: [UInt32]
        public let conservativeTimeOfImpact: Double
        public let achievedDistanceTolerance: Double
        public let nativeDetail: NativeClothCollision.Detail?
        /// Nil for CCD-only possible initial contact; otherwise an unrounded closest-feature distance.
        public let initialDistance: Double?
    }
    public struct Report: Sendable {
        public let status: Status
        /// Fraction of the original previous->candidate motion. No failed/uncertain query authorizes movement.
        public let safeTime: Double
        public let conservativeTimeOfImpact: Double?
        public let minimumSeparation: Double
        public let reason: String
        public let witness: Witness?
        public let statistics: Statistics
        public var permitsWholeCandidate: Bool { status == .clear && safeTime == 1 }
    }
    public struct Bounds: Sendable, Equatable {
        public let minimum: Vector
        public let maximum: Vector
        public init(minimum: Vector, maximum: Vector) {
            self.minimum = minimum; self.maximum = maximum
        }
        fileprivate func overlaps(_ b: Bounds) -> Bool {
            minimum.x <= b.maximum.x && maximum.x >= b.minimum.x &&
            minimum.y <= b.maximum.y && maximum.y >= b.minimum.y &&
            minimum.z <= b.maximum.z && maximum.z >= b.minimum.z
        }
        fileprivate func union(_ b: Bounds) -> Bounds {
            Bounds(minimum: low(minimum,b.minimum),maximum: high(maximum,b.maximum))
        }
    }
    private struct Node: Sendable {
        var bounds: Bounds
        var left = -1, right = -1, begin = 0, end = 0
    }
    private struct Feature: Hashable {
        let kind: FeatureKind
        let a: UInt32, b: UInt32, c: UInt32, d: UInt32
    }

    /// Stores precisely the supplied visible geometry, including original vertex and face ordering.
    /// Open surfaces are accepted. This guard certifies paths, not initial inside/outside containment.
    public struct Prepared: Sendable {
        public let bodyPositions: [Vector]
        public let bodyTriangleIndices: [UInt32]
        public let estimatedResidentBytes: Int
        private let faceBounds: [Bounds]
        private let order: [Int]
        private let nodes: [Node]

        public init(bodyPositions: [Vector], triangleIndices: [UInt32],
                    limits: Limits = .init(), isCancelled: (() -> Bool)? = nil) throws {
            if isCancelled?() == true { throw Failure.cancelled }
            guard valid(limits) else { throw Failure.invalid("limits") }
            guard !bodyPositions.isEmpty, !triangleIndices.isEmpty, triangleIndices.count % 3 == 0 else {
                throw Failure.invalid("empty or incomplete body triangles")
            }
            let faces = triangleIndices.count / 3
            guard bodyPositions.count <= limits.maximumBodyVertices, faces <= limits.maximumBodyTriangles else {
                throw Failure.budgetExceeded("body geometry")
            }
            let bytesPerFace = MemoryLayout<Bounds>.stride + 2 * MemoryLayout<Node>.stride +
                MemoryLayout<Int>.stride + 3 * MemoryLayout<UInt32>.stride
            let estimate = bodyPositions.count * MemoryLayout<Vector>.stride + faces * bytesPerFace + 1_024
            guard estimate <= limits.maximumEstimatedBytes else { throw Failure.budgetExceeded("body resident bytes") }
            for (i,p) in bodyPositions.enumerated() {
                if i % 256 == 0, isCancelled?() == true { throw Failure.cancelled }
                guard finite(p) else { throw Failure.invalid("body coordinate") }
            }
            var bounds: [Bounds] = []; bounds.reserveCapacity(faces)
            for f in 0..<faces {
                if f % 256 == 0, isCancelled?() == true { throw Failure.cancelled }
                let ids = [triangleIndices[3*f],triangleIndices[3*f+1],triangleIndices[3*f+2]]
                guard ids.allSatisfy({Int($0)<bodyPositions.count}), Set(ids).count == 3 else {
                    throw Failure.invalid("body triangle index")
                }
                let a=bodyPositions[Int(ids[0])],b=bodyPositions[Int(ids[1])],c=bodyPositions[Int(ids[2])]
                guard usable(a,b,c) else { throw Failure.invalid("degenerate body triangle") }
                bounds.append(triangleBounds(a,b,c))
            }
            var builder = Builder(bounds: bounds, limits: limits, isCancelled: isCancelled)
            _ = try builder.build(0,faces)
            if isCancelled?() == true { throw Failure.cancelled }
            self.bodyPositions = bodyPositions; self.bodyTriangleIndices = triangleIndices
            self.faceBounds = bounds; self.order = builder.order; self.nodes = builder.nodes
            self.estimatedResidentBytes = estimate
        }

        /// Read-only diagnostic query. Returns the complete, sorted candidate set or throws; never partial IDs.
        public func candidateTriangleIDs(in bounds: Bounds, maximumVisits: Int = 20_000_000,
                                         maximumCandidates: Int = 500_000,
                                         isCancelled: (() -> Bool)? = nil) throws -> [UInt32] {
            guard validBounds(bounds), maximumVisits > 0, maximumVisits <= 100_000_000,
                  maximumCandidates > 0, maximumCandidates <= 5_000_000 else {
                throw Failure.invalid("candidate query")
            }
            var visits = 0
            return try search(bounds, visits: &visits, maximumVisits: maximumVisits,
                              maximumCandidates: maximumCandidates,isCancelled: isCancelled)
        }

        private func search(_ bounds: Bounds, visits: inout Int, maximumVisits: Int,
                            maximumCandidates: Int, isCancelled: (() -> Bool)?) throws -> [UInt32] {
            var stack = [0], result: [UInt32] = []
            while let n = stack.popLast() {
                if isCancelled?() == true { throw Failure.cancelled }
                guard visits < maximumVisits else { throw Failure.budgetExceeded("BVH visits") }
                visits += 1
                let node = nodes[n]
                if !node.bounds.overlaps(bounds) { continue }
                if node.left >= 0 {
                    stack.append(node.right);stack.append(node.left)
                } else {
                    for j in node.begin..<node.end {
                        let face=order[j]
                        if faceBounds[face].overlaps(bounds) {
                            guard result.count < maximumCandidates else { throw Failure.budgetExceeded("triangle candidates") }
                            result.append(UInt32(face))
                        }
                    }
                }
            }
            return result.sorted()
        }

        public func guardMotion(previous: [Vector], candidate: [Vector], clothTriangleIndices: [UInt32],
                                options: Options = .init(), isCancelled: (() -> Bool)? = nil) -> Report {
            var stats=Statistics()
            stats.bodyTriangles=bodyTriangleIndices.count/3
            stats.clothTriangles=clothTriangleIndices.count/3
            stats.estimatedWorkingBytes=estimatedResidentBytes
            var earliest: Double?, earliestWitness: Witness?
            func report(_ status: Status,_ reason: String,_ witness: Witness? = nil) -> Report {
                var time=0.0
                if status == .clear { time=1 }
                if status == .limited, let t=earliest, t>0 {
                    time=max(0,min(t.nextDown,t*options.safetyFactor))
                }
                return Report(status:status,safeTime:time,conservativeTimeOfImpact:earliest,
                              minimumSeparation:options.minimumSeparation,reason:reason,
                              witness:witness ?? earliestWitness,statistics:stats)
            }
            if isCancelled?() == true { return report(.cancelled,"cancelled before query") }
            guard FloatingPointEnvironment.isNearestRounding else { return report(.uncertain,"unsupported floating-point rounding") }
            guard valid(options.limits), options.minimumSeparation.isFinite,
                  options.minimumSeparation>=0,options.minimumSeparation<1,
                  options.distanceTolerance.isFinite,options.distanceTolerance>0,options.distanceTolerance<=1,
                  options.maximumIterationsPerFeature>=1,options.maximumIterationsPerFeature<=100_000,
                  options.safetyFactor.isFinite,options.safetyFactor>0,options.safetyFactor<1 else {
                return report(.invalid,"options")
            }
            let l=options.limits
            guard !previous.isEmpty,previous.count==candidate.count,
                  !clothTriangleIndices.isEmpty,clothTriangleIndices.count%3==0 else {
                return report(.invalid,"cloth arrays")
            }
            guard previous.count<=l.maximumClothVertices,stats.clothTriangles<=l.maximumClothTriangles else {
                return report(.budgetExceeded,"cloth geometry")
            }
            let baseBytes=estimatedResidentBytes+previous.count*2*MemoryLayout<Vector>.stride +
                clothTriangleIndices.count*MemoryLayout<UInt32>.stride+1_024
            stats.estimatedWorkingBytes=baseBytes
            guard baseBytes<=l.maximumEstimatedBytes else { return report(.budgetExceeded,"query base bytes") }
            for i in previous.indices {
                if i%256==0,isCancelled?() == true { return report(.cancelled,"cancelled validating vertices") }
                guard finite(previous[i]),finite(candidate[i]) else { return report(.invalid,"cloth coordinate") }
            }
            // Check scratch BEFORE allocating candidate lists or issuing any native query.
            // The finite upstream refinement cap also bounds interval/map storage. This is a
            // conservative reservation, not an allocator/VM peak measurement.
            let searchScratch=bodyTriangleIndices.count/3*16+nodes.count*MemoryLayout<Int>.stride
            let nativeScratch=Int(options.maximumIterationsPerFeature)*1_024+65_536
            let certificateScratch=1_048_576
            let reservedBytes=baseBytes+searchScratch+nativeScratch+certificateScratch
            stats.estimatedWorkingBytes=reservedBytes
            guard reservedBytes<=l.maximumEstimatedBytes else {return report(.budgetExceeded,"query scratch bytes")}
            var unique=Set<Feature>(),features:[Feature]=[]
            func add(_ f: Feature) throws {
                if unique.contains(f) { return }
                guard features.count<l.maximumFeatureQueries else { throw Failure.budgetExceeded("unique features") }
                // Includes conservative Array/Set capacity allowance, candidate list and BVH traversal storage.
                let bytes=reservedBytes+(features.count+1)*256
                guard bytes<=l.maximumEstimatedBytes else { throw Failure.budgetExceeded("query working bytes") }
                stats.estimatedWorkingBytes=max(stats.estimatedWorkingBytes,bytes)
                unique.insert(f);features.append(f)
                switch f.kind {
                case .clothVertexBodyFace:stats.uniqueClothVertexBodyFace+=1
                case .bodyVertexClothFace:stats.uniqueBodyVertexClothFace+=1
                case .edgeEdge:stats.uniqueEdgeEdge+=1
                }
            }
            do {
                for cf in 0..<stats.clothTriangles {
                    if isCancelled?() == true { throw Failure.cancelled }
                    let ci=[clothTriangleIndices[3*cf],clothTriangleIndices[3*cf+1],clothTriangleIndices[3*cf+2]]
                    guard ci.allSatisfy({Int($0)<previous.count}),Set(ci).count==3 else {
                        throw Failure.invalid("cloth triangle index")
                    }
                    let a=previous[Int(ci[0])],b=previous[Int(ci[1])],c=previous[Int(ci[2])]
                    let d=candidate[Int(ci[0])],e=candidate[Int(ci[1])],f=candidate[Int(ci[2])]
                    guard usable(a,b,c),usable(d,e,f) else { throw Failure.invalid("degenerate cloth endpoint triangle") }
                    let swept=expanded(triangleBounds(a,b,c).union(triangleBounds(d,e,f)),
                                       by:options.minimumSeparation+options.distanceTolerance)
                    guard stats.trianglePairs<l.maximumTrianglePairs else { throw Failure.budgetExceeded("triangle pairs") }
                    let body=try search(swept,visits:&stats.bvhNodeVisits,maximumVisits:l.maximumBVHVisits,
                                        maximumCandidates:l.maximumTrianglePairs-stats.trianglePairs,isCancelled:isCancelled)
                    for bf in body {
                        if isCancelled?() == true {throw Failure.cancelled}
                        stats.trianglePairs+=1
                        let bi=bodyIDs(bf)
                        for v in ci { try add(Feature(kind:.clothVertexBodyFace,a:v,b:bf,c:0,d:0)) }
                        for v in bi { try add(Feature(kind:.bodyVertexClothFace,a:v,b:UInt32(cf),c:0,d:0)) }
                        for i in 0..<3 { for j in 0..<3 {
                            let ca=min(ci[i],ci[(i+1)%3]),cb=max(ci[i],ci[(i+1)%3])
                            let ba=min(bi[j],bi[(j+1)%3]),bb=max(bi[j],bi[(j+1)%3])
                            try add(Feature(kind:.edgeEdge,a:ca,b:cb,c:ba,d:bb))
                        }}
                    }
                }
            } catch let f as Failure {
                switch f {
                case .cancelled:return report(.cancelled,"cancelled generating candidates")
                case .invalid(let why):return report(.invalid,why)
                case .budgetExceeded(let why):return report(.budgetExceeded,why)
                }
            } catch { return report(.uncertain,"unexpected candidate failure") }
            let ccdOptions=NativeClothCollision.Options(minimumSeparation:options.minimumSeparation,
                maximumTime:1,distanceTolerance:options.distanceTolerance,
                maximumIterations:options.maximumIterationsPerFeature)
            for feature in features {
                if isCancelled?() == true { return report(.cancelled,"cancelled evaluating features") }
                stats.evaluatedFeatures+=1
                let ci: [UInt32],bi: [UInt32],start:[Vector],end:[Vector]
                switch feature.kind {
                case .clothVertexBodyFace:
                    ci=[feature.a];bi=bodyIDs(feature.b)
                    start=[previous[Int(feature.a)]]+bi.map{bodyPositions[Int($0)]}
                    end=[candidate[Int(feature.a)]]+bi.map{bodyPositions[Int($0)]}
                case .bodyVertexClothFace:
                    ci=[clothTriangleIndices[3*Int(feature.b)],clothTriangleIndices[3*Int(feature.b)+1],clothTriangleIndices[3*Int(feature.b)+2]]
                    bi=[feature.a]
                    start=[bodyPositions[Int(feature.a)]]+ci.map{previous[Int($0)]}
                    end=[bodyPositions[Int(feature.a)]]+ci.map{candidate[Int($0)]}
                case .edgeEdge:
                    ci=[feature.a,feature.b];bi=[feature.c,feature.d]
                    start=ci.map{previous[Int($0)]}+bi.map{bodyPositions[Int($0)]}
                    end=ci.map{candidate[Int($0)]}+bi.map{bodyPositions[Int($0)]}
                }
                let d2=feature.kind == .edgeEdge ? segmentDistance2(start[0],start[1],start[2],start[3])
                    : pointTriangleDistance2(start[0],start[1],start[2],start[3])
                let scale=start.reduce(1.0){max($0,max(abs($1.x),max(abs($1.y),abs($1.z))))}
                let contactDistance=options.minimumSeparation+scale*32*Double.ulpOfOne
                if !d2.isFinite || d2<0 { return report(.uncertain,"initial distance arithmetic") }
                if d2<=contactDistance*contactDistance {
                    earliest=0
                    let w=Witness(kind:feature.kind,clothVertexIDs:ci,bodyVertexIDs:bi,
                        conservativeTimeOfImpact:0,achievedDistanceTolerance:0,nativeDetail:nil,initialDistance:d2.squareRoot())
                    return report(.blockedInitialContact,"initial contact within separation/numerical bound",w)
                }
                func flat(_ x:[Vector])->[Double] {x.flatMap{[$0.x,$0.y,$0.z]}}
                stats.nativeQueries+=1
                let result=feature.kind == .edgeEdge
                    ? NativeClothCollision.edgeEdge(start:flat(start),end:flat(end),options:ccdOptions,isCancelled:isCancelled)
                    : NativeClothCollision.vertexFace(start:flat(start),end:flat(end),options:ccdOptions,isCancelled:isCancelled)
                let w=Witness(kind:feature.kind,clothVertexIDs:ci,bodyVertexIDs:bi,
                    conservativeTimeOfImpact:result.conservativeTimeOfImpact,
                    achievedDistanceTolerance:result.achievedDistanceTolerance,nativeDetail:result.detail,initialDistance:nil)
                // The pinned native wrapper certifies the VF triangle / both
                // EE edges BEFORE invoking CCD. Its precisionOrBudget return
                // (NativeClothCollision.cpp:88-93) also occurs after that domain
                // proof. No other uncertain detail has this fallback policy.
                let certifiedNativeDomain=(result.status == .conservativeHit && result.detail == .none) ||
                    (result.status == .uncertain && result.detail == .precisionOrBudget)
                if certifiedNativeDomain {
                    // Positive separation uses a coordinate box, which can report an
                    // early hit outside the Euclidean barrier shell. Only an
                    // independent strict whole-path distance proof may clear
                    // this feature. Uncertain geometry is never overridden.
                    let remaining=l.maximumEuclideanCertificateNodes-stats.euclideanCertificateNodes
                    guard remaining>0 else { return report(.budgetExceeded,"Euclidean certificate node budget",w) }
                    var certificateLimits=FeatureSeparationCertificate.Limits()
                    certificateLimits.maximumNodes=min(certificateLimits.maximumNodes,remaining)
                    stats.euclideanCertificateAttempts+=1
                    let certificate=FeatureSeparationCertificate.certify(
                        kind:feature.kind == .edgeEdge ? .edgeEdge:.vertexFace,
                        start:start,end:end,minimumSeparation:options.minimumSeparation,
                        limits:certificateLimits,isCancelled:{isCancelled?() == true})
                    stats.euclideanCertificateNodes+=certificate.processedNodes
                    if isCancelled?() == true || certificate.status == .cancelled {return report(.cancelled,"cancelled Euclidean certificate",w)}
                    switch certificate.status {
                    case .separated:
                        if result.status == .uncertain {stats.euclideanCertifiedAfterPrecisionLimit+=1}
                        stats.euclideanCertifiedFeatures+=1;continue
                    case .budgetExceeded:return report(.budgetExceeded,"Euclidean certificate work/memory budget",w)
                    case .invalid,.unsupportedRounding:return report(.uncertain,"Euclidean certificate input/rounding unresolved",w)
                    case .notCertified:break
                    case .cancelled:return report(.cancelled,"cancelled Euclidean certificate",w)
                    }
                }
                switch result.status {
                case .invalid:return report(.invalid,"native CCD input rejected",w)
                case .uncertain:
                    return report(result.detail == .cancelled ? .cancelled:.uncertain,"native CCD unresolved: \(result.detail)",w)
                case .noHit:break
                case .conservativeHit:
                    let t=result.conservativeTimeOfImpact
                    if t==0 {earliest=0;return report(.blockedInitialContact,"possible initial contact from conservative CCD",w)}
                    if earliest == nil || t<earliest! {earliest=t;earliestWitness=w}
                }
            }
            if isCancelled?() == true {return report(.cancelled,"cancelled completing query")}
            guard FloatingPointEnvironment.isNearestRounding else {return report(.uncertain,"unsupported floating-point rounding completing query")}
            stats.completedAllFeatures=true
            return report(earliest == nil ? .clear:.limited,earliest == nil ? "all necessary features clear":"complete query limited by conservative TOI")
        }
        private func bodyIDs(_ f:UInt32)->[UInt32] {
            let i=3*Int(f);return [bodyTriangleIndices[i],bodyTriangleIndices[i+1],bodyTriangleIndices[i+2]]
        }
    }

    private struct Builder {
        let bounds:[Bounds],limits:Limits,isCancelled:(()->Bool)?
        var order:[Int],nodes:[Node]=[],work=0
        init(bounds:[Bounds],limits:Limits,isCancelled:(()->Bool)?) {
            self.bounds=bounds;self.limits=limits;self.isCancelled=isCancelled
            self.order=Array(bounds.indices)
        }
        mutating func tick() throws {
            guard work<limits.maximumBuildWork else {throw Failure.budgetExceeded("BVH build work")}
            work+=1
            if work%256==0,isCancelled?() == true {throw Failure.cancelled}
        }
        func center(_ i:Int,_ axis:Int)->Double {
            (bounds[i].minimum[axis]+bounds[i].maximum[axis])*0.5
        }
        mutating func select(_ begin:Int,_ end:Int,_ middle:Int,_ axis:Int) throws {
            var lo=begin,hi=end-1
            while lo<hi {
                let pivot=center(order[(lo+hi)/2],axis)
                var i=lo,j=hi
                while i<=j {
                    while i<=hi && center(order[i],axis)<pivot {try tick();i+=1}
                    while j>=lo && center(order[j],axis)>pivot {try tick();j-=1}
                    if i<=j {try tick();order.swapAt(i,j);i+=1;j-=1}
                }
                if middle<=j {hi=j} else if middle>=i {lo=i} else {return}
            }
        }
        mutating func build(_ begin:Int,_ end:Int) throws -> Int {
            guard nodes.count<limits.maximumBVHNodes else {throw Failure.budgetExceeded("BVH nodes")}
            var b=bounds[order[begin]]
            for i in begin..<end {try tick();b=b.union(bounds[order[i]])}
            let n=nodes.count;nodes.append(Node(bounds:b,begin:begin,end:end))
            if end-begin>8 {
                let extent=b.maximum-b.minimum
                let axis=extent.x>=extent.y && extent.x>=extent.z ? 0:(extent.y>=extent.z ? 1:2)
                let m=(begin+end)/2
                try select(begin,end,m,axis)
                let left=try build(begin,m),right=try build(m,end)
                nodes[n].left=left;nodes[n].right=right
            }
            return n
        }
    }
    private static func valid(_ l:Limits)->Bool {
        let counts=[l.maximumBodyVertices,l.maximumBodyTriangles,l.maximumClothVertices,l.maximumClothTriangles,l.maximumBVHNodes]
        return counts.allSatisfy{$0>0 && $0<=1_000_000} &&
            l.maximumBuildWork>0 && l.maximumBuildWork<=500_000_000 &&
            l.maximumBVHVisits>0 && l.maximumBVHVisits<=100_000_000 &&
            l.maximumTrianglePairs>0 && l.maximumTrianglePairs<=5_000_000 &&
            l.maximumFeatureQueries>0 && l.maximumFeatureQueries<=5_000_000 &&
            l.maximumEuclideanCertificateNodes>=0 && l.maximumEuclideanCertificateNodes<=1_048_576 &&
            l.maximumEstimatedBytes>0 && l.maximumEstimatedBytes<=1_024*1_024*1_024
    }
    private static func finite(_ p:Vector)->Bool {
        p.x.isFinite && p.y.isFinite && p.z.isFinite && max(abs(p.x),max(abs(p.y),abs(p.z)))<=1e6
    }
    private static func low(_ a:Vector,_ b:Vector)->Vector {Vector(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z))}
    private static func high(_ a:Vector,_ b:Vector)->Vector {Vector(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z))}
    private static func dot(_ a:Vector,_ b:Vector)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func cross(_ a:Vector,_ b:Vector)->Vector {
        Vector(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
    }
    private static func usable(_ a:Vector,_ b:Vector,_ c:Vector)->Bool {
        let u=b-a,v=c-a,area2=dot(cross(u,v),cross(u,v))
        return area2.isFinite && area2>max(1e-48,max(dot(u,u),dot(v,v))*max(dot(u,u),dot(v,v))*1e-24)
    }
    private static func triangleBounds(_ a:Vector,_ b:Vector,_ c:Vector)->Bounds {
        Bounds(minimum:low(a,low(b,c)),maximum:high(a,high(b,c)))
    }
    private static func expanded(_ b:Bounds,by d:Double)->Bounds {
        Bounds(minimum:Vector((b.minimum.x-d).nextDown,(b.minimum.y-d).nextDown,(b.minimum.z-d).nextDown),
               maximum:Vector((b.maximum.x+d).nextUp,(b.maximum.y+d).nextUp,(b.maximum.z+d).nextUp))
    }
    private static func validBounds(_ b:Bounds)->Bool {
        [b.minimum.x,b.minimum.y,b.minimum.z,b.maximum.x,b.maximum.y,b.maximum.z].allSatisfy{$0.isFinite} &&
            b.minimum.x<=b.maximum.x && b.minimum.y<=b.maximum.y && b.minimum.z<=b.maximum.z
    }
    private static func pointSegmentDistance2(_ p:Vector,_ a:Vector,_ b:Vector)->Double {
        let d=b-a,den=dot(d,d)
        let t=den>0 ? min(1,max(0,dot(p-a,d)/den)):0
        let q=p-(a+d*t);return max(0,dot(q,q))
    }
    private static func pointTriangleDistance2(_ p:Vector,_ a:Vector,_ b:Vector,_ c:Vector)->Double {
        let u=b-a,v=c-a,w=p-a
        let uu=dot(u,u),uv=dot(u,v),vv=dot(v,v),wu=dot(w,u),wv=dot(w,v),den=uu*vv-uv*uv
        var d=min(pointSegmentDistance2(p,a,b),min(pointSegmentDistance2(p,b,c),pointSegmentDistance2(p,c,a)))
        if den>0 {
            let s=(wu*vv-wv*uv)/den,t=(wv*uu-wu*uv)/den
            if s>=0 && t>=0 && s+t<=1 {
                let n=cross(u,v),nn=dot(n,n)
                if nn>0 {d=min(d,dot(w,n)*dot(w,n)/nn)}
            }
        }
        return max(0,d)
    }
    private static func segmentDistance2(_ a:Vector,_ b:Vector,_ c:Vector,_ d:Vector)->Double {
        var distance=min(pointSegmentDistance2(a,c,d),min(pointSegmentDistance2(b,c,d),
                         min(pointSegmentDistance2(c,a,b),pointSegmentDistance2(d,a,b))))
        let u=b-a,v=d-c,w=a-c
        let uu=dot(u,u),uv=dot(u,v),vv=dot(v,v),uw=dot(u,w),vw=dot(v,w),den=uu*vv-uv*uv
        if den>0 {
            let s=(uv*vw-vv*uw)/den,t=(uu*vw-uv*uw)/den
            if s>=0 && s<=1 && t>=0 && t<=1 {
                let delta=(a+u*s)-(c+v*t);distance=min(distance,dot(delta,delta))
            }
        }
        return max(0,distance)
    }
}

