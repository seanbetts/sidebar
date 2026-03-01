import XCTest
@testable import sideBar

final class AppTextSizeOptionTests: XCTestCase {
    func testResolvedFallsBackToSystemForUnknownRawValue() {
        XCTAssertEqual(AppTextSizeOption.resolved(from: "unknown"), .system)
    }

    func testAllOptionsAreAvailableForSelection() {
        XCTAssertEqual(
            Set(AppTextSizeOption.allCases),
            Set([.system, .small, .medium, .large])
        )
    }

    func testScaleMultiplierMapping() {
        XCTAssertEqual(AppTextSizeOption.system.scaleMultiplier, 1.0, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.small.scaleMultiplier, 0.8, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.medium.scaleMultiplier, 0.9, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.large.scaleMultiplier, 1.05, accuracy: 0.0001)
    }
}
