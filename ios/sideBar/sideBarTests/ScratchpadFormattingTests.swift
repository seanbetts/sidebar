import XCTest
@testable import sideBar

@MainActor
final class ScratchpadFormattingTests: XCTestCase {
    func testStripHeadingRemovesScratchpadHeading() {
        let content = "# ✏️ Scratchpad\n\nHello\n"
        let stripped = ScratchpadFormatting.stripHeading(content)
        XCTAssertEqual(stripped, "Hello")
    }

    func testStripHeadingLeavesOtherContent() {
        let content = "# Notes\n\nHello"
        let stripped = ScratchpadFormatting.stripHeading(content)
        XCTAssertEqual(stripped, content)
    }

    func testWithHeadingWrapsBody() {
        let wrapped = ScratchpadFormatting.withHeading("Hello")
        XCTAssertEqual(wrapped, "# ✏️ Scratchpad\n\nHello\n")
    }

    func testWithHeadingHandlesEmptyContent() {
        let wrapped = ScratchpadFormatting.withHeading("")
        XCTAssertEqual(wrapped, "# ✏️ Scratchpad\n")
    }

    func testRemoveEmptyTaskItemsRemovesBlankTasks() {
        let content = "- [ ]\n- [x] Done\n\n* [ ]\n"
        let cleaned = ScratchpadFormatting.removeEmptyTaskItems(content)
        XCTAssertEqual(cleaned, "- [x] Done")
    }
}
