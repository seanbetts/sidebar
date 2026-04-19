import XCTest
@testable import sideBar

final class ChatToolComponentsTests: XCTestCase {
    func testSummaryPresentationUsesCompactMultiToolErrorLabel() {
        let toolCalls = [
            ToolCall(id: "tool-1", name: "Create Note", parameters: [:], status: .error),
            ToolCall(id: "tool-2", name: "Create Note", parameters: [:], status: .success)
        ]

        let presentation = ChatToolSummaryPresentation.from(toolCalls: toolCalls)

        XCTAssertEqual(presentation.text, "2 skills used")
        XCTAssertEqual(presentation.iconName, "exclamationmark.circle")
        XCTAssertTrue(presentation.hasError)
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
