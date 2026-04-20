import XCTest
@testable import sideBar

final class ChatMessagePresentationTests: XCTestCase {
    func testShowsThinkingPlaceholderForStreamingAssistantMessageWithEmptyContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertTrue(ChatMessagePresentation.showsHeaderThinkingIndicator(for: message))
    }

    func testShowsThinkingPlaceholderForStreamingAssistantMessageWithWhitespaceContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "   \n ")

        XCTAssertTrue(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertTrue(ChatMessagePresentation.showsHeaderThinkingIndicator(for: message))
    }

    func testDoesNotShowThinkingPlaceholderForStreamingAssistantMessageWithContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertTrue(ChatMessagePresentation.showsHeaderThinkingIndicator(for: message))
    }

    func testDoesNotShowThinkingIndicatorsForStreamingUserMessage() {
        let message = makeMessage(role: .user, status: .streaming, content: "")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsHeaderThinkingIndicator(for: message))
    }

    func testDoesNotShowThinkingIndicatorsForCompleteAssistantMessage() {
        let message = makeMessage(role: .assistant, status: .complete, content: "Hello")

        XCTAssertFalse(ChatMessagePresentation.showsThinkingPlaceholder(for: message))
        XCTAssertFalse(ChatMessagePresentation.showsHeaderThinkingIndicator(for: message))
    }

    func testShouldAnimateThinkingDismissalWhenStreamingAssistantTransitionsFromEmptyToContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello")

        XCTAssertTrue(
            ChatMessagePresentation.shouldAnimateThinkingDismissal(
                for: message,
                previousContent: " \n ",
                newContent: "Hello",
                reduceMotion: false
            )
        )
    }

    func testShouldNotAnimateThinkingDismissalWhenStreamingAssistantAlreadyHasContent() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello again")

        XCTAssertFalse(
            ChatMessagePresentation.shouldAnimateThinkingDismissal(
                for: message,
                previousContent: "Hello",
                newContent: "Hello again",
                reduceMotion: false
            )
        )
    }

    func testShouldNotAnimateThinkingDismissalForCompleteAssistantMessage() {
        let message = makeMessage(role: .assistant, status: .complete, content: "Hello")

        XCTAssertFalse(
            ChatMessagePresentation.shouldAnimateThinkingDismissal(
                for: message,
                previousContent: "",
                newContent: "Hello",
                reduceMotion: false
            )
        )
    }

    func testShowsCompletionIndicatorForCompletedAssistantMessage() {
        let message = makeMessage(role: .assistant, status: .complete, content: "Done")

        XCTAssertTrue(ChatMessagePresentation.showsCompletionIndicator(for: message))
    }

    func testDoesNotShowCompletionIndicatorForEmptyCompletedAssistantMessage() {
        let message = makeMessage(role: .assistant, status: .complete, content: " \n ")

        XCTAssertFalse(ChatMessagePresentation.showsCompletionIndicator(for: message))
    }

    func testReduceMotionDisablesThinkingDismissalAnimation() {
        let message = makeMessage(role: .assistant, status: .streaming, content: "Hello")

        XCTAssertFalse(
            ChatMessagePresentation.shouldAnimateThinkingDismissal(
                for: message,
                previousContent: "",
                newContent: "Hello",
                reduceMotion: true
            )
        )
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
