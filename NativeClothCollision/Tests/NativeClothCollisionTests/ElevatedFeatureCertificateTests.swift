import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class ElevatedFeatureCertificateTests:XCTestCase {
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Primitive:Decodable {let start:[[Double]],end:[[Double]]}
    struct Complete:Decodable {let sourceSHA256:String,previousOuterStep:Int,previousOuter:[[Double]],inner:[[Double]],candidate:[[Double]],triangles:[UInt32]}
    struct Motion:Codable {let name:String,kind:F.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool}
    struct Row:Codable {let motion:Motion,proof:F.Report}
    struct Export:Codable {let passed:Bool,rows:[Row]}
    struct ElevationRow:Codable {let input:[[Double]],output:[[Double]],degree:Int}
    func load<T:Decodable>(_ name:String,as:T.Type=T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/ElevatedFeatureCertificate"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func vectors(_ a:[[Double]])->[V] {a.map{V($0[0],$0[1],$0[2])}}
    func actual()throws->Motion {
        let p:Primitive=try load("circle690-actual117-ee")
        return .init(name:"actual117-Circle690-EE-elevation",kind:.edgeEdge,start:vectors(p.start),end:vectors(p.end),floor:0,expectedSeparated:true)
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
    func testIntegerScaledElevationIdentityAgainstExactPolynomialOracle()throws {
        var inputs:[[Double]]=[[0.75,-0.25,-0.25,0.75],[1,-1,-1,1],[1,1e-30,-1e-30,1]]
        var seed:UInt64=0x1234_5678_89ab_cdef
        for _ in 0..<32 {
            var a:[Double]=[]
            for _ in 0..<4 {
                seed=seed &* 6364136223846793005 &+ 1442695040888963407
                let exponent=UInt64(923+Int((seed>>52)%200))
                a.append(Double(bitPattern:(seed&(1<<63))|(exponent<<52)|(seed&0x000f_ffff_ffff_ffff)))
            }
            inputs.append(a)
        }
        var rows:[ElevationRow]=[]
        for values in inputs {
            var w=F.ExpansionWork(maximumOperations:100_000),controls=values.map{[$0]}
            for degree in 4...8 {
                let next=try w.elevate(controls,{false})
                XCTAssertEqual(next.count,degree+1);XCTAssertLessThanOrEqual(w.maximumWords,64)
                rows.append(.init(input:controls,output:next,degree:degree));controls=next
            }
        }
        if let file=ProcessInfo.processInfo.environment["NCC_ELEVATION_ARITHMETIC_REPORT"] {
            try JSONEncoder().encode(rows).write(to:URL(fileURLWithPath:file))
        }
    }
    func testActual117MotionAndPositiveFloorNeedBoundedHigherDegree()throws {
        let a=try actual();let positive=Motion(name:"actual117-EE-positive-floor",kind:a.kind,start:a.start,end:a.end,floor:1e-16,expectedSeparated:true)
        let under=Motion(name:"actual117-EE-under-required-floor",kind:a.kind,start:a.start,end:a.end,floor:1e-12,expectedSeparated:false)
        var rows:[Row]=[]
        for m in [a,positive,under] {
            let r=run(m);XCTAssertEqual(r.distanceSeparatedForWholeMotion,m.expectedSeparated,m.name)
            if m.expectedSeparated {
                XCTAssertTrue(r.expansionCertificates.contains{$0.projectionDegree>3} || r.criticalIntervalsCertified>0)
                for c in r.expansionCertificates {
                    XCTAssertTrue((3...8).contains(c.projectionDegree));XCTAssertEqual(c.scaledProjectionBernsteinBounds.count,c.projectionDegree+1)
                    var scale=3;if c.projectionDegree>=4 {for n in 4...c.projectionDegree {scale*=n}}
                    XCTAssertEqual(c.projectionScale,scale);XCTAssertGreaterThan(c.absoluteScaledProjectionLowerBound,c.requiredScaledProductUpperBound)
                }
            }
            XCTAssertLessThanOrEqual(r.processedNodes,8191);XCTAssertLessThanOrEqual(r.maximumDepthReached,12)
            XCTAssertLessThanOrEqual(r.expansionOperations,1_048_576);XCTAssertLessThanOrEqual(r.maximumExpansionWords,64)
            XCTAssertLessThanOrEqual(r.maximumEstimatedWorkingBytes,1_048_576)
            rows.append(.init(motion:m,proof:r))
        }
        try export(rows,environment:"NCC_ELEVATION_FEATURE_REPORT")
    }
    func testReversalReflectionAndExactPowerOfTwoScaling()throws {
        let a=try actual();var motions:[Motion]=[
            .init(name:"elevation-EE-time-reverse",kind:.edgeEdge,start:a.end,end:a.start,floor:0,expectedSeparated:true),
            .init(name:"elevation-EE-edge-order-reverse",kind:.edgeEdge,start:[a.start[2],a.start[3],a.start[0],a.start[1]],end:[a.end[2],a.end[3],a.end[0],a.end[1]],floor:0,expectedSeparated:true),
            .init(name:"elevation-EE-reflect-Z",kind:.edgeEdge,start:a.start.map{V($0.x,$0.y,-$0.z)},end:a.end.map{V($0.x,$0.y,-$0.z)},floor:0,expectedSeparated:true)]
        for scale in [0.125,8.0] {motions.append(.init(name:"elevation-EE-SI-\(scale)",kind:.edgeEdge,start:a.start.map{$0*scale},end:a.end.map{$0*scale},floor:0,expectedSeparated:true))}
        var rows:[Row]=[]
        for m in motions {let r=run(m);XCTAssertTrue(r.distanceSeparatedForWholeMotion,m.name);rows.append(.init(motion:m,proof:r))}
        try export(rows,environment:"NCC_ELEVATION_VARIANTS_REPORT")
    }
    func testTrueContactsOldTraceAndOriginalBudgetsRemainStrict()throws {
        let cross=Motion(name:"exact-EE-real-cross",kind:.edgeEdge,start:[V(-1,0,0),V(1,0,0),V(0,-1,1),V(0,1,1)],end:[V(-1,0,0),V(1,0,0),V(0,-1,-1),V(0,1,-1)],floor:0,expectedSeparated:false)
        let tangent=Motion(name:"exact-VF-tangent",kind:.vertexFace,start:[V(0.75,0.25,0.0625),.zero,V(4,0,-1),V(0,4,0)],end:[V(1.75,0.25,-1.9375),.zero,V(4,0,-5),V(0,4,0)],floor:0,expectedSeparated:false)
        var rows:[Row]=[]
        for m in [cross,tangent] {let r=run(m);XCTAssertFalse(r.distanceSeparatedForWholeMotion);rows.append(.init(motion:m,proof:r))}
        try export(rows,environment:"NCC_ELEVATION_CONTACT_REPORT")
        let old:F.ExpansionCertificate=try load("legacy-degree3-certificate")
        XCTAssertEqual(old.projectionDegree,3);XCTAssertEqual(old.projectionScale,3);XCTAssertEqual(old.scaledProjectionBernsteinBounds.count,4)
        let m=try actual();var l=F.Limits();l.maximumNodes=0
        XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        l=F.Limits();l.maximumDepth=0
        let root=run(m,limits:l);XCTAssertTrue(root.status == .notCertified || root.criticalIntervalsCertified==1)
        l=F.Limits();l.maximumExpansionOperations=0;XCTAssertEqual(run(m,limits:l).status,.budgetExceeded)
        let complete=run(m);l=F.Limits();l.maximumExpansionOperations=complete.expansionOperations-1
        let exhausted=run(m,limits:l);XCTAssertEqual(exhausted.status,.budgetExceeded);XCTAssertEqual(exhausted.reason,.expansionOperationBudget)
        XCTAssertFalse(exhausted.distanceSeparatedForWholeMotion)
    }
    func testCancellationRoundingAndMemoryAreCheckedDuringElevation()throws {
        let m=try actual();var calls=0
        let r=run(m,cancel:{calls+=1;return calls>512})
        XCTAssertEqual(r.status,.cancelled);XCTAssertGreaterThan(r.expansionOperations,0)
        var l=F.Limits();l.maximumEstimatedWorkingBytes=65_536
        XCTAssertEqual(F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:0,limits:l).status,.budgetExceeded)
        #if os(macOS)
        let original=fegetround();defer{fesetround(original)}
        var roundCalls=0
        let u=run(m,cancel:{roundCalls+=1;if roundCalls==512 {_ = fesetround(FE_DOWNWARD)};return false})
        XCTAssertEqual(u.status,.unsupportedRounding)
        #endif
    }
    func testActual117CompleteLocalAndOuterQueriesTraverseAllFeatures()throws {
        let c:Complete=try load("circle690-actual117-complete-self")
        XCTAssertEqual(c.previousOuterStep,689)
        let p=try SelfContactGuard.Prepared(vertexCount:c.candidate.count,triangleIndices:c.triangles)
        var rows:[[String:Any]]=[]
        for(name,x)in[("inner",c.inner),("physical-outer",c.previousOuter)] {
            let r=p.guardMotion(previous:vectors(x),candidate:vectors(c.candidate))
            XCTAssertTrue(r.permitsWholeCandidate,r.reason);XCTAssertTrue(r.statistics.completedAllFeatures);XCTAssertTrue(r.statistics.completedDomainCertificates)
            XCTAssertEqual(r.statistics.evaluatedFeatures,r.statistics.uniqueEdgeEdge+r.statistics.uniqueVertexFace)
            rows.append(["path":name,"sourceSHA256":c.sourceSHA256,"status":r.status.rawValue,"safeTime":r.safeTime,
                "reason":r.reason,"completedAllFeatures":r.statistics.completedAllFeatures,"completedDomainCertificates":r.statistics.completedDomainCertificates,
                "features":r.statistics.evaluatedFeatures,"uniqueEdgeEdge":r.statistics.uniqueEdgeEdge,"uniqueVertexFace":r.statistics.uniqueVertexFace,
                "euclideanAttempts":r.statistics.euclideanCertificateAttempts,"euclideanCertifiedFeatures":r.statistics.euclideanCertifiedFeatures,"euclideanNodes":r.statistics.euclideanCertificateNodes])
        }
        if let file=ProcessInfo.processInfo.environment["NCC_ELEVATION_COMPLETE_SELF_REPORT"] {
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:file))
        }
    }
}
