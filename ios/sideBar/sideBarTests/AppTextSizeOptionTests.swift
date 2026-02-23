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
}
