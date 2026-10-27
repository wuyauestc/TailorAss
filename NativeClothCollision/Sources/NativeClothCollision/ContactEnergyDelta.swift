import Foundation
import CIPCBodyContact

/// Increment estimates for the original signed IPC contact energy. A stable
/// formula applies to an identical canonical leaf/weight set; transitions use
/// the complete original rounded-block difference and explicitly report it.
/// Neither branch certifies a sign or changes E, gradient, raw Hessian or CCD.
public enum ContactEnergyDelta {
    public typealias Vector=SIMD3<Double>
    public enum Failure:Error,Sendable,Equatable {
        case invalid(String),foreignSnapshot,infeasible,degenerate,numerical,cancelled,unsupportedRounding,budgetExceeded
    }
    public struct Parameters:Sendable {
        public let stiffnessPascals:Double,minimumDistanceMeters:Double,activationGapMeters:Double
        public init(stiffnessPascals:Double,minimumDistanceMeters:Double,activationGapMeters:Double) {
            self.stiffnessPascals=stiffnessPascals;self.minimumDistanceMeters=minimumDistanceMeters
            self.activationGapMeters=activationGapMeters
        }
    }
    public struct Limits:Sendable {
        public var maximumVertices=20_000
        public var maximumLeaves=400_000
        /// Conservative charged payload, not allocator/RSS instrumentation.
        public var maximumSnapshotBytes=64*1_024*1_024
        public init() {}
    }
    public struct Leaf:Sendable {
        public let kind:Int32,vertexIDs:[UInt32],cachedDistanceType:Int32
        public let signedRestAreaSquareMeters:Double,roundedEnergyJoules:Double
        public init(kind:Int32,vertexIDs:[UInt32],cachedDistanceType:Int32,
                    signedRestAreaSquareMeters:Double,roundedEnergyJoules:Double) {
            self.kind=kind;self.vertexIDs=vertexIDs;self.cachedDistanceType=cachedDistanceType
            self.signedRestAreaSquareMeters=signedRestAreaSquareMeters;self.roundedEnergyJoules=roundedEnergyJoules
        }
        public init(bodyBlock:BodyContactPotential.LocalBlock) {
            self.init(kind:bodyBlock.kind.rawValue,vertexIDs:bodyBlock.stencilVertexIDs,
                cachedDistanceType:bodyBlock.cachedDistanceType,signedRestAreaSquareMeters:bodyBlock.signedRestAreaSquareMeters,
                roundedEnergyJoules:bodyBlock.energyJoules)
        }
        public init(clothBlock:ClothContactPotential.LocalBlock) {
            self.init(kind:clothBlock.kind.rawValue,vertexIDs:clothBlock.vertexIDs,
                cachedDistanceType:clothBlock.cachedDistanceType,signedRestAreaSquareMeters:clothBlock.signedRestAreaSquareMeters,
                roundedEnergyJoules:clothBlock.energyJoules)
        }
    }
    public struct Snapshot:Sendable {
        fileprivate let owner:UUID,positions:[Vector],body:[Leaf],cloth:[Leaf]
        public let chargedBytes:Int
        fileprivate init(owner:UUID,positions:[Vector],body:[Leaf],cloth:[Leaf],chargedBytes:Int) {
            self.owner=owner;self.positions=positions;self.body=body;self.cloth=cloth;self.chargedBytes=chargedBytes
        }
    }
    public enum Method:String,Sendable,Codable {case stableFixedLeaves,roundedBlockFallback}
    public enum FallbackReason:String,Sendable,Codable {case featureSetChanged,weightChanged,effectiveDistanceTypeChanged}
    public struct GroupReport:Sendable,Codable {
        public let deltaJoules:Double
        public let method:Method
        public let fallbackReason:FallbackReason?
        public let fixedLeaves:Int,attemptedStableLeaves:Int
        public let activationTransitions:Int,mollifierTransitions:Int
        public let originalRoundedBlockDeltaJoules:Double,absoluteStoredEnergyScaleJoules:Double
        fileprivate func choosingOriginalFallback(_ value:Double)->GroupReport {
            guard method == .roundedBlockFallback else {return self}
            return .init(deltaJoules:value,method:method,fallbackReason:fallbackReason,fixedLeaves:fixedLeaves,
                attemptedStableLeaves:attemptedStableLeaves,activationTransitions:activationTransitions,
                mollifierTransitions:mollifierTransitions,originalRoundedBlockDeltaJoules:value,
                absoluteStoredEnergyScaleJoules:absoluteStoredEnergyScaleJoules)
        }
    }
    public struct Report:Sendable,Codable {
        public let body:GroupReport,cloth:GroupReport
        public let isDoubleEstimate:Bool
        /// The original force owner can preserve its exact legacy accumulator
        /// bits on every fallback. Stable reports are unaffected; returned
        /// deltaJoules always denotes the value actually selected by the owner.
        public func selectingOriginalRoundedFallbacks(body bodyValue:Double,cloth clothValue:Double)throws->Report {
            guard bodyValue.isFinite,clothValue.isFinite else {throw Failure.numerical}
            return .init(body:body.choosingOriginalFallback(bodyValue),cloth:cloth.choosingOriginalFallback(clothValue),isDoubleEstimate:true)
        }
    }
    private struct Key:Hashable {
        let kind:Int32,ids:[UInt32],dtype:Int32
        init(_ leaf:Leaf){kind=leaf.kind;ids=leaf.vertexIDs;dtype=leaf.cachedDistanceType}
    }
    public struct Prepared:Sendable {
        public let restPositions:[Vector],fixedPositions:[Vector],limits:Limits
        public let bodyParameters:Parameters,clothParameters:Parameters
        private let owner=UUID()
        public init(restPositions:[Vector],fixedPositions:[Vector]=[],bodyParameters:Parameters,
                    clothParameters:Parameters,limits:Limits = .init(),isCancelled:(@Sendable()->Bool)?=nil)throws {
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
            guard (1...20_000).contains(limits.maximumVertices),(1...400_000).contains(limits.maximumLeaves),
                  (1...(128*1_024*1_024)).contains(limits.maximumSnapshotBytes),!restPositions.isEmpty else {throw Failure.invalid("limits/rest")}
            guard restPositions.count<=limits.maximumVertices,fixedPositions.count<=limits.maximumVertices-restPositions.count else {throw Failure.budgetExceeded}
            guard valid(bodyParameters),valid(clothParameters) else {throw Failure.invalid("physical parameters")}
            for (i,p) in (restPositions+fixedPositions).enumerated() {
                if i%256==0,isCancelled?() == true {throw Failure.cancelled}
                guard finite(p) else {throw Failure.invalid("rest coordinate")}
            }
            self.restPositions=restPositions;self.fixedPositions=fixedPositions;self.bodyParameters=bodyParameters
            self.clothParameters=clothParameters;self.limits=limits
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
        }
        /// The force producer supplies its actual complete leaves and positions.
        /// This receipt binds subsequent differences to this immutable source;
        /// it does not independently authenticate an arbitrary external producer.
        public func capture(positions:[Vector],bodyLeaves:[Leaf],clothLeaves:[Leaf],
                            isCancelled:(@Sendable()->Bool)?=nil)throws->Snapshot {
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
            guard positions.count==restPositions.count else {throw Failure.invalid("position count")}
            guard bodyLeaves.count<=limits.maximumLeaves,clothLeaves.count<=limits.maximumLeaves-bodyLeaves.count else {throw Failure.budgetExceeded}
            let charged=positions.count*32+(bodyLeaves.count+clothLeaves.count)*160+256
            guard charged<=limits.maximumSnapshotBytes else {throw Failure.budgetExceeded}
            for (i,p) in positions.enumerated() {
                if i%256==0,isCancelled?() == true {throw Failure.cancelled}
                guard finite(p) else {throw Failure.invalid("position")}
            }
            try validate(bodyLeaves,vertexCount:positions.count+fixedPositions.count,requiresMovingVertex:true,isCancelled:isCancelled)
            try validate(clothLeaves,vertexCount:positions.count,requiresMovingVertex:false,isCancelled:isCancelled)
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
            return Snapshot(owner:owner,positions:positions,body:bodyLeaves,cloth:clothLeaves,chargedBytes:charged)
        }
        public func difference(from a:Snapshot,to b:Snapshot,isCancelled:(@Sendable()->Bool)?=nil)throws->Report {
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
            guard a.owner==owner,b.owner==owner else {throw Failure.foreignSnapshot}
            let body=try group(a.body,b.body,from:a.positions+fixedPositions,to:b.positions+fixedPositions,
                rest:restPositions+fixedPositions,parameters:bodyParameters,isCancelled:isCancelled)
            let cloth=try group(a.cloth,b.cloth,from:a.positions,to:b.positions,rest:restPositions,
                parameters:clothParameters,isCancelled:isCancelled)
            if isCancelled?() == true {throw Failure.cancelled}
            guard FloatingPointEnvironment.isNearestRounding else {throw Failure.unsupportedRounding}
            return .init(body:body,cloth:cloth,isDoubleEstimate:true)
        }
        private func validate(_ leaves:[Leaf],vertexCount:Int,requiresMovingVertex:Bool,isCancelled:(@Sendable()->Bool)?)throws {
            var keys=Set<Key>();keys.reserveCapacity(leaves.count)
            for (i,b) in leaves.enumerated() {
                if i%32==0,isCancelled?() == true {throw Failure.cancelled}
                let nv=b.kind==0 ? 2:(b.kind==1 ? 3:4),maximumType=b.kind==0 ? 0:(b.kind==1 ? 2:(b.kind==2 ? 8:6))
                guard (0...3).contains(b.kind),b.vertexIDs.count==nv,Set(b.vertexIDs).count==nv,
                      b.vertexIDs.allSatisfy({Int($0)<vertexCount}),(-1...maximumType).contains(Int(b.cachedDistanceType)),
                      b.signedRestAreaSquareMeters.isFinite,b.roundedEnergyJoules.isFinite,
                      !requiresMovingVertex || b.vertexIDs.contains(where:{Int($0)<restPositions.count}),
                      keys.insert(Key(b)).inserted else {throw Failure.invalid("leaf identity/weight/energy")}
            }
        }
        private func group(_ old:[Leaf],_ new:[Leaf],from x0:[Vector],to x1:[Vector],rest:[Vector],parameters p:Parameters,
                           isCancelled:(@Sendable()->Bool)?)throws->GroupReport {
            var legacy=Sum(),scale=Sum()
            for (sign,blocks) in [(1.0,new),(-1.0,old)] {
                for (i,b) in blocks.enumerated() {
                    if i%32==0,isCancelled?() == true {throw Failure.cancelled}
                    legacy.add(sign*b.roundedEnergyJoules);scale.add(abs(b.roundedEnergyJoules))
                }
            }
            guard legacy.value.isFinite,scale.value.isFinite else {throw Failure.numerical}
            func fallback(_ reason:FallbackReason,_ attempts:Int)->GroupReport {
                .init(deltaJoules:legacy.value,method:.roundedBlockFallback,fallbackReason:reason,fixedLeaves:0,
                      attemptedStableLeaves:attempts,activationTransitions:0,mollifierTransitions:0,
                      originalRoundedBlockDeltaJoules:legacy.value,absoluteStoredEnergyScaleJoules:scale.value)
            }
            guard old.count==new.count else {return fallback(.featureSetChanged,0)}
            var lookup=[Key:Leaf]();lookup.reserveCapacity(new.count)
            for (i,b) in new.enumerated() {
                if i%32==0,isCancelled?() == true {throw Failure.cancelled}
                lookup[Key(b)]=b
            }
            for (i,a) in old.enumerated() {
                if i%32==0,isCancelled?() == true {throw Failure.cancelled}
                guard let b=lookup[Key(a)] else {return fallback(.featureSetChanged,0)}
                guard a.signedRestAreaSquareMeters.bitPattern==b.signedRestAreaSquareMeters.bitPattern else {return fallback(.weightChanged,0)}
            }
            var stable=Sum(),activation=0,mollifier=0
            for (i,a) in old.enumerated() {
                if i%32==0,isCancelled?() == true {throw Failure.cancelled}
                let previous=a.vertexIDs.flatMap{let v=x0[Int($0)];return [v.x,v.y,v.z]},current=a.vertexIDs.flatMap{let v=x1[Int($0)];return [v.x,v.y,v.z]}
                let reference=a.vertexIDs.flatMap{let v=rest[Int($0)];return [v.x,v.y,v.z]}
                var r=IPCEDResult()
                let status=previous.withUnsafeBufferPointer{aa in current.withUnsafeBufferPointer{bb in reference.withUnsafeBufferPointer{rr in
                    ipced_evaluate_local(a.kind,aa.baseAddress,aa.count,bb.baseAddress,bb.count,rr.baseAddress,rr.count,
                        a.cachedDistanceType,a.signedRestAreaSquareMeters,p.stiffnessPascals,p.minimumDistanceMeters,
                        p.activationGapMeters,nil,nil,&r)
                }}}
                if status==6 {return fallback(.effectiveDistanceTypeChanged,i+1)}
                guard status==0 else {throw nativeFailure(status)}
                guard r.delta_joules.isFinite else {throw Failure.numerical}
                stable.add(r.delta_joules);activation+=Int(r.activation_transition);mollifier+=Int(r.mollifier_transition)
            }
            guard stable.value.isFinite else {throw Failure.numerical}
            if isCancelled?() == true {throw Failure.cancelled}
            return .init(deltaJoules:stable.value,method:.stableFixedLeaves,fallbackReason:nil,fixedLeaves:old.count,
                         attemptedStableLeaves:old.count,activationTransitions:activation,mollifierTransitions:mollifier,
                         originalRoundedBlockDeltaJoules:legacy.value,absoluteStoredEnergyScaleJoules:scale.value)
        }
    }
    private struct Sum {
        private var s=0.0,c=0.0
        mutating func add(_ x:Double){let t=s+x;c += abs(s)>=abs(x) ? (s-t)+x:(x-t)+s;s=t}
        var value:Double{s+c}
    }
    private static func valid(_ p:Parameters)->Bool {
        p.stiffnessPascals.isFinite && p.stiffnessPascals>0 && p.minimumDistanceMeters.isFinite &&
        p.minimumDistanceMeters>=0 && p.activationGapMeters.isFinite && p.activationGapMeters>0 &&
        (p.minimumDistanceMeters+p.activationGapMeters).isFinite
    }
    private static func finite(_ p:Vector)->Bool {p.x.isFinite && p.y.isFinite && p.z.isFinite && max(abs(p.x),abs(p.y),abs(p.z))<=1e6}
    private static func nativeFailure(_ s:Int32)->Failure {
        switch s {case 1:return .invalid("native increment");case 2:return .infeasible;case 3:return .degenerate;
        case 5:return .cancelled;case 7:return .unsupportedRounding;default:return .numerical}
    }
}
