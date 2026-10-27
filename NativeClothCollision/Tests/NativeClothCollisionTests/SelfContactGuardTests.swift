import XCTest
import Foundation
import CryptoKit
import CNativeClothCollision
@testable import NativeClothCollision

final class SelfContactGuardTests:XCTestCase {
    typealias S=SelfContactGuard
    typealias V=S.Vector
    let two:[UInt32]=[0,1,2,3,4,5]
    func limited(_ r:S.Report,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(r.status,.limited,r.reason,file:file,line:line)
        XCTAssertTrue(r.statistics.completedAllFeatures,file:file,line:line)
        XCTAssertTrue(r.statistics.completedDomainCertificates,file:file,line:line)
        XCTAssertGreaterThan(r.safeTime,0,file:file,line:line);XCTAssertLessThan(r.safeTime,0.5,file:file,line:line)
        XCTAssertTrue(r.requiresIntersectionFreeInitialState,file:file,line:line)
    }
    func testPrimitiveAdjacencyMatchesOfficialAndBothOppositeFVRemain()throws {
        let q=[V(0,0,0),V(0.02,0,0),V(0.02,0.02,0),V(0,0.02,0)]
        let p=try S.Prepared(vertexCount:4,triangleIndices:[0,1,2,0,2,3]),clear=p.guardMotion(previous:q,candidate:q)
        XCTAssertTrue(clear.permitsWholeCandidate,clear.reason);XCTAssertEqual(clear.statistics.uniqueVertexFace,2);XCTAssertEqual(clear.statistics.uniqueEdgeEdge,0);XCTAssertEqual(clear.statistics.aabbPrunedEdgeEdgeVisits,2)
        let a=[V(0,0,0),V(0.02,0,0),V(0,0.02,0),V(0.012,0.004,0.001),V(0.004,0.012,0.001)]
        var b=a;b[3].z = -0.001;b[4].z = -0.001
        let r=try S.Prepared(vertexCount:5,triangleIndices:[0,1,2,0,3,4]).guardMotion(previous:a,candidate:b)
        limited(r);XCTAssertEqual(r.statistics.uniqueVertexFace,2);XCTAssertEqual(r.statistics.uniqueEdgeEdge,3);XCTAssertEqual(r.statistics.aabbPrunedPrimitiveVisits,4)
        XCTAssertTrue(r.witness?.vertexIDs == [3,0,1,2] || r.witness?.vertexIDs == [4,0,1,2])
        let edge=[V(0,0,0),V(0.02,0,0),V(0.01,0.01,0.001),V(0.01,0.02,0)]
        var moved=edge;moved[2].z = -0.001
        let e=try S.Prepared(vertexCount:4,triangleIndices:[0,1,2,0,1,3]).guardMotion(previous:edge,candidate:moved)
        limited(e);XCTAssertEqual(e.statistics.uniqueVertexFace,1);XCTAssertEqual(e.statistics.uniqueEdgeEdge,2);XCTAssertEqual(e.statistics.aabbPrunedPrimitiveVisits,1)
    }
    func testAllVerticesMoveAndEdgeInteriorOnlyCollision()throws {
        let a=[V(-0.02,-0.01,0),V(0.02,-0.01,0),V(0,0.025,0)]
        let initial=a+a.map{$0+V(0,0,0.002)},translated=initial.map{$0+V(0,0,0.003)}
        let p=try S.Prepared(vertexCount:6,triangleIndices:two),clear=p.guardMotion(previous:initial,candidate:translated)
        XCTAssertTrue(clear.permitsWholeCandidate,clear.reason);XCTAssertGreaterThan(clear.statistics.nativeQueries,0)
        let b=[V(-0.02,0.01,0.001),V(0.02,0.01,0.001),V(0,-0.025,0.001)]
        var moved=a+b;for i in 3..<6{moved[i].z = -0.001}
        let r=p.guardMotion(previous:a+b,candidate:moved);limited(r);XCTAssertEqual(r.witness?.kind,.edgeEdge)
    }
    func testIndependentStitchedIDsAndExplicitBootstrapPrecondition()throws {
        let a=[V(-0.02,-0.01,0),V(0.02,-0.01,0),V(0,0.025,0)],p=try S.Prepared(vertexCount:6,triangleIndices:two)
        let touching=p.guardMotion(previous:a+a,candidate:a+a)
        XCTAssertEqual(touching.status,.blockedInitialContact);XCTAssertEqual(touching.safeTime,0);XCTAssertFalse(touching.statistics.completedAllFeatures)
        // This static edge pierces a face interior although every VF/EE distance
        // can be positive. Event CCD is not a static bootstrap intersection test.
        let bad=[V(-0.02,-0.02,0),V(0.02,-0.02,0),V(0,0.02,0),V(0,-0.005,-0.01),V(0,-0.005,0.01),V(0,0.005,0.01)]
        let conditional=p.guardMotion(previous:bad,candidate:bad)
        XCTAssertEqual(conditional.status,.clear)
        XCTAssertTrue(conditional.requiresIntersectionFreeInitialState)
        let independentBootstrapIntersectionFree=false
        XCTAssertFalse(independentBootstrapIntersectionFree && conditional.permitsWholeCandidate)
    }
    func testEveryPrimitiveDomainEvenWithoutCollisionCandidates()throws {
        let a=[V(0,0,1),V(1,0,1),V(0,1,1)],p=try S.Prepared(vertexCount:3,triangleIndices:[0,1,2])
        let midCollapse=[V(0,0,1),V(-1,0,1),V(0,-1,1)],r=p.guardMotion(previous:a,candidate:midCollapse)
        XCTAssertEqual(r.status,.uncertain);XCTAssertEqual(r.safeTime,0);XCTAssertEqual(r.witness?.kind,.triangleDomain);XCTAssertEqual(r.statistics.nativeQueries,0)
        let angle=117*Double.pi/180,b=[V(0,0,1),V(cos(angle),sin(angle),1),V(-sin(angle),cos(angle),1)]
        let edge=p.guardMotion(previous:a,candidate:b)
        XCTAssertEqual(edge.status,.uncertain);XCTAssertEqual(edge.witness?.kind,.edgeDomain);XCTAssertEqual(edge.safeTime,0)
        let clear=p.guardMotion(previous:a,candidate:a.map{$0+V(0,0,1)})
        XCTAssertTrue(clear.permitsWholeCandidate);XCTAssertEqual(clear.statistics.certifiedTriangles,1);XCTAssertEqual(clear.statistics.certifiedEdges,3)
    }
    func testPartialBudgetsNativeUncertaintyAndLateCancellationAreAtomic()throws {
        let a=[V(0,0,0),V(0.02,0,0),V(0,0.02,0),V(0.012,0.004,0.001),V(0.004,0.012,0.001)]
        var b=a;b[3].z = -0.001;b[4].z = -0.001
        let p=try S.Prepared(vertexCount:5,triangleIndices:[0,1,2,0,3,4])
        var features=S.Options();features.limits.maximumFeatureQueries=1
        var domain=S.Options();domain.limits.maximumCertificateNodes=1
        var memory=S.Options();memory.limits.maximumEstimatedBytes=1
        for options in [features,domain,memory] {
            let r=p.guardMotion(previous:a,candidate:b,options:options)
            XCTAssertEqual(r.status,.budgetExceeded,r.reason);XCTAssertEqual(r.safeTime,0);XCTAssertFalse(r.statistics.completedAllFeatures)
        }
        let uncertainty=p.guardMotion(previous:a,candidate:b,options:.init(maximumIterationsPerFeature:1))
        XCTAssertEqual(uncertainty.status,.uncertain);XCTAssertEqual(uncertainty.safeTime,0);XCTAssertFalse(uncertainty.statistics.completedAllFeatures)
        var count=0
        let first=p.guardMotion(previous:a,candidate:b,isCancelled:{count+=1;return false})
        XCTAssertEqual(first.status,.limited)
        var called=0
        let late=p.guardMotion(previous:a,candidate:b,isCancelled:{called+=1;return called>=count-2})
        XCTAssertEqual(late.status,.cancelled);XCTAssertEqual(late.safeTime,0);XCTAssertFalse(late.statistics.completedAllFeatures)
        XCTAssertNotNil(late.conservativeTimeOfImpact) // Earlier hit cannot authorize a partial prefix.
        XCTAssertEqual(a[3].z,0.001);XCTAssertEqual(b[3].z,-0.001)
    }
    func testSweptPrimitiveAABBRetainsThicknessAndOutwardBoundary()throws {
        let a=[V(-0.02,-0.01,0),V(0.02,-0.01,0),V(0,0.025,0)]
        let previous=a+a.map{$0+V(0,0,0.001)},candidate=a+a.map{$0+V(0,0,0.0001)}
        let p=try S.Prepared(vertexCount:6,triangleIndices:two)
        let thickness=p.guardMotion(previous:previous,candidate:candidate,options:.init(minimumSeparation:0.0002))
        // The frozen native kernel conservatively saturates precision for
        // this finite-thickness parallel case. AABB pruning must retain it,
        // preserve the explicit failure, and never authorize the crossing.
        XCTAssertEqual(thickness.status,.uncertain,thickness.reason)
        XCTAssertEqual(thickness.witness?.nativeDetail,.precisionOrBudget)
        XCTAssertEqual(thickness.safeTime,0)
        XCTAssertFalse(thickness.statistics.completedAllFeatures)
        XCTAssertGreaterThan(thickness.statistics.nativeQueries,0)
        let boundary=a+a.map{$0+V(0,0,0.0002+0.5e-8)}
        let near=p.guardMotion(previous:boundary,candidate:boundary,options:.init(minimumSeparation:0.0002))
        XCTAssertGreaterThan(near.statistics.nativeQueries,0) // Expanded-box boundary cannot be pruned.
        XCTAssertTrue(near.statistics.completedDomainCertificates)
    }
    func testInvalidSourceAndPose()throws {
        XCTAssertThrowsError(try S.Prepared(vertexCount:4,triangleIndices:[0,1,2]))
        XCTAssertThrowsError(try S.Prepared(vertexCount:3,triangleIndices:[0,1,2,2,1,0]))
        XCTAssertThrowsError(try S.Prepared(vertexCount:3,triangleIndices:[0,1,9]))
        XCTAssertThrowsError(try S.Prepared(vertexCount:3,triangleIndices:[0,1,2],isCancelled:{true}))
        let a=[V(0,0,0),V(0.02,0,0),V(0,0.02,0)],p=try S.Prepared(vertexCount:3,triangleIndices:[0,1,2])
        var bad=a;bad[0].x = .nan
        XCTAssertEqual(p.guardMotion(previous:bad,candidate:a).status,.invalid)
        XCTAssertEqual(p.guardMotion(previous:a,candidate:a,options:.init(safetyFactor:1)).safeTime,0)
    }
    func testCertificateTimeMappingNodeBudgetAndInputRows() {
        let a:[Double]=[0,0,0,1,0,0,0,1,0],b:[Double]=[0,0,0,-1,0,0,0,-1,0]
        func triangle(_ time:Double,_ nodes:Int32=128)->NCCSelfCertificateResult {
            a.withUnsafeBufferPointer{x in b.withUnsafeBufferPointer{y in ncc_self_triangle_certificate(x.baseAddress,x.count,y.baseAddress,y.count,time,nodes)}}
        }
        XCTAssertEqual(triangle(0.25).status,1);XCTAssertEqual(triangle(1).status,2);XCTAssertEqual(triangle(1,0).status,0)
        let e:[Double]=[0,0,0,1,0,0],f:[Double]=[0,0,0,-1,0,0]
        let prefix=e.withUnsafeBufferPointer{x in f.withUnsafeBufferPointer{y in ncc_self_edge_certificate(x.baseAddress,x.count,y.baseAddress,y.count,0.25)}}
        let full=e.withUnsafeBufferPointer{x in f.withUnsafeBufferPointer{y in ncc_self_edge_certificate(x.baseAddress,x.count,y.baseAddress,y.count,1)}}
        XCTAssertEqual(prefix.status,1);XCTAssertEqual(full.status,2);XCTAssertEqual(a,[0,0,0,1,0,0,0,1,0])
    }
    struct Case:Decodable {let current:[[Double]],triangles:[UInt32]}
    struct Point:Decodable {let x:Double,y:Double,z:Double;var vector:V{V(x,y,z)}}
    struct Pose:Decodable {let positions:[Point]}
    func data(_ path:String)throws->Data {try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:path,withExtension:"json",subdirectory:"Fixtures")))}
    func sha(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    func testRealPositiveSourcesAndExact236ToBodyBlocked237()throws {
        let metadata=try XCTUnwrap(JSONSerialization.jsonObject(with:data("SelfContactGuard/manifest")) as? [String:Any]),files=try XCTUnwrap(metadata["files"] as? [String:String])
        for (name,hash) in files {XCTAssertEqual(sha(try data(name)),hash)}
        for name in ["clear-case","shirt-case"] {
            let input=try JSONDecoder().decode(Case.self,from:data("IPCClothContact/"+name)),p=input.current.map{V($0[0],$0[1],$0[2])},prepared=try S.Prepared(vertexCount:p.count,triangleIndices:input.triangles)
            let r=prepared.guardMotion(previous:p,candidate:p)
            XCTAssertTrue(r.permitsWholeCandidate,r.reason);XCTAssertTrue(r.requiresIntersectionFreeInitialState)
        }
        let before=try JSONDecoder().decode(Pose.self,from:data("SelfContactGuard/accepted-r236")).positions.map(\.vector)
        let after=try JSONDecoder().decode(Pose.self,from:data("SelfContactGuard/body-blocked-r237-trial")).positions.map(\.vector)
        let topology=try JSONDecoder().decode(Case.self,from:data("IPCClothContact/r237-case")),p=try S.Prepared(vertexCount:before.count,triangleIndices:topology.triangles)
        let r=p.guardMotion(previous:before,candidate:after)
        XCTAssertEqual(r.status,.clear,r.reason);XCTAssertTrue(r.statistics.completedAllFeatures);XCTAssertEqual(r.statistics.certifiedTriangles,3472);XCTAssertEqual(r.statistics.uniqueVertexFace,22);XCTAssertEqual(r.statistics.uniqueEdgeEdge,168);XCTAssertEqual(r.statistics.nativeQueries,190);XCTAssertGreaterThan(r.statistics.aabbPrunedPrimitiveVisits,0)
        XCTAssertEqual(metadata["independentInitialProperPairs"] as? Int,0);XCTAssertEqual(metadata["independentInitialCoplanarPairs"] as? Int,0)
        XCTAssertEqual(metadata["overall237TrialAccepted"] as? Bool,false) // Body force still required.
    }
}
