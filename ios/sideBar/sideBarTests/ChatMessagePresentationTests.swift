import XCTest
@testable import sideBar

final class ChatMessagePresentationTests: XCTestCase {
    func testShowsThinkingPlaceholderForStreamingAssistantMessageWithEmptyContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsStreamingThinkingFooter(for: message))
    }

    func testShowsThinkingPlaceholderForStreamingAssistantMessageWithWhitespaceContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "   \n ")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsStreamingThinkingFooter(for: message))
    }

    func testShowsStreamingThinkingFooterForStreamingAssistantMessageWithContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertTrue(ChatMessagePresentation.showsStreamingThinkingFooter(for: message))
    }

    func testDoesNotShowThinkingIndicatorsForStreamingUserMessage() {
        let message = makeMessage(role: .user, status: .streaming, content: "")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsStreamingThinkingFooter(for: message))
    }

    func testDoesNotShowThinkingIndicatorsForCompleteAssistantMessage() {
        let message = makeMessage(role: .assistant, status: .complete, content: "Hello")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsStreamingThinkingFooter(for: message))
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
