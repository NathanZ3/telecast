import XCTest
@testable import CastNet

final class CastNetSmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(CastNet.version.isEmpty)
    }
}
