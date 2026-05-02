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
                parameters: ["title": AnyCodable("Shopping List")],
                status: .success
            )
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "Create Note")
        XCTAssertEqual(presentation.iconName, "note.text")
        XCTAssertFalse(presentation.hasError)
    }

    func testSummaryPresentationUsesCompactMultiToolErrorLabel() {
        let toolCalls = [
            ToolCall(id: "tool-1", name: "Create Note", parameters: [:], status: .error),
            ToolCall(id: "tool-2", name: "Create Task", parameters: [:], status: .success)
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "2 skills used")
        XCTAssertEqual(presentation.iconName, "exclamationmark.circle")
        XCTAssertTrue(presentation.hasError)
    }

    func testVisibleToolCallsCollapseRecoveredRetryFailures() {
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
                parameters: ["title": AnyCodable("Shopping List")],
                status: .success
            )
        ]

        XCTAssertEqual(
            ChatToolPresentation.visibleToolCalls(from: toolCalls).map(\.id),
            ["tool-2"]
        )
    }

    func testVisibleToolCallsKeepDistinctFailedOperationWhenParametersDiffer() {
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
            ["tool-1", "tool-2"]
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
