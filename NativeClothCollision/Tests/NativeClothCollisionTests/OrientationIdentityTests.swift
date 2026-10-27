import XCTest
import Foundation
@testable import NativeClothCollision

final class OrientationIdentityTests:XCTestCase {
    typealias V=SIMD3<Double>
    struct BodyCase:Decodable {
        let name:String,clothRest:[[Double]],clothCurrent:[[Double]],bodyPositions:[[Double]]
        let clothTriangles:[[UInt32]],bodyTriangles:[[UInt32]]
        let kappa:Double,dmin:Double,h:Double,expectedEnergy:Double
        let clothGradient:[Double],clothHessian:[[Double]],clothHessianPSD:[[Double]]
    }
    struct SelfCase:Decodable {
        let name:String,restPositions:[[Double]],currentPositions:[[Double]],triangles:[[UInt32]]
        let kappa:Double,dmin:Double,h:Double,expectedEnergy:Double
        let gradient:[Double],hessian:[[Double]],hessianPSD:[[Double]]
    }
    struct Cases<T:Decodable>:Decodable {let cases:[T]}
    struct Key:Hashable {let i:Int,j:Int}
    func load<T:Decodable>(_ name:String,as:T.Type = T.self)throws->T {
        let p=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures/IPCOrientationIdentity"))
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:p))
    }
    func vectors(_ a:[[Double]])->[V] {a.map{V($0[0],$0[1],$0[2])}}
    func matrix(_ blocks:[([UInt32],[Double])])->[Key:Double] {
        var result:[Key:Double]=[:]
        for (ids,H) in blocks {let n=ids.count*3;for i in 0..<n {for j in 0..<n {
            result[.init(i:Int(ids[i/3])*3+i%3,j:Int(ids[j/3])*3+j%3),default:0]+=H[i*n+j]
        }}}
        return result
    }
    func compare(_ actual:[Key:Double],_ triples:[[Double]],file:StaticString=#filePath,line:UInt=#line) {
        let expected=Dictionary(uniqueKeysWithValues:triples.map{(Key(i:Int($0[0]),j:Int($0[1])),$0[2])})
        let error=Set(actual.keys).union(expected.keys).map{abs(actual[$0,default:0]-expected[$0,default:0])}.max() ?? 0
        XCTAssertLessThan(error,1e-7,file:file,line:line)
    }
    func testIndependentOrientedSumToyAgainstCanonicalMergedRawAndPSD()throws {
        let cases=try load("self-contact-canonical-toy",as:Cases<SelfCase>.self).cases
        XCTAssertEqual(cases.count,2)
        for c in cases {
            let p=try ClothContactPotential.Prepared(restPositions:vectors(c.restPositions),triangleIndices:c.triangles.flatMap{$0})
            for mode in [ClothContactPotential.HessianMode.exact,.clampPositiveSemidefinite] {
                let e=try p.evaluate(positions:vectors(c.currentPositions),parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h,hessianMode:mode))
                XCTAssertEqual(e.energyJoules,c.expectedEnergy,accuracy:1e-13)
                XCTAssertLessThan(zip(e.gradientNewtons.flatMap{[$0.x,$0.y,$0.z]},c.gradient).map{abs($0-$1)}.max() ?? 0,1e-10)
                compare(matrix(e.localBlocks.map{($0.vertexIDs,$0.hessianRowMajorNewtonsPerMeter)}),mode == .exact ? c.hessian:c.hessianPSD)
            }
        }
    }
    func testFixedBodyRestrictionAndVertexRelabelingMatchCorrectedFullBuilder()throws {
        let cases=try load("fixed-body-canonical",as:Cases<BodyCase>.self).cases
        XCTAssertEqual(cases.count,2)
        for c in cases {
            let p=try BodyContactPotential.Prepared(clothRestPositions:vectors(c.clothRest),clothTriangleIndices:c.clothTriangles.flatMap{$0},body:.init(bodyPositions:vectors(c.bodyPositions),triangleIndices:c.bodyTriangles.flatMap{$0}))
            for mode in [BodyContactPotential.HessianMode.exact,.clampPositiveSemidefinite] {
                let e=try p.evaluate(clothPositions:vectors(c.clothCurrent),parameters:.init(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h,hessianMode:mode))
                XCTAssertEqual(e.energyJoules,c.expectedEnergy,accuracy:1e-17)
                XCTAssertLessThan(zip(e.clothGradientNewtons.flatMap{[$0.x,$0.y,$0.z]},c.clothGradient).map{abs($0-$1)}.max() ?? 0,1e-12)
                compare(matrix(e.localBlocks.map{($0.clothVertexIDs,$0.clothHessianRowMajorNewtonsPerMeter)}),mode == .exact ? c.clothHessian:c.clothHessianPSD)
                XCTAssertEqual(p.body.bodyPositions,vectors(c.bodyPositions))
            }
        }
    }
    func testCorrectedFixedBodyEnergyGradientAndRawHessianFiniteDifferences()throws {
        let c=try XCTUnwrap(load("fixed-body-canonical",as:Cases<BodyCase>.self).cases.first)
        let x=vectors(c.clothCurrent),p=try BodyContactPotential.Prepared(clothRestPositions:vectors(c.clothRest),clothTriangleIndices:c.clothTriangles.flatMap{$0},body:.init(bodyPositions:vectors(c.bodyPositions),triangleIndices:c.bodyTriangles.flatMap{$0}))
        let parameters=BodyContactPotential.Parameters(stiffnessPascals:c.kappa,minimumDistanceMeters:c.dmin,activationGapMeters:c.h)
        let e=try p.evaluate(clothPositions:x,parameters:parameters),H=matrix(e.localBlocks.map{($0.clothVertexIDs,$0.clothHessianRowMajorNewtonsPerMeter)}),step=1e-8
        for j in 0..<x.count*3 {
            var plus=x,minus=x;plus[j/3][j%3]+=step;minus[j/3][j%3]-=step
            let a=try p.evaluate(clothPositions:plus,parameters:parameters),b=try p.evaluate(clothPositions:minus,parameters:parameters)
            XCTAssertEqual((a.energyJoules-b.energyJoules)/(2*step),e.clothGradientNewtons[j/3][j%3],accuracy:1e-10)
            for i in 0..<x.count*3 {
                XCTAssertEqual((a.clothGradientNewtons[i/3][i%3]-b.clothGradientNewtons[i/3][i%3])/(2*step),H[.init(i:i,j:j),default:0],accuracy:1e-6)
            }
        }
    }
}
