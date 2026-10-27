import CIPCBodyContact

/// IPC v1.6.1 signed, area-weighted triangle-surface body potential.
/// Body DOFs are fixed, but their rest integration areas and body-vertex / cloth-
/// face forces are retained. This is not cloth self-contact or an outside test.
public enum BodyContactPotential {
    public typealias Vector=SIMD3<Double>
    public enum HessianMode:Int32,Sendable {case exact=0,clampPositiveSemidefinite=1,absolutePositiveSemidefinite=2}
    public enum FeatureKind:Int32,Sendable {case vertexVertex=0,edgeVertex=1,edgeEdge=2,faceVertex=3}
    public enum Failure:Error,Sendable,Equatable {
        case invalid(String),infeasible,degenerate,numerical,cancelled,budgetExceeded(String),unsupportedTopology
    }
    public struct Parameters:Sendable {
        public let stiffnessPascals:Double
        public let minimumDistanceMeters:Double
        public let activationGapMeters:Double
        public let hessianMode:HessianMode
        /// Experimental parameters, not a calibrated fabric/contact material.
        public init(stiffnessPascals:Double,minimumDistanceMeters:Double,activationGapMeters:Double,
                    hessianMode:HessianMode = .exact) {
            self.stiffnessPascals=stiffnessPascals;self.minimumDistanceMeters=minimumDistanceMeters
            self.activationGapMeters=activationGapMeters;self.hessianMode=hessianMode
        }
    }
    public struct Limits:Sendable {
        public var maximumCombinedVertices=20_000
        public var maximumCombinedTriangles=40_000
        public var maximumPrimaryCandidates=200_000
        public var maximumStencils=200_000
        public var maximumFacePairs=200_000
        public var maximumBVHVisitsPerClothFace=10_000
        /// The product of the face count and this per-face limit bounds query
        /// work; the native builder also checks cancellation every 32 visits.
        public var maximumStagedBlockBytes=64*1_024*1_024
        public init() {}
    }
    public struct LocalBlock:Sendable {
        public let kind:FeatureKind
        /// Original combined IDs: cloth first, followed by immutable body IDs.
        public let stencilVertexIDs:[UInt32]
        /// Original cloth IDs only; no body DOF is present in these arrays.
        public let clothVertexIDs:[UInt32]
        public let signedRestAreaSquareMeters:Double
        public let cachedDistanceType:Int32
        public let energyJoules:Double
        public let clothGradientNewtons:[Vector]
        /// Row-major (3*clothVertexIDs.count)^2. Selected PSD, if any, was
        /// applied to the WHOLE signed local block before fixed-body removal.
        public let clothHessianRowMajorNewtonsPerMeter:[Double]
        public var isBodyVertexClothFace:Bool {
            kind == .faceVertex && stencilVertexIDs.first.map{!clothVertexIDs.contains($0)} == true
        }
    }
    public struct Statistics:Sendable {
        public let completeBVHFacePairs:Int
        public let primaryFeatureCandidates:Int
        public let stencils:Int
        public let negativeStencils:Int
        public let clothVertexBodyFaceStencils:Int
        public let bodyVertexClothFaceStencils:Int
        public let edgeVertexStencils:Int
        public let edgeEdgeStencils:Int
        public let vertexVertexStencils:Int
        public let chargedStagedBlockBytes:Int
        public let minimumCandidateDistanceMeters:Double?
    }
    public struct Evaluation:Sendable {
        public let energyJoules:Double
        public let clothGradientNewtons:[Vector]
        public let localBlocks:[LocalBlock]
        public let hessianMode:HessianMode
        public let statistics:Statistics
        /// Matrix-free application of already-complete, cloth-restricted blocks.
        /// A raw Hessian can be indefinite. Projected local blocks are solver
        /// surrogates; neither mode certifies exterior or nonnegative energy.
        public func hessianProduct(direction:[Vector],isCancelled:(@Sendable()->Bool)?=nil)throws->[Vector] {
            guard direction.count==clothGradientNewtons.count,direction.allSatisfy(finite) else {throw Failure.invalid("Hessian direction")}
            if isCancelled?() == true {throw Failure.cancelled}
            var result=Array(repeating:Vector.zero,count:direction.count)
            for (blockID,b) in localBlocks.enumerated() {
                if blockID%32==0,isCancelled?() == true {throw Failure.cancelled}
                let n=b.clothVertexIDs.count*3,H=b.clothHessianRowMajorNewtonsPerMeter
                for i in 0..<n {
                    var value=0.0
                    for j in 0..<n {value += H[i*n+j]*direction[Int(b.clothVertexIDs[j/3])][j%3]}
                    result[Int(b.clothVertexIDs[i/3])][i%3] += value
                }
            }
            guard result.allSatisfy(finite) else {throw Failure.numerical}
            if isCancelled?() == true {throw Failure.cancelled};return result
        }
    }
    /// Immutable native rest topology and the exact visible-body BVH. The native
    /// handle is read-only during evaluation; each call owns its trial buffers.
    public final class Prepared:@unchecked Sendable {
        public let clothRestPositions:[Vector]
        public let clothTriangleIndices:[UInt32]
        public let body:ContinuousBodyContact.Prepared
        public let limits:Limits
        private let handle:OpaquePointer
        private let combinedRest:[Double]
        public init(clothRestPositions:[Vector],clothTriangleIndices:[UInt32],
                    body:ContinuousBodyContact.Prepared,limits:Limits = .init(),
                    isCancelled:(@Sendable()->Bool)?=nil)throws {
            if isCancelled?() == true {throw Failure.cancelled}
            guard valid(limits) else {throw Failure.invalid("limits")}
            guard !clothRestPositions.isEmpty,!clothTriangleIndices.isEmpty,clothTriangleIndices.count%3==0 else {throw Failure.invalid("empty or incomplete cloth surface")}
            let nv=clothRestPositions.count+body.bodyPositions.count,nf=clothTriangleIndices.count/3+body.bodyTriangleIndices.count/3
            guard nv<=limits.maximumCombinedVertices,nf<=limits.maximumCombinedTriangles else {throw Failure.budgetExceeded("combined rest geometry")}
            for (i,p) in clothRestPositions.enumerated() {
                if i%256==0,isCancelled?() == true {throw Failure.cancelled}
                guard finite(p),max(abs(p.x),abs(p.y),abs(p.z))<=1e6 else {throw Failure.invalid("cloth rest coordinate")}
            }
            guard clothTriangleIndices.allSatisfy({Int($0)<clothRestPositions.count}) else {throw Failure.invalid("cloth triangle index")}
            let rest=(clothRestPositions+body.bodyPositions).flatMap{[$0.x,$0.y,$0.z]}
            let offset=UInt32(clothRestPositions.count),triangles=clothTriangleIndices+body.bodyTriangleIndices.map{$0+offset}
            let state=CallState(clothCount:clothRestPositions.count,maximumBytes:limits.maximumStagedBlockBytes,isCancelled:isCancelled)
            var status:Int32 = -1
            let pointer=withExtendedLifetime(state) {
                rest.withUnsafeBufferPointer{r in triangles.withUnsafeBufferPointer{t in
                    ipcb_create(r.baseAddress,nv,clothRestPositions.count,t.baseAddress,nf,limits.maximumPrimaryCandidates,limits.maximumStencils,
                                cancellationCallback,Unmanaged.passUnretained(state).toOpaque(),&status)
                }}
            }
            guard let pointer,status==0 else {throw failure(status)}
            if isCancelled?() == true {ipcb_destroy(pointer);throw Failure.cancelled}
            self.clothRestPositions=clothRestPositions;self.clothTriangleIndices=clothTriangleIndices;self.body=body
            self.limits=limits;self.handle=pointer;self.combinedRest=rest
        }
        deinit {ipcb_destroy(handle)}
        /// Builds all body BVH face pairs and all signed bidirectional VF/EE
        /// stencils. Outputs and callback blocks remain private until SUCCESS;
        /// any budget, cancellation or native failure discards the entire trial.
        public func evaluate(clothPositions:[Vector],parameters:Parameters,
                             isCancelled:(@Sendable()->Bool)?=nil)throws->Evaluation {
            if isCancelled?() == true {throw Failure.cancelled}
            let radius=parameters.minimumDistanceMeters+parameters.activationGapMeters
            guard clothPositions.count==clothRestPositions.count,parameters.stiffnessPascals.isFinite,parameters.stiffnessPascals>0,
                  parameters.minimumDistanceMeters.isFinite,parameters.minimumDistanceMeters>=0,
                  parameters.activationGapMeters.isFinite,parameters.activationGapMeters>0,radius.isFinite else {throw Failure.invalid("coordinates or parameters")}
            for (i,p) in clothPositions.enumerated() {
                if i%256==0,isCancelled?() == true {throw Failure.cancelled}
                guard finite(p),max(abs(p.x),abs(p.y),abs(p.z))<=1e6 else {throw Failure.invalid("current cloth coordinate")}
            }
            let clothFaces=clothTriangleIndices.count/3
            var pairs:[IPCBFacePair]=[]
            for f in 0..<clothFaces {
                if isCancelled?() == true {throw Failure.cancelled}
                let a=clothPositions[Int(clothTriangleIndices[3*f])],b=clothPositions[Int(clothTriangleIndices[3*f+1])],c=clothPositions[Int(clothTriangleIndices[3*f+2])]
                let lo=low(a,low(b,c)),hi=high(a,high(b,c))
                let bounds=ContinuousBodyContact.Bounds(minimum:.init((lo.x-radius).nextDown,(lo.y-radius).nextDown,(lo.z-radius).nextDown),
                                                        maximum:.init((hi.x+radius).nextUp,(hi.y+radius).nextUp,(hi.z+radius).nextUp))
                let remaining=limits.maximumFacePairs-pairs.count
                let candidates:[UInt32]
                do {candidates=try body.candidateTriangleIDs(in:bounds,maximumVisits:limits.maximumBVHVisitsPerClothFace,
                    maximumCandidates:max(1,remaining),isCancelled:isCancelled)}
                catch let e as ContinuousBodyContact.Failure {
                    switch e {case .cancelled:throw Failure.cancelled;case let .budgetExceeded(s):throw Failure.budgetExceeded(s);case let .invalid(s):throw Failure.invalid(s)}
                }
                guard candidates.count<=remaining else {throw Failure.budgetExceeded("complete face pairs")}
                pairs += candidates.map{IPCBFacePair(cloth_face:UInt32(f),body_face:UInt32(clothFaces)+$0)}
            }
            // Body is not an evaluate argument: it remains exactly its prepared
            // rest geometry, including its nonzero integration areas.
            let xyz=clothPositions.flatMap{[$0.x,$0.y,$0.z]}+Array(combinedRest.dropFirst(3*clothRestPositions.count))
            var gradient=Array(repeating:0.0,count:3*clothPositions.count),report=IPCBResult()
            let state=CallState(clothCount:clothPositions.count,maximumBytes:limits.maximumStagedBlockBytes,isCancelled:isCancelled)
            let code=withExtendedLifetime(state) {
                xyz.withUnsafeBufferPointer{x in pairs.withUnsafeBufferPointer{p in gradient.withUnsafeMutableBufferPointer{g in
                    ipcb_evaluate(handle,x.baseAddress,x.count,p.baseAddress,p.count,parameters.stiffnessPascals,parameters.minimumDistanceMeters,
                        parameters.activationGapMeters,parameters.hessianMode.rawValue,g.baseAddress,g.count,blockCallback,
                        Unmanaged.passUnretained(state).toOpaque(),cancellationCallback,Unmanaged.passUnretained(state).toOpaque(),&report)
                }}}
            }
            if let error=state.error {throw error}
            guard code==0,report.status==0 else {throw failure(code)}
            if isCancelled?() == true {throw Failure.cancelled}
            guard report.energy_joules.isFinite,gradient.allSatisfy(\.isFinite),state.blocks.count==report.stencil_count else {throw Failure.numerical}
            let g=stride(from:0,to:gradient.count,by:3).map{Vector(gradient[$0],gradient[$0+1],gradient[$0+2])}
            let stats=Statistics(completeBVHFacePairs:pairs.count,primaryFeatureCandidates:report.candidate_count,stencils:report.stencil_count,
                negativeStencils:report.negative_stencil_count,clothVertexBodyFaceStencils:report.fv_count,bodyVertexClothFaceStencils:report.bvf_count,
                edgeVertexStencils:report.ev_count,edgeEdgeStencils:report.ee_count,vertexVertexStencils:report.vv_count,
                chargedStagedBlockBytes:state.bytes,minimumCandidateDistanceMeters:report.minimum_candidate_distance_meters.isFinite ? report.minimum_candidate_distance_meters:nil)
            return Evaluation(energyJoules:report.energy_joules,clothGradientNewtons:g,localBlocks:state.blocks,hessianMode:parameters.hessianMode,statistics:stats)
        }
    }
    private final class CallState {
        let clothCount:Int,maximumBytes:Int,isCancelled:(@Sendable()->Bool)?
        var bytes=0,blocks:[LocalBlock]=[],error:Failure?
        init(clothCount:Int,maximumBytes:Int,isCancelled:(@Sendable()->Bool)?){self.clothCount=clothCount;self.maximumBytes=maximumBytes;self.isCancelled=isCancelled}
        func append(_ b:IPCBBlock) {
            if error != nil {return}
            guard let kind=FeatureKind(rawValue:b.kind),(2...4).contains(Int(b.num_vertices)),b.local.status==0 else {error = .numerical;return}
            let n=Int(b.num_vertices),ids=(b.vertex_ids.0,b.vertex_ids.1,b.vertex_ids.2,b.vertex_ids.3)
            func id(_ i:Int)->UInt32{switch i{case 0:return ids.0;case 1:return ids.1;case 2:return ids.2;default:return ids.3}}
            var cloth=0
            for i in 0..<n {if Int(id(i))<clothCount {cloth+=1}}
            guard cloth>0 else {error = .numerical;return}
            let dofs=cloth*3
            // Conservative allowance for Array growth/capacity and allocation
            // headers. Charged BEFORE copying any variable-sized local block.
            let charge=256+2*MemoryLayout<LocalBlock>.stride+8*n+8*cloth+64*cloth+16*dofs*dofs
            guard charge<=maximumBytes-bytes else {error = .budgetExceeded("staged local blocks");return}
            bytes+=charge
            let allIDs=(0..<n).map(id),slots=(0..<n).filter{Int(id($0))<clothCount},clothIDs=slots.map(id)
            guard Set(allIDs).count==n else {error = .numerical;return}
            let g=withUnsafeBytes(of:b.local.gradient_newtons){raw->[Vector] in
                let a=raw.bindMemory(to:Double.self);return slots.map{Vector(a[3*$0],a[3*$0+1],a[3*$0+2])}
            }
            let h=withUnsafeBytes(of:b.local.hessian_row_major_newtons_per_meter){raw->[Double] in
                let a=raw.bindMemory(to:Double.self),full=n*3;var result:[Double]=[];result.reserveCapacity(dofs*dofs)
                for i in slots {for ax in 0..<3 {for j in slots {for ay in 0..<3 {result.append(a[(3*i+ax)*full+3*j+ay])}}}}
                return result
            }
            guard b.signed_rest_area_m2.isFinite,b.local.energy_joules.isFinite,g.allSatisfy(finite),h.allSatisfy(\.isFinite) else {error = .numerical;return}
            blocks.append(LocalBlock(kind:kind,stencilVertexIDs:allIDs,clothVertexIDs:clothIDs,signedRestAreaSquareMeters:b.signed_rest_area_m2,
                cachedDistanceType:b.distance_type,energyJoules:b.local.energy_joules,clothGradientNewtons:g,clothHessianRowMajorNewtonsPerMeter:h))
        }
    }
    private static let cancellationCallback:@convention(c)(UnsafeMutableRawPointer?)->Int32 = {context in
        guard let context else{return 0};let state=Unmanaged<CallState>.fromOpaque(context).takeUnretainedValue()
        return state.error != nil || state.isCancelled?() == true ? 1:0
    }
    private static let blockCallback:@convention(c)(UnsafePointer<IPCBBlock>?,UnsafeMutableRawPointer?)->Void = {pointer,context in
        guard let pointer,let context else{return};Unmanaged<CallState>.fromOpaque(context).takeUnretainedValue().append(pointer.pointee)
    }
    private static func valid(_ l:Limits)->Bool {
        (1...20_000).contains(l.maximumCombinedVertices) && (1...40_000).contains(l.maximumCombinedTriangles) &&
        (1...200_000).contains(l.maximumPrimaryCandidates) && (1...200_000).contains(l.maximumStencils) &&
        (1...200_000).contains(l.maximumFacePairs) && (1...100_000).contains(l.maximumBVHVisitsPerClothFace) &&
        (1...256*1_024*1_024).contains(l.maximumStagedBlockBytes)
    }
    private static func failure(_ status:Int32)->Failure {
        switch status {case 2:return .infeasible;case 3:return .degenerate;case 4:return .numerical;case 5:return .cancelled;case 6:return .budgetExceeded("native candidates, stencils or topology");case 7:return .unsupportedTopology;default:return .invalid("native status \(status)")}
    }
    private static func finite(_ p:Vector)->Bool{p.x.isFinite && p.y.isFinite && p.z.isFinite}
    private static func low(_ a:Vector,_ b:Vector)->Vector{.init(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z))}
    private static func high(_ a:Vector,_ b:Vector)->Vector{.init(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z))}
}
