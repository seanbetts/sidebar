import Foundation
import XCTest
@testable import sideBar

final class MarkdownEditingTests: XCTestCase {
    func testApplyInlineStyleWithSelection() {
        let text = "Hello"
        let result = MarkdownEditing.applyInlineStyle(
            text: text,
            range: NSRange(location: 0, length: 5),
            prefix: "**",
            suffix: "**",
            placeholder: "bold"
        )

        XCTAssertEqual(result.text, "**Hello**")
        XCTAssertEqual(result.selectedRange.location, 2)
        XCTAssertEqual(result.selectedRange.length, 5)
    }

    func testApplyInlineStyleWithEmptySelectionUsesPlaceholder() {
        let result = MarkdownEditing.applyInlineStyle(
            text: "",
            range: NSRange(location: 0, length: 0),
            prefix: "*",
            suffix: "*",
            placeholder: "italic"
        )

        XCTAssertEqual(result.text, "*italic*")
        XCTAssertEqual(result.selectedRange.length, "italic".utf16.count)
    }

    func testToggleLinePrefixAddsAndRemoves() {
        let text = "Line one\nLine two"
        let range = NSRange(location: 0, length: text.utf16.count)
        let added = MarkdownEditing.toggleLinePrefix(text: text, range: range, prefix: "> ")
        XCTAssertTrue(added.text.contains("> Line one"))

        let removed = MarkdownEditing.toggleLinePrefix(text: added.text, range: range, prefix: "> ")
        XCTAssertEqual(removed.text, text)
    }

    func testToggleOrderedListAddsNumbers() {
        let text = "First\nSecond"
        let range = NSRange(location: 0, length: text.utf16.count)
        let result = MarkdownEditing.toggleOrderedList(text: text, range: range)

        XCTAssertTrue(result.text.contains("1. First"))
        XCTAssertTrue(result.text.contains("2. Second"))
    }

    func testInsertCodeBlockWrapsSelection() {
        let text = "code"
        let range = NSRange(location: 0, length: text.utf16.count)
        let result = MarkdownEditing.insertCodeBlock(text: text, range: range)

        XCTAssertTrue(result.text.hasPrefix("```"))
        XCTAssertTrue(result.text.contains("code"))
        XCTAssertTrue(result.text.hasSuffix("```"))
    }

    func testInsertLinkUsesSelection() {
        let text = "Link"
        let range = NSRange(location: 0, length: text.utf16.count)
        let result = MarkdownEditing.insertLink(text: text, range: range)

        XCTAssertEqual(result.text, "[Link](https://)")
    }

    func testInsertTableCreatesMinimumSize() {
        let result = MarkdownEditing.insertTable(text: "", range: NSRange(location: 0, length: 0), columns: 1, rows: 0)

        XCTAssertTrue(result.text.contains("Header"))
        XCTAssertTrue(result.text.contains("---"))
        XCTAssertTrue(result.text.contains("Cell"))
    }
}
