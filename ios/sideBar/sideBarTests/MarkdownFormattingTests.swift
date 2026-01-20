import XCTest
@testable import sideBar

final class MarkdownFormattingTests: XCTestCase {
    func testRenderAndSerializeRoundTrip() {
        let markdown = "# Title\n- [x] Done\n- Item"
        let attributed = MarkdownFormatting.render(markdown: markdown)
        let serialized = MarkdownFormatting.serialize(attributedText: attributed)

        XCTAssertTrue(serialized.contains("# Title"))
        XCTAssertTrue(serialized.contains("- [x] Done"))
        XCTAssertTrue(serialized.contains("- Item"))
    }

    func testSerializeEmitsCodeBlockMarkers() {
        let markdown = "```\ncode\n```"
        let attributed = MarkdownFormatting.render(markdown: markdown)
        let serialized = MarkdownFormatting.serialize(attributedText: attributed)

        XCTAssertTrue(serialized.contains("```"))
        XCTAssertTrue(serialized.contains("code"))
    }
}
