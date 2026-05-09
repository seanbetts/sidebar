import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelEmptyAssistantFailureTests: XCTestCase {
    func testUnexpectedEOFWithEmptyAssistantMessagePreservesRetryableFailure() async throws {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: IncompleteChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: initialMessage.id)
        viewModel.latestRetrySource = makeRetrySource(assistantMessageID: initialMessage.id)

        await viewModel.startStream(
            request: ChatStreamRequest(
                message: "Hello",
                conversationId: "conv-1",
                userMessageId: "user-1",
                assistantMessageId: initialMessage.id
            )
        )

        let failedAssistant = try XCTUnwrap(viewModel.messages.last)
        XCTAssertEqual(failedAssistant.id, initialMessage.id)
        XCTAssertEqual(failedAssistant.status, .error)
        XCTAssertEqual(
            failedAssistant.error,
            "The response stream ended unexpectedly. Please try again."
        )
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, initialMessage.id)
    }

    func testErrorEventWithEmptyAssistantMessagePreservesRetryableFailure() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: initialMessage.id)
        viewModel.latestRetrySource = makeRetrySource(assistantMessageID: initialMessage.id)

        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable(["error": "Google response contained no text and no tool calls"])
            )
        )

        let failedAssistant = viewModel.messages.first(where: { $0.id == initialMessage.id })
        XCTAssertEqual(failedAssistant?.status, .error)
        XCTAssertEqual(
            failedAssistant?.error,
            "The AI provider returned an empty response. Please try again."
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, initialMessage.id)
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testCompleteEventWithEmptyAssistantMessagePreservesRetryableFailure() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: initialMessage.id)
        viewModel.latestRetrySource = makeRetrySource(assistantMessageID: initialMessage.id)

        viewModel.handle(event: ChatStreamEvent(type: .complete, data: AnyCodable([:])))

        let failedAssistant = viewModel.messages.first(where: { $0.id == initialMessage.id })
        XCTAssertEqual(failedAssistant?.status, .error)
        XCTAssertEqual(
            failedAssistant?.error,
            "The AI provider returned an empty response. Please try again."
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, initialMessage.id)
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testErrorAfterSuccessfulToolOnlyResponseDoesNotSurfaceAssistantError() async throws {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: initialMessage.id)
        viewModel.handle(
            event: ChatStreamEvent(
                type: .toolResult,
                data: AnyCodable([
                    "id": "tool-1",
                    "name": "Edit Note",
                    "status": "success",
                    "result": [
                        "success": true,
                        "summary": "Updated note"
                    ]
                ])
            )
        )

        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable([
                    "error": "transport stream closed after tool completion"
                ])
            )
        )

        let finalizedAssistant = try XCTUnwrap(viewModel.messages.first(where: { $0.id == initialMessage.id }))
        XCTAssertEqual(finalizedAssistant.status, .complete)
        XCTAssertNil(finalizedAssistant.error)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(finalizedAssistant.toolCalls?.map(\.status), [.success])
        XCTAssertNil(viewModel.latestRetryableAssistantMessageID)
    }

    private func makeRetrySource(assistantMessageID: String) -> ChatRetrySource {
        ChatRetrySource(
            conversationID: "conv-1",
            userMessageID: "user-1",
            userMessageText: "Hello",
            assistantMessageID: assistantMessageID,
            attachments: nil,
            openContext: nil,
            currentLocation: nil,
            currentLocationLevels: nil,
            currentWeather: nil,
            currentTimezone: nil
        )
    }
}
