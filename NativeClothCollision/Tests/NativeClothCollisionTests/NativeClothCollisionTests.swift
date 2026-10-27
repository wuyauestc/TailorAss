import XCTest
import CNativeClothCollision
@testable import NativeClothCollision
import Foundation
import Darwin

final class NativeClothCollisionTests: XCTestCase {
    typealias CCD = NativeClothCollision
    let start = [0.0,0,1, -1,-1,0, 1,-1,0, 0,1,0]
    let end = [0.0,0,-1, -1,-1,0, 1,-1,0, 0,1,0]
    func assertTOI(_ r: CCD.Result, _ t: Double, accuracy: Double = 1e-7, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.status, .conservativeHit, file: file, line: line)
        XCTAssertLessThanOrEqual(r.conservativeTimeOfImpact, t + 1e-12, file: file, line: line)
        XCTAssertEqual(r.conservativeTimeOfImpact, t, accuracy: accuracy, file: file, line: line)
        XCTAssertLessThanOrEqual(r.achievedDistanceTolerance, 1e-8, file: file, line: line)
        XCTAssertFalse(r.permitsWholeInterval, file: file, line: line)
    }
    func testVertexFaceAnalyticTime() { assertTOI(CCD.vertexFace(start: start, end: end), 0.5) }
    func testEdgeEdgeAnalyticTime() {
        let a = [-1.0,0,0, 1,0,0, 0,-1,1, 0,1,1]
        let b = [-1.0,0,0, 1,0,0, 0,-1,-1, 0,1,-1]
        assertTOI(CCD.edgeEdge(start: a, end: b), 0.5)
    }
    func testNoHitAndClippedInterval() {
        var a = start, b = end; a[0] = 3; b[0] = 3
        let miss = CCD.vertexFace(start: a, end: b)
        XCTAssertEqual(miss.status, .noHit); XCTAssertTrue(miss.permitsWholeInterval)
        XCTAssertTrue(miss.conservativeTimeOfImpact.isInfinite)
        let clipped = CCD.vertexFace(start: start, end: end, options: .init(maximumTime: 0.25))
        XCTAssertEqual(clipped.status, .noHit)
    }
    func testInitialContactIsNeverSkipped() {
        var a = start; a[2] = 0
        let r = CCD.vertexFace(start: a, end: end)
        assertTOI(r, 0)
    }
    func testFiniteThicknessCannotReturnLaterImpact() {
        let r = CCD.vertexFace(start: start, end: end, options: .init(minimumSeparation: 0.001, distanceTolerance: 2e-5, maximumIterations: 100_000))
        XCTAssertEqual(r.status, .conservativeHit, String(describing: r))
        XCTAssertLessThanOrEqual(r.conservativeTimeOfImpact, (1 - 0.001)/2)
        XCTAssertGreaterThan(r.conservativeTimeOfImpact, 0.49)
    }
    func testPositiveThicknessPrecisionSaturationIsExplicitlyUncertain() {
        let r = CCD.vertexFace(start: start, end: end,
            options: .init(minimumSeparation: 0.001, distanceTolerance: 1e-8, maximumIterations: 100_000))
        XCTAssertEqual(r.status, .uncertain); XCTAssertEqual(r.detail, .precisionOrBudget)
        XCTAssertFalse(r.permitsWholeInterval)
        XCTAssertGreaterThan(r.achievedDistanceTolerance, 1e-8)
    }
    func testMotionOfWholeTriangle() {
        var a = start, b = start; a[2] = 0; b[2] = 0
        for i in [5,8,11] { a[i] = 1; b[i] = -1 }
        assertTOI(CCD.vertexFace(start: a, end: b), 0.5)
    }
    func testExactAxisRotationTranslationAndScale() {
        func transform(_ x: [Double], _ s: Double) -> [Double] {
            var out: [Double] = []
            for i in stride(from: 0, to: 12, by: 3) {
                out.append(s * x[i+1] + 0.11)
                out.append(s * x[i+2] - 0.27)
                out.append(s * x[i] + 0.04)
            }
            return out
        }
        for s in [0.1,1.0,10.0] {
            assertTOI(CCD.vertexFace(start: transform(start,s), end: transform(end,s)), 0.5, accuracy: 1e-6)
        }
    }
    func testCoplanarAndEdgeTouchCannotReturnSafeNoHit() {
        var a = start, b = end; a[0] = 2; a[2] = 0; b[2] = 0
        XCTAssertNotEqual(CCD.vertexFace(start: a, end: b).status, .noHit)
        a = start; b = end; a[0] = -1; a[1] = -1; b[0] = -1; b[1] = -1
        XCTAssertNotEqual(CCD.vertexFace(start: a, end: b).status, .noHit)
    }
    func testDegenerateAndIntermediateCollapseAreExplicitlyUncertain() {
        var a = start, b = end
        for i in 6..<9 { a[i] = a[i-3]; b[i] = b[i-3] }
        XCTAssertEqual(CCD.vertexFace(start: a, end: b).detail, .uncertainGeometry)
        // Both endpoint faces have positive normal, but the entire triangle collapses at t=.5.
        a = [0,0,1, 0,0,0, 1,0,0, 0,1,0]
        b = [0,0,-1, 0,0,0, -1,0,0, 0,-1,0]
        let r = CCD.vertexFace(start: a, end: b)
        XCTAssertEqual(r.status, .uncertain); XCTAssertFalse(r.permitsWholeInterval)
        let ee = CCD.edgeEdge(start: [-1,0,0, 1,0,0, 0,-1,1, 0,1,1],
                             end: [1,0,0, -1,0,0, 0,-1,-1, 0,1,-1])
        XCTAssertEqual(ee.status, .uncertain); XCTAssertEqual(ee.detail, .uncertainGeometry)
    }
    func testAllInvalidParameterBoundaries() {
        let bad: [CCD.Options] = [
            .init(minimumSeparation: -1), .init(minimumSeparation: .nan), .init(minimumSeparation: .infinity),
            .init(minimumSeparation: 1),
            .init(maximumTime: 0), .init(maximumTime: -1), .init(maximumTime: 1.01),
            .init(maximumTime: .nan), .init(maximumTime: .infinity),
            .init(distanceTolerance: 0), .init(distanceTolerance: -1),
            .init(distanceTolerance: .nan), .init(distanceTolerance: .infinity), .init(distanceTolerance: 1.01),
            .init(maximumIterations: 0), .init(maximumIterations: -1), .init(maximumIterations: 100_001),
            .init(maximumIterations: Int64.max)
        ]
        for o in bad {
            XCTAssertEqual(CCD.vertexFace(start: start, end: end, options: o).status, .invalid)
            XCTAssertEqual(CCD.edgeEdge(start: start, end: end, options: o).status, .invalid)
        }
        for bad in [Double.nan, .infinity, -.infinity, 1_000_001] {
            var a = start; a[0] = bad
            XCTAssertEqual(CCD.vertexFace(start: a, end: end).status, .invalid)
        }
        XCTAssertEqual(CCD.vertexFace(start: [], end: end).status, .invalid)
        XCTAssertEqual(CCD.vertexFace(start: start, end: end + [0]).status, .invalid)
        let o = NCCOptions(minimum_separation: 0, maximum_time: 1, distance_tolerance: 1e-8, maximum_iterations: 100)
        XCTAssertEqual(ncc_vertex_face(nil, 12, nil, 12, o).status, Int32(NCC_STATUS_INVALID.rawValue))
    }
    func testUnsupportedRoundingModeDoesNotMutateThreadEnvironment() {
        let old = fegetround(); defer { _ = fesetround(old) }
        XCTAssertEqual(fesetround(FE_UPWARD), 0)
        let r = CCD.vertexFace(start: start, end: end)
        XCTAssertEqual(r.status, .uncertain); XCTAssertEqual(r.detail, .roundingMode)
        XCTAssertEqual(fegetround(), FE_UPWARD)
    }
    struct Fixture: Decodable {
        struct Witness: Decodable { let segmentParameter: Double; let triangle: [[Double]]; let vertexStart: [Double]; let vertexEnd: [Double] }
        let queryStart: [[Double]], queryEnd: [[Double]]
        let witness: Witness
        let acceptanceClaimed: Bool
    }
    func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "upper-pd-motion", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func testActualUpperMotionAgainstIndependentSegmentTriangleOracle() throws {
        let f = try fixture(), w = f.witness
        func sub(_ a: [Double],_ b: [Double]) -> [Double] { zip(a,b).map(-) }
        func dot(_ a: [Double],_ b: [Double]) -> Double { zip(a,b).map(*).reduce(0,+) }
        func cross(_ a: [Double],_ b: [Double]) -> [Double] {
            [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
        }
        let d=sub(w.vertexEnd,w.vertexStart), e1=sub(w.triangle[1],w.triangle[0]), e2=sub(w.triangle[2],w.triangle[0])
        let h=cross(d,e2), det=dot(e1,h), ss=sub(w.vertexStart,w.triangle[0]), q=cross(ss,e1)
        let u=dot(ss,h)/det, v=dot(d,q)/det, t=dot(e2,q)/det
        XCTAssertGreaterThan(u,0); XCTAssertGreaterThan(v,0); XCTAssertLessThan(u+v,1)
        XCTAssertEqual(t,w.segmentParameter,accuracy:1e-13); XCTAssertFalse(f.acceptanceClaimed)
        let r=CCD.vertexFace(start:f.queryStart.flatMap{$0},end:f.queryEnd.flatMap{$0})
        assertTOI(r,t,accuracy:1e-5)
        XCTAssertLessThanOrEqual((t-r.conservativeTimeOfImpact)*sqrt(dot(d,d)),4e-8)
        let thick=CCD.vertexFace(start:f.queryStart.flatMap{$0},end:f.queryEnd.flatMap{$0},
                                options:.init(minimumSeparation:0.0005))
        XCTAssertEqual(thick.status,.conservativeHit)
        XCTAssertLessThan(thick.conservativeTimeOfImpact,r.conservativeTimeOfImpact)
    }
    func testBudgetExhaustionIsNotSafeNoHit() throws {
        let f=try fixture()
        let r=CCD.vertexFace(start:f.queryStart.flatMap{$0},end:f.queryEnd.flatMap{$0},
                             options:.init(maximumIterations:1))
        XCTAssertEqual(r.status,.uncertain); XCTAssertEqual(r.detail,.precisionOrBudget)
        XCTAssertFalse(r.permitsWholeInterval); XCTAssertGreaterThan(r.achievedDistanceTolerance,1e-8)
        XCTAssertEqual(r.configuredIterationBudget,1)
    }
    func testCancellationBeforeAndAfterBoundedCallPreservesInputs() {
        let a=start,b=end
        let before=CCD.vertexFace(start:a,end:b,isCancelled:{true})
        XCTAssertEqual(before.detail,.cancelled);XCTAssertFalse(before.permitsWholeInterval)
        var checks=0
        let after=CCD.vertexFace(start:a,end:b,isCancelled:{checks+=1;return checks==2})
        XCTAssertEqual(after.detail,.cancelled);XCTAssertFalse(after.permitsWholeInterval)
        XCTAssertEqual(a,start);XCTAssertEqual(b,end)
    }
    func testIndependentCallsCanRunConcurrently() async {
        let a=start,b=end
        let passed=await withTaskGroup(of:Bool.self,returning:Bool.self) { group in
            for _ in 0..<16 { group.addTask {
                let r=CCD.vertexFace(start:a,end:b)
                return r.status == .conservativeHit && abs(r.conservativeTimeOfImpact-0.5)<1e-7
            }}
            var ok=true
            for await item in group { ok = ok && item }
            return ok
        }
        XCTAssertTrue(passed)
    }
    func testLargeRigidEndpointRotationCanCertifyNoHit() {
        let angle=117.0*Double.pi/180,c=cos(angle),s=sin(angle)
        let a=[10.0,10,10, 0,0,0, 1,0,0, 0,1,0]
        let b=[10.0,10,10, 0,0,0, 1,0,0, 0,c,s]
        let r=CCD.vertexFace(start:a,end:b)
        XCTAssertEqual(r.status,.noHit);XCTAssertTrue(r.permitsWholeInterval)
        // The requested domain is [0,.75], rather than a rescaled answer for [0,1].
        let clipped=CCD.vertexFace(start:a,end:b,options:.init(maximumTime:0.75))
        XCTAssertEqual(clipped.status,.noHit)
    }
    func testRotatingFaceActualInteriorHitCannotBecomeNoHit() {
        let angle=117.0*Double.pi/180,c=cos(angle),s=sin(angle)
        let p=[0.25,(1+c)/4,s/4]
        let a=p+[0,0,0, 1,0,0, 0,1,0],b=p+[0,0,0, 1,0,0, 0,c,s]
        assertTOI(CCD.vertexFace(start:a,end:b),0.5,accuracy:1e-6)
    }
    func testClippedDomainCollapseAndNearZeroRemainUncertain() {
        let a=[10.0,10,10, 0,0,0, 1,0,0, 0,1,0]
        let b=[10.0,10,10, 0,0,0, 1,0,0, 0,-1,0]
        XCTAssertEqual(CCD.vertexFace(start:a,end:b,options:.init(maximumTime:0.25)).status,.noHit)
        for time in [0.5,0.75,1.0] {
            let r=CCD.vertexFace(start:a,end:b,options:.init(maximumTime:time))
            XCTAssertEqual(r.detail,.uncertainGeometry);XCTAssertFalse(r.permitsWholeInterval)
        }
        let near=[10.0,10,10, 0,0,0, 1,0,0, 1,1e-13,0]
        let r=CCD.vertexFace(start:near,end:near)
        XCTAssertEqual(r.detail,.uncertainGeometry);XCTAssertFalse(r.permitsWholeInterval)
    }
    struct RotationWitness:Decodable {let queryStartXYZ:[Double],queryEndXYZ:[Double],physicalAcceptance:Bool}
    func testActualClothTriangleRotationCertificate() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"cloth-triangle-rotation",withExtension:"json",subdirectory:"Fixtures"))
        let f=try JSONDecoder().decode(RotationWitness.self,from:Data(contentsOf:url))
        XCTAssertFalse(f.physicalAcceptance)
        let r=CCD.vertexFace(start:f.queryStartXYZ,end:f.queryEndXYZ)
        XCTAssertTrue([CCD.Status.noHit,.conservativeHit].contains(r.status),String(describing:r))
        XCTAssertEqual(r.detail,.none)
    }

}

