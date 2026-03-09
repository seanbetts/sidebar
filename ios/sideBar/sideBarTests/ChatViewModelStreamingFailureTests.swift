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
        let viewModel = makeViewModel(
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

    func testErrorEventWithEmptyAssistantMessageDoesNotPersistPlaceholder() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .error,
                data: AnyCodable(["error": "Google response contained no text and no tool calls"])
            )
        )

        XCTAssertFalse(viewModel.messages.contains(where: { $0.id == "assistant-1" }))
        XCTAssertEqual(viewModel.errorMessage, "Google response contained no text and no tool calls")
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testCompleteEventWithEmptyAssistantMessageIsTreatedAsError() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
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
        let viewModel = makeViewModel(
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

        let converged = await waitForCondition {
            viewModel.messages.first?.content == "Hello"
        }
        XCTAssertTrue(converged)
        let cachedMessages: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "conv-1"))
        XCTAssertEqual(cachedMessages?.first?.content, "")
    }

    func testTypingRevealConvergesToTargetContent() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Typing reveal works"])
            )
        )

        let converged = await waitForCondition {
            viewModel.messages.first?.content == "Typing reveal works"
        }
        XCTAssertTrue(converged)
    }

    func testFinalizeStreamingFlushesRemainingRevealContent() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
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
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        await viewModel.sendMessage(text: "Show me the prompt preview")

        await settleAsyncWork()
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testFinalizeStreamingDoesNotPersistAssistantMessageDuringStreaming() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: SuccessfulChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
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

        await settleAsyncWork()
        XCTAssertEqual(conversationsAPI.addMessageCalls.count, 0)
    }

    func testStopStreamClearsTypingRevealState() async {
        let cache = TestCacheClient()
        let conversationsAPI = StubConversationsAPI()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
        viewModel.messages = [initialMessage]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(
            event: ChatStreamEvent(
                type: .token,
                data: AnyCodable(["content": "Hello"])
            )
        )

        let taskStarted = await waitForCondition {
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
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            streamClient: FailingChatStreamClient()
        )

        let initialMessage = seedStreamingMessage(on: viewModel)
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

    private func seedStreamingMessage(on viewModel: ChatViewModel) -> Message {
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
        return initialMessage
    }

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 250_000_000,
        pollNanoseconds: UInt64 = 1_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return condition()
    }

    private func settleAsyncWork(iterations: Int = 10) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private func makeViewModel(
        api: StubConversationsAPI,
        cache: CacheClient,
        streamClient: ChatStreamClient
    ) -> ChatViewModel {
        let resolvedChatAPI = ChatAPI(client: Self.sharedAPIClient)
        let themeDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailureTheme") ?? .standard
        themeDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailureTheme")
        let themeManager = ThemeManager(userDefaults: themeDefaults)
        let uiDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailure") ?? .standard
        uiDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailure")
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let ingestionAPI = IngestionAPI(client: Self.sharedAPIClient)

        return ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: resolvedChatAPI,
                conversationsAPI: api,
                ingestionAPI: ingestionAPI,
                streamClient: streamClient,
                networkStatus: AlwaysOnlineNetworkStatus()
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore
            ),
            ui: ChatUICoordinator(
                themeManager: themeManager,
                userDefaults: uiDefaults,
                clock: { Date(timeIntervalSince1970: 0) },
                typingRevealFrameIntervalNanoseconds: 0,
                typingRevealMinimumStep: 1_024,
                typingRevealMaximumStep: 1_024
            )
        )
    }
}

private struct AlwaysOnlineNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool = true
    let isOffline: Bool = false
}

private enum StreamFailureError: Error {
    case forced
}

private final class FailingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
        throw StreamFailureError.forced
    }

    func disconnect() {
    }
}

private final class SuccessfulChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    func disconnect() {
    }
}

private final class StubConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    private(set) var addMessageCalls: [ConversationMessageCreate] = []

    func list() async throws -> [Conversation] {
        []
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        return ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil,
            messages: []
        )
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return []
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        return deletedConversation
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        return deletedConversation
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        addMessageCalls.append(message)
        return deletedConversation
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        return deletedConversation
    }

    private var deletedConversation: Conversation {
        Conversation(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
    }
}
