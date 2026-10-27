import XCTest
import Foundation
import CIPCBodyContact
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class ContactEnergyDeltaTests:XCTestCase {
    typealias D=ContactEnergyDelta
    typealias V=SIMD3<Double>
    struct Case:Decodable {
        let name:String,kind:Int32,dtype:Int32,weight:Double,kappa:Double,dmin:Double,h:Double
        let rest:[[Double]],previous:[[Double]],current:[[Double]],oracleDelta100:String
        let group:String?
        var r:[V]{rest.map{V($0[0],$0[1],$0[2])}}
        var a:[V]{previous.map{V($0[0],$0[1],$0[2])}}
        var b:[V]{current.map{V($0[0],$0[1],$0[2])}}
    }
    struct Cases:Decodable {let cases:[Case]}
    final class Counter:@unchecked Sendable {
        private let lock=NSLock();private var count=0
        func tick()->Int {lock.lock();defer{lock.unlock()};count+=1;return count}
    }
    func load(_ name:String)throws->[Case] {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/ContactEnergyDelta"))
        return try JSONDecoder().decode(Cases.self,from:Data(contentsOf:u)).cases
    }
    func native(_ c:Case,cancel:IPCEDCancel?=nil,context:UnsafeMutableRawPointer?=nil)->IPCEDResult {
        let a=c.previous.flatMap{$0},b=c.current.flatMap{$0},r=c.rest.flatMap{$0};var result=IPCEDResult()
        _=a.withUnsafeBufferPointer{aa in b.withUnsafeBufferPointer{bb in r.withUnsafeBufferPointer{rr in
            ipced_evaluate_local(c.kind,aa.baseAddress,aa.count,bb.baseAddress,bb.count,rr.baseAddress,rr.count,
                c.dtype,c.weight,c.kappa,c.dmin,c.h,cancel,context,&result)
        }}}
        return result
    }
    func rawLeaf(kind:Int32=0,ids:[UInt32]=[0,1],type:Int32=0,weight:Double=0.0001,positions:[V])->D.Leaf {
        let xyz=ids.flatMap{let q=positions[Int($0)];return [q.x,q.y,q.z]};var e=IPCEnergyResult()
        _=xyz.withUnsafeBufferPointer{p in ipce_evaluate_local(kind,p.baseAddress,p.count,p.baseAddress,p.count,type,weight,35,0,0.002,0,&e)}
        XCTAssertEqual(e.status,0)
        return .init(kind:kind,vertexIDs:ids,cachedDistanceType:type,signedRestAreaSquareMeters:weight,roundedEnergyJoules:e.energy_joules)
    }
    func prepared(_ rest:[V],limits:D.Limits = .init())throws->D.Prepared {
        try D.Prepared(restPositions:rest,bodyParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002),
            clothParameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.002),limits:limits)
    }
    func testAllPrimitiveTypesAndPhysicalTransitionsAgainstIndependentOracle()throws {
        let cases=try load("synthetic");XCTAssertEqual(cases.count,25)
        var ee=Set<Int32>(),activation=0,mollifier=0
        for c in cases {
            let r=native(c);XCTAssertEqual(r.status,0,c.name)
            let expected=try XCTUnwrap(Double(c.oracleDelta100))
            XCTAssertLessThanOrEqual(abs(r.delta_joules-expected),max(1e-25,abs(expected)*2e-11),c.name)
            if c.kind==2 {ee.insert(c.dtype)}
            activation+=Int(r.activation_transition);mollifier+=Int(r.mollifier_transition)
        }
        XCTAssertEqual(ee,Set<Int32>(0...8));XCTAssertGreaterThanOrEqual(activation,4);XCTAssertGreaterThanOrEqual(mollifier,2)
    }
    func testActualCompleteFixedLeavesPreserveSignedCorrectionsAndNearStationaryAccuracy()throws {
        let cases=try load("actual-fresh005");XCTAssertEqual(cases.count,1705)
        var values=[String:[Double]](),expected=[String:[Double]](),negatives=0
        for c in cases {
            let r=native(c);XCTAssertEqual(r.status,0,c.name)
            let ref=try XCTUnwrap(Double(c.oracleDelta100));XCTAssertLessThan(abs(r.delta_joules-ref),1e-24,c.name)
            values[c.group!,default:[]].append(r.delta_joules);expected[c.group!,default:[]].append(ref)
            if c.weight<0 {negatives+=1}
        }
        XCTAssertEqual(negatives,236)
        for group in ["Body","Self"] {
            let a=compensated(values[group]!),b=compensated(expected[group]!)
            XCTAssertLessThan(abs(a-b),1e-25,group)
        }
    }
    func testRigidCoordinatePermutationAndExactIdentity()throws {
        for c in try load("synthetic").prefix(9) {
            func rotate(_ x:[[Double]])->[[Double]] {x.map{[-$0[2],$0[0],-$0[1]]}}
            let r=Case(name:c.name,kind:c.kind,dtype:c.dtype,weight:c.weight,kappa:c.kappa,dmin:c.dmin,h:c.h,
                rest:rotate(c.rest),previous:rotate(c.previous),current:rotate(c.current),oracleDelta100:c.oracleDelta100,group:nil)
            let a=native(c),b=native(r);XCTAssertEqual(b.status,0)
            XCTAssertLessThan(abs(a.delta_joules-b.delta_joules),max(1e-25,abs(a.delta_joules)*2e-11))
            let same=Case(name:c.name,kind:c.kind,dtype:c.dtype,weight:c.weight,kappa:c.kappa,dmin:c.dmin,h:c.h,
                rest:c.rest,previous:c.previous,current:c.previous,oracleDelta100:"0",group:nil)
            XCTAssertEqual(native(same).delta_joules,0)
        }
    }
    func testSameSourceSnapshotBindingAndExplicitStructuralFallbacks()throws {
        let a=[V(0,0,0),V(0.001,0,0),V(0.01,0.002,0)],b=[V(0,0,0),V(0.0010000001,0,0),V(0.01,0.002,0)]
        let p=try prepared(a),foreign=try prepared(a)
        let old=try p.capture(positions:a,bodyLeaves:[],clothLeaves:[rawLeaf(positions:a)])
        let new=try p.capture(positions:b,bodyLeaves:[],clothLeaves:[rawLeaf(positions:b)])
        let d=try p.difference(from:old,to:new);XCTAssertEqual(d.cloth.method,.stableFixedLeaves);XCTAssertNil(d.cloth.fallbackReason)
        XCTAssertThrowsError(try foreign.difference(from:old,to:new)){XCTAssertEqual($0 as? D.Failure,.foreignSnapshot)}
        let changed=try p.capture(positions:b,bodyLeaves:[],clothLeaves:[rawLeaf(weight:0.0002,positions:b)])
        let w=try p.difference(from:old,to:changed);XCTAssertEqual(w.cloth.method,.roundedBlockFallback);XCTAssertEqual(w.cloth.fallbackReason,.weightChanged)
        XCTAssertEqual(w.cloth.deltaJoules,w.cloth.originalRoundedBlockDeltaJoules)
        let empty=try p.capture(positions:b,bodyLeaves:[],clothLeaves:[])
        let f=try p.difference(from:old,to:empty);XCTAssertEqual(f.cloth.fallbackReason,.featureSetChanged)
        XCTAssertEqual(f.cloth.deltaJoules,-rawLeaf(positions:a).roundedEnergyJoules)
        let selected=try f.selectingOriginalRoundedFallbacks(body:17,cloth:-0.125)
        XCTAssertEqual(selected.cloth.deltaJoules.bitPattern,(-0.125).bitPattern)
        XCTAssertEqual(selected.cloth.originalRoundedBlockDeltaJoules.bitPattern,(-0.125).bitPattern)
        XCTAssertEqual(selected.body.deltaJoules,0) // stable empty body is unaffected
    }
    func testLegacyFallbackPreservesFullArrayOrderAndCompensatedResidual()throws {
        // Opaque force-producer values intentionally test the accumulator, not
        // a synthetic claim that these scalar values are a garment solution.
        let x=[V(0,0,0),V(0.001,0,0),V(0.0015,0,0),V(0.0019,0,0)],p=try prepared(x)
        let leaves=zip([UInt32(1),2,3],[1e16,1.0,-1e16]).map {id,energy in
            D.Leaf(kind:0,vertexIDs:[0,id],cachedDistanceType:0,
                signedRestAreaSquareMeters:energy<0 ? -0.0001:0.0001,roundedEnergyJoules:energy)
        }
        let old=try p.capture(positions:x,bodyLeaves:[],clothLeaves:[]),new=try p.capture(positions:x,bodyLeaves:[],clothLeaves:leaves)
        let forward=try p.difference(from:old,to:new),reverse=try p.difference(from:new,to:old)
        XCTAssertEqual(forward.cloth.method,.roundedBlockFallback)
        XCTAssertEqual(forward.cloth.deltaJoules.bitPattern,1.0.bitPattern)
        XCTAssertEqual(reverse.cloth.deltaJoules.bitPattern,(-1.0).bitPattern)
        XCTAssertEqual(forward.cloth.originalRoundedBlockDeltaJoules.bitPattern,forward.cloth.deltaJoules.bitPattern)
    }
    func testNearestRequiredEvenForEmptyLeafGroups()throws {
        #if os(macOS)
        let x=[V(0,0,0)],p=try prepared(x)
        let s=try p.capture(positions:x,bodyLeaves:[],clothLeaves:[])
        let rounding=fegetround();defer{fesetround(rounding)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        XCTAssertThrowsError(try p.difference(from:s,to:s)){XCTAssertEqual($0 as? D.Failure,.unsupportedRounding)}
        XCTAssertThrowsError(try p.capture(positions:x,bodyLeaves:[],clothLeaves:[])){XCTAssertEqual($0 as? D.Failure,.unsupportedRounding)}
        #endif
    }
    func testAutomaticDistanceBranchChangePreservesFullRoundedFallback()throws {
        let a=[V(-0.001,0.001,0),V(0,0,0),V(0.01,0,0)],b=[V(0.001,0.001,0),V(0,0,0),V(0.01,0,0)]
        let p=try prepared(a)
        let la=rawLeaf(kind:1,ids:[0,1,2],type:-1,positions:a),lb=rawLeaf(kind:1,ids:[0,1,2],type:-1,positions:b)
        let aa=try p.capture(positions:a,bodyLeaves:[],clothLeaves:[la]),bb=try p.capture(positions:b,bodyLeaves:[],clothLeaves:[lb])
        let d=try p.difference(from:aa,to:bb)
        XCTAssertEqual(d.cloth.fallbackReason,.effectiveDistanceTypeChanged);XCTAssertEqual(d.cloth.method,.roundedBlockFallback)
        XCTAssertEqual(d.cloth.deltaJoules,lb.roundedEnergyJoules-la.roundedEnergyJoules)
        XCTAssertNotEqual(d.cloth.deltaJoules,0)
    }
    func testBudgetsCancellationAndBadCaptureAreNotZeroIncrements()throws {
        let a=[V(0,0,0),V(0.001,0,0)]
        let p=try prepared(a),leaves=[rawLeaf(positions:a)]
        let s=try p.capture(positions:a,bodyLeaves:[],clothLeaves:leaves)
        XCTAssertThrowsError(try p.capture(positions:a,bodyLeaves:[],clothLeaves:leaves,isCancelled:{true})){XCTAssertEqual($0 as? D.Failure,.cancelled)}
        let counter=Counter()
        XCTAssertThrowsError(try p.difference(from:s,to:s,isCancelled:{counter.tick()>=3})){XCTAssertEqual($0 as? D.Failure,.cancelled)}
        var limits=D.Limits();limits.maximumSnapshotBytes=1
        let bounded=try prepared(a,limits:limits)
        XCTAssertThrowsError(try bounded.capture(positions:a,bodyLeaves:[],clothLeaves:leaves)){XCTAssertEqual($0 as? D.Failure,.budgetExceeded)}
        XCTAssertThrowsError(try p.capture(positions:a,bodyLeaves:[],clothLeaves:leaves+leaves))
        let bad=D.Leaf(kind:0,vertexIDs:[0,1],cachedDistanceType:0,signedRestAreaSquareMeters:1,roundedEnergyJoules:.nan)
        XCTAssertThrowsError(try p.capture(positions:a,bodyLeaves:[],clothLeaves:[bad]))
        XCTAssertEqual(try p.difference(from:s,to:s).cloth.deltaJoules,0)
    }
    func testNativeInvalidDegenerateInfeasibleAndCancellationRemainExplicit()throws {
        let base=try load("synthetic")[0]
        let cancel:IPCEDCancel={_ in 1}
        let c=native(base,cancel:cancel);XCTAssertEqual(c.status,5);XCTAssertTrue(c.delta_joules.isNaN)
        let counter=Counter()
        let after:IPCEDCancel={context in
            Unmanaged<Counter>.fromOpaque(context!).takeUnretainedValue().tick()>=2 ? 1:0
        }
        let late=native(base,cancel:after,context:Unmanaged.passUnretained(counter).toOpaque())
        XCTAssertEqual(late.status,5);XCTAssertTrue(late.delta_joules.isNaN)
        let tiny=Case(name:"tiny",kind:1,dtype:2,weight:1,kappa:35,dmin:0,h:0.002,
            rest:[[0,0,0],[0,0,0],[1e-13,0,0]],previous:[[0,0.001,0],[0,0,0],[1e-13,0,0]],
            current:[[0,0.0011,0],[0,0,0],[1e-13,0,0]],oracleDelta100:"0",group:nil)
        XCTAssertEqual(native(tiny).status,3)
        let hit=Case(name:"hit",kind:0,dtype:0,weight:1,kappa:35,dmin:0,h:0.002,rest:[[0,0,0],[0.001,0,0]],
            previous:[[0,0,0],[0,0,0]],current:[[0,0,0],[0.001,0,0]],oracleDelta100:"0",group:nil)
        XCTAssertEqual(native(hit).status,2)
        let invalid=Case(name:"nan",kind:0,dtype:0,weight:1,kappa:35,dmin:0,h:0.002,rest:hit.rest,
            previous:[[.nan,0,0],[0.001,0,0]],current:hit.current,oracleDelta100:"0",group:nil)
        XCTAssertEqual(native(invalid).status,1)
        let flat=Case(name:"flat",kind:3,dtype:6,weight:1,kappa:35,dmin:0,h:0.03,
            rest:[[0,0,0.001],[0,0,0],[0.01,0,0],[0.02,1e-15,0]],
            previous:[[0,0,0.001],[0,0,0],[0.01,0,0],[0.02,1e-15,0]],
            current:[[0,0,0.0011],[0,0,0],[0.01,0,0],[0.02,1e-15,0]],oracleDelta100:"0",group:nil)
        XCTAssertEqual(native(flat).status,3)
        let parallel=Case(name:"parallel",kind:2,dtype:8,weight:1,kappa:35,dmin:0,h:0.03,
            rest:[[0,0,0],[0.01,0,0],[0,0.001,0],[0.01,0.001,0]],
            previous:[[0,0,0],[0.01,0,0],[0,0.001,0],[0.01,0.001,0]],
            current:[[0,0,0],[0.01,0,0],[0,0.0011,0],[0.01,0.0011,0]],oracleDelta100:"0",group:nil)
        XCTAssertEqual(native(parallel).status,3)
        #if os(macOS)
        let rounding=fegetround();defer{fesetround(rounding)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        XCTAssertEqual(native(base).status,7)
        #endif
    }
    private func compensated(_ values:[Double])->Double {
        var s=0.0,c=0.0
        for x in values {let t=s+x;c += abs(s)>=abs(x) ? (s-t)+x:(x-t)+s;s=t}
        return s+c
    }
}
