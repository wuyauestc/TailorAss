import XCTest
import Darwin
@testable import NativeClothCollision

final class NativeSparseCholeskyTests:XCTestCase {
    private func make(_ limits:NativeSparseCholesky.Limits = .init())throws->NativeSparseCholesky {
        try .init(dimension:3,columnStarts:[0,2,4,5],rowIndices:[0,1,1,2,2],limits:limits)
    }
    private func near(_ x:[Double],_ y:[Double],file:StaticString=#filePath,line:UInt=#line){
        XCTAssertEqual(x.count,y.count,file:file,line:line)
        for (a,b) in zip(x,y){XCTAssertEqual(a,b,accuracy:1e-10,file:file,line:line)}
    }
    func testAnalyticCreateRefactorAndSolve()throws {
        let p=try make(),rhs=[6.0,10,8]
        let a=try p.refactor(values:[4,1,3,1,2]),first=try p.solve(rhs:rhs,generation:a.generation)
        near(first.values,[1,2,3]);XCTAssertLessThan(first.diagnostics.relativeResidual,1e-12);XCTAssertGreaterThan(first.diagnostics.quadraticForm,0)
        let b=try p.refactor(values:[8,2,6,2,4]);XCTAssertGreaterThan(b.generation,a.generation)
        near(try p.solve(rhs:rhs,generation:b.generation).values,[0.5,1,1.5]);near(rhs,[6,10,8])
        near(try p.solve(rhs:[0,0,0],generation:b.generation).values,[0,0,0])
        XCTAssertEqual(b.numericFactorizations,2);XCTAssertGreaterThan(b.factorBytesMinimum,0)
    }
    func testMalformedPatternsRejected()throws {
        for (columns,rows) in [([Int64(0),2,3,4],[Int32(0),0,1,2]),([0,1,2,3],[1,1,2]),([0,1,2,3],[0,2,1]),([0,1,2,4],[0,1,2])]{
            XCTAssertThrowsError(try NativeSparseCholesky(dimension:3,columnStarts:columns,rowIndices:rows))
        }
    }
    func testBudgetBeforeNumericStorage()throws {
        var limits=NativeSparseCholesky.Limits();limits.maximumFactorBytes=1
        XCTAssertThrowsError(try make(limits)){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.budgetExceeded)}
        limits=NativeSparseCholesky.Limits();limits.maximumLowerNonzeros=4
        XCTAssertThrowsError(try make(limits)){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.budgetExceeded)}
    }
    func testNotSPDInvalidatesAndCanRecoverWithoutJitter()throws {
        let p=try make();let first=try p.refactor(values:[4,1,3,1,2])
        XCTAssertThrowsError(try p.refactor(values:[-1,0,-1,0,-1])){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.notPositiveDefinite)}
        XCTAssertFalse(p.diagnostics.numericReady)
        XCTAssertThrowsError(try p.solve(rhs:[6,10,8],generation:first.generation)){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.staleFactor)}
        let next=try p.refactor(values:[4,1,3,1,2]);near(try p.solve(rhs:[6,10,8],generation:next.generation).values,[1,2,3])
    }
    func testNonfiniteAndCancellationNeverPublishAStaleFactor()throws {
        let p=try make();let first=try p.refactor(values:[4,1,3,1,2])
        XCTAssertThrowsError(try p.refactor(values:[4,1,.nan,1,2]))
        XCTAssertThrowsError(try p.solve(rhs:[6,10,8],generation:first.generation))
        let next=try p.refactor(values:[4,1,3,1,2])
        XCTAssertThrowsError(try p.solve(rhs:[6,10,8],generation:next.generation,isCancelled:{true})){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.cancelled)}
        XCTAssertFalse(p.diagnostics.numericReady)
        XCTAssertThrowsError(try p.refactor(values:[4,1,3,1,2],isCancelled:{true})){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.cancelled)}
        XCTAssertThrowsError(try NativeSparseCholesky(dimension:3,columnStarts:[0,2,4,5],rowIndices:[0,1,1,2,2],isCancelled:{true}))
    }
    func testWrongGenerationAndExplicitInvalidation()throws {
        let p=try make();let first=try p.refactor(values:[4,1,3,1,2])
        XCTAssertThrowsError(try p.solve(rhs:[6,10,8],generation:first.generation+1)){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.staleFactor)}
        p.invalidate();XCTAssertFalse(p.diagnostics.numericReady)
        XCTAssertThrowsError(try p.solve(rhs:[6,10,8],generation:first.generation))
    }
    func testNonNearestRoundingRejected()throws {
        let old=fegetround();defer{_ = fesetround(old)}
        XCTAssertEqual(fesetround(FE_UPWARD),0)
        XCTAssertThrowsError(try make()){XCTAssertEqual($0 as? NativeSparseCholesky.Failure,.unsupportedRounding)}
    }
}
