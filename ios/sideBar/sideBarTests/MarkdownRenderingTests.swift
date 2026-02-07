import XCTest
import sideBarShared
@testable import sideBar

final class MarkdownRenderingTests: XCTestCase {
    private static let expectedYouTubeEmbedURL =
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" +
        "?playsinline=1&rel=0&modestbranding=1&origin=https://www.youtube-nocookie.com"

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

    func testNormalizedBlocksConvertsYouTubeMarkdownLinkToEmbedBlock() {
        let input = "[YouTube](https://www.youtube.com/watch?v=dQw4w9WgXcQ)"
        let blocks = MarkdownRendering.normalizedBlocks(from: input)

        guard case .youtube(let embed)? = blocks.first else {
            XCTFail("Expected YouTube block")
            return
        }
        XCTAssertEqual(
            embed.embedURL.absoluteString,
            Self.expectedYouTubeEmbedURL
        )
        XCTAssertEqual(embed.sourceURL, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(embed.videoId, "dQw4w9WgXcQ")
    }

    func testNormalizedBlocksConvertsBareYouTubeUrlToEmbedBlock() {
        let input = "https://youtu.be/dQw4w9WgXcQ"
        let blocks = MarkdownRendering.normalizedBlocks(from: input)

        guard case .youtube(let embed)? = blocks.first else {
            XCTFail("Expected YouTube block")
            return
        }
        XCTAssertEqual(
            embed.embedURL.absoluteString,
            Self.expectedYouTubeEmbedURL
        )
        XCTAssertEqual(embed.sourceURL, "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(embed.videoId, "dQw4w9WgXcQ")
    }

    func testNormalizedBlocksLeavesNonYouTubeUrlAsMarkdown() {
        let input = "https://example.com/article"
        let blocks = MarkdownRendering.normalizedBlocks(from: input)

        guard case .markdown(let markdown)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(markdown, input)
    }
}
