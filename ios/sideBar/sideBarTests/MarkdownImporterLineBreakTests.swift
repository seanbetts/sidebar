import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class MarkdownImporterLineBreakTests: XCTestCase {
    func testImporterPreservesSingleLineBreaksAsNewlines() {
        let markdown = "line1\nline2\nline3"

        let imported = MarkdownImporter().attributedString(from: markdown).attributedString

        XCTAssertEqual(String(imported.characters), markdown)
    }
}
