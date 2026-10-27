import XCTest
import Foundation
@testable import NativeClothCollision

final class ContinuousBodyContactTests: XCTestCase {
    typealias CBC=ContinuousBodyContact
    typealias V=SIMD3<Double>
    let body=[V(-1,-1,0),V(1,-1,0),V(0,1,0)]
    let small=[V(-0.1,-0.1,1),V(0.1,-0.1,1),V(0,0.1,1)]
    let indices:[UInt32]=[0,1,2]
    func prepared(_ p:[V]?=nil,_ t:[UInt32]?=nil)throws->CBC.Prepared {
        try CBC.Prepared(bodyPositions:p ?? body,triangleIndices:t ?? indices)
    }
    func moved(_ p:[V],_ d:V)->[V] {p.map{$0+d}}
    func assertLimited(_ r:CBC.Report,_ oracle:Double,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(r.status,.limited,r.reason,file:file,line:line)
        XCTAssertFalse(r.permitsWholeCandidate,file:file,line:line)
        XCTAssertGreaterThan(r.safeTime,0,file:file,line:line)
        XCTAssertLessThan(r.safeTime,try! XCTUnwrap(r.conservativeTimeOfImpact),file:file,line:line)
        XCTAssertLessThanOrEqual(r.conservativeTimeOfImpact ?? 2,oracle+1e-12,file:file,line:line)
        XCTAssertEqual(r.conservativeTimeOfImpact ?? 2,oracle,accuracy:1e-6,file:file,line:line)
        XCTAssertTrue(r.statistics.completedAllFeatures,file:file,line:line)
    }
    func testClothVertexFacePathAndUnchangedBody() throws {
        let p=try prepared()
        let r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices)
        assertLimited(r,0.5)
        XCTAssertEqual(r.witness?.kind,.clothVertexBodyFace)
        XCTAssertEqual(p.bodyPositions,body);XCTAssertEqual(p.bodyTriangleIndices,indices)
        XCTAssertEqual(r.minimumSeparation,0)
    }
    func testBodyVertexMovingClothFacePath() throws {
        let b=[V(0,0,0),V(0.1,0,0),V(0,0.1,0)]
        let a=[V(-2,-2,1),V(2,-2,1),V(0,2,1)]
        let r=try prepared(b).guardMotion(previous:a,candidate:moved(a,V(0,0,-2)),clothTriangleIndices:indices)
        assertLimited(r,0.5);XCTAssertEqual(r.witness?.kind,.bodyVertexClothFace)
    }
    func testEdgeEdgeOnlyPathHasNoVertexPlaneCrossing() throws {
        let a=[V(-2,-0.2,-1),V(-2,0.2,-1),V(-2,0,1)]
        let b=moved(a,V(4,0,0))
        // Cloth vertices remain strictly z=+-1; body vertices' y=+-1 lies outside the moving face.
        let r=try prepared().guardMotion(previous:a,candidate:b,clothTriangleIndices:indices)
        assertLimited(r,0.3625);XCTAssertEqual(r.witness?.kind,.edgeEdge)
    }
    func testMissIncludesOverlappingTriangleAABBs() throws {
        let p=try prepared()
        let far=small.map{$0+V(5,0,0)}
        var r=p.guardMotion(previous:far,candidate:moved(far,V(0,0,-2)),clothTriangleIndices:indices)
        XCTAssertEqual(r.status,.clear);XCTAssertEqual(r.safeTime,1);XCTAssertTrue(r.permitsWholeCandidate)
        let outside=[V(0.8,0.8,1),V(0.9,0.8,1),V(0.8,0.9,1)]
        r=p.guardMotion(previous:outside,candidate:moved(outside,V(0,0,-2)),clothTriangleIndices:indices)
        XCTAssertGreaterThan(r.statistics.trianglePairs,0)
        XCTAssertEqual(r.status,.clear);XCTAssertEqual(r.safeTime,1)
        XCTAssertTrue(r.statistics.completedAllFeatures)
    }
    func testNecessaryFeaturesAreDeduplicatedAcrossTrianglePairs() throws {
        let b=[V(-1,-1,0),V(1,-1,0),V(1,1,0),V(-1,1,0)]
        let p=try prepared(b,[0,1,2,0,2,3])
        let r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices)
        assertLimited(r,0.5)
        XCTAssertEqual(r.statistics.trianglePairs,2)
        XCTAssertEqual(r.statistics.uniqueClothVertexBodyFace,6)
        XCTAssertEqual(r.statistics.uniqueBodyVertexClothFace,4)
        XCTAssertEqual(r.statistics.uniqueEdgeEdge,15)
        XCTAssertEqual(r.statistics.evaluatedFeatures,25)
        XCTAssertEqual(r.statistics.nativeQueries,25)
    }
    func testGlobalMinimumIsNotTheFirstNonzeroHit() throws {
        let b=body+body.map{$0+V(0,0,0.5)}
        let r=try prepared(b,[0,1,2,3,4,5]).guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices)
        assertLimited(r,0.25)
        XCTAssertTrue(r.witness?.bodyVertexIDs.allSatisfy{$0>=3} == true)
    }
    func testSeededRigidTransformsRetainAnalyticFirstContact() throws {
        var g=Generator()
        for _ in 0..<24 {
            let a=g.next()*6.0,b=g.next()*6.0,c=g.next()*6.0
            let scale=0.1+g.next()*1.9,t=0.2+g.next()*0.6
            let offset=V(g.next()-0.5,g.next()-0.5,g.next()-0.5)
            func transform(_ p:V)->V {
                let q=V(p.x,cos(a)*p.y-sin(a)*p.z,sin(a)*p.y+cos(a)*p.z)
                let r=V(cos(b)*q.x+sin(b)*q.z,q.y,-sin(b)*q.x+cos(b)*q.z)
                return V(cos(c)*r.x-sin(c)*r.y,sin(c)*r.x+cos(c)*r.y,r.z)*scale+offset
            }
            let p=try prepared(body.map(transform))
            let r=p.guardMotion(previous:small.map(transform),candidate:moved(small,V(0,0,-1/t)).map(transform),clothTriangleIndices:indices)
            assertLimited(r,t)
        }
    }
    func testInitialContactAndExplicitPositiveSeparationBlock() throws {
        let p=try prepared()
        for separation in [0.0,0.0005] {
            let z=separation*0.5
            let a=small.map{V($0.x,$0.y,z)}
            let r=p.guardMotion(previous:a,candidate:small,clothTriangleIndices:indices,
                                options:.init(minimumSeparation:separation))
            XCTAssertEqual(r.status,.blockedInitialContact,r.reason)
            XCTAssertEqual(r.safeTime,0);XCTAssertFalse(r.statistics.completedAllFeatures)
            XCTAssertNotNil(r.witness?.initialDistance)
            XCTAssertEqual(r.minimumSeparation,separation)
        }
    }
    func testUnsupportedIntermediateCollapseIsUncertainAndCannotAdvance() throws {
        let p=try prepared()
        let a=[V(0,0,1),V(1,0,1),V(0,1,1)]
        let b=[V(0,0,-1),V(-1,0,-1),V(0,-1,-1)]
        let r=p.guardMotion(previous:a,candidate:b,clothTriangleIndices:indices)
        XCTAssertEqual(r.status,.uncertain,r.reason);XCTAssertEqual(r.safeTime,0)
        XCTAssertFalse(r.permitsWholeCandidate)
    }
    struct Generator {
        var state:UInt64=0xa428c31a5e7b992d
        mutating func next()->Double {
            state=state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state>>11)/Double(UInt64(1)<<53)
        }
    }
    func testSeededBVHCandidateSetsMatchIndependentFullScan() throws {
        var g=Generator(),positions:[V]=[],tris:[UInt32]=[]
        for _ in 0..<160 {
            let a=V(g.next()*2-1,g.next()*2-1,g.next()*2-1)
            let d=0.005+g.next()*0.06
            let first=UInt32(positions.count)
            positions += [a,a+V(d,0.3*d,0),a+V(0,0.2*d,d)]
            tris += [first,first+1,first+2]
        }
        let p=try prepared(positions,tris)
        for _ in 0..<240 {
            let a=V(g.next()*2-1,g.next()*2-1,g.next()*2-1)
            let b=a+V(g.next()*0.5,g.next()*0.5,g.next()*0.5)
            let bounds=CBC.Bounds(minimum:a,maximum:b)
            var expected:[UInt32]=[]
            for f in 0..<tris.count/3 {
                let v=(0..<3).map{positions[Int(tris[3*f+$0])]}
                let lo=V(v.map{$0.x}.min()!,v.map{$0.y}.min()!,v.map{$0.z}.min()!)
                let hi=V(v.map{$0.x}.max()!,v.map{$0.y}.max()!,v.map{$0.z}.max()!)
                if lo.x<=b.x && hi.x>=a.x && lo.y<=b.y && hi.y>=a.y && lo.z<=b.z && hi.z>=a.z {
                    expected.append(UInt32(f))
                }
            }
            XCTAssertEqual(try p.candidateTriangleIDs(in:bounds),expected)
        }
        // Inclusive boundary query must retain a face touched at a vertex.
        let a=positions[0]
        XCTAssertTrue(try p.candidateTriangleIDs(in:.init(minimum:a,maximum:a)).contains(0))
    }
    func testCandidateBudgetFailureDoesNotReturnPartialIDs() throws {
        let p=try prepared([V(-1,-1,0),V(1,-1,0),V(1,1,0),V(-1,1,0)],[0,1,2,0,2,3])
        XCTAssertThrowsError(try p.candidateTriangleIDs(in:.init(minimum:V(-2,-2,-1),maximum:V(2,2,1)),
                                                       maximumCandidates:1))
    }
    func testAllResourceBudgetsBlockExplicitly() throws {
        let p=try prepared([V(-1,-1,0),V(1,-1,0),V(1,1,0),V(-1,1,0)],[0,1,2,0,2,3])
        var limits=CBC.Limits()
        limits.maximumTrianglePairs=1
        var r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                            options:.init(limits:limits))
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0)
        limits = .init();limits.maximumFeatureQueries=1
        r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                        options:.init(limits:limits))
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0)
        limits = .init();limits.maximumEstimatedBytes=p.estimatedResidentBytes
        r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                        options:.init(limits:limits))
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0)
        var vertices:[V]=[],triangles:[UInt32]=[]
        for i in 0..<12 {
            let k=UInt32(vertices.count)
            vertices += body.map{$0+V(0,0,Double(i)*0.001)}
            triangles += [k,k+1,k+2]
        }
        let many=try prepared(vertices,triangles)
        limits = .init();limits.maximumBVHVisits=1
        r=many.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                           options:.init(limits:limits))
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0)
        limits = .init();limits.maximumBuildWork=1
        XCTAssertThrowsError(try CBC.Prepared(bodyPositions:[V(-1,-1,0),V(1,-1,0),V(1,1,0),V(-1,1,0)],
                                              triangleIndices:[0,1,2,0,2,3],limits:limits))
        limits = .init();limits.maximumBodyVertices=2
        XCTAssertThrowsError(try CBC.Prepared(bodyPositions:body,triangleIndices:indices,limits:limits))
    }
    func testSIMDStrideAndScratchAreBudgetedBeforeAllocationOrTraversal() throws {
        var positions=body
        positions += Array(repeating:V(0.2,0.2,0.2),count:20_000)
        var limits=CBC.Limits()
        limits.maximumEstimatedBytes=positions.count*24+256+1_024
        XCTAssertLessThan(limits.maximumEstimatedBytes,positions.count*MemoryLayout<V>.stride)
        XCTAssertThrowsError(try CBC.Prepared(bodyPositions:positions,triangleIndices:indices,limits:limits))
        let p=try prepared()
        limits = .init()
        limits.maximumEstimatedBytes=p.estimatedResidentBytes+small.count*2*MemoryLayout<V>.stride+indices.count*4+1_024
        let r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                            options:.init(limits:limits))
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.safeTime,0)
        XCTAssertEqual(r.statistics.bvhNodeVisits,0)
        XCTAssertEqual(r.statistics.nativeQueries,0)
    }
    func testInvalidAndCancellationNeverClaimSafety() throws {
        XCTAssertThrowsError(try prepared([V(0,0,0),V(1,0,0),V(2,0,0)]))
        XCTAssertThrowsError(try prepared(body,[0,1,UInt32.max]))
        XCTAssertThrowsError(try CBC.Prepared(bodyPositions:body,triangleIndices:indices,isCancelled:{true}))
        let p=try prepared()
        XCTAssertEqual(p.guardMotion(previous:small,candidate:[],clothTriangleIndices:indices).status,.invalid)
        var bad=small;bad[0].x = .nan
        XCTAssertEqual(p.guardMotion(previous:bad,candidate:small,clothTriangleIndices:indices).status,.invalid)
        XCTAssertEqual(p.guardMotion(previous:small,candidate:small,clothTriangleIndices:[0,1,99]).status,.invalid)
        for o in [CBC.Options(minimumSeparation:-1),.init(distanceTolerance:0),
                  .init(maximumIterationsPerFeature:0),.init(safetyFactor:1),.init(safetyFactor:0)] {
            let r=p.guardMotion(previous:small,candidate:small,clothTriangleIndices:indices,options:o)
            XCTAssertEqual(r.status,.invalid);XCTAssertEqual(r.safeTime,0)
        }
        var calls=0
        let r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                            isCancelled:{calls+=1;return calls>=5})
        XCTAssertEqual(r.status,.cancelled);XCTAssertEqual(r.safeTime,0)
        XCTAssertFalse(r.permitsWholeCandidate);XCTAssertFalse(r.statistics.completedAllFeatures)
    }
    func testCancellationDuringCandidateFeatureExpansionRunsNoNativeQueries() throws {
        var vertices:[V]=[],faces:[UInt32]=[]
        for i in 0..<12 {
            let k=UInt32(vertices.count)
            vertices += body.map{$0+V(0,0,Double(i)*0.001)}
            faces += [k,k+1,k+2]
        }
        let p=try prepared(vertices,faces)
        var calls=0
        let r=p.guardMotion(previous:small,candidate:moved(small,V(0,0,-2)),clothTriangleIndices:indices,
                            isCancelled:{calls+=1;return calls>=8})
        XCTAssertEqual(r.status,.cancelled);XCTAssertEqual(r.safeTime,0)
        XCTAssertEqual(r.statistics.nativeQueries,0)
        XCTAssertFalse(r.statistics.completedAllFeatures)
    }
    struct FullFixture:Decodable {
        let previous:[[Double]],candidate:[[Double]],bodyPositions:[[Double]]
        let clothTriangleIndices:[UInt32],bodyTriangleIndices:[UInt32]
        let knownUnrestrictedVertexSweeps:Int
    }
    func testRealUpperPDGuardRetainsOriginalGeometryAndReportsActualStatus() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"upper-body-motion",withExtension:"json",subdirectory:"Fixtures"))
        let f=try JSONDecoder().decode(FullFixture.self,from:Data(contentsOf:url))
        func vectors(_ p:[[Double]])->[V] {p.map{V($0[0],$0[1],$0[2])}}
        let a=vectors(f.previous),b=vectors(f.candidate),body=vectors(f.bodyPositions)
        let prepared=try CBC.Prepared(bodyPositions:body,triangleIndices:f.bodyTriangleIndices)
        let r=prepared.guardMotion(previous:a,candidate:b,clothTriangleIndices:f.clothTriangleIndices)
        XCTAssertTrue([CBC.Status.limited,.uncertain,.blockedInitialContact].contains(r.status),r.reason)
        XCTAssertFalse(r.permitsWholeCandidate)
        XCTAssertLessThan(r.safeTime,1)
        if r.status == .limited {
            XCTAssertGreaterThan(r.safeTime,0)
            XCTAssertTrue(r.statistics.completedAllFeatures)
        } else {
            XCTAssertEqual(r.safeTime,0)
            XCTAssertFalse(r.statistics.completedAllFeatures)
        }
        XCTAssertEqual(prepared.bodyPositions,body);XCTAssertEqual(prepared.bodyTriangleIndices,f.bodyTriangleIndices)
        XCTAssertEqual(f.knownUnrestrictedVertexSweeps,99)
        if let path=ProcessInfo.processInfo.environment["NCC_BODY_GUARD_REPORT"] {
            let st=r.statistics
            let data:[String:Any]=[
                "status":r.status.rawValue,"safeTime":r.safeTime,"reason":r.reason,
                "conservativeTOI":r.conservativeTimeOfImpact.map{NSNumber(value:$0)} ?? NSNull(),
                "trianglePairs":st.trianglePairs,"clothVF":st.uniqueClothVertexBodyFace,
                "bodyVF":st.uniqueBodyVertexClothFace,"edgeEdge":st.uniqueEdgeEdge,
                "evaluatedFeatures":st.evaluatedFeatures,"nativeQueries":st.nativeQueries,
                "estimatedWorkingBytes":st.estimatedWorkingBytes,"bvhVisits":st.bvhNodeVisits,
                "completedAllFeatures":st.completedAllFeatures,
                "witnessKind":r.witness?.kind.rawValue ?? "",
                "witnessClothIDs":r.witness?.clothVertexIDs ?? [],
                "witnessBodyIDs":r.witness?.bodyVertexIDs ?? [],
                "witnessTOI":r.witness?.conservativeTimeOfImpact.isFinite == true ? r.witness!.conservativeTimeOfImpact:0,
                "witnessInitialDistance":r.witness?.initialDistance.map{NSNumber(value:$0)} ?? NSNull(),
                "acceptedClothOutputClaimed":false,"knownUnrestrictedVertexSweeps":99
            ]
            try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        }
    }
}

