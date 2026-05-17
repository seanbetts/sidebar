import XCTest
import sideBarShared
@testable import sideBar

final class ChatToolComponentsTests: XCTestCase {
    func testSummaryPresentationHidesRecoveredRetryFailure() {
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Create Note",
                parameters: ["title": AnyCodable("Shopping List")],
                status: .error
            ),
            ToolCall(
                id: "tool-2",
                name: "Create Note",
                parameters: [
                    "title": AnyCodable("Shopping List"),
                    "document": AnyCodable([
                        ["type": "checkbox", "checked": false]
                    ])
                ],
                status: .success
            )
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "Create Note")
        XCTAssertEqual(presentation.icon, AppIcon.Content.note)
        XCTAssertFalse(presentation.hasError)
    }

    func testSummaryPresentationUsesCompactMultiToolErrorLabel() {
        let toolCalls = [
            ToolCall(id: "tool-1", name: "Create Note", parameters: [:], status: .error),
            ToolCall(id: "tool-2", name: "Create Task", parameters: [:], status: .success)
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "2 skills used")
        XCTAssertEqual(presentation.icon, AppIcon.State.error)
        XCTAssertTrue(presentation.hasError)
    }

    func testVisibleToolCallsCollapseRecoveredRetryFailures() {
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Create Note",
                parameters: [
                    "title": AnyCodable("Shopping List"),
                    "document": AnyCodable([
                        ["type": "checkbox", "checked": "false"]
                    ])
                ],
                status: .error
            ),
            ToolCall(
                id: "tool-2",
                name: "Create Note",
                parameters: [
                    "title": AnyCodable("Shopping List"),
                    "document": AnyCodable([
                        ["type": "checkbox", "checked": false]
                    ])
                ],
                status: .success
            )
        ]

        XCTAssertEqual(
            ChatToolPresentation.visibleToolCalls(from: toolCalls).map(\.id),
            ["tool-2"]
        )
    }

    func testVisibleToolCallsCollapseRecoveredRetryFailuresWhenParametersDiffer() {
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Create Note",
                parameters: ["title": AnyCodable("First Note")],
                status: .error
            ),
            ToolCall(
                id: "tool-2",
                name: "Create Note",
                parameters: ["title": AnyCodable("Second Note")],
                status: .success
            )
        ]

        XCTAssertEqual(
            ChatToolPresentation.visibleToolCalls(from: toolCalls).map(\.id),
            ["tool-2"]
        )
    }

    func testVisibleToolCallsKeepDistinctSuccessfulOperationsForRepeatedSkill() {
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Create Note",
                parameters: ["title": AnyCodable("First Note")],
                status: .success
            ),
            ToolCall(
                id: "tool-2",
                name: "Create Note",
                parameters: ["title": AnyCodable("Second Note")],
                status: .success
            )
        ]

        XCTAssertEqual(
            ChatToolPresentation.visibleToolCalls(from: toolCalls).map(\.id),
            ["tool-1", "tool-2"]
        )
    }

    func testVisibleToolCallsHideGetNoteWhenEditNoteSucceedsForSameNote() {
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Get Note",
                parameters: ["id": AnyCodable("note-1")],
                status: .success,
                result: AnyCodable([
                    "success": true,
                    "data": [
                        "id": "note-1",
                        "title": "Q2 Testing Priorities"
                    ]
                ])
            ),
            ToolCall(
                id: "tool-2",
                name: "Edit Note",
                parameters: ["note_id": AnyCodable("note-1")],
                status: .success,
                result: AnyCodable([
                    "success": true,
                    "data": [
                        "id": "note-1",
                        "title": "Q2 Testing Priorities"
                    ]
                ])
            )
        ]

        XCTAssertEqual(
            ChatToolPresentation.visibleToolCalls(from: toolCalls).map(\.id),
            ["tool-2"]
        )
    }

    func testSummaryPresentationKeepsSingleToolNameWhenNoFailuresExist() {
        let toolCalls = [
            ToolCall(id: "tool-1", name: "Create Note", parameters: [:], status: .success)
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "Create Note")
        XCTAssertFalse(presentation.hasError)
    }
}
