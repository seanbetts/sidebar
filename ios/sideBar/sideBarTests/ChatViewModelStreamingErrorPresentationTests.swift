import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamErrorPresentationTests: XCTestCase {
    func testStructuredErrorEventStoresFriendlySummaryAndStructuredDetails() async {
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

        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable([
                    "error": "The response hit an error. Please try again.",
                    "error_details": [
                        "category": "provider_billing",
                        "provider": "openai",
                        "request_id": "req_123",
                        "retryable": false,
                        "user_action_required": true
                    ]
                ])
            )
        )

        XCTAssertEqual(viewModel.messages.first?.status, .error)
        XCTAssertEqual(
            viewModel.messages.first?.error,
            "The AI provider account needs billing attention."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "The AI provider account needs billing attention."
        )
        XCTAssertTrue(viewModel.messages.first?.errorDetails?.contains("req_123") == true)
    }

    func testErrorEventStoresFriendlySummaryAndRawDetailsOnAssistantMessage() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let toastCenter = ToastCenter()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient(),
            toastCenter: toastCenter
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
        XCTAssertNil(toastCenter.toast)
    }
}
