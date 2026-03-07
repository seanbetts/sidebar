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
            ),
            requestBudgetReport: ChatRequestBudgetReport(
                provider: "anthropic",
                model: "claude-sonnet-4-6",
                contextWindowChars: 200000,
                reservedOutputChars: 20000,
                availableInputChars: 177000,
                providerFramingChars: 3000,
                systemPromptChars: 123,
                bootstrapHistoryChars: 40,
                conversationHistoryChars: 15,
                currentMessageChars: 5,
                toolSchemaChars: 90,
                totalInputChars: 273,
                overflowChars: 0,
                withinBudget: true,
                failureReason: nil,
                trimmingApplied: false,
                compactionApplied: false
            )
        )

        let surface = PromptPreviewWorkspaceSurfaceFactory.makeSurface(from: preview)

        XCTAssertNotNil(surface)
        let markdown = surface?.payload["markdown"] ?? ""
        XCTAssertTrue(markdown.contains("## Prompt Report"))
        XCTAssertTrue(markdown.contains("## Request Budget"))
        XCTAssertTrue(markdown.contains("- Provider: anthropic / claude-sonnet-4-6"))
        XCTAssertTrue(markdown.contains("- Tool schema: 90 chars"))
        XCTAssertTrue(markdown.contains("## System Prompt"))
        XCTAssertTrue(markdown.contains("## First Message Prompt"))
    }
}
