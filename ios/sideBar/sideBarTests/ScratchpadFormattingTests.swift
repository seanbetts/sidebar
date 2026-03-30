import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ScratchpadFormattingTests: XCTestCase {
    func testStripHeadingRemovesScratchpadHeading() async {
        let content = "# ✏️ Scratchpad\n\nHello\n"
        let stripped = ScratchpadFormatting.stripHeading(content)
        XCTAssertEqual(stripped, "Hello")
    }

    func testStripHeadingRemovesPlainScratchpadTitle() async {
        let content = "✏️ Scratchpad\n\nHello\n"
        let stripped = ScratchpadFormatting.stripHeading(content)
        XCTAssertEqual(stripped, "Hello")
    }

    func testStripHeadingLeavesOtherContent() async {
        let content = "# Notes\n\nHello"
        let stripped = ScratchpadFormatting.stripHeading(content)
        XCTAssertEqual(stripped, content)
    }

    func testWithHeadingWrapsBody() async {
        let wrapped = ScratchpadFormatting.withHeading("Hello")
        XCTAssertEqual(wrapped, "# ✏️ Scratchpad\n\nHello\n")
    }

    func testWithHeadingHandlesEmptyContent() async {
        let wrapped = ScratchpadFormatting.withHeading("")
        XCTAssertEqual(wrapped, "# ✏️ Scratchpad\n")
    }

    func testRemoveEmptyTaskItemsRemovesBlankTasks() async {
        let content = "- [ ]\n- [x] Done\n\n* [ ]\n"
        let cleaned = ScratchpadFormatting.removeEmptyTaskItems(content)
        XCTAssertEqual(cleaned, "- [x] Done")
    }

    func testPlaceholderDoesNotContainMarkdownMarkers() async {
        XCTAssertFalse(ScratchpadConstants.placeholder.contains("_"))
    }
}
