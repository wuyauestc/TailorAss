import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class ExpansionFeatureCertificateTests:XCTestCase {
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Primitive:Decodable {let start:[[Double]],end:[[Double]],vertexIDs:[UInt32]}
    struct Complete:Decodable {let sourceSHA256:String,previousOuterStep:Int,previousOuter:[[Double]],inner:[[Double]],candidate:[[Double]],triangles:[UInt32]}
    struct ArithmeticRow:Codable {let a:Double,b:Double,sum:[Double],product:[Double]}
    struct Motion:Codable {let name:String,kind:F.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool}
    struct Row:Codable {let motion:Motion,proof:F.Report}
    struct Export:Codable {let passed:Bool,rows:[Row]}
    func load<T:Decodable>(_ name:String,as:T.Type=T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/ExpansionFeatureCertificate"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func vectors(_ a:[[Double]])->[V] {a.map{V($0[0],$0[1],$0[2])}}
    func actual()throws->Motion {
        let p:Primitive=try load("circle690-fsc111-ee")
        return .init(name:"actual111-Circle690-near-EE",kind:.edgeEdge,start:vectors(p.start),end:vectors(p.end),floor:0,expectedSeparated:true)
    }
    func run(_ m:Motion,limits:F.Limits = .init(),cancel:()->Bool={false})->F.Report {
        var l=limits;l.recordLeafCertificates=true
        return F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:l,isCancelled:cancel)
    }
    func export(_ rows:[Row],environment:String)throws {
        if let file=ProcessInfo.processInfo.environment[environment] {
            let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.prettyPrinted]
            try e.encode(Export(passed:true,rows:rows)).write(to:URL(fileURLWithPath:file))
        }
    }
    func testEFTSumProductAgainstIndependentExactBinaryOracle()throws {
        var inputs:[(Double,Double)]=[(1,Double.ulpOfOne),(1,-1),(1e6,-1e6),(1e100,1e-100),
            (Double.leastNormalMagnitude,0.5),(0,Double.leastNonzeroMagnitude),(Double.leastNonzeroMagnitude,1)]
        var seed:UInt64=0x6b8b_4567_327b_23c6
        for _ in 0..<192 {
            func next()->Double {
                seed=seed &* 6364136223846793005 &+ 1442695040888963407
                let exponent=UInt64(623+Int((seed>>52)%800))
                return Double(bitPattern:(seed&(1<<63))|(exponent<<52)|(seed&0x000f_ffff_ffff_ffff))
            }
            inputs.append((next(),next()))
        }
        var rows:[ArithmeticRow]=[]
        for(a,b)in inputs {
            var w=F.ExpansionWork(maximumOperations:100_000)
            let s=try w.sum(a==0 ? []:[a],b==0 ? []:[b],{false})
            let p=try w.product(a==0 ? []:[a],b==0 ? []:[b],{false})
            XCTAssertLessThanOrEqual(w.maximumWords,64)
            rows.append(.init(a:a,b:b,sum:s,product:p))
        }
        if let file=ProcessInfo.processInfo.environment["NCC_EXPANSION_ARITHMETIC_REPORT"] {
            try JSONEncoder().encode(rows).write(to:URL(fileURLWithPath:file))
        }
    }
    func testUnderflowOverflowAndOperationBudgetAreExplicit()throws {
        var w=F.ExpansionWork(maximumOperations:10_000)
        XCTAssertThrowsError(try w.product([Double.leastNonzeroMagnitude],[0.5],{false})) {
            XCTAssertEqual(String(describing:$0),"underflow")
        }
        XCTAssertThrowsError(try w.product([Double.greatestFiniteMagnitude],[2],{false})) {
            XCTAssertEqual(String(describing:$0),"nonfinite")
        }
        w=F.ExpansionWork(maximumOperations:0)
        XCTAssertThrowsError(try w.product([1],[1],{false})) {XCTAssertEqual(String(describing:$0),"operations")}
        let m=try actual();var l=F.Limits();l.maximumExpansionOperations=0
        let r=run(m,limits:l)
        XCTAssertEqual(r.status,.budgetExceeded);XCTAssertEqual(r.reason,.expansionOperationBudget)
        XCTAssertFalse(r.distanceSeparatedForWholeMotion)
        l=F.Limits();l.maximumEstimatedWorkingBytes=65_536
        XCTAssertEqual(F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:l).status,.budgetExceeded)
    }
    func testActualNearEEAndPositiveFloorUseSeparateScaledTrace()throws {
        let a=try actual()
        let positive=Motion(name:"actual111-EE-positive-floor",kind:a.kind,start:a.start,end:a.end,floor:1e-16,expectedSeparated:true)
        let tooClose=Motion(name:"actual111-EE-under-required-floor",kind:a.kind,start:a.start,end:a.end,floor:1e-12,expectedSeparated:false)
        var rows:[Row]=[]
        for m in [a,positive,tooClose] {
            let r=run(m);XCTAssertEqual(r.distanceSeparatedForWholeMotion,m.expectedSeparated,m.name)
            if m.expectedSeparated {
                XCTAssertGreaterThan(r.expansionIntervalsCertified+r.criticalIntervalsCertified,0)
                XCTAssertEqual(r.certifiedIntervals,r.fixedIntervalsCertified+r.movingNormalIntervalsCertified+r.expansionIntervalsCertified+r.criticalIntervalsCertified)
                XCTAssertEqual(r.certifiedIntervals,r.leafCertificates.count+r.movingNormalCertificates.count+r.expansionCertificates.count+r.criticalCertificates.count)
                for c in r.expansionCertificates {var scale=3;for n in 4...max(4,c.projectionDegree) where n<=c.projectionDegree {scale*=n}
                    XCTAssertEqual(c.projectionScale,scale);XCTAssertEqual(c.scaledProjectionBernsteinBounds.count,c.projectionDegree+1);XCTAssertLessThanOrEqual(c.projectionDegree,8);XCTAssertGreaterThan(c.absoluteScaledProjectionLowerBound,c.requiredScaledProductUpperBound)}
            }
            XCTAssertLessThanOrEqual(r.processedNodes,8191);XCTAssertLessThanOrEqual(r.maximumDepthReached,12)
            XCTAssertLessThanOrEqual(r.expansionOperations,1_048_576);XCTAssertLessThanOrEqual(r.maximumExpansionWords,64)
            rows.append(.init(motion:m,proof:r))
        }
        try export(rows,environment:"NCC_EXPANSION_FEATURE_REPORT")
    }
    func testReversalTranslationAndSIScaleRetainFullPathChecks()throws {
        let a=try actual();var motions:[Motion]=[
            .init(name:"near-EE-time-reversal",kind:.edgeEdge,start:a.end,end:a.start,floor:0,expectedSeparated:true),
            .init(name:"near-EE-order-reversal",kind:.edgeEdge,start:[a.start[2],a.start[3],a.start[0],a.start[1]],end:[a.end[2],a.end[3],a.end[0],a.end[1]],floor:0,expectedSeparated:true)]
        // Power-of-two SI rescaling preserves every stored input exactly.
        for scale in [0.125,8.0] {motions.append(.init(name:"near-EE-SI-scale-\(scale)",kind:.edgeEdge,start:a.start.map{$0*scale},end:a.end.map{$0*scale},floor:0,expectedSeparated:true))}
        var rows:[Row]=[]
        for m in motions {let r=run(m);XCTAssertTrue(r.distanceSeparatedForWholeMotion,m.name);rows.append(.init(motion:m,proof:r))}
        try export(rows,environment:"NCC_EXPANSION_VARIANTS_REPORT")
    }
    func testTrueContactsCancellationRoundingAndOldJSON()throws {
        let a=try actual()
        let crossing=Motion(name:"exact-EE-real-cross",kind:.edgeEdge,start:[V(-1,0,0),V(1,0,0),V(0,-1,1),V(0,1,1)],end:[V(-1,0,0),V(1,0,0),V(0,-1,-1),V(0,1,-1)],floor:0,expectedSeparated:false)
        let tangent=Motion(name:"exact-VF-tangent",kind:.vertexFace,start:[V(0.75,0.25,0.0625),.zero,V(4,0,-1),V(0,4,0)],end:[V(1.75,0.25,-1.9375),.zero,V(4,0,-5),V(0,4,0)],floor:0,expectedSeparated:false)
        var rows:[Row]=[]
        for m in [crossing,tangent] {let r=run(m);XCTAssertFalse(r.distanceSeparatedForWholeMotion);rows.append(.init(motion:m,proof:r))}
        try export(rows,environment:"NCC_EXPANSION_CONTACT_REPORT")
        var calls=0
        let cancelled=run(a,cancel:{calls+=1;return calls>128})
        XCTAssertEqual(cancelled.status,.cancelled);XCTAssertGreaterThan(cancelled.expansionOperations,0)
        #if os(macOS)
        let originalRounding=fegetround();defer{fesetround(originalRounding)}
        var roundCalls=0
        let unsupported=run(a,cancel:{roundCalls+=1;if roundCalls==128 {_ = fesetround(FE_UPWARD)};return false})
        XCTAssertEqual(unsupported.status,.unsupportedRounding)
        _ = fesetround(originalRounding)
        #endif
        let legacy=Motion(name:"old-fixed",kind:.vertexFace,start:[V(0,0,1),.zero,V(1,0,0),V(0,1,0)],end:[V(0,0,1),.zero,V(1,0,0),V(0,1,0)],floor:0,expectedSeparated:true)
        let r=run(legacy);XCTAssertEqual(r.expansionAttempts,0);XCTAssertEqual(r.expansionOperations,0)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(r))as?[String:Any])
        for key in ["expansionAttempts","expansionIntervalsCertified","expansionOperations","maximumExpansionWords","expansionUnavailableReason","expansionCertificates"] {object.removeValue(forKey:key)}
        let old=try JSONDecoder().decode(F.Report.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(old.distanceSeparatedForWholeMotion);XCTAssertEqual(old.expansionIntervalsCertified,0)
    }
    func testActualCompleteQueriesContinueEveryFeatureAfterNearWitness()throws {
        let c:Complete=try load("circle690-fsc111-complete-self")
        XCTAssertEqual(c.previousOuterStep,689)
        let p=try SelfContactGuard.Prepared(vertexCount:c.candidate.count,triangleIndices:c.triangles)
        var rows:[[String:Any]]=[]
        for (name,x) in [("inner",c.inner),("physical-outer",c.previousOuter)] {
            let r=p.guardMotion(previous:vectors(x),candidate:vectors(c.candidate))
            XCTAssertTrue(r.permitsWholeCandidate,r.reason)
            XCTAssertTrue(r.statistics.completedDomainCertificates);XCTAssertTrue(r.statistics.completedAllFeatures)
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueEdgeEdge+r.statistics.uniqueVertexFace)
            XCTAssertGreaterThan(r.statistics.evaluatedFeatures,599)
            rows.append(["path":name,"sourceSHA256":c.sourceSHA256,"status":r.status.rawValue,"safeTime":r.safeTime,
                "reason":r.reason,"completedAllFeatures":r.statistics.completedAllFeatures,
                "completedDomainCertificates":r.statistics.completedDomainCertificates,
                "features":r.statistics.evaluatedFeatures,"uniqueEdgeEdge":r.statistics.uniqueEdgeEdge,
                "uniqueVertexFace":r.statistics.uniqueVertexFace,"euclideanAttempts":r.statistics.euclideanCertificateAttempts,
                "euclideanCertifiedFeatures":r.statistics.euclideanCertifiedFeatures,"euclideanNodes":r.statistics.euclideanCertificateNodes,
                "euclideanAfterPrecisionLimit":r.statistics.euclideanCertifiedAfterPrecisionLimit])
        }
        if let file=ProcessInfo.processInfo.environment["NCC_EXPANSION_COMPLETE_SELF_REPORT"] {
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:file))
        }
    }
}
