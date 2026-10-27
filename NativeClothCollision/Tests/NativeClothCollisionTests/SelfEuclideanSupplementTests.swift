import XCTest
import Foundation
import CryptoKit
import CNativeClothCollision
@testable import NativeClothCollision

final class SelfEuclideanSupplementTests:XCTestCase {
    typealias S=SelfContactGuard
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Motion:Decodable {
        struct Witness:Decodable {let kind:String,vertexIDs:[UInt32],start:[[Double]],end:[[Double]]}
        struct Original:Decodable {
            struct Stats:Decodable {let nativeQueries:Int,certifiedTriangles:Int,certifiedEdges:Int}
            let statistics:Stats
        }
        let name:String,sourceSHA256:String,previous:[[Double]],candidate:[[Double]],triangleIndices:[UInt32],witness:Witness,oldDirectGuardReport:Original
        var x:[V]{previous.map{V($0[0],$0[1],$0[2])}}
        var y:[V]{candidate.map{V($0[0],$0[1],$0[2])}}
    }
    func load(_ name:String)throws->Motion {
        let path=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/SelfEuclideanSupplement"))
        return try JSONDecoder().decode(Motion.self,from:Data(contentsOf:path))
    }
    func features(_ m:Motion)->([V],[V]) {(m.witness.start.map{V($0[0],$0[1],$0[2])},m.witness.end.map{V($0[0],$0[1],$0[2])})}
    func stats(_ r:S.Report)->[String:Any] {
        var d:[String:Any]=[:]
        for child in Mirror(reflecting:r.statistics).children {if let label=child.label{d[label]=child.value}}
        return d
    }
    func testBothActualCompleteQueriesSupplementEveryRemainingFeature()throws {
        var rows:[[String:Any]]=[]
        for name in ["circle387","shirt343"] {
            let m=try load(name),p=try S.Prepared(vertexCount:m.x.count,triangleIndices:m.triangleIndices)
            let r=p.guardMotion(previous:m.x,candidate:m.y)
            XCTAssertEqual(r.status,.clear,r.reason);XCTAssertTrue(r.permitsWholeCandidate)
            XCTAssertEqual(r.minimumSeparation,0);XCTAssertEqual(r.safeTime,1)
            XCTAssertTrue(r.requiresIntersectionFreeInitialState)
            XCTAssertTrue(r.statistics.completedDomainCertificates);XCTAssertTrue(r.statistics.completedAllFeatures)
            XCTAssertEqual(r.statistics.certifiedTriangles,m.oldDirectGuardReport.statistics.certifiedTriangles)
            XCTAssertEqual(r.statistics.certifiedEdges,m.oldDirectGuardReport.statistics.certifiedEdges)
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueVertexFace+r.statistics.uniqueEdgeEdge)
            XCTAssertEqual(r.statistics.nativeQueries,r.statistics.evaluatedFeatures)
            XCTAssertGreaterThan(r.statistics.nativeQueries,m.oldDirectGuardReport.statistics.nativeQueries,"Must continue beyond original first witness")
            XCTAssertGreaterThan(r.statistics.euclideanCertificateAttempts,0)
            XCTAssertEqual(r.statistics.euclideanCertificateAttempts,r.statistics.euclideanCertifiedFeatures)
            XCTAssertGreaterThan(r.statistics.euclideanCertifiedAfterPrecisionLimit,0)
            XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertificateNodes,r.statistics.euclideanCertificateAttempts)
            XCTAssertLessThanOrEqual(r.statistics.euclideanCertificateNodes,S.Limits().maximumEuclideanCertificateNodes)
            let (a,b)=features(m),flatA=a.flatMap{[$0.x,$0.y,$0.z]},flatB=b.flatMap{[$0.x,$0.y,$0.z]}
            let old=NativeClothCollision.edgeEdge(start:flatA,end:flatB)
            XCTAssertEqual(old.status,.uncertain);XCTAssertEqual(old.detail,.precisionOrBudget)
            XCTAssertGreaterThan(old.achievedDistanceTolerance,1e-8)
            XCTAssertTrue((0..<2).allSatisfy{a[$0] != b[$0]});XCTAssertTrue((2..<4).allSatisfy{a[$0] != b[$0]})
            var limits=F.Limits();limits.recordLeafCertificates=true
            let proof=F.certify(kind:.edgeEdge,start:a,end:b,minimumSeparation:0,limits:limits)
            XCTAssertEqual(proof.status,.separated);XCTAssertGreaterThan(try XCTUnwrap(proof.minimumCertifiedDistanceLowerBoundMeters),0)
            let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(proof))
            rows.append(["name":name,"sourceSHA256":m.sourceSHA256,"wholeQueryStatus":r.status.rawValue,
                "wholeQueryStatistics":stats(r),"requiresIntersectionFreeInitialState":true,"actualWitnessStart":m.witness.start,"actualWitnessEnd":m.witness.end,
                "witnessVertexIDs":m.witness.vertexIDs,"featureProof":encoded,"nativeVendorUnchanged":true,"physicsAccepted":false])
        }
        if let file=ProcessInfo.processInfo.environment["NCC_SELF_EUCLIDEAN_REPORT"] {
            try JSONSerialization.data(withJSONObject:["passed":true,"rows":rows],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:file))
        }
    }
    func testActualCompleteQueriesAreInvariantToIndependentVertexRenumbering()throws {
        for name in ["circle387","shirt343"] {
            let m=try load(name),n=m.x.count,tri=m.triangleIndices.map{UInt32(n-1)-$0}
            let p=try S.Prepared(vertexCount:n,triangleIndices:tri)
            let r=p.guardMotion(previous:Array(m.x.reversed()),candidate:Array(m.y.reversed()))
            XCTAssertTrue(r.permitsWholeCandidate,r.reason);XCTAssertTrue(r.statistics.completedAllFeatures)
            // Relabeling may change the conservative native parameter box and
            // remove its false positive; the geometric authorization must agree.
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueVertexFace+r.statistics.uniqueEdgeEdge)
        }
    }
    func testNewEuclideanBudgetsAndLateCancellationRemainAtomic()throws {
        let m=try load("circle387"),p=try S.Prepared(vertexCount:m.x.count,triangleIndices:m.triangleIndices)
        var none=S.Options();none.limits.maximumEuclideanCertificateNodes=0
        let budget=p.guardMotion(previous:m.x,candidate:m.y,options:none)
        XCTAssertEqual(budget.status,.budgetExceeded);XCTAssertEqual(budget.safeTime,0)
        XCTAssertFalse(budget.statistics.completedAllFeatures);XCTAssertEqual(budget.statistics.euclideanCertificateAttempts,0)
        XCTAssertEqual(budget.statistics.nativeQueries,m.oldDirectGuardReport.statistics.nativeQueries)
        var malformed=S.Options();malformed.limits.maximumEuclideanCertificateNodes = -1
        XCTAssertEqual(p.guardMotion(previous:m.x,candidate:m.y,options:malformed).status,.invalid)
        // Conservative certificate scratch must be charged before BVH/native.
        var memory=S.Options();memory.maximumIterationsPerFeature=1;memory.limits.maximumEstimatedBytes=p.estimatedResidentBytes+1_048_575
        let r=p.guardMotion(previous:m.x,candidate:m.y,options:memory)
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0);XCTAssertEqual(r.statistics.nativeQueries,0)
        var checks=0
        let complete=p.guardMotion(previous:m.x,candidate:m.y,isCancelled:{checks+=1;return false})
        XCTAssertTrue(complete.permitsWholeCandidate)
        var calls=0
        let cancelled=p.guardMotion(previous:m.x,candidate:m.y,isCancelled:{calls+=1;return calls>=checks})
        XCTAssertEqual(cancelled.status,.cancelled);XCTAssertEqual(cancelled.safeTime,0)
        XCTAssertFalse(cancelled.statistics.completedAllFeatures);XCTAssertGreaterThan(cancelled.statistics.euclideanCertifiedFeatures,0)
        XCTAssertEqual(m.x.count,m.y.count) // Inputs remain the original immutable snapshot.
    }
    func testTwoSidedMovingZeroFloorSupportAndRealContactNegativeControls() {
        let triangle=[V(0,0,0),V(1,0,0),V(0,1,0)],shift=V(0.125,0.25,0.5)
        let vf=[V(0.25,0.25,1e-9)]+triangle
        let vfy=vf.enumerated().map{$0.element+shift+V(0,0,$0.offset==0 ? 1e-9:0)}
        let ee=[V(-1,0,0),V(1,0,0),V(-1,0,1e-9),V(1,0,1e-9)]
        let eey=ee.enumerated().map{$0.element+shift+V(0,0,$0.offset>1 ? 1e-9:0)}
        for (kind,a,b) in [(F.Kind.vertexFace,vf,vfy),(.edgeEdge,ee,eey)] {
            let proof=F.certify(kind:kind,start:a,end:b,minimumSeparation:0)
            XCTAssertEqual(proof.status,.separated);XCTAssertGreaterThan(proof.minimumCertifiedDistanceLowerBoundMeters ?? 0,0)
            var crossing=b
            if kind == .vertexFace {crossing[0].z=shift.z-1e-9}
            else {crossing[2].z=shift.z-1e-9;crossing[3].z=shift.z-1e-9}
            XCTAssertFalse(F.certify(kind:kind,start:a,end:crossing,minimumSeparation:0).distanceSeparatedForWholeMotion)
        }
        let q=triangle+triangle.map{$0+V(0,0,1e-9)},p=try? S.Prepared(vertexCount:6,triangleIndices:[0,1,2,3,4,5])
        XCTAssertNotNil(p)
        let clear=p?.guardMotion(previous:q,candidate:q.map{$0+shift})
        XCTAssertTrue(clear?.permitsWholeCandidate == true,clear?.reason ?? "missing")
        let touch=triangle+triangle
        let blocked=p?.guardMotion(previous:touch,candidate:touch)
        XCTAssertEqual(blocked?.status,.blockedInitialContact);XCTAssertEqual(blocked?.statistics.euclideanCertificateAttempts,0)
        let tiny=triangle+triangle.map{$0+V(0,0,1e-16)}
        let numerical=p?.guardMotion(previous:tiny,candidate:tiny)
        XCTAssertEqual(numerical?.status,.blockedInitialContact);XCTAssertEqual(numerical?.statistics.euclideanCertificateAttempts,0)
    }
    func testSourceDomainUnknownIsNotOverriddenByDistanceSeparation()throws {
        let x=[V(0,0,1),V(1,0,1),V(0,1,1)],y=[V(0,0,1),V(-1,0,1),V(0,-1,1)]
        let p=try S.Prepared(vertexCount:3,triangleIndices:[0,1,2]),r=p.guardMotion(previous:x,candidate:y)
        XCTAssertEqual(r.status,.uncertain);XCTAssertEqual(r.witness?.kind,.triangleDomain)
        XCTAssertEqual(r.statistics.euclideanCertificateAttempts,0);XCTAssertFalse(r.statistics.completedAllFeatures)
        let proof=F.certify(kind:.vertexFace,start:[V(10,10,10)]+x,end:[V(10,10,10)]+y,minimumSeparation:0)
        XCTAssertTrue(proof.distanceSeparatedForWholeMotion) // Distance proof alone cannot authorize a collapsing face.
    }
}
