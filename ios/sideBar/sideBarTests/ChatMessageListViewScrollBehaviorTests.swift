import XCTest
import sideBarShared
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

    func testCompletedToolMetadataChangeDoesNotScrollBottom() {
        let oldMessage = makeMessage(
            content: "Answer",
            status: .complete,
            toolCalls: [
                ToolCall(id: "tool-1", name: "Search", parameters: [:], status: .success)
            ]
        )
        let newMessage = makeMessage(
            content: "Answer",
            status: .complete,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "Search",
                    parameters: [:],
                    status: .success,
                    skillId: "web-search",
                    iconKey: "web-search"
                )
            ]
        )

        let shouldScroll = ChatMessageListScrollBehavior.shouldScrollForLastMessageChange(
            from: ChatMessageScrollSignature(message: oldMessage),
            to: ChatMessageScrollSignature(message: newMessage),
            isStreaming: false,
            shouldScrollToBottom: false
        )

        XCTAssertFalse(shouldScroll)
    }

    func testWorkspaceSurfaceResultChangeScrollsBottom() {
        let oldMessage = makeMessage(
            content: "Answer",
            status: .complete,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "Generate Prompts",
                    parameters: [:],
                    status: .success,
                    skillId: "prompt-preview",
                    iconKey: "prompt-preview"
                )
            ]
        )
        let newMessage = makeMessage(
            content: "Answer",
            status: .complete,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "Generate Prompts",
                    parameters: [:],
                    status: .success,
                    result: AnyCodable([
                        "data": [
                            "workspace_patch": [
                                "version": 1,
                                "operations": [
                                    [
                                        "op": "upsert_agent_surface",
                                        "pane": "primary",
                                        "surface": [
                                            "type": "markdown",
                                            "surface_id": "surface-1",
                                            "title": "Preview"
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]),
                    skillId: "prompt-preview",
                    iconKey: "prompt-preview"
                )
            ]
        )

        let oldSignature = ChatMessageScrollSignature(message: oldMessage)
        let newSignature = ChatMessageScrollSignature(message: newMessage)

        XCTAssertNotEqual(
            oldSignature.visibleWorkspaceTargetsSignature,
            newSignature.visibleWorkspaceTargetsSignature
        )

        let shouldScroll = ChatMessageListScrollBehavior.shouldScrollForLastMessageChange(
            from: oldSignature,
            to: newSignature,
            isStreaming: false,
            shouldScrollToBottom: false
        )

        XCTAssertTrue(shouldScroll)
    }

    func testActiveToolChangesDoNotScrollChatList() {
        XCTAssertFalse(ChatMessageListScrollBehavior.shouldScrollForActiveToolChange())
    }

    func testRetryAppendKeepsBottomPinnedWithoutJudder() {
        let current = [failedAssistantMessage]
        let incoming = [failedAssistantMessage, retryStreamingAssistantMessage]

        XCTAssertEqual(
            ChatMessageListScrollBehavior.scrollMode(
                previousMessages: current,
                messages: incoming,
                activeToolChanged: false
            ),
            .pinBottomWithoutAnimation
        )
    }

    func testInitialStreamingAssistantAppendPinsBottomWithoutAnimation() {
        let current = [
            makeMessage(id: "assistant-complete", role: .assistant, content: "Previous answer", status: .complete),
            makeMessage(id: "user-latest", role: .user, content: "New prompt", status: .complete)
        ]
        let incoming = [
            current[0],
            current[1],
            makeMessage(id: "assistant-streaming", role: .assistant, content: "", status: .streaming)
        ]

        XCTAssertEqual(
            ChatMessageListScrollBehavior.scrollMode(
                previousMessages: current,
                messages: incoming,
                activeToolChanged: false
            ),
            .pinBottomWithoutAnimation
        )
    }

    func testMessageAppendSchedulesDeferredBottomScroll() {
        XCTAssertTrue(
            ChatMessageListScrollBehavior.shouldScheduleDeferredBottomScroll(
                previousMessageCount: 2,
                messageCount: 4,
                scrollMode: .pinBottomWithAnimation
            )
        )
    }

    func testNoScrollModeDoesNotScheduleDeferredBottomScroll() {
        XCTAssertFalse(
            ChatMessageListScrollBehavior.shouldScheduleDeferredBottomScroll(
                previousMessageCount: 2,
                messageCount: 4,
                scrollMode: .noScroll
            )
        )
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

    func testMessageScrollSignatureIgnoresStreamingContentChanges() {
        let oldMessage = makeMessage(content: "A", status: .streaming)
        let newMessage = makeMessage(content: "AB", status: .streaming)

        XCTAssertEqual(
            ChatMessageScrollSignature(message: oldMessage),
            ChatMessageScrollSignature(message: newMessage)
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
        id: String = "message-1",
        role: MessageRole = .assistant,
        content: String = "Hello world",
        status: MessageStatus = .streaming,
        toolCalls: [ToolCall]? = nil,
        needsNewline: Bool? = false
    ) -> Message {
        Message(
            id: id,
            role: role,
            content: content,
            status: status,
            toolCalls: toolCalls,
            needsNewline: needsNewline,
            timestamp: "2026-02-18T19:10:00Z",
            error: nil
        )
    }

    private var failedAssistantMessage: Message {
        Message(
            id: "assistant-failed",
            role: .assistant,
            content: "",
            status: .error,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-02-18T19:10:00Z",
            error: "The AI provider is busy right now. Please try again in a moment.",
            errorDetails: "{'error': {'type': 'overloaded_error'}}"
        )
    }

    private var retryStreamingAssistantMessage: Message {
        Message(
            id: "assistant-retry",
            role: .assistant,
            content: "",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-02-18T19:10:01Z",
            error: nil
        )
    }
}
