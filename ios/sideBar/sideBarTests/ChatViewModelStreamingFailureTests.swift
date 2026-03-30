import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelStreamingFailureTests: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )

    func testStartStreamFailureFinalizesStreamingMessageAsError() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        viewModel.selectedConversationId = "conv-1"
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "partial response",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        await viewModel.startStream(
            request: ChatStreamRequest(
                message: "Hello",
                conversationId: "conv-1"
            )
        )

        XCTAssertEqual(viewModel.messages.first?.status, .error)
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertNil(viewModel.currentStreamMessageId)
        XCTAssertNil(viewModel.streamingConversationId)
    }

    func testStartStreamUnexpectedEOFFinalizesStreamingMessageAsError() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: IncompleteChatStreamClient()
        )

        viewModel.selectedConversationId = "conv-1"
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "partial response",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        await viewModel.startStream(
            request: ChatStreamRequest(
                message: "Hello",
                conversationId: "conv-1"
            )
        )

        XCTAssertEqual(viewModel.messages.first?.status, .error)
        XCTAssertEqual(
            viewModel.messages.first?.error,
            "The response stream ended unexpectedly. Please try again."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "The response stream ended unexpectedly. Please try again."
        )
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertNil(viewModel.currentStreamMessageId)
        XCTAssertNil(viewModel.streamingConversationId)
    }

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
        viewModel.latestRetrySource = ChatRetrySource(
            conversationID: "conv-1",
            userMessageID: "user-1",
            userMessageText: "Hello",
            assistantMessageID: initialMessage.id,
            attachments: nil,
            openContext: nil,
            currentLocation: nil,
            currentLocationLevels: nil,
            currentWeather: nil,
            currentTimezone: nil
        )

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

    func testErrorEventWithEmptyAssistantMessageDoesNotPersistPlaceholder() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable(["error": "Google response contained no text and no tool calls"])
            )
        )

        XCTAssertFalse(viewModel.messages.contains(where: { $0.id == "assistant-1" }))
        XCTAssertEqual(
            viewModel.errorMessage,
            "The AI provider returned an empty response. Please try again."
        )
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testCompleteEventWithEmptyAssistantMessageIsTreatedAsError() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(event: ChatStreamEvent(type: .complete, data: AnyCodable([:])))

        XCTAssertFalse(viewModel.messages.contains(where: { $0.id == "assistant-1" }))
        XCTAssertEqual(viewModel.errorMessage, "Assistant returned an empty response. Please try again.")
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testTokenUpdatesDoNotPersistUntilFinalize() async {
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
            content: "",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil
        )
        viewModel.chatStore.upsertConversationDetail(
            ConversationWithMessages(
                id: "conv-1",
                title: "Chat",
                titleGenerated: false,
                createdAt: "2026-01-02T00:00:00Z",
                updatedAt: "2026-01-02T00:00:00Z",
                messageCount: 1,
                firstMessage: nil,
                isArchived: nil,
                messages: [initialMessage]
            )
        )
        viewModel.selectedConversationId = "conv-1"
        viewModel.streamingConversationId = "conv-1"
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Hello"])
            )
        )

        let converged = await waitForStreamingFailureCondition {
            viewModel.messages.first?.content == "Hello"
        }
        XCTAssertTrue(converged)
        let cachedMessages: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "conv-1"))
        XCTAssertEqual(cachedMessages?.first?.content, "")
    }

    func testTypingRevealConvergesToTargetContent() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Typing reveal works"])
            )
        )

        let converged = await waitForStreamingFailureCondition {
            viewModel.messages.first?.content == "Typing reveal works"
        }
        XCTAssertTrue(converged)
    }

    func testFinalizeStreamingFlushesRemainingRevealContent() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        let fullContent = String(repeating: "x", count: 120)
        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": fullContent])
            )
        )
        viewModel.finalizeStreaming(status: .complete)

        XCTAssertEqual(viewModel.messages.first?.content, fullContent)
        XCTAssertEqual(viewModel.messages.first?.status, .complete)
        let cachedMessages: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "conv-1"))
        XCTAssertEqual(cachedMessages?.first?.content, fullContent)
    }

    func testSendMessageDoesNotPersistUserMessageDuringStreaming() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        await viewModel.sendMessage(text: "Show me the prompt preview")

        await settleStreamingFailureAsyncWork()
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testFinalizeStreamingDoesNotPersistAssistantMessageDuringStreaming() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [
            Message(
                id: initialMessage.id,
                role: .assistant,
                content: "Prompt preview ready",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: initialMessage.timestamp,
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.finalizeStreaming(status: .complete)

        await settleStreamingFailureAsyncWork()
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testStopStreamClearsTypingRevealState() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Hello"])
            )
        )

        let taskStarted = await waitForStreamingFailureCondition {
            viewModel.typingRevealTask != nil
        }
        XCTAssertTrue(taskStarted)

        viewModel.stopStream()

        XCTAssertNil(viewModel.typingRevealTask)
        XCTAssertTrue(viewModel.typingRevealTargetsByMessageId.isEmpty)
    }

    func testFinalizeStreamingErrorClearsTypingRevealState() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Hello"])
            )
        )
        viewModel.finalizeStreaming(status: .error)

        XCTAssertNil(viewModel.typingRevealTask)
        XCTAssertTrue(viewModel.typingRevealTargetsByMessageId.isEmpty)
        XCTAssertEqual(viewModel.messages.first?.status, .error)
    }

    func testTypingRevealUsesLargerStepsForLargeBacklog() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModelWithDefaultRevealConfig(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        let current = ""
        let target = String(repeating: "x", count: 600)

        let nextContent = viewModel.nextDisplayedContent(current: current, target: target)

        XCTAssertGreaterThan(nextContent.count, 20)
        XCTAssertLessThan(nextContent.count, target.count)
    }

    func testNonPersistentMessageUpdatesDoNotRepublishConversationDetail() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        let initialMessage = seedStreamingFailureMessage(on: viewModel)
        viewModel.messages = [initialMessage]

        viewModel.updateMessage(id: "assistant-1", persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: "Local only",
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }

        XCTAssertEqual(viewModel.messages.first?.content, "Local only")
        XCTAssertEqual(
            viewModel.chatStore.conversationDetails["conv-1"]?.messages.first?.content,
            ""
        )
    }

    func testTypingRevealFinishesSmallBacklogWithoutOneCharacterCrawl() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeStreamingFailureViewModelWithDefaultRevealConfig(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        let current = String(repeating: "x", count: 10)
        let target = String(repeating: "x", count: 25)

        let nextContent = viewModel.nextDisplayedContent(current: current, target: target)

        XCTAssertEqual(nextContent, target)
    }
}
