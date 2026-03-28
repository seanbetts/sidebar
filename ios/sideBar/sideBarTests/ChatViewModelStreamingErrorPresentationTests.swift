import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamErrorPresentationTests: XCTestCase {
    func testErrorEventStoresFriendlySummaryAndRawDetailsOnAssistantMessage() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Partial answer",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil,
            errorDetails: nil
        )
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        let rawError = "{'type': 'error', 'error': {'details': None, 'type': " +
            "'overloaded_error', 'message': 'Overloaded'}, 'request_id': 'req_123'}"
        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable(["error": rawError])
            )
        )

        XCTAssertEqual(viewModel.messages.first?.status, .error)
        XCTAssertEqual(
            viewModel.messages.first?.error,
            "The AI provider is busy right now. Please try again in a moment."
        )
        XCTAssertEqual(viewModel.messages.first?.errorDetails, rawError)
        XCTAssertEqual(
            viewModel.errorMessage,
            "The AI provider is busy right now. Please try again in a moment."
        )
    }
}
