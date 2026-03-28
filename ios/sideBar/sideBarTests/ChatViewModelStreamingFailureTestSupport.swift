import XCTest
import sideBarShared
@testable import sideBar

let streamingFailureSharedAPIClient = APIClient(
    config: APIClientConfig(
        baseUrl: URL(string: "https://example.com")!,
        accessTokenProvider: { nil }
    )
)

func makeStreamingFailureViewModel(
    api: StubConversationsAPI,
    cache: CacheClient,
    streamClient: ChatStreamClient
) -> ChatViewModel {
    let resolvedChatAPI = ChatAPI(client: streamingFailureSharedAPIClient)
    let themeDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailureTheme") ?? .standard
    themeDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailureTheme")
    let themeManager = ThemeManager(userDefaults: themeDefaults)
    let uiDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailure") ?? .standard
    uiDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailure")
    let chatStore = ChatStore(conversationsAPI: api, cache: cache)
    let ingestionAPI = IngestionAPI(client: streamingFailureSharedAPIClient)

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

func makeStreamingFailureViewModelWithDefaultRevealConfig(
    api: StubConversationsAPI,
    cache: CacheClient,
    streamClient: ChatStreamClient
) -> ChatViewModel {
    let resolvedChatAPI = ChatAPI(client: streamingFailureSharedAPIClient)
    let themeDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailureTheme.DefaultReveal") ?? .standard
    themeDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailureTheme.DefaultReveal")
    let themeManager = ThemeManager(userDefaults: themeDefaults)
    let uiDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailure.DefaultReveal") ?? .standard
    uiDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailure.DefaultReveal")
    let chatStore = ChatStore(conversationsAPI: api, cache: cache)
    let ingestionAPI = IngestionAPI(client: streamingFailureSharedAPIClient)

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
            clock: { Date(timeIntervalSince1970: 0) }
        )
    )
}

func seedStreamingFailureMessage(on viewModel: ChatViewModel) -> Message {
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

func waitForStreamingFailureCondition(
    timeoutNanoseconds: UInt64 = 250_000_000,
    pollNanoseconds: UInt64 = 0,
    condition: @escaping () -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if condition() {
            return true
        }
        if pollNanoseconds == 0 {
            await Task.yield()
        } else {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
    return condition()
}

func settleStreamingFailureAsyncWork(iterations: Int = 10) async {
    for _ in 0..<iterations {
        await Task.yield()
    }
}

struct AlwaysOnlineNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool = true
    let isOffline: Bool = false
}

enum StreamFailureError: Error {
    case forced
}

final class FailingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
        throw StreamFailureError.forced
    }

    func disconnect() {
    }
}

final class SuccessfulChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    func disconnect() {
    }
}

final class IncompleteChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    func disconnect() {
    }
}

final class StubConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
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
