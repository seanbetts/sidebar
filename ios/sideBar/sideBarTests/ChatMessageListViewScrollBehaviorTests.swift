import XCTest
@testable import sideBar

@MainActor
final class ChatMessageListViewScrollBehaviorTests: XCTestCase {
    func testStreamingAutoScrollAllowsFirstUpdate() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))

        XCTAssertTrue(shouldScroll)
    }

    func testStreamingAutoScrollThrottlesRapidUpdates() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))

        XCTAssertFalse(shouldScroll)
    }

    func testStreamingAutoScrollAllowsUpdateAfterThrottleInterval() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.10))

        XCTAssertTrue(shouldScroll)
    }

    func testStreamingAutoScrollResetAllowsImmediateScroll() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))
        controller.reset()

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.05))

        XCTAssertTrue(shouldScroll)
    }

    func testTerminalStreamingTransitionDoesNotAnimateBottomScroll() {
        let oldMessage = makeMessage(content: "Final answer", status: .streaming)
        let newMessage = makeMessage(content: "Final answer", status: .complete)

        let shouldAnimate = ChatMessageListScrollBehavior.shouldAnimateLastMessageChange(
            from: ChatMessageScrollSignature(message: oldMessage),
            to: ChatMessageScrollSignature(message: newMessage),
            isStreaming: false,
            shouldScrollToBottom: false
        )

        XCTAssertFalse(shouldAnimate)
    }

    func testTerminalStreamingTransitionWithFinalContentFlushDoesNotAnimateBottomScroll() {
        let oldMessage = makeMessage(content: "Final", status: .streaming)
        let newMessage = makeMessage(content: "Final answer", status: .complete)

        let shouldAnimate = ChatMessageListScrollBehavior.shouldAnimateLastMessageChange(
            from: ChatMessageScrollSignature(message: oldMessage),
            to: ChatMessageScrollSignature(message: newMessage),
            isStreaming: false,
            shouldScrollToBottom: false
        )

        XCTAssertFalse(shouldAnimate)
    }

    func testCompletedMessageContentChangeStillAnimatesWhenNotATerminalStreamTransition() {
        let oldMessage = makeMessage(content: "Before", status: .complete)
        let newMessage = makeMessage(content: "After", status: .complete)

        let shouldAnimate = ChatMessageListScrollBehavior.shouldAnimateLastMessageChange(
            from: ChatMessageScrollSignature(message: oldMessage),
            to: ChatMessageScrollSignature(message: newMessage),
            isStreaming: false,
            shouldScrollToBottom: false
        )

        XCTAssertTrue(shouldAnimate)
    }

    func testMessageScrollSignatureChangesWhenStatusChanges() {
        let message = makeMessage()
        let changedStatusMessage = Message(
            id: message.id,
            role: message.role,
            content: message.content,
            status: .complete,
            toolCalls: message.toolCalls,
            needsNewline: message.needsNewline,
            timestamp: message.timestamp,
            error: message.error
        )

        XCTAssertNotEqual(
            ChatMessageScrollSignature(message: message),
            ChatMessageScrollSignature(message: changedStatusMessage)
        )
    }

    func testMessageScrollSignatureChangesWhenToolCallsChange() {
        let message = makeMessage(toolCalls: nil)
        let withToolCall = Message(
            id: message.id,
            role: message.role,
            content: message.content,
            status: message.status,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "prompt_preview",
                    parameters: [:],
                    status: .pending
                )
            ],
            needsNewline: message.needsNewline,
            timestamp: message.timestamp,
            error: message.error
        )

        XCTAssertNotEqual(
            ChatMessageScrollSignature(message: message),
            ChatMessageScrollSignature(message: withToolCall)
        )
    }

    func testMessageScrollSignatureChangesWhenNeedsNewlineChanges() {
        let message = makeMessage(needsNewline: false)
        let changedNeedsNewline = Message(
            id: message.id,
            role: message.role,
            content: message.content,
            status: message.status,
            toolCalls: message.toolCalls,
            needsNewline: true,
            timestamp: message.timestamp,
            error: message.error
        )

        XCTAssertNotEqual(
            ChatMessageScrollSignature(message: message),
            ChatMessageScrollSignature(message: changedNeedsNewline)
        )
    }

    func testMessageScrollSignatureSameForEquivalentMessages() {
        let message = makeMessage()
        let copy = makeMessage()

        XCTAssertEqual(
            ChatMessageScrollSignature(message: message),
            ChatMessageScrollSignature(message: copy)
        )
    }

    private func makeMessage(
        content: String = "Hello world",
        status: MessageStatus = .streaming,
        toolCalls: [ToolCall]? = nil,
        needsNewline: Bool? = false
    ) -> Message {
        Message(
            id: "message-1",
            role: .assistant,
            content: content,
            status: status,
            toolCalls: toolCalls,
            needsNewline: needsNewline,
            timestamp: "2026-02-18T19:10:00Z",
            error: nil
        )
    }
}
