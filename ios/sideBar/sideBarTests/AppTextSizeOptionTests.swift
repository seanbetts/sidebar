import XCTest
import SwiftUI
@testable import sideBar

final class AppTextSizeOptionTests: XCTestCase {
    func testResolvedFallsBackToSystemForUnknownRawValue() {
        XCTAssertEqual(AppTextSizeOption.resolved(from: "unknown"), .system)
    }

    func testDynamicTypeSizeMapping() {
        XCTAssertNil(AppTextSizeOption.system.dynamicTypeSize)
        XCTAssertEqual(AppTextSizeOption.small.dynamicTypeSize, .medium)
        XCTAssertEqual(AppTextSizeOption.medium.dynamicTypeSize, .large)
        XCTAssertEqual(AppTextSizeOption.large.dynamicTypeSize, .xLarge)
    }

    func testScaleMultiplierMapping() {
        XCTAssertEqual(AppTextSizeOption.system.scaleMultiplier, 1.0, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.small.scaleMultiplier, 0.9, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.medium.scaleMultiplier, 1.05, accuracy: 0.0001)
        XCTAssertEqual(AppTextSizeOption.large.scaleMultiplier, 1.2, accuracy: 0.0001)
    }
}
