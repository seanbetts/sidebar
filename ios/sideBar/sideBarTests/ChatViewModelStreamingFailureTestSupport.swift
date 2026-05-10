import XCTest
import sideBarShared
@testable import sideBar

@MainActor
let streamingFailureSharedAPIClient = APIClient(
    config: APIClientConfig(
        baseUrl: URL(string: "https://example.com")!,
        accessTokenProvider: { nil }
    )
)

@MainActor
func makeStreamingFailureViewModel(
    api: StubConversationsAPI,
    cache: CacheClient,
    streamClient: ChatStreamClient,
    requestContextProvider: (() -> ChatRequestContext?)? = nil,
    toastCenter: ToastCenter? = nil
) -> ChatViewModel {
    let resolvedChatAPI = ChatAPI(client: streamingFailureSharedAPIClient)
    let themeDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailureTheme") ?? .standard
    themeDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailureTheme")
    let themeManager = ThemeManager(userDefaults: themeDefaults)
    let uiDefaults = UserDefaults(suiteName: "ChatViewModelStreamingFailure") ?? .standard
    uiDefaults.removePersistentDomain(forName: "ChatViewModelStreamingFailure")
    let chatStore = ChatStore(conversationsAPI: api, cache: cache)
    let ingestionAPI = IngestionAPI(client: streamingFailureSharedAPIClient)
    let resolvedToastCenter = toastCenter ?? ToastCenter()

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
            toastCenter: resolvedToastCenter,
            userDefaults: uiDefaults,
            clock: { Date(timeIntervalSince1970: 0) },
            requestContextProvider: requestContextProvider,
            typingRevealFrameIntervalNanoseconds: 0,
            typingRevealMinimumStep: 1_024,
            typingRevealMaximumStep: 1_024
        )
    )
}

@MainActor
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
            toastCenter: ToastCenter(),
            userDefaults: uiDefaults,
            clock: { Date(timeIntervalSince1970: 0) }
        )
    )
}

@MainActor
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
    private let error: Error

    init(error: Error = StreamFailureError.forced) {
        self.error = error
    }

    func connect(request: ChatStreamRequest) async throws {
        _ = request
        throw error
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

final class RecordingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?
    private(set) var lastRequest: ChatStreamRequest?
    private(set) var connectCallCount = 0

    func connect(request: ChatStreamRequest) async throws {
        connectCallCount += 1
        lastRequest = request
    }

    func disconnect() {
    }
}

final class CompletingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?
    private(set) var lastRequest: ChatStreamRequest?
    private let responseText: String?

    init(responseText: String? = nil) {
        self.responseText = responseText
    }

    func connect(request: ChatStreamRequest) async throws {
        lastRequest = request
        await MainActor.run {
            if let responseText {
                handler?.handle(
                    event: ChatStreamEvent(type: .token, data: AnyCodable(["content": responseText]))
                )
            }
            handler?.handle(event: ChatStreamEvent(type: .complete, data: AnyCodable([:])))
        }
    }

    func disconnect() {
    }
}

final class BlockingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?
    private(set) var lastRequest: ChatStreamRequest?
    private(set) var connectCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func connect(request: ChatStreamRequest) async throws {
        connectCallCount += 1
        lastRequest = request
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func disconnect() {
        release()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

final class SleepingChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?
    private(set) var connectCallCount = 0
    private let sleepNanoseconds: UInt64

    init(sleepNanoseconds: UInt64 = 60_000_000_000) {
        self.sleepNanoseconds = sleepNanoseconds
    }

    func connect(request: ChatStreamRequest) async throws {
        _ = request
        connectCallCount += 1
        try await Task.sleep(nanoseconds: sleepNanoseconds)
    }

    func disconnect() {
    }
}

@MainActor
func seedRetryableFailure(
    on viewModel: ChatViewModel,
    requestText: String = "Original question",
    attachments: [ChatAttachment]? = nil,
    openContext: [String: AnyCodable]? = nil,
    location: String? = nil,
    locationLevels: [String: String]? = nil,
    weather: [String: AnyCodable]? = nil,
    timezone: String? = nil
) {
    let userMessage = Message(
        id: "user-1",
        role: .user,
        content: requestText,
        status: .complete,
        toolCalls: nil,
        needsNewline: nil,
        timestamp: "2026-01-02T00:00:00Z",
        error: nil
    )
    let failedAssistantMessage = Message(
        id: "assistant-failed",
        role: .assistant,
        content: "",
        status: .error,
        toolCalls: nil,
        needsNewline: nil,
        timestamp: "2026-01-02T00:00:01Z",
        error: "The AI provider is busy right now. Please try again in a moment.",
        errorDetails: "{'error': {'type': 'overloaded_error'}}"
    )
    let messages = [userMessage, failedAssistantMessage]
    viewModel.chatStore.upsertConversationDetail(
        ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:01Z",
            messageCount: messages.count,
            firstMessage: userMessage.content,
            isArchived: nil,
            messages: messages
        )
    )
    viewModel.selectedConversationId = "conv-1"
    viewModel.messages = messages
    viewModel.latestRetrySource = ChatRetrySource(
        conversationID: "conv-1",
        userMessageID: userMessage.id,
        userMessageText: requestText,
        assistantMessageID: failedAssistantMessage.id,
        attachments: attachments,
        openContext: openContext,
        currentLocation: location,
        currentLocationLevels: locationLevels,
        currentWeather: weather,
        currentTimezone: timezone
    )
    viewModel.latestRetryableAssistantMessageID = failedAssistantMessage.id
}

@MainActor
func invalidateRetrySourceForTesting(on viewModel: ChatViewModel) {
    viewModel.latestRetrySource = nil
}

extension ChatAttachment {
    static func fixture(id: String, filename: String = "Attachment.txt") -> ChatAttachment {
        ChatAttachment(fileId: id, filename: filename)
    }
}

final class StubConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    private(set) var addMessageCalls: [ConversationMessageCreate] = []
    private let deleteResult: Result<Conversation, Error>

    init(deleteResult: Result<Conversation, Error> = .success(StubConversationsAPI.defaultConversation)) {
        self.deleteResult = deleteResult
    }

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
        return try deleteResult.get()
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        return Self.defaultConversation
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        addMessageCalls.append(message)
        return Self.defaultConversation
    }

    func updateMessage(
        conversationId: String,
        messageId: String,
        message: ConversationMessageCreate
    ) async throws -> Conversation {
        _ = conversationId
        _ = messageId
        _ = message
        return Self.defaultConversation
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        return Self.defaultConversation
    }

    private static var defaultConversation: Conversation {
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
