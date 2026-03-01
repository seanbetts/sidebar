import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class MarkdownImporterLineBreakTests: XCTestCase {
    func testImporterConvertsSoftBreaksToSpaces() {
        let markdown = "line1\nline2\nline3"

        let imported = MarkdownImporter().attributedString(from: markdown).attributedString

        XCTAssertEqual(String(imported.characters), "line1 line2 line3")
    }

    func testImporterPreservesHardLineBreaksAsNewlines() {
        let markdown = "line1  \nline2"

        let imported = MarkdownImporter().attributedString(from: markdown).attributedString

        XCTAssertEqual(String(imported.characters), "line1\nline2")
    }
}
