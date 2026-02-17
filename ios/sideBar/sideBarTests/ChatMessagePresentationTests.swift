import XCTest
@testable import sideBar

final class ChatMessagePresentationTests: XCTestCase {
    func testShowsThinkingIndicatorForStreamingAssistantMessageWithEmptyContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingIndicator(for: message))
    }

    func testShowsThinkingIndicatorForStreamingAssistantMessageWithWhitespaceContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "   \n ")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingIndicator(for: message))
    }

    func testDoesNotShowThinkingIndicatorForStreamingAssistantMessageWithContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingIndicator(for: message))
    }

    func testDoesNotShowThinkingIndicatorForStreamingUserMessage() {
        let message = makeMessage(role: .user, status: .streaming, content: "")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingIndicator(for: message))
    }

    private func makeMessage(role: MessageRole, status: MessageStatus, content: String) -> Message {
        Message(
            id: UUID().uuidString,
            role: role,
            content: content,
            status: status,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-02-17T12:00:00Z",
            error: nil
        )
    }
}
