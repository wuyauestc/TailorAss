import CNativeClothCollision

/// Conservative whole-path self CCD for a triangle surface with all vertices
/// moving. Requires an independently intersection-free previous state. It
/// prevents NEW contacts; static VF/EE events cannot detect all already pierced
/// triangle interiors. It has no sewing mask, contact force, body or drape solver.
public enum SelfContactGuard {
    public typealias Vector = SIMD3<Double>
    public enum Status: String, Sendable {
        case clear, limited, blockedInitialContact, uncertain, invalid, cancelled, budgetExceeded
    }
    public enum WitnessKind: String, Sendable {case vertexFace, edgeEdge, triangleDomain, edgeDomain}
    public enum Failure: Error, Sendable, Equatable {case invalid(String),budgetExceeded(String),cancelled}
    public struct Limits: Sendable {
        public var maximumVertices=20_000,maximumTriangles=40_000,maximumBVHNodes=80_000
        public var maximumBuildWork=10_000_000,maximumBVHVisits=20_000_000
        public var maximumTrianglePairs=500_000,maximumFeatureQueries=1_000_000
        public var maximumCertificateNodes=10_000_000,maximumEstimatedBytes=256*1_024*1_024
        /// Independent bounded Euclidean supplementation after a native result
        /// whose primitive domain is already certified. Physical tol is unchanged.
        public var maximumEuclideanCertificateNodes=262_144
        public init() {}
    }
    public struct Options: Sendable {
        public var minimumSeparation:Double,distanceTolerance:Double,safetyFactor:Double
        public var maximumIterationsPerFeature:Int64
        public var limits:Limits
        public init(minimumSeparation:Double=0,distanceTolerance:Double=1e-8,
                    maximumIterationsPerFeature:Int64=10_000,safetyFactor:Double=0.9,limits:Limits = .init()) {
            self.minimumSeparation=minimumSeparation;self.distanceTolerance=distanceTolerance
            self.maximumIterationsPerFeature=maximumIterationsPerFeature;self.safetyFactor=safetyFactor;self.limits=limits
        }
    }
    public struct Statistics: Sendable {
        public internal(set) var vertices=0,triangles=0,edges=0
        public internal(set) var certifiedTriangles=0,certifiedEdges=0,certificateNodes=0
        public internal(set) var bvhNodes=0,bvhBuildWork=0,bvhNodeVisits=0,trianglePairs=0
        public internal(set) var uniqueVertexFace=0,uniqueEdgeEdge=0,evaluatedFeatures=0,nativeQueries=0
        public internal(set) var excludedPrimitiveAdjacencies=0,estimatedWorkingBytes=0
        /// Conservative swept primitive-box separation visits, before canonical
        /// feature deduplication; no native CCD call is needed for these visits.
        public internal(set) var aabbPrunedVertexFaceVisits=0,aabbPrunedEdgeEdgeVisits=0
        public var aabbPrunedPrimitiveVisits:Int {aabbPrunedVertexFaceVisits+aabbPrunedEdgeEdgeVisits}
        public internal(set) var euclideanCertificateAttempts=0,euclideanCertifiedFeatures=0
        public internal(set) var euclideanCertificateNodes=0,euclideanCertifiedAfterPrecisionLimit=0
        public internal(set) var completedDomainCertificates=false,completedAllFeatures=false
    }
    public struct Witness: Sendable {
        public let kind:WitnessKind
        /// Original independent source IDs in the exact native query order.
        public let vertexIDs:[UInt32]
        public let faceID:UInt32?
        public let conservativeTimeOfImpact:Double?
        public let achievedDistanceTolerance:Double?
        public let nativeDetail:NativeClothCollision.Detail?
        public let initialDistance:Double?
    }
    public struct Report: Sendable {
        public let status:Status,safeTime:Double,conservativeTimeOfImpact:Double?
        public let minimumSeparation:Double,reason:String,witness:Witness?,statistics:Statistics
        /// Every authorization is conditional on the independently certified
        /// initial state; .clear does not establish that bootstrap proof.
        public var requiresIntersectionFreeInitialState:Bool {true}
        public var permitsWholeCandidate:Bool {status == .clear && safeTime==1}
        public var permitsCertifiedPrefix:Bool {(status == .clear || status == .limited) && statistics.completedAllFeatures && safeTime>0}
    }
    private struct Edge:Hashable,Sendable {let a:UInt32,b:UInt32;init(_ a:UInt32,_ b:UInt32){self.a=min(a,b);self.b=max(a,b)}}
    private struct FaceKey:Hashable {let a:UInt32,b:UInt32,c:UInt32}
    private struct Feature:Hashable {let edgeEdge:Bool,a:UInt32,b:UInt32,c:UInt32,d:UInt32}
    private struct Bounds:Sendable {
        let minimum:Vector,maximum:Vector
        func overlaps(_ b:Bounds)->Bool {minimum.x<=b.maximum.x && b.minimum.x<=maximum.x && minimum.y<=b.maximum.y && b.minimum.y<=maximum.y && minimum.z<=b.maximum.z && b.minimum.z<=maximum.z}
        func union(_ b:Bounds)->Bounds {.init(minimum:low(minimum,b.minimum),maximum:high(maximum,b.maximum))}
    }
    private struct Node:Sendable {var bounds:Bounds;var left = -1,right = -1,begin=0,end=0}
    public struct Prepared:Sendable {
        public let vertexCount:Int,triangleIndices:[UInt32],estimatedResidentBytes:Int
        private let edges:[Edge]
        public init(vertexCount:Int,triangleIndices:[UInt32],limits:Limits = .init(),isCancelled:(()->Bool)?=nil)throws {
            if isCancelled?()==true{throw Failure.cancelled}
            guard valid(limits),vertexCount>0,!triangleIndices.isEmpty,triangleIndices.count%3==0 else{throw Failure.invalid("source topology or limits")}
            let count=triangleIndices.count/3
            guard vertexCount<=limits.maximumVertices,count<=limits.maximumTriangles else{throw Failure.budgetExceeded("source topology")}
            // Reserve constructor's complete edge/face sets before allocating.
            let estimate=triangleIndices.count*MemoryLayout<UInt32>.stride+count*(3*64+96)+vertexCount*2+1_024
            guard estimate<=limits.maximumEstimatedBytes else{throw Failure.budgetExceeded("prepared topology bytes")}
            var referenced=Array(repeating:false,count:vertexCount),seen=Set<FaceKey>(),uniqueEdges=Set<Edge>()
            for f in 0..<count {
                if f%128==0,isCancelled?()==true{throw Failure.cancelled}
                let ids=Array(triangleIndices[3*f..<3*f+3]),sorted=ids.sorted()
                guard Int(sorted[2])<vertexCount,sorted[0] != sorted[1],sorted[1] != sorted[2],seen.insert(.init(a:sorted[0],b:sorted[1],c:sorted[2])).inserted else{throw Failure.invalid("source face IDs or duplicate indexed face")}
                for i in 0..<3{referenced[Int(ids[i])]=true;uniqueEdges.insert(Edge(ids[i],ids[(i+1)%3]))}
            }
            guard referenced.allSatisfy({$0}) else{throw Failure.invalid("unreferenced source vertex; triangle surfaces only")}
            if isCancelled?()==true{throw Failure.cancelled}
            self.vertexCount=vertexCount;self.triangleIndices=triangleIndices;self.estimatedResidentBytes=estimate
            self.edges=uniqueEdges.sorted{$0.a==$1.a ? $0.b<$1.b:$0.a<$1.a}
        }
        /// Call only with the complete independently intersection-free initial
        /// mesh, then with states accepted by a prior COMPLETE guard result.
        /// Uncertain/cancelled/budget results cannot advance or replace that state.
        public func guardMotion(previous:[Vector],candidate:[Vector],options:Options = .init(),isCancelled:(()->Bool)?=nil)->Report {
            var stats=Statistics();stats.vertices=vertexCount;stats.triangles=triangleIndices.count/3;stats.edges=edges.count;stats.estimatedWorkingBytes=estimatedResidentBytes
            var earliest:Double?,earliestWitness:Witness?
            func report(_ status:Status,_ reason:String,_ witness:Witness?=nil)->Report {
                let safe:Double
                if status == .clear{safe=1}
                else if status == .limited,let t=earliest,t>0{safe=max(0,min(t.nextDown,t*options.safetyFactor))}
                else{safe=0}
                return .init(status:status,safeTime:safe,conservativeTimeOfImpact:earliest,minimumSeparation:options.minimumSeparation,reason:reason,witness:witness ?? earliestWitness,statistics:stats)
            }
            if isCancelled?()==true{return report(.cancelled,"cancelled before query")}
            let l=options.limits
            guard valid(l),options.minimumSeparation.isFinite,options.minimumSeparation>=0,options.minimumSeparation<1,
                  options.distanceTolerance.isFinite,options.distanceTolerance>0,options.distanceTolerance<=1,
                  options.safetyFactor.isFinite,options.safetyFactor>0,options.safetyFactor<1,
                  options.maximumIterationsPerFeature>=1,options.maximumIterationsPerFeature<=100_000 else{return report(.invalid,"options")}
            guard previous.count==vertexCount,candidate.count==vertexCount else{return report(.invalid,"pose vertex count")}
            guard vertexCount<=l.maximumVertices,stats.triangles<=l.maximumTriangles else{return report(.budgetExceeded,"query topology")}
            let topologyAndPoses=estimatedResidentBytes+2*vertexCount*MemoryLayout<Vector>.stride
            let bvhScratch=stats.triangles*(MemoryLayout<Bounds>.stride+2*MemoryLayout<Node>.stride+3*MemoryLayout<Int>.stride)
            let nativeScratch=Int(options.maximumIterationsPerFeature)*1_024+65_536
            // Same conservative 1MiB ephemeral certificate reservation as the
            // body guard, charged before candidates/native queries. It is not RSS.
            let certificateScratch=1_048_576
            let reserved=topologyAndPoses+bvhScratch+nativeScratch+certificateScratch+1_024
            stats.estimatedWorkingBytes=reserved
            guard reserved<=l.maximumEstimatedBytes else{return report(.budgetExceeded,"complete query base/scratch bytes")}
            for i in 0..<vertexCount {
                if i%128==0,isCancelled?()==true{return report(.cancelled,"cancelled validating coordinates")}
                guard finite(previous[i]),finite(candidate[i]) else{return report(.invalid,"nonfinite/unsupported pose coordinate")}
            }
            // Even an isolated face with no collision candidates must not
            // collapse between endpoints. No primitive query with fake geometry.
            for f in 0..<stats.triangles {
                if isCancelled?()==true{return report(.cancelled,"cancelled certifying all triangles")}
                let ids=faceIDs(f),start=flat(ids.map{previous[Int($0)]}),end=flat(ids.map{candidate[Int($0)]})
                let remaining=l.maximumCertificateNodes-stats.certificateNodes
                guard remaining>0 else{return report(.budgetExceeded,"triangle certificate nodes")}
                let certificate=start.withUnsafeBufferPointer {a in end.withUnsafeBufferPointer {b in
                    ncc_self_triangle_certificate(a.baseAddress,a.count,b.baseAddress,b.count,1,Int32(min(128,remaining)))
                }}
                stats.certificateNodes+=Int(certificate.visited_nodes)
                if certificate.status != 1 {
                    let witness=Witness(kind:.triangleDomain,vertexIDs:ids,faceID:UInt32(f),conservativeTimeOfImpact:nil,achievedDistanceTolerance:nil,nativeDetail:.init(rawValue:certificate.detail),initialDistance:nil)
                    let status:Status=certificate.status==0 ? .invalid:((remaining<128 && certificate.detail==4) ? .budgetExceeded:.uncertain)
                    return report(status,"whole-interval triangle domain not certified",witness)
                }
                stats.certifiedTriangles+=1
            }
            for e in edges {
                if isCancelled?()==true{return report(.cancelled,"cancelled certifying all edges")}
                guard stats.certificateNodes<l.maximumCertificateNodes else{return report(.budgetExceeded,"edge certificate nodes")}
                let ids=[e.a,e.b],start=flat(ids.map{previous[Int($0)]}),end=flat(ids.map{candidate[Int($0)]})
                let certificate=start.withUnsafeBufferPointer {a in end.withUnsafeBufferPointer {b in
                    ncc_self_edge_certificate(a.baseAddress,a.count,b.baseAddress,b.count,1)
                }}
                stats.certificateNodes+=Int(certificate.visited_nodes)
                if certificate.status != 1 {
                    let witness=Witness(kind:.edgeDomain,vertexIDs:ids,faceID:nil,conservativeTimeOfImpact:nil,achievedDistanceTolerance:nil,nativeDetail:.init(rawValue:certificate.detail),initialDistance:nil)
                    return report(certificate.status==0 ? .invalid:.uncertain,"whole-interval edge domain not certified",witness)
                }
                stats.certifiedEdges+=1
            }
            stats.completedDomainCertificates=true
            // Round the SUM outward too: outward rounding only the later box
            // subtraction/addition does not cover a rounded-down dmin+tol.
            let separationPadding=(options.minimumSeparation+options.distanceTolerance).nextUp
            var boxes:[Bounds]=[];boxes.reserveCapacity(stats.triangles)
            for f in 0..<stats.triangles {
                if f%128==0,isCancelled?()==true{return report(.cancelled,"cancelled preparing swept faces")}
                let ids=faceIDs(f),a=triangleBounds(previous[Int(ids[0])],previous[Int(ids[1])],previous[Int(ids[2])]),b=triangleBounds(candidate[Int(ids[0])],candidate[Int(ids[1])],candidate[Int(ids[2])])
                boxes.append(a.union(b))
            }
            var builder=Builder(bounds:boxes,limits:l,isCancelled:isCancelled)
            var features:[Feature]=[],unique=Set<Feature>()
            func add(_ f:Feature)throws {
                if unique.contains(f){return}
                guard features.count<l.maximumFeatureQueries else{throw Failure.budgetExceeded("unique self features")}
                let bytes=reserved+(features.count+1)*256
                guard bytes<=l.maximumEstimatedBytes else{throw Failure.budgetExceeded("complete feature list/Set bytes")}
                stats.estimatedWorkingBytes=max(stats.estimatedWorkingBytes,bytes);unique.insert(f);features.append(f)
                if f.edgeEdge{stats.uniqueEdgeEdge+=1}else{stats.uniqueVertexFace+=1}
            }
            do {
                _=try builder.build(0,stats.triangles);stats.bvhNodes=builder.nodes.count;stats.bvhBuildWork=builder.work
                for a in 0..<stats.triangles {
                    if isCancelled?()==true{throw Failure.cancelled}
                    let query=expanded(boxes[a],by:separationPadding)
                    let hits=try search(query,after:a,nodes:builder.nodes,order:builder.order,bounds:boxes,visits:&stats.bvhNodeVisits,remainingPairs:l.maximumTrianglePairs-stats.trianglePairs,limits:l,isCancelled:isCancelled)
                    let ai=faceIDs(a)
                    for b in hits {
                        stats.trianglePairs+=1;let bi=faceIDs(b)
                        // Sharing a vertex NEVER removes the whole face pair.
                        for v in ai {if bi.contains(v){stats.excludedPrimitiveAdjacencies+=1}else{
                            let point=sweptPointBounds(previous[Int(v)],candidate[Int(v)])
                            if expanded(point,by:separationPadding).overlaps(boxes[b]) {try add(.init(edgeEdge:false,a:v,b:UInt32(b),c:0,d:0))}
                            else{stats.aabbPrunedVertexFaceVisits+=1}
                        }}
                        for v in bi {if ai.contains(v){stats.excludedPrimitiveAdjacencies+=1}else{
                            let point=sweptPointBounds(previous[Int(v)],candidate[Int(v)])
                            if expanded(point,by:separationPadding).overlaps(boxes[a]) {try add(.init(edgeEdge:false,a:v,b:UInt32(a),c:0,d:0))}
                            else{stats.aabbPrunedVertexFaceVisits+=1}
                        }}
                        for i in 0..<3{for j in 0..<3 {
                            let ea=Edge(ai[i],ai[(i+1)%3]),eb=Edge(bi[j],bi[(j+1)%3])
                            if ea.a==eb.a || ea.a==eb.b || ea.b==eb.a || ea.b==eb.b {stats.excludedPrimitiveAdjacencies+=1;continue}
                            let aBox=sweptPointBounds(previous[Int(ea.a)],candidate[Int(ea.a)]).union(sweptPointBounds(previous[Int(ea.b)],candidate[Int(ea.b)]))
                            let bBox=sweptPointBounds(previous[Int(eb.a)],candidate[Int(eb.a)]).union(sweptPointBounds(previous[Int(eb.b)],candidate[Int(eb.b)]))
                            if !expanded(aBox,by:separationPadding).overlaps(bBox){stats.aabbPrunedEdgeEdgeVisits+=1;continue}
                            let first=ea.a<eb.a || (ea.a==eb.a && ea.b<eb.b) ? ea:eb,second=first==ea ? eb:ea
                            try add(.init(edgeEdge:true,a:first.a,b:first.b,c:second.a,d:second.b))
                        }}
                    }
                }
            }catch let failure as Failure {
                stats.bvhNodes=builder.nodes.count;stats.bvhBuildWork=builder.work
                switch failure {case .cancelled:return report(.cancelled,"cancelled generating complete self candidates")
                case let .invalid(reason):return report(.invalid,reason)
                case let .budgetExceeded(reason):return report(.budgetExceeded,reason)}
            }catch{stats.bvhNodes=builder.nodes.count;stats.bvhBuildWork=builder.work;return report(.uncertain,"unexpected self broadphase failure")}
            features.sort {a,b in
                if a.edgeEdge != b.edgeEdge{return !a.edgeEdge}
                if a.a != b.a{return a.a<b.a};if a.b != b.b{return a.b<b.b};if a.c != b.c{return a.c<b.c};return a.d<b.d
            }
            let ccd=NativeClothCollision.Options(minimumSeparation:options.minimumSeparation,maximumTime:1,distanceTolerance:options.distanceTolerance,maximumIterations:options.maximumIterationsPerFeature)
            for feature in features {
                if isCancelled?()==true{return report(.cancelled,"cancelled evaluating complete self candidates")}
                let ids:[UInt32],kind:WitnessKind,face:UInt32?
                if feature.edgeEdge{ids=[feature.a,feature.b,feature.c,feature.d];kind = .edgeEdge;face=nil}
                else{ids=[feature.a]+faceIDs(Int(feature.b));kind = .vertexFace;face=feature.b}
                let start=ids.map{previous[Int($0)]},end=ids.map{candidate[Int($0)]}
                let d2=feature.edgeEdge ? segmentDistance2(start[0],start[1],start[2],start[3]):pointTriangleDistance2(start[0],start[1],start[2],start[3])
                guard d2.isFinite,d2>=0 else{return report(.uncertain,"initial self feature distance arithmetic")}
                stats.evaluatedFeatures+=1
                let scale=start.reduce(1.0){max($0,max(abs($1.x),max(abs($1.y),abs($1.z))))},contactDistance=options.minimumSeparation+32*scale*Double.ulpOfOne
                if d2<=contactDistance*contactDistance {
                    earliest=0;let witness=Witness(kind:kind,vertexIDs:ids,faceID:face,conservativeTimeOfImpact:0,achievedDistanceTolerance:0,nativeDetail:nil,initialDistance:d2.squareRoot())
                    return report(.blockedInitialContact,"initial independent self primitive contact",witness)
                }
                stats.nativeQueries+=1
                let result=feature.edgeEdge ? NativeClothCollision.edgeEdge(start:flat(start),end:flat(end),options:ccd,isCancelled:isCancelled):NativeClothCollision.vertexFace(start:flat(start),end:flat(end),options:ccd,isCancelled:isCancelled)
                let witness=Witness(kind:kind,vertexIDs:ids,faceID:face,conservativeTimeOfImpact:result.conservativeTimeOfImpact,achievedDistanceTolerance:result.achievedDistanceTolerance,nativeDetail:result.detail,initialDistance:nil)
                // Both allowed details are returned only AFTER the pinned native
                // triangle/edge domain checks. A distance-only certificate must
                // never override uncertain geometry, invalid inputs or rounding.
                let certifiedNativeDomain=(result.status == .conservativeHit && result.detail == .none) ||
                    (result.status == .uncertain && result.detail == .precisionOrBudget)
                if certifiedNativeDomain {
                    let remaining=l.maximumEuclideanCertificateNodes-stats.euclideanCertificateNodes
                    guard remaining>0 else{return report(.budgetExceeded,"self Euclidean certificate node budget",witness)}
                    var certificateLimits=FeatureSeparationCertificate.Limits()
                    certificateLimits.maximumNodes=min(certificateLimits.maximumNodes,remaining)
                    stats.euclideanCertificateAttempts+=1
                    let certificate=FeatureSeparationCertificate.certify(kind:feature.edgeEdge ? .edgeEdge:.vertexFace,
                        start:start,end:end,minimumSeparation:options.minimumSeparation,
                        limits:certificateLimits,isCancelled:{isCancelled?() == true})
                    stats.euclideanCertificateNodes+=certificate.processedNodes
                    if isCancelled?() == true || certificate.status == .cancelled{return report(.cancelled,"cancelled self Euclidean certificate",witness)}
                    switch certificate.status {
                    case .separated:
                        stats.euclideanCertifiedFeatures+=1
                        if result.status == .uncertain{stats.euclideanCertifiedAfterPrecisionLimit+=1}
                        continue // This one feature only; all remaining features still run.
                    case .budgetExceeded:return report(.budgetExceeded,"self Euclidean certificate work/memory budget",witness)
                    case .invalid,.unsupportedRounding:return report(.uncertain,"self Euclidean certificate input/rounding unresolved",witness)
                    case .notCertified:break
                    case .cancelled:return report(.cancelled,"cancelled self Euclidean certificate",witness)
                    }
                }
                switch result.status {
                case .invalid:return report(.invalid,"native self CCD input rejected",witness)
                case .uncertain:return report(result.detail == .cancelled ? .cancelled:.uncertain,"native self CCD unresolved: \(result.detail)",witness)
                case .noHit:break
                case .conservativeHit:
                    let t=result.conservativeTimeOfImpact
                    if t==0{earliest=0;return report(.blockedInitialContact,"possible initial self contact from conservative CCD",witness)}
                    if earliest==nil || t<earliest!{earliest=t;earliestWitness=witness}
                }
            }
            if isCancelled?() == true{return report(.cancelled,"cancelled completing self query")}
            guard FloatingPointEnvironment.isNearestRounding else{return report(.uncertain,"unsupported floating-point rounding completing self query")}
            stats.completedAllFeatures=true
            return report(earliest==nil ? .clear:.limited,earliest==nil ? "all moving self features and domains certified clear":"complete self query limited by conservative TOI")
        }
        private func faceIDs(_ f:Int)->[UInt32] {Array(triangleIndices[3*f..<3*f+3])}
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
    private static func search(_ bounds:Bounds,after:Int,nodes:[Node],order:[Int],bounds faceBounds:[Bounds],visits:inout Int,remainingPairs:Int,limits:Limits,isCancelled:(()->Bool)?)throws->[Int] {
        var stack=[0],result:[Int]=[]
        while let index=stack.popLast() {
            if isCancelled?()==true{throw Failure.cancelled}
            guard visits<limits.maximumBVHVisits else{throw Failure.budgetExceeded("self BVH visits")}
            visits+=1;let node=nodes[index]
            if !node.bounds.overlaps(bounds){continue}
            if node.left>=0{stack.append(node.right);stack.append(node.left)}
            else{for i in node.begin..<node.end {
                let face=order[i]
                if face>after && faceBounds[face].overlaps(bounds) {
                    guard result.count<remainingPairs else{throw Failure.budgetExceeded("complete self triangle pairs")}
                    result.append(face)
                }
            }}
        }
        return result.sorted()
    }
    private static func valid(_ l:Limits)->Bool {
        l.maximumVertices>0 && l.maximumVertices<=20_000 && l.maximumTriangles>0 && l.maximumTriangles<=40_000 &&
        l.maximumBVHNodes>0 && l.maximumBVHNodes<=80_000 && l.maximumBuildWork>0 && l.maximumBuildWork<=10_000_000 &&
        l.maximumBVHVisits>0 && l.maximumBVHVisits<=20_000_000 && l.maximumTrianglePairs>0 && l.maximumTrianglePairs<=500_000 &&
        l.maximumFeatureQueries>0 && l.maximumFeatureQueries<=1_000_000 && l.maximumCertificateNodes>0 && l.maximumCertificateNodes<=10_000_000 &&
        l.maximumEuclideanCertificateNodes>=0 && l.maximumEuclideanCertificateNodes<=1_048_576 &&
        l.maximumEstimatedBytes>0 && l.maximumEstimatedBytes<=256*1_024*1_024
    }
    private static func flat(_ p:[Vector])->[Double] {p.flatMap{[$0.x,$0.y,$0.z]}}
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
    private static func sweptPointBounds(_ previous:Vector,_ candidate:Vector)->Bounds {
        Bounds(minimum:low(previous,candidate),maximum:high(previous,candidate))
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
