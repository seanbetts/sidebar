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
                "prompt_report": [
                    "system_prompt": [
                        "total_chars": 42,
                        "max_chars": 40000,
                        "truncated": false,
                        "sections": []
                    ]
                ]
            ]
        ])

        let preview = PromptPreviewPayloadParser.parseToolResult(result)

        XCTAssertEqual(preview?.systemPrompt, "System prompt text")
        XCTAssertEqual(preview?.firstMessagePrompt, "First prompt text")
        XCTAssertEqual(preview?.systemPromptSections.first?.id, "context")
        XCTAssertEqual(preview?.promptReport?.systemPrompt?.totalChars, 42)
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
