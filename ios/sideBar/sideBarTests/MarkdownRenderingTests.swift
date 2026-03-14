import XCTest
import sideBarShared
@testable import sideBar

final class MarkdownRenderingTests: XCTestCase {
    private static let expectedYouTubeEmbedURL =
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" +
        "?playsinline=1&rel=0&modestbranding=1&fs=1&origin=https://www.youtube-nocookie.com"

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

    func testNormalizedWebsiteBlocksUnwrapsLinkedImageWithMatchingTarget() {
        let input = "[![](https://example.com/image.png)](https://example.com/image.png)"
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(normalized, "![](https://example.com/image.png)")
    }

    func testNormalizedWebsiteBlocksUnwrapsSubstackProxyLinkedImage() {
        let input =
            "[![](https://substackcdn.com/image/fetch/$s_def,w_1456/" +
            "https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.webp)]" +
            "(https://substack-post-media.s3.amazonaws.com/public/images/hero.webp)"
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(
            normalized,
            "![](https://substackcdn.com/image/fetch/$s_def,w_1456/" +
            "https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.webp)"
        )
    }

    func testNormalizedWebsiteBlocksKeepsLinkedImageWithDifferentTarget() {
        let input = "[![](https://example.com/image.png)](https://example.com/article)"
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(normalized, input)
    }

    func testNormalizedWebsiteBlocksUnwrapsBracketOnlyImage() {
        let input = "[![](https://example.com/image.png)]"
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(normalized, "![](https://example.com/image.png)")
    }

    func testNormalizedWebsiteBlocksUnwrapsDanglingBracketImage() {
        let input = "[![](https://example.com/image.png)"
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }
        XCTAssertEqual(normalized, "![](https://example.com/image.png)")
    }

    func testNormalizedWebsiteBlocksUnwrapsSubstackSplitImageWrapper() {
        let wrappedTarget =
            "https://substackcdn.com/image/fetch/$s_!IOnc!,f_auto,q_auto:good,fl_progressive:steep/" +
            "https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fcc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png"
        let expectedImage =
            "![Image](https://substack-post-media.s3.amazonaws.com/public/images/" +
            "cc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png \"Image\")"
        let input = """
        [![Image](https://substack-post-media.s3.amazonaws.com/public/images/cc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png "Image")

        ](\(wrappedTarget))
        """
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }

        XCTAssertTrue(normalized.contains(expectedImage))
        XCTAssertFalse(normalized.contains("](https://substackcdn.com/image/fetch/"))
    }

    func testNormalizedWebsiteBlocksRemovesSubstackWrapperPreludeArtifacts() {
        let wrappedTarget =
            "https://substackcdn.com/image/fetch/$s_!5NR5!,f_auto,q_auto:good,fl_progressive:steep/" +
            "https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F933c53d7-43f9-455e-b4e7-2ee52f4a33ee_1565x1184.png"
        let input = """
        Before

        [, ask questions of the sources and material (the middle) and turn them into things like slide shows (on the right)")

        ](\(wrappedTarget))

        After
        """
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }

        XCTAssertTrue(normalized.contains("Before"))
        XCTAssertTrue(normalized.contains("After"))
        XCTAssertFalse(normalized.contains("[, ask questions of the sources"))
        XCTAssertFalse(normalized.contains("](https://substackcdn.com/image/fetch/"))
    }

    func testNormalizedWebsiteBlocksRemovesNYTimesBoilerplateArtifacts() {
        let input = """
        Advertisement

        [SKIP ADVERTISEMENT](https://www.nytimes.com/example#after-top)

        The A.I. Disruption We’ve Been Waiting for Has Arrived

        Credit Credit...Brendan Conroy

        By Paul Ford

        [Subscribe to The Times](https://www.nytimes.com/subscription) to read as many articles as you like.

        Advertisement
        """
        let blocks = MarkdownRendering.normalizedWebsiteBlocks(from: input)

        guard case .markdown(let normalized)? = blocks.first else {
            XCTFail("Expected markdown block")
            return
        }

        XCTAssertTrue(normalized.contains("The A.I. Disruption We’ve Been Waiting for Has Arrived"))
        XCTAssertTrue(normalized.contains("By Paul Ford"))
        XCTAssertFalse(normalized.contains("Advertisement"))
        XCTAssertFalse(normalized.contains("SKIP ADVERTISEMENT"))
        XCTAssertFalse(normalized.contains("Credit Credit"))
        XCTAssertFalse(normalized.contains("Subscribe to The Times"))
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

    func testPreprocessTranscriptMarkdownReturnsOriginalTextWhenNoArtifactsExist() {
        let input = """
        # Heading

        Plain markdown body.
        """

        let processed = MarkdownRendering.preprocessTranscriptMarkdown(input)

        XCTAssertEqual(processed, input)
    }

    func testPreprocessTranscriptMarkdownRemovesTranscriptArtifactsAndCompactsBlankLines() {
        let input = """
        Intro

        <!-- YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ -->

        ### Transcript of Example video

        Body



        Tail
        """

        let processed = MarkdownRendering.preprocessTranscriptMarkdown(input)

        XCTAssertEqual(processed, "Intro\nBody\n\nTail")
    }

    func testPlainTextForWebsiteShareRemovesFrontmatterAndMarkdownSyntax() {
        let input = """
        ---
        title: Example title
        ---
        # Heading

        This is **bold** with a [link label](https://example.com).
        """

        let sharedText = MarkdownRendering.plainTextForWebsiteShare(input)

        XCTAssertTrue(sharedText.contains("Heading"))
        XCTAssertTrue(sharedText.contains("bold"))
        XCTAssertTrue(sharedText.contains("link label"))
        XCTAssertFalse(sharedText.contains("title: Example title"))
        XCTAssertFalse(sharedText.contains("---"))
        XCTAssertFalse(sharedText.contains("**"))
        XCTAssertFalse(sharedText.contains("[link label]"))
    }

    func testPlainTextForWebsiteShareRemovesTranscriptArtifactsAndKeepsVideoURL() {
        let input = """
        <!-- YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ -->
        ### Transcript of Example video
        [YouTube](https://www.youtube.com/watch?v=dQw4w9WgXcQ)

        Article body.
        """

        let sharedText = MarkdownRendering.plainTextForWebsiteShare(input)

        XCTAssertFalse(sharedText.contains("YOUTUBE_TRANSCRIPT"))
        XCTAssertFalse(sharedText.contains("Transcript of Example video"))
        XCTAssertTrue(sharedText.contains("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertTrue(sharedText.contains("Article body."))
    }

    func testPlainTextForWebsiteShareRemovesNYTimesBoilerplateArtifacts() {
        let input = """
        Advertisement
        [SKIP ADVERTISEMENT](https://www.nytimes.com/example#after-top)
        Credit Credit...Brendan Conroy

        By Paul Ford
        [Subscribe to The Times](https://www.nytimes.com/subscription) to read as many articles as you like.

        On weekday evenings, heading home on the subway.

        Advertisement
        """

        let sharedText = MarkdownRendering.plainTextForWebsiteShare(input)

        XCTAssertTrue(sharedText.contains("By Paul Ford"))
        XCTAssertTrue(sharedText.contains("On weekday evenings, heading home on the subway."))
        XCTAssertFalse(sharedText.contains("Advertisement"))
        XCTAssertFalse(sharedText.contains("SKIP ADVERTISEMENT"))
        XCTAssertFalse(sharedText.contains("Credit Credit"))
        XCTAssertFalse(sharedText.contains("Subscribe to The Times"))
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
