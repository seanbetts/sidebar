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

        XCTAssertEqual(viewModel.messages.first?.content, "Hello")
        let cachedMessages: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "conv-1"))
        XCTAssertEqual(cachedMessages?.first?.content, "")
    }

    private func makeViewModel(
        api: StubConversationsAPI,
        cache: CacheClient,
        streamClient: ChatStreamClient
    ) -> ChatViewModel {
        let chatAPI = ChatAPI(client: Self.sharedAPIClient)
        let themeDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailureTheme") ?? .standard
        themeDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailureTheme")
        let themeManager = ThemeManager(userDefaults: themeDefaults)
        let uiDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailure") ?? .standard
        uiDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailure")
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let ingestionAPI = IngestionAPI(client: Self.sharedAPIClient)

        return ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: chatAPI,
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
                clock: { Date(timeIntervalSince1970: 0) }
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

private struct StubConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
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
        _ = message
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
