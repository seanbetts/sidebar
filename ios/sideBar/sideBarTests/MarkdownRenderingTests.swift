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

    func testStripWebsiteTranscriptArtifactsRemovesMarkerAndLegacyTitle() {
        let input = """
        ___

        <!-- YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ -->

        ### Transcript of Example video

        Hello world transcript.
        """

        let stripped = MarkdownRendering.stripWebsiteTranscriptArtifacts(input)

        XCTAssertTrue(stripped.contains("___"))
        XCTAssertTrue(stripped.contains("Hello world transcript."))
        XCTAssertFalse(stripped.contains("YOUTUBE_TRANSCRIPT"))
        XCTAssertFalse(stripped.contains("Transcript of Example video"))
    }

    func testNormalizedWebsiteBlocksSuppressesInlineSVG() {
        let input = """
        Intro paragraph.

        <svg width="100" height="100"><circle cx="50" cy="50" r="40"></circle></svg>

        Outro paragraph.
        """

        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        XCTAssertEqual(blocks.count, 3)
        guard case .markdown(let intro)? = blocks.first else {
            XCTFail("Expected first markdown block")
            return
        }
        XCTAssertTrue(intro.contains("Intro paragraph."))

        guard case .suppressedSVG(let suppressed)? = blocks.dropFirst().first else {
            XCTFail("Expected suppressed SVG block")
            return
        }
        XCTAssertTrue(suppressed.rawSVG.contains("<svg"))
        XCTAssertTrue(suppressed.rawSVG.contains("</svg>"))

        guard case .markdown(let outro)? = blocks.last else {
            XCTFail("Expected trailing markdown block")
            return
        }
        XCTAssertTrue(outro.contains("Outro paragraph."))
    }

    func testNormalizedBlocksLeavesInlineSVGAsMarkdown() {
        let input = "Before\n\n<svg><rect width=\"10\" height=\"10\"></rect></svg>\n\nAfter"
        let blocks = MarkdownRendering.normalizedBlocks(from: input)

        XCTAssertEqual(blocks.count, 1)
        guard case .markdown(let markdown)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertTrue(markdown.contains("<svg>"))
        XCTAssertTrue(markdown.contains("</svg>"))
    }
}
