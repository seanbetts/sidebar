import XCTest
@testable import sideBar

final class PromptPreviewSurfaceFactoryTests: XCTestCase {
    func testMakeSurfaceFormatsWrapperTagsForReadableMarkdown() {
        let preview = ChatPromptPreview(
            systemPrompt: "<tasks>\n### Overdue\n- [ ] Pay rent\n</tasks>",
            firstMessagePrompt: nil
        )

        let surface = PromptPreviewWorkspaceSurfaceFactory.makeSurface(from: preview)

        XCTAssertNotNil(surface)
        let markdown = surface?.payload["markdown"] ?? ""
        XCTAssertTrue(markdown.contains("`<tasks>`"))
        XCTAssertTrue(markdown.contains("`</tasks>`"))
        XCTAssertTrue(markdown.contains("### Overdue"))
        XCTAssertTrue(markdown.contains("- [ ] Pay rent"))
        XCTAssertEqual(
            surface?.contextMenuActions,
            [.copyMarkdown, .shareText, .download]
        )
    }

    func testMakeSurfaceUsesStructuredMarkdownHeadings() {
        let preview = ChatPromptPreview(
            systemPrompt: "System text",
            firstMessagePrompt: "First message text",
            promptReport: ChatPromptReport(
                systemPrompt: ChatPromptReportDocument(
                    totalChars: 123,
                    maxChars: 40000,
                    truncated: false,
                    sections: []
                ),
                firstMessagePrompt: nil
            )
        )

        let surface = PromptPreviewWorkspaceSurfaceFactory.makeSurface(from: preview)

        XCTAssertNotNil(surface)
        let markdown = surface?.payload["markdown"] ?? ""
        XCTAssertTrue(markdown.contains("## Prompt Report"))
        XCTAssertTrue(markdown.contains("## System Prompt"))
        XCTAssertTrue(markdown.contains("## First Message Prompt"))
    }
}
