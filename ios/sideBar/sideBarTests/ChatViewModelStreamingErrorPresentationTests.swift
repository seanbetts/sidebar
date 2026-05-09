import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamErrorPresentationTests: XCTestCase {
    func testStructuredAssistantContextDoesNotBecomeVisibleErrorDetails() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        viewModel.messages = [streamingAssistantMessage(content: "")]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        let explanation = "I couldn't complete this response because OpenAI reported " +
            "that the account needs billing attention."
        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable([
                    "type": "error",
                    "version": 2,
                    "error": "The AI provider account needs billing attention.",
                    "category": "provider_billing",
                    "retryable": false,
                    "request_id": "req_123",
                    "assistant_explanation": explanation,
                    "assistant_context": [
                        "visibility": "assistant_only",
                        "category": "provider_billing",
                        "provider": "openai",
                        "request_id": "req_123",
                        "message": "quota exhausted"
                    ]
                ])
            )
        )

        XCTAssertEqual(viewModel.messages.first?.status, .error)
        XCTAssertEqual(viewModel.messages.first?.content, explanation)
        XCTAssertEqual(
            viewModel.messages.first?.error,
            "The AI provider account needs billing attention."
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.messages.first?.errorDetails)
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

        viewModel.messages = [streamingAssistantMessage(content: "Partial answer")]
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
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(toastCenter.toast)
    }

    private func streamingAssistantMessage(content: String) -> Message {
        Message(
            id: "assistant-1",
            role: .assistant,
            content: content,
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil,
            errorDetails: nil
        )
    }
}
