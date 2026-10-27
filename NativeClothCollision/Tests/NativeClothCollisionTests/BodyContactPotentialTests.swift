import XCTest
import Foundation
import Darwin
@testable import NativeClothCollision

final class BodyContactPotentialTests:XCTestCase {
    typealias P=BodyContactPotential
    typealias V=SIMD3<Double>
    struct Case:Decodable {
        let name:String,clothRest:[[Double]],clothCurrent:[[Double]],bodyPositions:[[Double]]
        let clothTriangles:[UInt32],bodyTriangles:[UInt32]
        let kappa:Double,dmin:Double,h:Double
        var rest:[V]{clothRest.map{V($0[0],$0[1],$0[2])}}
        var current:[V]{clothCurrent.map{V($0[0],$0[1],$0[2])}}
        var body:[V]{bodyPositions.map{V($0[0],$0[1],$0[2])}}
        func parameters(_ mode:P.HessianMode = .exact)->P.Parameters{.init(stiffnessPascals:kappa,minimumDistanceMeters:dmin,activationGapMeters:h,hessianMode:mode)}
    }
    struct Cases:Decodable {let cases:[Case]}
    struct Golden:Decodable {
        let name:String,energy:Double,clothGradient:[Double],clothHessian:[[Double]],clothHessianPSD:[[Double]]
        let stencilCount:Int,negativeStencilCount:Int,fullVertexCount:Int,referenceVertexAreas:[Double],referenceEdgeAreas:[Double]
    }
    struct Goldens:Decodable {let cases:[Golden]}
    struct Actual:Decodable {let `case`:Golden}
    struct MatrixKey:Hashable {let i:Int,j:Int}
    final class Count:@unchecked Sendable {
        private let lock=NSLock();private var count=0
        func increment()->Int{lock.lock();defer{lock.unlock()};count+=1;return count}
    }
    func load<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let path=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/IPCBodyContact"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:path))
    }
    func corrected<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/IPCOrientationIdentity"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func prepared(_ c:Case,_ limits:P.Limits = .init())throws->P.Prepared {
        try P.Prepared(clothRestPositions:c.rest,clothTriangleIndices:c.clothTriangles,
            body:.init(bodyPositions:c.body,triangleIndices:c.bodyTriangles),limits:limits)
    }
    func sparse(_ e:P.Evaluation)->[MatrixKey:Double] {
        var out:[MatrixKey:Double]=[:]
        for b in e.localBlocks {
            let n=b.clothVertexIDs.count*3
            for i in 0..<n {for j in 0..<n {
                out[.init(i:Int(b.clothVertexIDs[i/3])*3+i%3,j:Int(b.clothVertexIDs[j/3])*3+j%3),default:0]+=b.clothHessianRowMajorNewtonsPerMeter[i*n+j]
            }}
        }
        return out
    }
    func expected(_ entries:[[Double]])->[MatrixKey:Double] {Dictionary(uniqueKeysWithValues:entries.map{(.init(i:Int($0[0]),j:Int($0[1])),$0[2])})}
    func compare(_ e:P.Evaluation,_ g:Golden,projected:Bool=false,actual:Bool=false,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(e.energyJoules,g.energy,accuracy:1e-15,file:file,line:line)
        let flat=e.clothGradientNewtons.flatMap{[$0.x,$0.y,$0.z]}
        XCTAssertEqual(flat.count,g.clothGradient.count,file:file,line:line)
        XCTAssertLessThanOrEqual(zip(flat,g.clothGradient).map{abs($0-$1)}.max() ?? 0,1e-10,file:file,line:line)
        let a=sparse(e),b=expected(projected ? g.clothHessianPSD:g.clothHessian),keys=Set(a.keys).union(b.keys)
        let error=keys.map{abs(a[$0,default:0]-b[$0,default:0])}.max() ?? 0
        XCTAssertLessThanOrEqual(error,actual ? 1e-6:1e-6,file:file,line:line)
        XCTAssertEqual(e.localBlocks.count,g.stencilCount,file:file,line:line)
        XCTAssertEqual(e.statistics.negativeStencils,g.negativeStencilCount,file:file,line:line)
        XCTAssertTrue(g.referenceVertexAreas.allSatisfy{$0>0},"Fixed body keeps its positive rest areas",file:file,line:line)
        XCTAssertTrue(g.referenceEdgeAreas.allSatisfy{$0>0},file:file,line:line)
    }
    func testCorrectedFullBuilderCanonical18CasesRawAndWholeLocalPSD()throws {
        let cases=try load("body-cases",as:Cases.self).cases,goldens=try corrected("body-canonical-goldens",as:Goldens.self).cases
        XCTAssertEqual(cases.count,18)
        for c in cases {
            let g=try XCTUnwrap(goldens.first{$0.name==c.name}),p=try prepared(c)
            for mode in [P.HessianMode.exact,.clampPositiveSemidefinite] {
                let e=try p.evaluate(clothPositions:c.current,parameters:c.parameters(mode))
                compare(e,g,projected:mode != .exact)
                XCTAssertEqual(p.body.bodyPositions,c.body);XCTAssertEqual(p.clothRestPositions,c.rest)
                XCTAssertLessThanOrEqual(e.statistics.chargedStagedBlockBytes,p.limits.maximumStagedBlockBytes)
            }
        }
    }
    func testCompleteActual15380VertexSourceAgainstCorrectedSparseGoldens()throws {
        let c=try load("actual-case",as:Case.self),g=try corrected("actual-body-golden",as:Actual.self).case,p=try prepared(c)
        XCTAssertEqual(c.rest.count+c.body.count,15_380)
        XCTAssertEqual(c.clothTriangles.count/3+c.bodyTriangles.count/3,30_228)
        for mode in [P.HessianMode.exact,.clampPositiveSemidefinite] {
            let e=try p.evaluate(clothPositions:c.current,parameters:c.parameters(mode))
            compare(e,g,projected:mode != .exact,actual:true)
            XCTAssertEqual(e.statistics.stencils,g.stencilCount);XCTAssertEqual(e.statistics.negativeStencils,g.negativeStencilCount)
            XCTAssertEqual(e.statistics.completeBVHFacePairs,3829)
            XCTAssertEqual(e.statistics.bodyVertexClothFaceStencils,97)
            let bvf=e.localBlocks.filter(\.isBodyVertexClothFace)
            XCTAssertEqual(bvf.count,97)
            XCTAssertGreaterThan(bvf.flatMap(\.clothGradientNewtons).map{$0.x*$0.x+$0.y*$0.y+$0.z*$0.z}.reduce(0,+),0)
            XCTAssertLessThan(e.statistics.chargedStagedBlockBytes,2*1_024*1_024)
            // This is the recorded exterior469 of a REJECTED cloth state;
            // contact energy does not certify source strain/self/garment fit.
            XCTAssertEqual(e.clothGradientNewtons.count,2000)
        }
    }
    func testAllSignedFeaturesAndEEOnlyPrimaryPathRemainPresent()throws {
        let cases=try load("body-cases",as:Cases.self).cases
        let c=try XCTUnwrap(cases.first{$0.name=="ee_first"}),e=try prepared(c).evaluate(clothPositions:c.current,parameters:c.parameters())
        XCTAssertEqual(e.statistics.clothVertexBodyFaceStencils,0)
        XCTAssertGreaterThan(e.statistics.edgeEdgeStencils,0)
        let negative=try XCTUnwrap(cases.first{$0.name=="concave_negative"})
        let n=try prepared(negative).evaluate(clothPositions:negative.current,parameters:negative.parameters())
        XCTAssertTrue(n.localBlocks.contains{$0.signedRestAreaSquareMeters<0})
        XCTAssertTrue(n.localBlocks.allSatisfy{$0.stencilVertexIDs.count>=2 && $0.clothVertexIDs.allSatisfy{Int($0)<negative.rest.count}})
    }
    func testProjectedModesPreserveEnergyGradientAndClothOnlyHv()throws {
        let c=try XCTUnwrap(load("body-cases",as:Cases.self).cases.first{$0.name=="concave_negative"}),p=try prepared(c)
        let raw=try p.evaluate(clothPositions:c.current,parameters:c.parameters()),d=c.current.indices.map{V(sin(Double($0)+0.3),cos(Double($0)+0.7),0.4)}
        for mode in [P.HessianMode.clampPositiveSemidefinite,.absolutePositiveSemidefinite] {
            let e=try p.evaluate(clothPositions:c.current,parameters:c.parameters(mode))
            XCTAssertEqual(e.energyJoules,raw.energyJoules);XCTAssertEqual(e.clothGradientNewtons,raw.clothGradientNewtons)
            let hd=try e.hessianProduct(direction:d),quadratic=zip(d,hd).map{$0.x*$1.x+$0.y*$1.y+$0.z*$1.z}.reduce(0,+)
            XCTAssertGreaterThanOrEqual(quadratic,-1e-9)
            let H=sparse(e)
            for i in 0..<d.count*3 {
                let expected=(0..<d.count*3).map{H[.init(i:i,j:$0),default:0]*d[$0/3][$0%3]}.reduce(0,+)
                XCTAssertEqual(hd[i/3][i%3],expected,accuracy:1e-10)
            }
        }
        XCTAssertThrowsError(try raw.hessianProduct(direction:[]))
        XCTAssertThrowsError(try raw.hessianProduct(direction:d,isCancelled:{true}))
    }
    func testOriginalGenericAwayTieEnergyGradientAndHessianFD()throws {
        let cases=try load("generic-fd-cases",as:Cases.self).cases
        XCTAssertEqual(cases.count,4)
        let step=1e-10
        for c in cases {
            let p=try prepared(c),e=try p.evaluate(clothPositions:c.current,parameters:c.parameters()),H=sparse(e)
            for axis in 0..<c.rest.count*3 {
                var plus=c.current,minus=c.current;plus[axis/3][axis%3]+=step;minus[axis/3][axis%3]-=step
                let a=try p.evaluate(clothPositions:plus,parameters:c.parameters()),b=try p.evaluate(clothPositions:minus,parameters:c.parameters())
                XCTAssertEqual(a.statistics.stencils,e.statistics.stencils);XCTAssertEqual(b.statistics.stencils,e.statistics.stencils)
                XCTAssertEqual((a.energyJoules-b.energyJoules)/(2*step),e.clothGradientNewtons[axis/3][axis%3],accuracy:1e-8)
                var maxDifference=0.0,scale=0.0
                for row in 0..<c.rest.count*3 {
                    let fd=(a.clothGradientNewtons[row/3][row%3]-b.clothGradientNewtons[row/3][row%3])/(2*step),expected=H[.init(i:row,j:axis),default:0]
                    maxDifference=max(maxDifference,abs(fd-expected));scale=max(scale,abs(expected))
                }
                XCTAssertLessThanOrEqual(maxDifference/max(scale,1e-3),2e-4)
            }
        }
    }
    func testDomainAndParameterFailuresNeverReturnPartialEvaluation()throws {
        let c=try XCTUnwrap(load("body-cases",as:Cases.self).cases.first{$0.name=="plane_body_refine_2"}),p=try prepared(c)
        XCTAssertThrowsError(try p.evaluate(clothPositions:[],parameters:c.parameters()))
        var nan=c.current;nan[0].x = .nan
        XCTAssertThrowsError(try p.evaluate(clothPositions:nan,parameters:c.parameters()))
        XCTAssertThrowsError(try p.evaluate(clothPositions:c.current,parameters:.init(stiffnessPascals:0,minimumDistanceMeters:c.dmin,activationGapMeters:c.h)))
        var touching=c.current
        for i in touching.indices {touching[i].z=0}
        XCTAssertThrowsError(try p.evaluate(clothPositions:touching,parameters:c.parameters())){XCTAssertEqual($0 as? P.Failure,.infeasible)}
        var unsupported=c.rest;unsupported.append(V(5,5,5))
        XCTAssertThrowsError(try P.Prepared(clothRestPositions:unsupported,clothTriangleIndices:c.clothTriangles,body:p.body)){XCTAssertEqual($0 as? P.Failure,.unsupportedTopology)}
    }
    func testEachBudgetAndCallbackMemoryLimitDiscardEntireTrial()throws {
        // More than one BVH leaf is necessary for a one-visit budget to fail.
        let c=try XCTUnwrap(load("body-cases",as:Cases.self).cases.first{$0.name=="plane_body_refine_4"})
        var limits=P.Limits();limits.maximumCombinedVertices=2
        XCTAssertThrowsError(try prepared(c,limits))
        limits = .init();limits.maximumCombinedTriangles=1
        XCTAssertThrowsError(try prepared(c,limits))
        for setting in 0..<5 {
            limits = .init()
            switch setting {case 0:limits.maximumPrimaryCandidates=1;case 1:limits.maximumStencils=1;case 2:limits.maximumFacePairs=1;case 3:limits.maximumBVHVisitsPerClothFace=1;default:limits.maximumStagedBlockBytes=1}
            let p=try prepared(c,limits)
            XCTAssertThrowsError(try p.evaluate(clothPositions:c.current,parameters:c.parameters())){error in
                guard case .budgetExceeded = error as? P.Failure else{return XCTFail("Expected explicit budget, got \(error)")}
            }
        }
    }
    func testCancellationAtPrepareBVHNativeAndHvAndImmutableConcurrentCalls()throws {
        let c=try load("actual-case",as:Case.self)
        XCTAssertThrowsError(try P.Prepared(clothRestPositions:c.rest,clothTriangleIndices:c.clothTriangles,body:.init(bodyPositions:c.body,triangleIndices:c.bodyTriangles),isCancelled:{true}))
        let p=try prepared(c),count=Count()
        XCTAssertThrowsError(try p.evaluate(clothPositions:c.current,parameters:c.parameters(),isCancelled:{count.increment()>20})){XCTAssertEqual($0 as? P.Failure,.cancelled)}
        let tiny=try XCTUnwrap(load("body-cases",as:Cases.self).cases.first{$0.name=="ee_first"}),q=try prepared(tiny),errors=Count()
        DispatchQueue.concurrentPerform(iterations:8){_ in
            do {let e=try q.evaluate(clothPositions:tiny.current,parameters:tiny.parameters());if e.statistics.edgeEdgeStencils==0 {_ = errors.increment()}}
            catch {_ = errors.increment()}
        }
        XCTAssertEqual(errors.increment(),1)
        XCTAssertEqual(q.body.bodyPositions,tiny.body)
    }
    func testNonNearestRoundingExplicitlyRejectedAndNotChangedByNative()throws {
        let c=try XCTUnwrap(load("body-cases",as:Cases.self).cases.first{$0.name=="ee_first"}),p=try prepared(c)
        let before=fegetround();defer{_ = fesetround(before)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        XCTAssertThrowsError(try p.evaluate(clothPositions:c.current,parameters:c.parameters()))
        XCTAssertEqual(fegetround(),FE_UPWARD)
    }
}
