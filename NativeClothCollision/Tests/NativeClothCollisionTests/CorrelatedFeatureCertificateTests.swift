import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class CorrelatedFeatureCertificateTests:XCTestCase {
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Primitive:Decodable {let start:[[Double]],end:[[Double]],vertexIDs:[UInt32]}
    struct Complete:Decodable {
        let previousOuterStep:Int,previousOuter:[[Double]],inner:[[Double]],candidate:[[Double]],triangles:[UInt32]
    }
    struct Motion:Codable {let name:String,kind:F.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool}
    struct Row:Codable {let motion:Motion,proof:F.Report}
    struct Export:Codable {let passed:Bool,rows:[Row]}
    func load<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/CorrelatedFeatureCertificate"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func vectors(_ a:[[Double]])->[V] {a.map{V($0[0],$0[1],$0[2])}}
    func actual()throws->Motion {
        let p:Primitive=try load("circle690-ee")
        return .init(name:"actual-Circle690-EE",kind:.edgeEdge,start:vectors(p.start),end:vectors(p.end),floor:0,expectedSeparated:true)
    }
    func movingFace(_ epsilon:Double,name:String,floor:Double=0,separated:Bool=true)->Motion {
        // n/16=(t+.25,0,1), g/16=(t-.5)^2+epsilon. The projected
        // point is inside the scaled triangle around the critical time.
        .init(name:name,kind:.vertexFace,
            start:[V(0.75,0.25,0.0625+epsilon),.zero,V(4,0,-1),V(0,4,0)],
            end:[V(1.75,0.25,-1.9375+epsilon),.zero,V(4,0,-5),V(0,4,0)],
            floor:floor,expectedSeparated:separated)
    }
    func run(_ m:Motion,trace:Bool=true,limits:F.Limits = .init(),cancel:()->Bool={false})->F.Report {
        var l=limits;l.recordLeafCertificates=trace
        return F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:l,isCancelled:cancel)
    }
    func testActualAndAnalyticMovingNormalsAgainstFractionTrace()throws {
        let a=try actual()
        let scaled=Motion(name:"actual-EE-positive-half-mm",kind:.edgeEdge,start:a.start.map{$0*100_000},
            end:a.end.map{$0*100_000},floor:0.0005,expectedSeparated:true)
        let motions=[a,scaled,movingFace(1e-10,name:"moving-VF-correlated-clear"),
            movingFace(0.001,name:"moving-VF-positive-floor",floor:0.0005),
            movingFace(0,name:"moving-VF-tangent-at-midpoint",separated:false),
            movingFace(-1.0/256,name:"moving-VF-two-real-crossings",separated:false)]
        var rows:[Row]=[]
        for m in motions {
            let p=run(m);XCTAssertEqual(p.distanceSeparatedForWholeMotion,m.expectedSeparated,m.name)
            if m.expectedSeparated {
                XCTAssertGreaterThan(p.movingNormalIntervalsCertified+p.expansionIntervalsCertified+p.criticalIntervalsCertified,0,m.name)
                XCTAssertEqual(p.fixedIntervalsCertified+p.movingNormalIntervalsCertified+p.expansionIntervalsCertified+p.criticalIntervalsCertified,p.certifiedIntervals)
                XCTAssertEqual(p.leafCertificates.count+p.movingNormalCertificates.count+p.expansionCertificates.count+p.criticalCertificates.count,p.certifiedIntervals)
                for c in p.movingNormalCertificates {
                    XCTAssertGreaterThan(c.absoluteProjectionLowerBound,c.requiredProductUpperBound)
                    XCTAssertEqual(c.normalBernsteinBounds.count,3);XCTAssertEqual(c.projectionBernsteinBounds.count,4)
                }
            }
            XCTAssertLessThanOrEqual(p.processedNodes,8191);XCTAssertLessThanOrEqual(p.maximumDepthReached,12)
            XCTAssertLessThanOrEqual(p.maximumEstimatedWorkingBytes,F.Limits().maximumEstimatedWorkingBytes)
            rows.append(.init(motion:m,proof:p))
        }
        if let file=ProcessInfo.processInfo.environment["NCC_CORRELATED_FEATURE_REPORT"] {
            let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys]
            try e.encode(Export(passed:true,rows:rows)).write(to:URL(fileURLWithPath:file))
        }
    }
    func testOrientationReversalTranslationAndSIUnits()throws {
        let a=try actual();var motions:[Motion]=[]
        motions.append(.init(name:"EE-time-reversal",kind:.edgeEdge,start:a.end,end:a.start,floor:0,expectedSeparated:true))
        motions.append(.init(name:"EE-edge-order-reversal",kind:.edgeEdge,start:[a.start[2],a.start[3],a.start[0],a.start[1]],
            end:[a.end[2],a.end[3],a.end[0],a.end[1]],floor:0,expectedSeparated:true))
        let shift=V(0.25,-0.125,0.5)
        motions.append(.init(name:"EE-world-translation",kind:.edgeEdge,start:a.start.map{$0+shift},end:a.end.map{$0+shift},floor:0,expectedSeparated:true))
        let vf=movingFace(0.001,name:"base",floor:0.0005)
        for scale in [0.001,1.0,1000.0] {
            motions.append(.init(name:"VF-SI-scale-\(scale)",kind:.vertexFace,start:vf.start.map{$0*scale},end:vf.end.map{$0*scale},
                floor:vf.floor*scale,expectedSeparated:true))
        }
        var rows:[Row]=[]
        for m in motions {let p=run(m);XCTAssertTrue(p.distanceSeparatedForWholeMotion,m.name);rows.append(.init(motion:m,proof:p))}
        if let file=ProcessInfo.processInfo.environment["NCC_CORRELATED_VARIANTS_REPORT"] {
            try JSONEncoder().encode(Export(passed:true,rows:rows)).write(to:URL(fileURLWithPath:file))
        }
    }
    func testRealEEContactNearParallelAndDomainRequirement()throws {
        let crossing=Motion(name:"EE-cross",kind:.edgeEdge,start:[V(-1,0,0),V(1,0,0),V(0,-1,1),V(0,1,1)],
            end:[V(-1,0,0),V(1,0,0),V(0,-1,-1),V(0,1,-1)],floor:0,expectedSeparated:false)
        let crossProof=run(crossing);XCTAssertFalse(crossProof.distanceSeparatedForWholeMotion)
        let parallel=Motion(name:"EE-parallel",kind:.edgeEdge,start:[V(-1,0,0),V(1,0,0),V(-1,0,0.001),V(1,0,0.001)],
            end:[V(-1,0,0),V(1,0,0),V(-1,1e-10,0.001),V(1,1e-10,0.001)],floor:0.0005,expectedSeparated:true)
        let parallelProof=run(parallel);XCTAssertTrue(parallelProof.distanceSeparatedForWholeMotion)
        let degenerate=Motion(name:"VF-degenerate-contact",kind:.vertexFace,start:[.zero,.zero,V(1,0,0),V(2,0,0)],
            end:[.zero,.zero,V(1,0,0),V(2,0,0)],floor:0,expectedSeparated:false)
        let p=run(degenerate);XCTAssertFalse(p.distanceSeparatedForWholeMotion)
        XCTAssertTrue(p.requiresIndependentPrimitiveDomainCertificate)
        if let file=ProcessInfo.processInfo.environment["NCC_CORRELATED_EDGE_REPORT"] {
            try JSONEncoder().encode(Export(passed:true,rows:[.init(motion:crossing,proof:crossProof),
                .init(motion:parallel,proof:parallelProof),.init(motion:degenerate,proof:p)])).write(to:URL(fileURLWithPath:file))
        }
    }
    func testOriginalBudgetsNearestAndCancellationCannotGrantPartialClear()throws {
        let m=try actual()
        var l=F.Limits();l.maximumNodes=0
        XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        l=F.Limits();l.maximumDepth=0
        let root=run(m,limits:l)
        XCTAssertTrue(root.status == .notCertified || root.criticalIntervalsCertified==1)
        l=F.Limits();l.maximumEstimatedWorkingBytes=4096
        XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        var calls=0
        let complete=run(m,cancel:{calls+=1;return false});XCTAssertEqual(complete.status,.separated)
        var cancelCalls=0
        let cancelled=run(m,cancel:{cancelCalls+=1;return cancelCalls>=calls})
        XCTAssertEqual(cancelled.status,.cancelled);XCTAssertFalse(cancelled.distanceSeparatedForWholeMotion)
        #if os(macOS)
        let rounding=fegetround();defer{fesetround(rounding)}
        XCTAssertEqual(fesetround(FE_DOWNWARD),0)
        XCTAssertEqual(run(m).status,.unsupportedRounding)
        #endif
    }
    func testLegacyFixedTraceAndOldJSONDecodeKeepTheirMeaning()throws {
        let m=Motion(name:"fixed",kind:.vertexFace,start:[V(0,0,1),.zero,V(1,0,0),V(0,1,0)],
            end:[V(0,0,1),.zero,V(1,0,0),V(0,1,0)],floor:0.0005,expectedSeparated:true)
        let p=run(m);XCTAssertEqual(p.fixedIntervalsCertified,1);XCTAssertEqual(p.movingNormalAttempts,0)
        XCTAssertTrue(p.movingNormalCertificates.isEmpty);XCTAssertEqual(p.leafCertificates.count,1)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
        for key in ["fixedIntervalsCertified","movingNormalAttempts","movingNormalIntervalsCertified","movingNormalCertificates"] {object.removeValue(forKey:key)}
        let old=try JSONDecoder().decode(F.Report.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(old.status,p.status);XCTAssertEqual(old.fixedIntervalsCertified,1)
        XCTAssertEqual(old.movingNormalIntervalsCertified,0);XCTAssertTrue(old.movingNormalCertificates.isEmpty)
    }
    func testActualEntirePhysicalAndLocalSelfQueriesContinuePastOldWitness()throws {
        let m:Complete=try load("circle690-complete-self")
        XCTAssertEqual(m.previousOuterStep,689)
        let p=try SelfContactGuard.Prepared(vertexCount:m.candidate.count,triangleIndices:m.triangles)
        for x in [m.inner,m.previousOuter] {
            let r=p.guardMotion(previous:vectors(x),candidate:vectors(m.candidate))
            XCTAssertTrue(r.permitsWholeCandidate,r.reason)
            XCTAssertTrue(r.statistics.completedDomainCertificates);XCTAssertTrue(r.statistics.completedAllFeatures)
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueEdgeEdge+r.statistics.uniqueVertexFace)
            XCTAssertGreaterThan(r.statistics.evaluatedFeatures,599)
            XCTAssertGreaterThan(r.statistics.euclideanCertifiedAfterPrecisionLimit,0)
            XCTAssertEqual(r.statistics.euclideanCertificateAttempts,r.statistics.euclideanCertifiedFeatures)
        }
    }
}
