import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

private final class SeparationCancellation {
    private let lock=NSLock();private var calls=0
    func check()->Bool {lock.lock();defer{lock.unlock()};calls+=1;return calls>=3}
}
final class FeatureSeparationCertificateTests:XCTestCase {
    typealias S=FeatureSeparationCertificate
    typealias C=NativeClothCollision
    typealias V=S.Vector
    struct Exact:Decodable {let pathMinimumMeters90Digit:String}
    struct Raw:Decodable {
        let originalFilename:String,start12:[Double],end12:[Double],startBits:[String],endBits:[String]
        let minimumSeparation:Double,distanceTolerance:Double,maximumIterations:Int64,maximumTime:Double
        let exactConvexQP:Exact
    }
    struct Fixture:Decodable {let rows:[Raw]}
    struct ExtraRaw:Decodable {
        let originalFilename:String,kind:S.Kind,start12:[Double],end12:[Double],startBits:[String],endBits:[String]
        let minimumSeparation:Double,distanceTolerance:Double,maximumIterations:Int64,maximumTime:Double
        let nativeReplayStatus:Int32,nativeReplayDetail:String,previousCertificateStatus:String
        let exactConvexQP:Exact?
    }
    struct ExtraFixture:Decodable {let rows:[ExtraRaw]}
    struct Motion:Codable {
        let name:String,kind:S.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool
    }
    struct Row:Codable {let motion:Motion,proof:S.Report}
    struct Export:Codable {let passed:Bool,rows:[Row]}
    func v(_ x:Double,_ y:Double,_ z:Double)->V {V(x,y,z)}
    func points(_ flat:[Double])->[V] {stride(from:0,to:flat.count,by:3).map{v(flat[$0],flat[$0+1],flat[$0+2])}}
    func fixture()throws->Fixture {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"actual-circle247-vf",withExtension:"json",subdirectory:"Fixtures/FeatureSeparationCertificate"))
        return try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url))
    }
    func extraFixture()throws->ExtraFixture {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"circle118-vf-shirt85-ee",withExtension:"json",subdirectory:"Fixtures/FeatureSeparationCertificate"))
        return try JSONDecoder().decode(ExtraFixture.self,from:Data(contentsOf:url))
    }
    func motions()throws->[Motion] {
        let a=v(-2,-2,0),b=v(2,-2,0),c=v(0,2,0)
        var result=try fixture().rows.map{Motion(name:$0.originalFilename,kind:.vertexFace,start:points($0.start12),end:points($0.end12),floor:$0.minimumSeparation,expectedSeparated:true)}
        func add(_ name:String,_ kind:S.Kind,_ start:[V],_ end:[V],_ clear:Bool) {result.append(.init(name:name,kind:kind,start:start,end:end,floor:0.0005,expectedSeparated:clear))}
        add("VF-midpath-collision-endpoints-clear",.vertexFace,[v(-1,0,0.1),a,b,c],[v(1,0,-0.1),a,b,c],false)
        add("VF-exact-floor-no-strict-clear",.vertexFace,[v(0,0,0.0005),a,b,c],[v(0,0,0.0005),a,b,c],false)
        add("VF-under-floor-no-ms-over-sqrt3",.vertexFace,[v(0,0,0.0004),a,b,c],[v(0,0,0.0004),a,b,c],false)
        add("VF-corner-clear-needs-subdivision",.vertexFace,[v(-1,0.9985,0),v(0,0,0),v(1,0,0),v(0,1,0)],[v(3,-3.0015,0),v(0,0,0),v(1,0,0),v(0,1,0)],true)
        add("VF-vertex-nearest-closed-feature",.vertexFace,[v(-0.001,-0.001,0.001),v(0,0,0),v(1,0,0),v(0,1,0)],[v(-0.001,-0.001,0.001),v(0,0,0),v(1,0,0),v(0,1,0)],true)
        add("VF-LInfinity-conservative-only",.vertexFace,[v(0.0004,0.0004,0.0004),v(1,-1,0),v(0,1,-1),v(-1,0,1)],[v(0.0004,0.0004,0.0004),v(1,-1,0),v(0,1,-1),v(-1,0,1)],true)
        let parallel=[v(-1,0,0),v(1,0,0),v(-1,0,0.001),v(1,0,0.001)],shift=v(5,2,3)
        add("EE-parallel-common-translation",.edgeEdge,parallel,parallel.map{$0+shift},true)
        add("EE-midpath-collision-endpoints-clear",.edgeEdge,[v(-1,-1,0),v(-1,1,0),v(-0.1,0,0),v(0.1,0,0)],[v(1,-1,0),v(1,1,0),v(-0.1,0,0),v(0.1,0,0)],false)
        add("EE-closed-endpoint-nearest",.edgeEdge,[v(0,0,0),v(1,0,0),v(2,0.001,0),v(2,1,0)],[v(0,0,0),v(1,0,0),v(2,0.001,0),v(2,1,0)],true)
        add("VF-moving-face-clear",.vertexFace,[v(0,0,2),a,b,c],[v(0,0,2),v(-2,-1,0.2),v(2,-1,0.2),v(0,2,0.2)],true)
        add("VF-collapse-domain-must-remain-rejected",.vertexFace,[v(10,10,10),v(0,0,0),v(1,0,0),v(0,1,0)],[v(10,10,10),v(0,0,0),v(-1,0,0),v(0,-1,0)],true)
        for row in try extraFixture().rows {
            result.append(.init(name:row.originalFilename,kind:row.kind,start:points(row.start12),end:points(row.end12),floor:row.minimumSeparation,expectedSeparated:true))
        }
        return result
    }
    func certificate(_ m:Motion,trace:Bool=true)->S.Report {
        var limits=S.Limits();limits.recordLeafCertificates=trace
        return S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits)
    }
    func testAnalyticMotionsAndExactOriginalWitnesses()throws {
        var rows:[Row]=[]
        for m in try motions() {
            let p=certificate(m)
            XCTAssertEqual(p.distanceSeparatedForWholeMotion,m.expectedSeparated,m.name)
            XCTAssertTrue(p.provesDistanceSeparationOnly);XCTAssertTrue(p.requiresIndependentPrimitiveDomainCertificate)
            XCTAssertLessThanOrEqual(p.processedNodes,8191);XCTAssertLessThanOrEqual(p.maximumDepthReached,12)
            XCTAssertLessThanOrEqual(p.maximumEstimatedWorkingBytes,S.Limits().maximumEstimatedWorkingBytes)
            if p.status == .separated {
                let leaves=(p.leafCertificates.map{($0.startTime,$0.endTime)}+p.movingNormalCertificates.map{($0.startTime,$0.endTime)}+p.expansionCertificates.map{($0.startTime,$0.endTime)}+p.criticalCertificates.map{($0.startTime,$0.endTime)}+p.affineNormalCertificates.map{($0.startTime,$0.endTime)}).sorted{$0.0<$1.0}
                XCTAssertEqual(leaves.count,p.certifiedIntervals)
                XCTAssertEqual(leaves.first?.0,0);XCTAssertEqual(leaves.last?.1,1)
                for (a,b) in zip(leaves,leaves.dropFirst()){XCTAssertEqual(a.1,b.0)}
                for leaf in p.leafCertificates {XCTAssertGreaterThan(leaf.projectionLowerBound,leaf.requiredProductUpperBound)}
            }
            rows.append(.init(motion:m,proof:p))
        }
        if let path=ProcessInfo.processInfo.environment["NCC_FEATURE_SEPARATION_REPORT"] {
            let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys]
            try e.encode(Export(passed:true,rows:rows)).write(to:URL(fileURLWithPath:path))
        }
    }
    func testWitnessBytesAndNativeConservativeResultsRemainUnmodified()throws {
        for row in try fixture().rows {
            XCTAssertEqual(row.start12.map{String(format:"%016llx",$0.bitPattern)},row.startBits)
            XCTAssertEqual(row.end12.map{String(format:"%016llx",$0.bitPattern)},row.endBits)
            let native=NativeClothCollision.vertexFace(start:row.start12,end:row.end12,
                options:.init(minimumSeparation:row.minimumSeparation,maximumTime:row.maximumTime,
                    distanceTolerance:row.distanceTolerance,maximumIterations:row.maximumIterations))
            XCTAssertEqual(native.status,.conservativeHit)
            let p=S.certify(kind:.vertexFace,start:points(row.start12),end:points(row.end12),minimumSeparation:row.minimumSeparation)
            XCTAssertEqual(p.status,.separated);XCTAssertEqual(p.processedNodes,1)
            XCTAssertGreaterThan(try XCTUnwrap(p.minimumCertifiedDistanceLowerBoundMeters),row.minimumSeparation)
            XCTAssertLessThan(try XCTUnwrap(p.minimumCertifiedDistanceLowerBoundMeters),try XCTUnwrap(Double(row.exactConvexQP.pathMinimumMeters90Digit)))
            XCTAssertTrue(p.leafCertificates.isEmpty,"Default production call does not retain trace arrays")
        }
    }
    func testStaticTrajectoryAxesAndPostDomainPrecisionWitnesses()throws {
        for row in try extraFixture().rows {
            XCTAssertEqual(row.start12.map{String(format:"%016llx",$0.bitPattern)},row.startBits)
            XCTAssertEqual(row.end12.map{String(format:"%016llx",$0.bitPattern)},row.endBits)
            let options=C.Options(minimumSeparation:row.minimumSeparation,maximumTime:row.maximumTime,
                distanceTolerance:row.distanceTolerance,maximumIterations:row.maximumIterations)
            let native=row.kind == .edgeEdge ? C.edgeEdge(start:row.start12,end:row.end12,options:options):C.vertexFace(start:row.start12,end:row.end12,options:options)
            XCTAssertEqual(native.status.rawValue,row.nativeReplayStatus)
            XCTAssertEqual(String(describing:native.detail),row.nativeReplayDetail)
            var limits=S.Limits();limits.recordLeafCertificates=true
            let p=S.certify(kind:row.kind,start:points(row.start12),end:points(row.end12),minimumSeparation:row.minimumSeparation,limits:limits)
            XCTAssertEqual(p.status,.separated);XCTAssertEqual(p.processedNodes,1);XCTAssertEqual(p.certifiedIntervals,1)
            XCTAssertGreaterThan(try XCTUnwrap(p.minimumCertifiedDistanceLowerBoundMeters),row.minimumSeparation)
            if let exact=row.exactConvexQP {
                XCTAssertEqual(row.previousCertificateStatus,"notCertified")
                XCTAssertLessThan(try XCTUnwrap(p.minimumCertifiedDistanceLowerBoundMeters),try XCTUnwrap(Double(exact.pathMinimumMeters90Digit)))
            }
        }
    }
    func testBoundedSubdivisionAndFailureIsNotCollisionOrAdvancePermission()throws {
        let m=try XCTUnwrap(motions().first{$0.name=="VF-corner-clear-needs-subdivision"})
        let complete=certificate(m)
        XCTAssertEqual(complete.status,.separated);XCTAssertGreaterThan(complete.processedNodes,1)
        XCTAssertGreaterThan(complete.maximumDepthReached,0)
        var limits=S.Limits();limits.maximumDepth=0
        let shallow=S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits)
        XCTAssertEqual(shallow.status,.notCertified);XCTAssertEqual(shallow.reason,.depthLimit)
        limits=S.Limits();limits.maximumNodes=0
        let zero=S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits)
        XCTAssertEqual(zero.status,.budgetExceeded);XCTAssertEqual(zero.reason,.nodeBudget);XCTAssertEqual(zero.processedNodes,0)
        limits=S.Limits();limits.maximumNodes=1
        XCTAssertEqual(S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits).status,.budgetExceeded)
        limits=S.Limits();limits.maximumDepth=16;limits.maximumNodes=65_535;limits.recordLeafCertificates=true
        let memory=S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits)
        XCTAssertEqual(memory.status,.budgetExceeded);XCTAssertEqual(memory.reason,.workingMemoryBudget);XCTAssertEqual(memory.processedNodes,0)
    }
    func testCancellationAndInputLimitsAreExplicit()throws {
        let m=try XCTUnwrap(motions().first{$0.name=="VF-corner-clear-needs-subdivision"})
        let counter=SeparationCancellation()
        let r=S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,isCancelled:{counter.check()})
        XCTAssertEqual(r.status,.cancelled);XCTAssertFalse(r.distanceSeparatedForWholeMotion)
        XCTAssertEqual(S.certify(kind:m.kind,start:Array(m.start.dropLast()),end:m.end,minimumSeparation:m.floor).status,.invalid)
        var bad=m.start;bad[0].x = .nan
        XCTAssertEqual(S.certify(kind:m.kind,start:bad,end:m.end,minimumSeparation:m.floor).status,.invalid)
        XCTAssertEqual(S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:-1).status,.invalid)
        var limits=S.Limits();limits.maximumDepth=17
        XCTAssertEqual(S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits).reason,.invalidLimits)
        limits=S.Limits();limits.maximumEstimatedWorkingBytes=4096
        XCTAssertEqual(S.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:limits).reason,.workingMemoryBudget)
    }
    func testNearestRoundingIsReadOnlyAndRequired()throws {
        #if os(macOS)
        let m=try XCTUnwrap(motions().first),saved=fegetround()
        defer{_ = fesetround(saved)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        let p=certificate(m)
        XCTAssertEqual(p.status,.unsupportedRounding);XCTAssertEqual(fegetround(),FE_UPWARD)
        #else
        XCTAssertTrue(FloatingPointEnvironment.isNearestRounding)
        #endif
    }
    func testDistanceCertificateNeverReplacesPrimitiveDomain()throws {
        let m=try XCTUnwrap(motions().first{$0.name=="VF-collapse-domain-must-remain-rejected"})
        let p=certificate(m)
        XCTAssertEqual(p.status,.separated)
        let native=NativeClothCollision.vertexFace(start:m.start.flatMap{[$0.x,$0.y,$0.z]},end:m.end.flatMap{[$0.x,$0.y,$0.z]},
            options:.init(minimumSeparation:m.floor))
        XCTAssertEqual(native.status,.uncertain);XCTAssertEqual(native.detail,.uncertainGeometry)
        XCTAssertTrue(p.requiresIndependentPrimitiveDomainCertificate)
        // No caller-supplied "domain=true" flag or advancement permission
        // exists on the certificate API.
    }
    func testSendableImmutableValuesAndMotionBinding()throws {
        func sendable<T:Sendable>(_ x:T) {}
        let m=try XCTUnwrap(motions().first),start=m.start,end=m.end
        let a=certificate(m,trace:false),b=certificate(m,trace:false)
        sendable(a);sendable(S.Limits());sendable(S.Kind.vertexFace)
        XCTAssertEqual(a.motionSHA256,b.motionSHA256);XCTAssertEqual(m.start,start);XCTAssertEqual(m.end,end)
        var changed=start;changed[0].x=changed[0].x.nextUp
        let other=S.certify(kind:m.kind,start:changed,end:end,minimumSeparation:m.floor)
        XCTAssertNotEqual(a.motionSHA256,other.motionSHA256)
        let floor=S.certify(kind:m.kind,start:start,end:end,minimumSeparation:m.floor.nextUp)
        XCTAssertNotEqual(a.motionSHA256,floor.motionSHA256)
    }
}

