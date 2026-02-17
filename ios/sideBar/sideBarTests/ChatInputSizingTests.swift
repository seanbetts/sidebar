import XCTest
@testable import sideBar

final class ChatInputSizingTests: XCTestCase {
    func testResolveUsesMinimumHeightWhenContentIsSmall() {
        let sizing = ChatInputSizing.resolve(contentHeight: 24, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 46)
        XCTAssertFalse(sizing.isOverflowing)
    }

    func testResolveUsesContentHeightWhenWithinBounds() {
        let sizing = ChatInputSizing.resolve(contentHeight: 96, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 96)
        XCTAssertFalse(sizing.isOverflowing)
    }

    func testResolveClampsToMaximumHeightAndOverflowsWhenNeeded() {
        let sizing = ChatInputSizing.resolve(contentHeight: 220, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 140)
        XCTAssertTrue(sizing.isOverflowing)
    }
}
