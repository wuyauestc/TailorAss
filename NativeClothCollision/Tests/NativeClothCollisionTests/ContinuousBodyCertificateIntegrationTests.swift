import XCTest
import Foundation
#if os(macOS)
import Darwin
#endif
@testable import NativeClothCollision

final class ContinuousBodyCertificateIntegrationTests:XCTestCase {
    typealias B=ContinuousBodyContact
    typealias C=NativeClothCollision
    typealias S=FeatureSeparationCertificate
    typealias V=SIMD3<Double>
    struct Raw:Decodable {
        let originalFilename:String,start12:[Double],end12:[Double]
        let minimumSeparation:Double,distanceTolerance:Double,maximumIterations:Int64,maximumTime:Double
    }
    struct Fixture:Decodable {let rows:[Raw]}
    struct ExtraRaw:Decodable {
        let originalFilename:String,kind:S.Kind,start12:[Double],end12:[Double]
        let minimumSeparation:Double,distanceTolerance:Double,maximumIterations:Int64,maximumTime:Double
    }
    struct ExtraFixture:Decodable {let rows:[ExtraRaw]}
    struct Case {
        let raw:Raw,body:[V],previous:[V],candidate:[V],normal:V
    }
    struct ExportRow:Codable {
        let name:String,body:[V],previous:[V],candidate:[V],separatingDirection:V,minimumSeparation:Double
        let status:String,safeTime:Double,nativeQueries:Int,certificateAttempts:Int,certifiedFeatures:Int,certificateNodes:Int
        let certifiedAfterPrecisionLimit:Int
        let uniqueFeatures:Int,evaluatedFeatures:Int,completedAllFeatures:Bool
    }
    struct Export:Codable {let passed:Bool,rows:[ExportRow]}
    let indices:[UInt32]=[0,1,2]
    func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    func cross(_ a:V,_ b:V)->V {V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)}
    func unit(_ p:V)->V {p/sqrt(dot(p,p))}
    func points(_ flat:[Double])->[V] {stride(from:0,to:flat.count,by:3).map{V(flat[$0],flat[$0+1],flat[$0+2])}}
    func cases()throws->[Case] {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"actual-circle247-vf",withExtension:"json",subdirectory:"Fixtures/FeatureSeparationCertificate"))
        return try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)).rows.map { raw in
            let start=points(raw.start12),end=points(raw.end12),body=Array(start[1...3])
            var n=unit(cross(body[1]-body[0],body[2]-body[0]))
            if dot(n,start[0]-body[0])<0 {n = -n}
            let u=unit(body[1]-body[0]),v=cross(n,u)
            // The other two particles are lifted along the positive normal.
            // The full moving cloth triangle stays on the same strictly
            // separated plane side as the actual point64 motion.
            let offsets=[V.zero,u*0.003+n*0.01,v*0.003+n*0.01]
            return Case(raw:raw,body:body,previous:offsets.map{start[0]+$0},candidate:offsets.map{end[0]+$0},normal:n)
        }
    }
    func options(_ c:Case,_ limits:B.Limits=B.Limits())->B.Options {
        .init(minimumSeparation:c.raw.minimumSeparation,distanceTolerance:c.raw.distanceTolerance,
              maximumIterationsPerFeature:c.raw.maximumIterations,safetyFactor:0.9,limits:limits)
    }
    func export(_ c:Case,_ r:B.Report)->ExportRow {
        let s=r.statistics
        return .init(name:c.raw.originalFilename,body:c.body,previous:c.previous,candidate:c.candidate,separatingDirection:c.normal,
          minimumSeparation:c.raw.minimumSeparation,status:r.status.rawValue,safeTime:r.safeTime,nativeQueries:s.nativeQueries,
          certificateAttempts:s.euclideanCertificateAttempts,certifiedFeatures:s.euclideanCertifiedFeatures,certificateNodes:s.euclideanCertificateNodes,
          certifiedAfterPrecisionLimit:s.euclideanCertifiedAfterPrecisionLimit,
          uniqueFeatures:s.uniqueClothVertexBodyFace+s.uniqueBodyVertexClothFace+s.uniqueEdgeEdge,evaluatedFeatures:s.evaluatedFeatures,completedAllFeatures:s.completedAllFeatures)
    }
    func writeExport(_ rows:[ExportRow])throws {
        guard let path=ProcessInfo.processInfo.environment["NCC_BODY_CERTIFICATE_REPORT"] else{return}
        let url=URL(fileURLWithPath:path)
        var all:[ExportRow]=[]
        if FileManager.default.fileExists(atPath:path) {all=try JSONDecoder().decode(Export.self,from:Data(contentsOf:url)).rows}
        let names=Set(rows.map(\.name));all=all.filter{!names.contains($0.name)}+rows
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(Export(passed:true,rows:all.sorted{$0.name<$1.name})).write(to:url,options:.atomic)
    }
    func testActualConservativeVFHitsBecomeCompleteClearQueriesWithoutChangingRawKernel()throws {
        var rows:[ExportRow]=[]
        for c in try cases() {
            let native=C.vertexFace(start:c.raw.start12,end:c.raw.end12,
                options:.init(minimumSeparation:c.raw.minimumSeparation,maximumTime:c.raw.maximumTime,
                              distanceTolerance:c.raw.distanceTolerance,maximumIterations:c.raw.maximumIterations))
            XCTAssertEqual(native.status,.conservativeHit);XCTAssertEqual(native.detail,.none)
            let prepared=try B.Prepared(bodyPositions:c.body,triangleIndices:indices)
            let r=prepared.guardMotion(previous:c.previous,candidate:c.candidate,clothTriangleIndices:indices,options:options(c))
            XCTAssertEqual(r.status,.clear,r.reason);XCTAssertTrue(r.permitsWholeCandidate)
            XCTAssertEqual(r.safeTime,1);XCTAssertNil(r.conservativeTimeOfImpact)
            XCTAssertEqual(r.statistics.uniqueClothVertexBodyFace,3);XCTAssertEqual(r.statistics.uniqueBodyVertexClothFace,3)
            XCTAssertEqual(r.statistics.uniqueEdgeEdge,9);XCTAssertEqual(r.statistics.evaluatedFeatures,15)
            XCTAssertEqual(r.statistics.nativeQueries,15);XCTAssertTrue(r.statistics.completedAllFeatures)
            XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertificateAttempts,1)
            XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertifiedFeatures,1)
            XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertificateNodes,r.statistics.euclideanCertifiedFeatures)
            XCTAssertEqual(r.minimumSeparation,0.0005)
            XCTAssertEqual(prepared.bodyPositions,c.body);XCTAssertEqual(prepared.bodyTriangleIndices,indices)
            XCTAssertEqual(C.vertexFace(start:c.raw.start12,end:c.raw.end12,
                options:.init(minimumSeparation:c.raw.minimumSeparation,maximumTime:c.raw.maximumTime,
                              distanceTolerance:c.raw.distanceTolerance,maximumIterations:c.raw.maximumIterations)).status,.conservativeHit)
            rows.append(export(c,r))
        }
        try writeExport(rows)
    }
    func testActualPrecisionLimitedEEBecomesClearOnlyWithCompleteDistanceProof()throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"circle118-vf-shirt85-ee",withExtension:"json",subdirectory:"Fixtures/FeatureSeparationCertificate"))
        let row=try XCTUnwrap(JSONDecoder().decode(ExtraFixture.self,from:Data(contentsOf:url)).rows.first{$0.kind == .edgeEdge})
        let start=points(row.start12),end=points(row.end12)
        let native=C.edgeEdge(start:row.start12,end:row.end12,options:.init(minimumSeparation:row.minimumSeparation,
            maximumTime:row.maximumTime,distanceTolerance:row.distanceTolerance,maximumIterations:row.maximumIterations))
        XCTAssertEqual(native.status,.uncertain);XCTAssertEqual(native.detail,.precisionOrBudget)
        var limits=S.Limits();limits.recordLeafCertificates=true
        let proof=S.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:row.minimumSeparation,limits:limits)
        XCTAssertEqual(proof.status,.separated);XCTAssertEqual(proof.certifiedIntervals,1)
        let axis=try XCTUnwrap(proof.leafCertificates.first?.direction),n=unit(axis)
        // Keep both exact original EE segments. The added third body/cloth
        // vertices extend away from their already certified support plane.
        let body=[start[2],start[3],(start[2]+start[3])*0.5-n*0.01]
        let previous=[start[0],start[1],(start[0]+start[1])*0.5+n*0.01]
        let candidate=[end[0],end[1],(end[0]+end[1])*0.5+n*0.01]
        let raw=Raw(originalFilename:row.originalFilename,start12:row.start12,end12:row.end12,
            minimumSeparation:row.minimumSeparation,distanceTolerance:row.distanceTolerance,
            maximumIterations:row.maximumIterations,maximumTime:row.maximumTime)
        let c=Case(raw:raw,body:body,previous:previous,candidate:candidate,normal:axis)
        let prepared=try B.Prepared(bodyPositions:body,triangleIndices:indices)
        let r=prepared.guardMotion(previous:previous,candidate:candidate,clothTriangleIndices:indices,options:options(c))
        XCTAssertEqual(r.status,.clear,r.reason);XCTAssertEqual(r.safeTime,1);XCTAssertTrue(r.statistics.completedAllFeatures)
        XCTAssertEqual(r.statistics.evaluatedFeatures,15);XCTAssertEqual(r.statistics.nativeQueries,15)
        XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertifiedAfterPrecisionLimit,1)
        XCTAssertGreaterThanOrEqual(r.statistics.euclideanCertifiedFeatures,r.statistics.euclideanCertifiedAfterPrecisionLimit)
        XCTAssertEqual(r.minimumSeparation,0.0005);XCTAssertEqual(prepared.bodyPositions,body)
        try writeExport([export(c,r)])
    }
    func testActualMidPathCrossingRemainsLimited()throws {
        let c=try XCTUnwrap(cases().first),prepared=try B.Prepared(bodyPositions:c.body,triangleIndices:indices)
        let crossed=c.previous.map{$0-c.normal*0.004}
        let r=prepared.guardMotion(previous:c.previous,candidate:crossed,clothTriangleIndices:indices,options:options(c))
        XCTAssertEqual(r.status,.limited,r.reason);XCTAssertFalse(r.permitsWholeCandidate)
        XCTAssertGreaterThan(r.safeTime,0);XCTAssertLessThan(r.safeTime,try XCTUnwrap(r.conservativeTimeOfImpact))
        XCTAssertTrue(r.statistics.completedAllFeatures)
    }
    func testMovingClothFaceCollapseCannotBeOverriddenByDistanceProof()throws {
        let body=[V(0.8,0.8,0),V(0.9,0.8,0),V(0.8,0.9,0)]
        let previous=[V.zero,V(1,0,0),V(0,1,0)],candidate=[V.zero,V(-1,0,0),V(0,-1,0)]
        let start=[body[0]]+previous,end=[body[0]]+candidate
        let distance=S.certify(kind:.vertexFace,start:start,end:end,minimumSeparation:0.0005)
        XCTAssertEqual(distance.status,.separated,"Distance is clear despite a collapsed triangle domain")
        let native=C.vertexFace(start:start.flatMap{[$0.x,$0.y,$0.z]},end:end.flatMap{[$0.x,$0.y,$0.z]},
                                options:.init(minimumSeparation:0.0005))
        XCTAssertEqual(native.status,.uncertain);XCTAssertEqual(native.detail,.uncertainGeometry)
        let p=try B.Prepared(bodyPositions:body,triangleIndices:indices)
        let r=p.guardMotion(previous:previous,candidate:candidate,clothTriangleIndices:indices,options:.init(minimumSeparation:0.0005))
        XCTAssertEqual(r.status,.uncertain,r.reason);XCTAssertEqual(r.witness?.nativeDetail,.uncertainGeometry)
        XCTAssertFalse(r.statistics.completedAllFeatures);XCTAssertFalse(r.permitsWholeCandidate)
        XCTAssertEqual(r.safeTime,0)
    }
    func testZeroAndSmallWholeQueryNodeBudgetsNeverResetPerFeature()throws {
        let c=try XCTUnwrap(cases().first),p=try B.Prepared(bodyPositions:c.body,triangleIndices:indices)
        var limits=B.Limits();limits.maximumEuclideanCertificateNodes=0
        let zero=p.guardMotion(previous:c.previous,candidate:c.candidate,clothTriangleIndices:indices,options:options(c,limits))
        XCTAssertEqual(zero.status,.budgetExceeded,zero.reason);XCTAssertEqual(zero.statistics.euclideanCertificateNodes,0)
        XCTAssertFalse(zero.statistics.completedAllFeatures);XCTAssertEqual(zero.safeTime,0)
        let previous=c.previous+c.previous,candidate=c.candidate+c.candidate,triangles:[UInt32]=[0,1,2,3,4,5]
        let complete=p.guardMotion(previous:previous,candidate:candidate,clothTriangleIndices:triangles,options:options(c))
        XCTAssertEqual(complete.status,.clear,complete.reason)
        XCTAssertGreaterThanOrEqual(complete.statistics.euclideanCertifiedFeatures,2)
        limits=B.Limits();limits.maximumEuclideanCertificateNodes=1
        let small=p.guardMotion(previous:previous,candidate:candidate,clothTriangleIndices:triangles,options:options(c,limits))
        XCTAssertEqual(small.status,.budgetExceeded,small.reason);XCTAssertLessThanOrEqual(small.statistics.euclideanCertificateNodes,1)
        XCTAssertGreaterThanOrEqual(small.statistics.euclideanCertificateAttempts,1)
        XCTAssertFalse(small.statistics.completedAllFeatures);XCTAssertFalse(small.permitsWholeCandidate);XCTAssertEqual(small.safeTime,0)
    }
    func testCancellationAfterCertificateAttemptPublishesNoCompletedQuery()throws {
        let c=try XCTUnwrap(cases().first),p=try B.Prepared(bodyPositions:c.body,triangleIndices:indices)
        var found:B.Report?
        for threshold in 1...100 {
            var calls=0
            let r=p.guardMotion(previous:c.previous,candidate:c.candidate,clothTriangleIndices:indices,options:options(c),
                isCancelled:{calls+=1;return calls>=threshold})
            if r.status == .cancelled && r.statistics.euclideanCertificateAttempts>0 {found=r;break}
        }
        let r=try XCTUnwrap(found,"No deterministic cancellation inside certificate phase was exercised")
        XCTAssertFalse(r.statistics.completedAllFeatures);XCTAssertFalse(r.permitsWholeCandidate);XCTAssertEqual(r.safeTime,0)
        XCTAssertEqual(p.bodyPositions,c.body)
        XCTAssertTrue(p.guardMotion(previous:c.previous,candidate:c.candidate,clothTriangleIndices:indices,options:options(c)).permitsWholeCandidate)
    }
    func testNonNearestWithNoCandidatesIsStillRejectedReadOnly()throws {
        #if os(macOS)
        let body=[V(-1,-1,0),V(1,-1,0),V(0,1,0)],p=try B.Prepared(bodyPositions:body,triangleIndices:indices)
        let far=[V(10,10,10),V(11,10,10),V(10,11,10)],saved=fegetround()
        defer{_ = fesetround(saved)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        let r=p.guardMotion(previous:far,candidate:far,clothTriangleIndices:indices,options:.init(minimumSeparation:0.0005))
        XCTAssertEqual(r.status,.uncertain);XCTAssertEqual(r.statistics.trianglePairs,0)
        XCTAssertEqual(r.statistics.nativeQueries,0);XCTAssertEqual(r.statistics.euclideanCertificateAttempts,0)
        XCTAssertFalse(r.statistics.completedAllFeatures);XCTAssertFalse(r.permitsWholeCandidate)
        XCTAssertEqual(r.safeTime,0);XCTAssertEqual(fegetround(),FE_UPWARD)
        #else
        XCTAssertTrue(FloatingPointEnvironment.isNearestRounding)
        #endif
    }
}

