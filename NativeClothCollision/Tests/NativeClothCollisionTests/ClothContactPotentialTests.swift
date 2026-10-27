import XCTest
import Foundation
@testable import NativeClothCollision

final class ClothContactPotentialTests:XCTestCase {
    typealias P=ClothContactPotential
    typealias V=SIMD3<Double>
    struct Case:Decodable {
        let name:String,rest:[[Double]],current:[[Double]],triangles:[UInt32],kappa:Double,dmin:Double,h:Double
        var r:[V]{rest.map{V($0[0],$0[1],$0[2])}}
        var x:[V]{current.map{V($0[0],$0[1],$0[2])}}
        func parameters(_ mode:P.HessianMode = .exact)->P.Parameters{.init(stiffnessPascals:kappa,minimumDistanceMeters:dmin,activationGapMeters:h,hessianMode:mode)}
    }
    struct Cases:Decodable {let cases:[Case]}
    struct Golden:Decodable {
        let name:String,energy:Double,gradient:[Double],hessian:[[Double]],hessianPSD:[[Double]]
        let stencilCount:Int,negativeStencilCount:Int,referenceVertexAreas:[Double],referenceEdgeAreas:[Double]
    }
    struct Goldens:Decodable {let cases:[Golden]}
    struct Actual:Decodable {let `case`:Golden}
    struct Key:Hashable {let i:Int,j:Int}
    final class Count:@unchecked Sendable {
        private let lock=NSLock();private var count=0
        func increment()->Int{lock.lock();defer{lock.unlock()};count+=1;return count}
    }
    func load<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/IPCClothContact"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func corrected<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let u=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/IPCOrientationIdentity"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:u))
    }
    func prepare(_ c:Case,_ limits:P.Limits = .init())throws->P.Prepared {try .init(restPositions:c.r,triangleIndices:c.triangles,limits:limits)}
    func sparse(_ e:P.Evaluation)->[Key:Double] {
        var a:[Key:Double]=[:]
        for b in e.localBlocks {
            let n=b.vertexIDs.count*3
            for i in 0..<n {for j in 0..<n {
                a[.init(i:Int(b.vertexIDs[i/3])*3+i%3,j:Int(b.vertexIDs[j/3])*3+j%3),default:0]+=b.hessianRowMajorNewtonsPerMeter[i*n+j]
            }}
        };return a
    }
    func compare(_ e:P.Evaluation,_ g:Golden,projected:Bool=false,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(e.energyJoules,g.energy,accuracy:1e-15,file:file,line:line)
        let flat=e.gradientNewtons.flatMap{[$0.x,$0.y,$0.z]}
        XCTAssertEqual(flat.count,g.gradient.count,file:file,line:line)
        XCTAssertLessThanOrEqual(zip(flat,g.gradient).map{abs($0-$1)}.max() ?? 0,1e-10,file:file,line:line)
        let a=sparse(e),b=Dictionary(uniqueKeysWithValues:(projected ? g.hessianPSD:g.hessian).map{(Key(i:Int($0[0]),j:Int($0[1])),$0[2])})
        XCTAssertLessThanOrEqual(Set(a.keys).union(b.keys).map{abs(a[$0,default:0]-b[$0,default:0])}.max() ?? 0,1e-6,file:file,line:line)
        XCTAssertEqual(e.statistics.stencils,g.stencilCount,file:file,line:line)
        XCTAssertEqual(e.statistics.negativeStencils,g.negativeStencilCount,file:file,line:line)
        XCTAssertTrue(g.referenceVertexAreas.allSatisfy{$0>0},file:file,line:line)
        XCTAssertTrue(g.referenceEdgeAreas.allSatisfy{$0>0},file:file,line:line)
    }
    func testCorrectedFullBuilder20AllMovingCasesRawAndWholeSignedLocalPSD()throws {
        let cases=try load("cloth-cases",as:Cases.self).cases,goldens=try corrected("cloth-canonical-goldens",as:Goldens.self).cases
        XCTAssertEqual(cases.count,20)
        for c in cases {
            let p=try prepare(c),g=try XCTUnwrap(goldens.first{$0.name==c.name})
            for mode in [P.HessianMode.exact,.clampPositiveSemidefinite] {
                let e=try p.evaluate(positions:c.x,parameters:c.parameters(mode));compare(e,g,projected:mode != .exact)
                XCTAssertEqual(p.restPositions,c.r);XCTAssertEqual(p.triangleIndices,c.triangles)
                XCTAssertTrue(e.localBlocks.allSatisfy{$0.vertexIDs.allSatisfy{Int($0)<c.r.count}})
                XCTAssertLessThanOrEqual(e.statistics.chargedStagedBlockBytes,p.limits.maximumStagedBlockBytes)
            }
        }
    }
    func testRealFullShirtSourceHasAllMovingActiveSignedForces()throws {
        let c=try load("shirt-case",as:Case.self),g=try corrected("shirt-golden",as:Actual.self).case,p=try prepare(c)
        XCTAssertEqual(c.r.count,1732);XCTAssertEqual(c.triangles.count/3,2710)
        for mode in [P.HessianMode.exact,.clampPositiveSemidefinite] {
            let e=try p.evaluate(positions:c.x,parameters:c.parameters(mode));compare(e,g,projected:mode != .exact)
            XCTAssertEqual(e.statistics.stencils,g.stencilCount);XCTAssertEqual(e.statistics.negativeStencils,g.negativeStencilCount)
            XCTAssertGreaterThan(e.statistics.faceVertexStencils,0);XCTAssertGreaterThan(e.statistics.edgeEdgeStencils,0)
            XCTAssertGreaterThan(e.energyJoules,0);XCTAssertTrue(e.gradientNewtons.contains{$0 != .zero})
            let force=e.gradientNewtons.reduce(.zero,+)
            XCTAssertLessThan(max(abs(force.x),abs(force.y),abs(force.z)),1e-12)
        }
    }
    func testUnmodifiedClearCircleAndMathematicalR237AreInactiveControls()throws {
        for name in ["clear","r237"] {
            let c=try load(name+"-case",as:Case.self),g=try load(name+"-golden",as:Actual.self).case
            let e=try prepare(c).evaluate(positions:c.x,parameters:c.parameters());compare(e,g)
            XCTAssertEqual(e.statistics.stencils,0);XCTAssertEqual(e.energyJoules,0)
            XCTAssertTrue(e.gradientNewtons.allSatisfy{$0 == .zero})
            // Endpoint inactivity is not a whole-path or garment acceptance proof.
        }
    }
    func testCompleteCircle218ActivationBoundaryHasNoFiniteEnergyJump()throws {
        let cases=try corrected("circle218-cases",as:Cases.self).cases
        let goldens=try corrected("circle218-goldens",as:Goldens.self).cases
        XCTAssertEqual(cases.count,2);XCTAssertEqual(cases[0].r.count,1679)
        XCTAssertEqual(cases[0].triangles.count/3,2830)
        XCTAssertEqual(cases[0].r,cases[1].r);XCTAssertEqual(cases[0].triangles,cases[1].triangles)
        let p=try prepare(cases[0]);var evaluations:[P.Evaluation]=[]
        for (c,g) in zip(cases,goldens) {
            let e=try p.evaluate(positions:c.x,parameters:c.parameters());compare(e,g)
            evaluations.append(e)
        }
        let displacement=zip(cases[0].x,cases[1].x).map{a,b in max(abs(a.x-b.x),abs(a.y-b.y),abs(a.z-b.z))}.max() ?? 0
        XCTAssertLessThan(displacement,7e-15)
        XCTAssertLessThan(abs(evaluations[1].energyJoules-evaluations[0].energyJoules),1e-14)
        XCTAssertLessThan(zip(evaluations[0].gradientNewtons,evaluations[1].gradientNewtons).map{a,b in max(abs(a.x-b.x),abs(a.y-b.y),abs(a.z-b.z))}.max() ?? 0,1e-10)
        // Historical uncorrected full-builder jump was 3.82443416104e-7 J.
        // The original immutable golden is evidence of the identity defect,
        // not an expectation for the corrected physical leaf sum.
    }
    func testSharedVertexOrSharedEdgeFacePairsRetainNonincidentActiveFeatures()throws {
        let cases=try load("cloth-cases",as:Cases.self).cases
        for token in ["one_vertex","shared_edge"] {
            let c=try XCTUnwrap(cases.first{$0.name.contains(token)}),e=try prepare(c).evaluate(positions:c.x,parameters:c.parameters())
            XCTAssertGreaterThan(e.statistics.faceVertexStencils,0);XCTAssertGreaterThan(e.energyJoules,0)
            XCTAssertTrue(e.localBlocks.contains{$0.kind == .faceVertex && $0.gradientNewtons.contains{$0 != .zero} && $0.hessianRowMajorNewtonsPerMeter.contains{$0 != 0}})
        }
        let sewn=try XCTUnwrap(cases.first{$0.name.contains("intended_sew")}),e=try prepare(sewn).evaluate(positions:sewn.x,parameters:sewn.parameters())
        XCTAssertGreaterThan(e.energyJoules,0);XCTAssertGreaterThan(e.statistics.stencils,0)
    }
    func testAllMovingAwayTieEnergyGradientAndHessianFD()throws {
        let cases=try load("generic-fd-cases",as:Cases.self).cases
        XCTAssertEqual(cases.count,4);let step=1e-9
        for c in cases {
            let p=try prepare(c),e=try p.evaluate(positions:c.x,parameters:c.parameters()),H=sparse(e)
            for axis in 0..<c.r.count*3 {
                var plus=c.x,minus=c.x;plus[axis/3][axis%3]+=step;minus[axis/3][axis%3]-=step
                let a=try p.evaluate(positions:plus,parameters:c.parameters()),b=try p.evaluate(positions:minus,parameters:c.parameters())
                XCTAssertEqual(a.statistics.stencils,e.statistics.stencils);XCTAssertEqual(b.statistics.stencils,e.statistics.stencils)
                XCTAssertEqual((a.energyJoules-b.energyJoules)/(2*step),e.gradientNewtons[axis/3][axis%3],accuracy:1e-8)
                var error=0.0,scale=0.0
                for row in 0..<c.r.count*3 {
                    let fd=(a.gradientNewtons[row/3][row%3]-b.gradientNewtons[row/3][row%3])/(2*step),h=H[.init(i:row,j:axis),default:0]
                    error=max(error,abs(fd-h));scale=max(scale,abs(h))
                }
                XCTAssertLessThanOrEqual(error/max(scale,1e-3),2e-4)
            }
        }
    }
    func testWholeSignedLocalProjectedModesAndMatrixFreeHv()throws {
        let c=try XCTUnwrap(load("cloth-cases",as:Cases.self).cases.first{$0.name.contains("concave")}),p=try prepare(c)
        let raw=try p.evaluate(positions:c.x,parameters:c.parameters()),d=c.x.indices.map{V(sin(Double($0)+0.3),cos(Double($0)+0.7),0.4)}
        XCTAssertTrue(raw.localBlocks.contains{$0.signedRestAreaSquareMeters<0})
        for mode in [P.HessianMode.clampPositiveSemidefinite,.absolutePositiveSemidefinite] {
            let e=try p.evaluate(positions:c.x,parameters:c.parameters(mode)),hd=try e.hessianProduct(direction:d),H=sparse(e)
            XCTAssertEqual(e.energyJoules,raw.energyJoules);XCTAssertEqual(e.gradientNewtons,raw.gradientNewtons)
            let q=zip(d,hd).map{$0.x*$1.x+$0.y*$1.y+$0.z*$1.z}.reduce(0,+)
            XCTAssertGreaterThanOrEqual(q,-1e-9)
            for i in 0..<d.count*3 {
                let expected=(0..<d.count*3).map{H[.init(i:i,j:$0),default:0]*d[$0/3][$0%3]}.reduce(0,+)
                XCTAssertEqual(hd[i/3][i%3],expected,accuracy:1e-9)
            }
        }
        XCTAssertThrowsError(try raw.hessianProduct(direction:[]))
        XCTAssertThrowsError(try raw.hessianProduct(direction:d,isCancelled:{true}))
    }
    func testRigidCurrentCovarianceWithUnchangedRestAndFullHv()throws {
        let c=try load("generic-fd-cases",as:Cases.self).cases[2],p=try prepare(c)
        func rotate(_ v:V)->V {V(-v.y,v.x,v.z)}
        let a=try p.evaluate(positions:c.x,parameters:c.parameters())
        let b=try p.evaluate(positions:c.x.map{rotate($0)+V(0.2,-0.3,0.4)},parameters:c.parameters())
        XCTAssertEqual(a.energyJoules,b.energyJoules,accuracy:1e-14)
        XCTAssertEqual(a.statistics.stencils,b.statistics.stencils)
        for i in a.gradientNewtons.indices {
            let e=rotate(a.gradientNewtons[i])-b.gradientNewtons[i]
            XCTAssertLessThan(max(abs(e.x),abs(e.y),abs(e.z)),1e-10)
        }
        let d=c.x.indices.map{V(sin(Double($0)),0.3,cos(Double($0)))},ha=try a.hessianProduct(direction:d),hb=try b.hessianProduct(direction:d.map(rotate))
        for i in ha.indices {
            let e=rotate(ha[i])-hb[i]
            XCTAssertLessThan(max(abs(e.x),abs(e.y),abs(e.z)),1e-6)
        }
        XCTAssertEqual(p.restPositions,c.r)
    }
    func testDomainsDoNotReturnPartialEvaluation()throws {
        let c=try XCTUnwrap(load("cloth-cases",as:Cases.self).cases.first{$0.name.contains("refine_2")}),p=try prepare(c)
        XCTAssertThrowsError(try p.evaluate(positions:[],parameters:c.parameters()))
        var x=c.x;x[0].x = .nan
        XCTAssertThrowsError(try p.evaluate(positions:x,parameters:c.parameters()))
        XCTAssertThrowsError(try p.evaluate(positions:c.x,parameters:.init(stiffnessPascals:0,minimumDistanceMeters:0,activationGapMeters:c.h)))
        // Identical distinct-ID triangles: zero raw distance stays infeasible,
        // even where an EE mollifier or signed cancellation could vanish.
        let r=[V(0,0,0),V(0.02,0,0),V(0,0.02,0)]
        let q=try P.Prepared(restPositions:r+r.map{$0+V(0,0,0.001)},triangleIndices:[0,1,2,3,4,5])
        XCTAssertThrowsError(try q.evaluate(positions:r+r,parameters:c.parameters())){XCTAssertEqual($0 as? P.Failure,.infeasible)}
        XCTAssertThrowsError(try P.Prepared(restPositions:c.r+[V(5,5,5)],triangleIndices:c.triangles)){XCTAssertEqual($0 as? P.Failure,.unsupportedTopology)}
        XCTAssertThrowsError(try P.Prepared(restPositions:[.zero,.zero,.zero],triangleIndices:[0,1,2]))
        XCTAssertThrowsError(try P.Prepared(restPositions:c.r,triangleIndices:c.triangles+Array(c.triangles.prefix(3))))
    }
    func testBudgetsDiscardEntireTrial()throws {
        let c=try XCTUnwrap(load("cloth-cases",as:Cases.self).cases.first{$0.name.contains("refine_4")})
        var l=P.Limits();l.maximumVertices=2;XCTAssertThrowsError(try prepare(c,l))
        l = .init();l.maximumTriangles=1;XCTAssertThrowsError(try prepare(c,l))
        for setting in 0..<5 {
            l = .init()
            switch setting {case 0:l.maximumPrimaryCandidates=1;case 1:l.maximumStencils=1;case 2:l.maximumFacePairs=1;case 3:l.maximumBVHVisitsPerFace=1;default:l.maximumStagedBlockBytes=1}
            let p=try prepare(c,l)
            XCTAssertThrowsError(try p.evaluate(positions:c.x,parameters:c.parameters())) {error in
                guard case .budgetExceeded = error as? P.Failure else {return XCTFail("expected budget, got \(error)")}
            }
        }
    }
    func testCancellationAndImmutableConcurrentCalls()throws {
        let c=try load("shirt-case",as:Case.self)
        XCTAssertThrowsError(try P.Prepared(restPositions:c.r,triangleIndices:c.triangles,isCancelled:{true}))
        let p=try prepare(c),count=Count()
        XCTAssertThrowsError(try p.evaluate(positions:c.x,parameters:c.parameters(),isCancelled:{count.increment()>30})){XCTAssertEqual($0 as? P.Failure,.cancelled)}
        let tiny=try XCTUnwrap(load("cloth-cases",as:Cases.self).cases.first{$0.name.contains("one_vertex")}),q=try prepare(tiny),errors=Count()
        DispatchQueue.concurrentPerform(iterations:8){_ in
            do {let e=try q.evaluate(positions:tiny.x,parameters:tiny.parameters());if e.statistics.faceVertexStencils==0 {_ = errors.increment()}}
            catch {_ = errors.increment()}
        }
        XCTAssertEqual(errors.increment(),1);XCTAssertEqual(q.restPositions,tiny.r)
    }
}
