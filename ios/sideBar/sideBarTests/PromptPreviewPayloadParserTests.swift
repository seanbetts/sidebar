import XCTest
import sideBarShared
@testable import sideBar

final class PromptPreviewPayloadParserTests: XCTestCase {
    func testParseToolResultReadsPromptPreviewFromDataPayload() {
        let result = AnyCodable([
            "success": true,
            "data": [
                "system_prompt": "System prompt text",
                "first_message_prompt": "First prompt text",
                "system_prompt_sections": [
                    [
                        "id": "context",
                        "title": "Context",
                        "source": "system",
                        "chars": 42
                    ]
                ],
                "workspace_context_menu_actions": [
                    "copy_markdown",
                    "share_text",
                    "download"
                ],
                "prompt_report": [
                    "system_prompt": [
                        "total_chars": 42,
                        "max_chars": 40000,
                        "truncated": false,
                        "sections": []
                    ]
                ],
                "request_budget_report": [
                    "provider": "anthropic",
                    "model": "claude-sonnet-4-6",
                    "context_window_chars": 200000,
                    "reserved_output_chars": 20000,
                    "available_input_chars": 177000,
                    "provider_framing_chars": 3000,
                    "system_prompt_chars": 42,
                    "bootstrap_history_chars": 25,
                    "conversation_history_chars": 12,
                    "current_message_chars": 9,
                    "tool_schema_chars": 100,
                    "total_input_chars": 188,
                    "overflow_chars": 0,
                    "within_budget": true,
                    "failure_reason": NSNull(),
                    "trimming_applied": false,
                    "compaction_applied": false
                ]
            ]
        ])

        let preview = PromptPreviewPayloadParser.parseToolResult(result)

        XCTAssertEqual(preview?.systemPrompt, "System prompt text")
        XCTAssertEqual(preview?.firstMessagePrompt, "First prompt text")
        XCTAssertEqual(preview?.systemPromptSections.first?.id, "context")
        XCTAssertEqual(preview?.promptReport?.systemPrompt?.totalChars, 42)
        XCTAssertEqual(preview?.requestBudgetReport?.provider, "anthropic")
        XCTAssertEqual(preview?.requestBudgetReport?.toolSchemaChars, 100)
        XCTAssertEqual(
            preview?.workspaceContextMenuActions,
            [.copyMarkdown, .shareText, .download]
        )
    }

    func testParseToolResultReadsPromptPreviewFromTopLevelPayload() {
        let result = AnyCodable([
            "system_prompt": "Top level system",
            "first_message_prompt_sections": [
                [
                    "id": "first",
                    "title": "First",
                    "source": "first_message",
                    "chars": "12"
                ]
            ]
        ])

        let preview = PromptPreviewPayloadParser.parseToolResult(result)

        XCTAssertEqual(preview?.systemPrompt, "Top level system")
        XCTAssertEqual(preview?.firstMessagePromptSections.first?.chars, 12)
    }

    func testParseToolResultReturnsNilForNonPreviewResult() {
        let result = AnyCodable([
            "success": true,
            "data": [
                "id": "note-1",
                "title": "A note"
            ]
        ])

        let preview = PromptPreviewPayloadParser.parseToolResult(result)

        XCTAssertNil(preview)
    }
}
