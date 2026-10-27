import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class AffineFeatureCertificateTests:XCTestCase {
    typealias F=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Primitive:Decodable {let startBits:[[String]],endBits:[[String]]}
    struct Motion:Codable {let name:String,kind:F.Kind,start:[V],end:[V],floor:Double,expectedSeparated:Bool}
    struct Row:Codable {
        let motion:Motion,proof:F.Report,runtimeStartBits:[[String]],runtimeEndBits:[[String]]
        init(_ motion:Motion,_ proof:F.Report) {
            self.motion=motion;self.proof=proof
            runtimeStartBits=motion.start.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}}
            runtimeEndBits=motion.end.map{v in (0..<3).map{String(v[$0].bitPattern,radix:16)}}
        }
    }
    struct Export:Codable {let passed:Bool,rows:[Row]}
    func load(_ name:String)throws->Motion {
        let url=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/AffineFeatureCertificate"))
        let p=try JSONDecoder().decode(Primitive.self,from:Data(contentsOf:url))
        func vectors(_ bits:[[String]])throws->[V] {
            try bits.map{r in V(try XCTUnwrap(UInt64(r[0],radix:16)).asDouble,try XCTUnwrap(UInt64(r[1],radix:16)).asDouble,try XCTUnwrap(UInt64(r[2],radix:16)).asDouble)}
        }
        return .init(name:name,kind:.edgeEdge,start:try vectors(p.startBits),end:try vectors(p.endBits),floor:0,expectedSeparated:name.contains("safe"))
    }
    func run(_ m:Motion,limits:F.Limits = .init(),cancel:()->Bool={false})->F.Report {
        var l=limits;l.recordLeafCertificates=true
        return F.certify(kind:m.kind,start:m.start,end:m.end,minimumSeparation:m.floor,limits:l,isCancelled:cancel)
    }
    func export(_ rows:[Row],environment:String="NCC_AFFINE_REPORT")throws {
        guard let path=ProcessInfo.processInfo.environment[environment] else{return}
        let data=Export(passed:true,rows:rows),e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys]
        try e.encode(data).write(to:URL(fileURLWithPath:path))
        let b=PropertyListEncoder();b.outputFormat = .binary
        try b.encode(data).write(to:URL(fileURLWithPath:path).deletingPathExtension().appendingPathExtension("plist"))
    }
    func testActualSafeNearTangencyNeedsNoExtraTimeOrArithmeticBudget()throws {
        let m=try load("circle1131-attempt13-safe-ee"),r=run(m)
        XCTAssertTrue(r.distanceSeparatedForWholeMotion)
        XCTAssertGreaterThan(r.affineNormalIntervalsCertified,0)
        XCTAssertEqual(r.affineNormalCertificates.count,r.affineNormalIntervalsCertified)
        XCTAssertLessThanOrEqual(r.maximumDepthReached,12);XCTAssertLessThanOrEqual(r.processedNodes,8191)
        XCTAssertLessThanOrEqual(r.maximumExpansionWords,64);XCTAssertLessThanOrEqual(r.expansionOperations,1_048_576)
        XCTAssertLessThanOrEqual(r.maximumEstimatedWorkingBytes,1_048_576)
        XCTAssertEqual(r.fixedIntervalsCertified+r.movingNormalIntervalsCertified+r.expansionIntervalsCertified+r.criticalIntervalsCertified+r.affineNormalIntervalsCertified,r.certifiedIntervals)
        XCTAssertTrue(r.requiresIndependentPrimitiveDomainCertificate)
        var rows=[Row(m,r)]
        for(name,order)in[("swap-edge-sides",[2,3,0,1]),("reverse-first-edge",[1,0,2,3]),("reverse-second-edge",[0,1,3,2])] {
            let v=Motion(name:name,kind:.edgeEdge,start:order.map{m.start[$0]},end:order.map{m.end[$0]},floor:0,expectedSeparated:true),p=run(v)
            XCTAssertTrue(p.distanceSeparatedForWholeMotion,name);rows.append(Row(v,p))
        }
        let reversed=Motion(name:"reverse-time",kind:.edgeEdge,start:m.end,end:m.start,floor:0,expectedSeparated:true)
        let positive=Motion(name:"positive-shell",kind:.edgeEdge,start:m.start,end:m.end,floor:1e-11,expectedSeparated:true)
        for v in [reversed,positive] {let p=run(v);XCTAssertTrue(p.distanceSeparatedForWholeMotion,v.name);rows.append(Row(v,p))}
        try export(rows)
    }
    func testActualE642NearTangencyUsesCommonAmplitudeAndFullExactPartition()throws {
        let m=try load("circle1131-e642-safe-common-ee"),r=run(m)
        XCTAssertTrue(r.distanceSeparatedForWholeMotion)
        XCTAssertGreaterThan(r.affineNormalAttempts,r.movingNormalAttempts)
        // The original proposal independently normalizes BOTH endpoints to
        // maximum component1. A common proposal preserves their amplitude
        // ratio; at least one endpoint of the actual accepted leaf is<1.
        XCTAssertTrue(r.affineNormalCertificates.contains{c in
            let a=max(abs(c.startDirection.x),max(abs(c.startDirection.y),abs(c.startDirection.z)))
            let b=max(abs(c.endDirection.x),max(abs(c.endDirection.y),abs(c.endDirection.z)))
            return min(a,b)<1-1e-12
        })
        XCTAssertLessThanOrEqual(r.processedNodes,8191);XCTAssertLessThanOrEqual(r.maximumDepthReached,12)
        XCTAssertLessThanOrEqual(r.expansionOperations,1_048_576);XCTAssertLessThanOrEqual(r.maximumExpansionWords,64)
        XCTAssertLessThanOrEqual(r.maximumEstimatedWorkingBytes,1_048_576)
        var rows=[Row(m,r)]
        for(name,order)in[("common-swap-sides",[2,3,0,1]),("common-reverse-first",[1,0,2,3]),("common-reverse-second",[0,1,3,2])] {
            let q=Motion(name:name,kind:.edgeEdge,start:order.map{m.start[$0]},end:order.map{m.end[$0]},floor:0,expectedSeparated:true),p=run(q)
            XCTAssertTrue(p.distanceSeparatedForWholeMotion,name);rows.append(Row(q,p))
        }
        for q in [Motion(name:"common-time-reverse",kind:.edgeEdge,start:m.end,end:m.start,floor:0,expectedSeparated:true),
                  Motion(name:"common-positive-shell",kind:.edgeEdge,start:m.start,end:m.end,floor:1e-11,expectedSeparated:true)] {
            let p=run(q);XCTAssertTrue(p.distanceSeparatedForWholeMotion,q.name);rows.append(Row(q,p))
        }
        try export(rows,environment:"NCC_COMMON_AFFINE_REPORT")
    }
    func testCommonFallbackSharesOriginalWorkLimitsCancellationAndTrueCrossingRejection()throws {
        let m=try load("circle1131-e642-safe-common-ee"),full=run(m)
        var l=F.Limits();l.maximumExpansionOperations=full.expansionOperations-1
        let exhausted=run(m,limits:l)
        XCTAssertEqual(exhausted.status,.budgetExceeded);XCTAssertEqual(exhausted.reason,.expansionOperationBudget)
        XCTAssertFalse(exhausted.distanceSeparatedForWholeMotion)
        for k in 0..<3 {l=F.Limits()
            switch k {case 0:l.maximumNodes=1;case 1:l.maximumDepth=0;default:l.maximumEstimatedWorkingBytes=4096}
            XCTAssertFalse(run(m,limits:l).distanceSeparatedForWholeMotion)
        }
        var count=0;_=run(m,cancel:{count+=1;return false});var ordinal=0
        let cancelled=run(m,cancel:{ordinal+=1;return ordinal>=max(1,count-3)})
        XCTAssertEqual(cancelled.status,.cancelled);XCTAssertFalse(cancelled.distanceSeparatedForWholeMotion)
        XCTAssertGreaterThan(cancelled.affineNormalAttempts,0)
        let cross=try load("circle1131-true-crossing-ee")
        XCTAssertFalse(run(cross).distanceSeparatedForWholeMotion)
        XCTAssertFalse(run(.init(name:"common-actual-cross-time-reverse",kind:.edgeEdge,start:cross.end,end:cross.start,floor:0,expectedSeparated:false)).distanceSeparatedForWholeMotion)
    }
    func testTrueCrossingsAndUnmetShellRemainUncertified()throws {
        let old=try load("circle1131-true-crossing-ee");XCTAssertFalse(run(old).distanceSeparatedForWholeMotion)
        let ee=Motion(name:"synthetic-edge-crossing",kind:.edgeEdge,start:[V(-1,0,0),V(1,0,0),V(0,-1,1),V(0,1,1)],end:[V(-1,0,0),V(1,0,0),V(0,-1,-1),V(0,1,-1)],floor:0,expectedSeparated:false)
        let vf=Motion(name:"synthetic-face-crossing",kind:.vertexFace,start:[V(0,0,1),V(-1,-1,0),V(1,-1,0),V(0,1,0)],end:[V(0,0,-1),V(-1,-1,0),V(1,-1,0),V(0,1,0)],floor:0,expectedSeparated:false)
        for m in [ee,vf] {XCTAssertFalse(run(m).distanceSeparatedForWholeMotion)}
        let m=try load("circle1131-attempt13-safe-ee")
        XCTAssertFalse(run(.init(name:"unmet-shell",kind:.edgeEdge,start:m.start,end:m.end,floor:1,expectedSeparated:false)).distanceSeparatedForWholeMotion)
    }
    func testEveryIndependentResourceLimitFailsClosed()throws {
        let m=try load("circle1131-attempt13-safe-ee")
        for k in 0..<4 {var l=F.Limits()
            switch k {case 0:l.maximumNodes=1;case 1:l.maximumDepth=0;case 2:l.maximumExpansionOperations=0;default:l.maximumEstimatedWorkingBytes=4096}
            XCTAssertFalse(run(m,limits:l).distanceSeparatedForWholeMotion,"resource \(k)")
        }
    }
    func testLateCancellationCannotPublishPartialAffineProof()throws {
        let m=try load("circle1131-attempt13-safe-ee");var count=0
        _=run(m,cancel:{count+=1;return false})
        let threshold=max(1,count-3);var ordinal=0
        let r=run(m,cancel:{ordinal+=1;return ordinal>=threshold})
        XCTAssertEqual(r.status,.cancelled);XCTAssertFalse(r.distanceSeparatedForWholeMotion)
        XCTAssertGreaterThan(r.affineNormalAttempts,0)
        XCTAssertEqual(run(m,cancel:{true}).status,.cancelled)
    }
    func testInvalidAndMidCallbackRoundingRemainRejected()throws {
        let m=try load("circle1131-attempt13-safe-ee");var bad=m.start;bad[0].x = .nan
        XCTAssertEqual(F.certify(kind:.edgeEdge,start:bad,end:m.end,minimumSeparation:0).status,.invalid)
        #if os(macOS)
        let original=fegetround();defer{fesetround(original)}
        var n=0;let r=run(m,cancel:{n+=1;if n==2048 {_ = fesetround(FE_UPWARD)};return false})
        XCTAssertEqual(r.status,.unsupportedRounding);XCTAssertFalse(r.distanceSeparatedForWholeMotion)
        #endif
    }
    func testDomainCollapseAndHistoricalDecodeDoNotGainPermission()throws {
        let p=try SelfContactGuard.Prepared(vertexCount:3,triangleIndices:[0,1,2])
        let r=p.guardMotion(previous:[V(0,0,0),V(1,0,0),V(0,1,0)],candidate:[V(0,0,0),V(-1,0,0),V(0,1,0)])
        XCTAssertFalse(r.permitsWholeCandidate);XCTAssertEqual(r.witness?.kind,.triangleDomain)
        let m=try load("circle1131-attempt13-safe-ee")
        var old=try XCTUnwrap(try JSONSerialization.jsonObject(with:JSONEncoder().encode(run(m)))as?[String:Any])
        old.removeValue(forKey:"affineNormalAttempts");old.removeValue(forKey:"affineNormalIntervalsCertified");old.removeValue(forKey:"affineNormalCertificates")
        let decoded=try JSONDecoder().decode(F.Report.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(decoded.affineNormalAttempts,0);XCTAssertEqual(decoded.affineNormalIntervalsCertified,0);XCTAssertTrue(decoded.affineNormalCertificates.isEmpty)
    }
}
private extension UInt64 {var asDouble:Double {Double(bitPattern:self)}}
