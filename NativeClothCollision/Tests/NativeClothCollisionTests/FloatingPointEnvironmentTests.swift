#if os(macOS)
import XCTest
import Darwin
@testable import NativeClothCollision

final class FloatingPointEnvironmentTests:XCTestCase {
    func testReadOnlyBridgeReportsAllRoundingModes() {
        let original=fegetround()
        defer {_ = fesetround(original)}
        for mode in [FE_TONEAREST,FE_DOWNWARD,FE_UPWARD,FE_TOWARDZERO] {
            XCTAssertEqual(fesetround(mode),0)
            XCTAssertEqual(FloatingPointEnvironment.isNearestRounding,mode==FE_TONEAREST)
            XCTAssertEqual(fegetround(),mode,"Query must not change the calling thread's fenv")
        }
    }
}
#endif
