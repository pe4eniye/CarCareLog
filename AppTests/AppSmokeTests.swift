import XCTest
import CarCareCore
@testable import CarCareLog

final class AppSmokeTests: XCTestCase {
    func testCoreIsLinked() {
        XCTAssertEqual(PartNumbers.normalize("a-1"), "A1")
    }
}
