import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelStreamingNewlineTests: ChatViewModelTestCase {
    func testAppendTokenPreservesSyntheticToolNewlineWhenTypingRevealBacklogExists() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.currentStreamMessageId = "assistant-1"
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: [
                    ToolCall(id: "tool-1", name: "Search", parameters: [:], status: .success)
                ],
                needsNewline: true,
                timestamp: "2026-01-02T00:00:01Z",
                error: nil
            )
        ]
        viewModel.typingRevealTargetsByMessageId["assistant-1"] = "Let me check that."

        viewModel.appendToken(
            from: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Good, I found it."])
            )
        )
        viewModel.typingRevealTask?.cancel()
        viewModel.typingRevealTask = nil

        XCTAssertEqual(
            viewModel.typingRevealTargetsByMessageId["assistant-1"],
            "Let me check that.\n\nGood, I found it."
        )
        XCTAssertEqual(viewModel.messages.first?.needsNewline, false)
    }

    func testToolStatusDisplayNameArmsSyntheticNewlineForFollowingToken() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.currentStreamMessageId = "assistant-1"
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "You're right, sorry — let me actually do it this time.",
                status: .streaming,
                toolCalls: [
                    ToolCall(id: "tool-1", name: "Create Note", parameters: [:], status: .success)
                ],
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:01Z",
                error: nil
            )
        ]

        let handlers = viewModel.makePrimitiveStreamEventHandlers()
        handlers[.toolStatus]?(
            ChatStreamEvent(
                type: .toolStatus,
                data: AnyCodable([
                    "display_name": "Create Note",
                    "status": "success",
                    "tool_call_id": "tool-1"
                ])
            )
        )

        viewModel.appendToken(
            from: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Done — **\"The Art of Breaking Things\"** is now in your notes."])
            )
        )
        viewModel.typingRevealTask?.cancel()
        viewModel.typingRevealTask = nil

        XCTAssertEqual(
            viewModel.typingRevealTargetsByMessageId["assistant-1"],
            "You're right, sorry — let me actually do it this time.\n\nDone — **\"The Art of Breaking Things\"** is now in your notes."
        )
        XCTAssertEqual(viewModel.messages.first?.needsNewline, false)
    }
}
