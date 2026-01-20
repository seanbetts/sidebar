import XCTest
@testable import sideBar

final class MarkdownRenderingTests: XCTestCase {
    func testNormalizeTaskListsStrikesCheckedItems() {
        let input = "- [x] done\n- [ ] todo"
        let normalized = MarkdownRendering.normalizeTaskLists(input)

        XCTAssertTrue(normalized.contains("~~done~~"))
        XCTAssertTrue(normalized.contains("- [ ] todo"))
    }

    func testStripFrontmatterRemovesHeader() {
        let input = "---\nlayout: post\n---\nBody"
        let stripped = MarkdownRendering.stripFrontmatter(input)

        XCTAssertEqual(stripped, "Body")
    }

    func testNormalizeImageCaptionsAddsCaptionMarker() {
        let input = "![Alt](https://example.com/image.png) *Caption*"
        let normalized = MarkdownRendering.normalizeMarkdownText(input)

        XCTAssertTrue(normalized.contains(MarkdownRendering.imageCaptionMarker))
    }

    func testSplitMarkdownContentExtractsGallery() {
        let html = "<figure class=\"image-gallery\" data-caption=\"Hello\"><img src=\"https://example.com/a.png\" /></figure>"
        let blocks = MarkdownRendering.splitMarkdownContent(html)

        guard case .gallery(let gallery)? = blocks.first else {
            XCTFail("Expected gallery block")
            return
        }
        XCTAssertEqual(gallery.imageUrls, ["https://example.com/a.png"])
        XCTAssertEqual(gallery.caption, "Hello")
    }
}
