import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class CriticalFeatureCertificateTests:XCTestCase {
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Primitive:Decodable {let start:[[Double]],end:[[Double]],startBits:[[String]],endBits:[[String]]}
    struct Complete:Decodable {let sourceSHA256:String,previousOuterStep:Int,previousOuter:[[Double]],inner:[[Double]],candidate:[[Double]],triangles:[UInt32]}
    struct Motion:Codable {let name:String,kind:F.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool}
    struct Row:Codable {
        let motion:Motion,proof:F.Report,runtimeStartBits:[[String]],runtimeEndBits:[[String]]
        init(motion:Motion,proof:F.Report) {
            self.motion=motion;self.proof=proof
            runtimeStartBits=motion.start.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}}
            runtimeEndBits=motion.end.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}}
        }
    }
    struct Export:Codable {let passed:Bool,rows:[Row]}
    func load<T:Decodable>(_ name:String,as:T.Type=T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/CriticalFeatureCertificate"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func vectors(_ a:[[Double]])->[V] {a.map{V($0[0],$0[1],$0[2])}}
    func actual()throws->Motion {
        let p:Primitive=try load("circle690-new123-ee")
        XCTAssertEqual(p.start.map{$0.map{String($0.bitPattern,radix:16)}},p.startBits)
        XCTAssertEqual(p.end.map{$0.map{String($0.bitPattern,radix:16)}},p.endBits)
        return .init(name:"actual-new123-replay690-critical-EE",kind:.edgeEdge,start:vectors(p.start),end:vectors(p.end),floor:0,expectedSeparated:true)
    }
    func run(_ m:Motion,limits:F.Limits = .init(),cancel:()->Bool={false})->F.Report {
        var l=limits;l.recordLeafCertificates=true
        return F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:l,isCancelled:cancel)
    }
    func export(_ rows:[Row],environment:String)throws {
        if let file=ProcessInfo.processInfo.environment[environment] {
            let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys]
            try e.encode(Export(passed:true,rows:rows)).write(to:URL(fileURLWithPath:file))
        }
    }
    // This affine VF realizes the exact cubic a*t^3+b*t^2+c*t+d.
    // n(t)=(t^2,-t,1), never zero. It does not assume point projection
    // lies inside the triangle: strict plane separation suffices.
    func polynomial(_ name:String,_ a:Double,_ b:Double,_ c:Double,_ d:Double,_ expected:Bool)->Motion {
        .init(name:name,kind:.vertexFace,start:[V(0.25,0.75,d),.zero,V(1,0,0),V(0,1,0)],
            end:[V(a+0.25,1-b,c+0.75+d),.zero,V(1,1,0),V(0,1,1)],floor:0,expectedSeparated:expected)
    }
    func testActualNew123CriticalMinimumHasPositiveDistanceWithoutMoreSubdivision()throws {
        let m=try actual();var l=F.Limits();l.maximumDepth=0
        let r=run(m,limits:l)
        XCTAssertTrue(r.distanceSeparatedForWholeMotion)
        XCTAssertEqual(r.processedNodes,1);XCTAssertEqual(r.maximumDepthReached,0)
        XCTAssertEqual(r.criticalIntervalsCertified,1);XCTAssertEqual(r.criticalCertificates.count,1)
        let c=try XCTUnwrap(r.criticalCertificates.first)
        XCTAssertEqual(c.proofKind,.positiveCubicMinimum);XCTAssertEqual(c.projectionScale,3)
        XCTAssertGreaterThan(c.absoluteNormalizedProjectionLowerBound,0)
        XCTAssertGreaterThan(c.distanceLowerBoundMeters,0)
        XCTAssertLessThanOrEqual(r.expansionOperations,1_048_576);XCTAssertLessThanOrEqual(r.maximumExpansionWords,64)
        XCTAssertLessThanOrEqual(r.maximumEstimatedWorkingBytes,1_048_576)
        try export([.init(motion:m,proof:r)],environment:"NCC_CRITICAL_ACTUAL_REPORT")
    }
    func testQuadraticCubicContactsAndPositiveShellAreNotChangedToSignOnly()throws {
        let eps=0x1p-48
        let safe=polynomial("critical-positive-quadratic",0,1,-1,0.25+eps,true)
        let tangent=polynomial("critical-exact-double-root",0,1,-1,0.25,false)
        let crossing=polynomial("critical-two-real-crossings",0,1,-1,0.25-eps,false)
        let cubic=polynomial("critical-monotone-cubic",1,-0.75,0.1875,0.001,true)
        let a=try actual();let shell=Motion(name:"critical-zero-only-positive-shell",kind:a.kind,start:a.start,end:a.end,floor:1e-12,expectedSeparated:false)
        var rows:[Row]=[]
        for m in [safe,tangent,crossing,cubic,shell] {
            let r=run(m);XCTAssertEqual(r.distanceSeparatedForWholeMotion,m.expectedSeparated,m.name)
            if m.floor>0 {XCTAssertEqual(r.criticalAttempts,0);XCTAssertEqual(r.criticalIntervalsCertified,0)}
            rows.append(.init(motion:m,proof:r))
        }
        try export(rows,environment:"NCC_CRITICAL_CONTROLS_REPORT")
    }
    func testCriticalVariantsStillBindActualRoundedCoordinatesAndFullPartition()throws {
        let a=try actual();var motions:[Motion]=[
            .init(name:"critical-EE-time-reverse",kind:.edgeEdge,start:a.end,end:a.start,floor:0,expectedSeparated:true),
            .init(name:"critical-EE-swap-edges",kind:.edgeEdge,start:[a.start[2],a.start[3],a.start[0],a.start[1]],end:[a.end[2],a.end[3],a.end[0],a.end[1]],floor:0,expectedSeparated:true),
            .init(name:"critical-EE-reflect-Z",kind:.edgeEdge,start:a.start.map{V($0.x,$0.y,-$0.z)},end:a.end.map{V($0.x,$0.y,-$0.z)},floor:0,expectedSeparated:true)]
        for scale in [0.125,8.0] {motions.append(.init(name:"critical-EE-SI-\(scale)",kind:.edgeEdge,start:a.start.map{$0*scale},end:a.end.map{$0*scale},floor:0,expectedSeparated:true))}
        var rows:[Row]=[]
        for m in motions {let r=run(m);XCTAssertTrue(r.distanceSeparatedForWholeMotion,m.name);rows.append(.init(motion:m,proof:r))}
        try export(rows,environment:"NCC_CRITICAL_VARIANTS_REPORT")
    }
    func testCriticalOriginalBudgetsCannotReturnClearFromPartialWork()throws {
        let m=try actual();let full=run(m);XCTAssertGreaterThan(full.criticalAttempts,0)
        var l=F.Limits();l.maximumExpansionOperations=full.expansionOperations-1
        let exhausted=run(m,limits:l);XCTAssertEqual(exhausted.status,.budgetExceeded);XCTAssertEqual(exhausted.reason,.expansionOperationBudget)
        XCTAssertEqual(exhausted.criticalIntervalsCertified,0)
        l=F.Limits();l.maximumNodes=0;XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        l=F.Limits();l.maximumEstimatedWorkingBytes=65_536
        XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        var calls=0;let cancelled=run(m,cancel:{calls+=1;return calls>full.expansionOperations/2})
        XCTAssertEqual(cancelled.status,.cancelled);XCTAssertFalse(cancelled.distanceSeparatedForWholeMotion)
    }
    func testCriticalNearestRoundingAndHistoricalReportDecode()throws {
        let m=try actual();var old=try XCTUnwrap(try JSONSerialization.jsonObject(with:JSONEncoder().encode(run(m))) as? [String:Any])
        old.removeValue(forKey:"criticalAttempts");old.removeValue(forKey:"criticalIntervalsCertified");old.removeValue(forKey:"criticalCertificates")
        // Historical reports have their original explicit fixed counts; only
        // additive fields default to zero. This is decode compatibility only.
        let decoded=try JSONDecoder().decode(F.Report.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(decoded.criticalAttempts,0);XCTAssertEqual(decoded.criticalIntervalsCertified,0);XCTAssertTrue(decoded.criticalCertificates.isEmpty)
        #if os(macOS)
        let original=fegetround();defer{fesetround(original)}
        var calls=0;let r=run(m,cancel:{calls+=1;if calls==2048 {_ = fesetround(FE_DOWNWARD)};return false})
        XCTAssertEqual(r.status,.unsupportedRounding)
        #endif
    }
    func testActualNew123WholeSelfChecksEveryInnerAndPhysicalFeature()throws {
        let c:Complete=try load("circle690-new123-complete-self");XCTAssertEqual(c.previousOuterStep,689)
        let witness=try actual(),ids=[60,61,1597,1598]
        XCTAssertEqual(ids.map{vectors(c.previousOuter)[$0]},witness.start)
        XCTAssertEqual(ids.map{vectors(c.candidate)[$0]},witness.end)
        let p=try SelfContactGuard.Prepared(vertexCount:c.candidate.count,triangleIndices:c.triangles)
        var rows:[[String:Any]]=[]
        for(name,x)in[("inner",c.inner),("physical-outer",c.previousOuter)] {
            let r=p.guardMotion(previous:vectors(x),candidate:vectors(c.candidate))
            XCTAssertTrue(r.permitsWholeCandidate,r.reason);XCTAssertTrue(r.statistics.completedAllFeatures);XCTAssertTrue(r.statistics.completedDomainCertificates)
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueEdgeEdge+r.statistics.uniqueVertexFace)
            rows.append(["path":name,"sourceSHA256":c.sourceSHA256,"status":r.status.rawValue,"safeTime":r.safeTime,"reason":r.reason,
                "completedAllFeatures":r.statistics.completedAllFeatures,"completedDomainCertificates":r.statistics.completedDomainCertificates,
                "features":r.statistics.evaluatedFeatures,"uniqueEdgeEdge":r.statistics.uniqueEdgeEdge,"uniqueVertexFace":r.statistics.uniqueVertexFace,
                "witnessVertexIDs":ids,"witnessStartBits":ids.map{vectors(x)[$0]}.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}},
                "witnessEndBits":ids.map{vectors(c.candidate)[$0]}.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}},
                "euclideanAttempts":r.statistics.euclideanCertificateAttempts,"euclideanCertifiedFeatures":r.statistics.euclideanCertifiedFeatures,"euclideanNodes":r.statistics.euclideanCertificateNodes])
        }
        if let file=ProcessInfo.processInfo.environment["NCC_CRITICAL_COMPLETE_SELF_REPORT"] {
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:file))
        }
    }
}
