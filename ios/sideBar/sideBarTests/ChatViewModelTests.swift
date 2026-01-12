import XCTest
@testable import sideBar

@MainActor
final class ChatViewModelTests: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )
    private static let sharedThemeManager: ThemeManager = {
        let defaults = UserDefaults(suiteName: "ChatViewModelTestsTheme") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelTestsTheme")
        return ThemeManager(userDefaults: defaults)
    }()
    private static var retainedViewModels: [ChatViewModel] = []

    func testLoadConversationsUsesCacheOnFailure() async {
        let cached = [Conversation(
            id: "conv-1",
            title: "Cached",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: nil
        )]
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversationsList, value: cached, ttlSeconds: CachePolicy.conversationsList)
        let api = MockConversationsAPI(listResult: .failure(MockError.forced))
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.loadConversations()

        XCTAssertEqual(viewModel.conversations.first?.id, "conv-1")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleToolCallUpdatesStreamingMessage() async {
        let cache = TestCacheClient()
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: nil,
            messages: [Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )]
        )
        let api = MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.selectConversation(id: "conv-1")

        let event = ChatStreamEvent(
            type: .toolCall,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Search",
                "parameters": ["query": "hello"],
                "status": "pending"
            ])
        )
        viewModel.handle(event: event)

        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(toolCall?.id, "tool-1")
        XCTAssertEqual(toolCall?.name, "Search")
        XCTAssertEqual(toolCall?.status, .pending)
    }

    func testNoteUpdateClearsCache() {
        let cache = TestCacheClient()
        let note = NotePayload(id: "note-1", name: "Test.md", content: "Hello", path: "note-1", modified: nil)
        cache.set(key: CacheKeys.notesTree, value: FileTree(children: []), ttlSeconds: 60)
        cache.set(key: CacheKeys.note(id: "note-1"), value: note, ttlSeconds: 60)
        let viewModel = makeViewModel(api: MockConversationsAPI(listResult: .success([])), cache: cache)

        let event = ChatStreamEvent(type: .noteUpdated, data: AnyCodable(["id": "note-1"]))
        viewModel.handle(event: event)

        let cachedNote: NotePayload? = cache.get(key: CacheKeys.note(id: "note-1"))
        let cachedTree: FileTree? = cache.get(key: CacheKeys.notesTree)
        XCTAssertNil(cachedNote)
        XCTAssertNil(cachedTree)
    }

    func testLoadConversationSortsMessagesByTimestamp() async {
        let cache = TestCacheClient()
        let messages = [
            Message(
                id: "msg-2",
                role: .assistant,
                content: "Second",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T10:00:00Z",
                error: nil
            ),
            Message(
                id: "msg-1",
                role: .user,
                content: "First",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T09:00:00Z",
                error: nil
            )
        ]
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T08:00:00Z",
            updatedAt: "2026-01-02T10:00:00Z",
            messageCount: messages.count,
            firstMessage: nil,
            isArchived: nil,
            messages: messages
        )
        let api = MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.selectConversation(id: "conv-1")

        XCTAssertEqual(viewModel.messages.first?.id, "msg-1")
        XCTAssertEqual(viewModel.messages.last?.id, "msg-2")
    }

    private func makeViewModel(api: MockConversationsAPI, cache: CacheClient) -> ChatViewModel {
        let chatAPI = ChatAPI(client: Self.sharedAPIClient)
        let themeManager = Self.sharedThemeManager
        let streamClient = MockChatStreamClient()
        let defaults = UserDefaults(suiteName: "ChatViewModelTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelTests")
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let viewModel = ChatViewModel(
            chatAPI: chatAPI,
            conversationsAPI: api,
            cache: cache,
            themeManager: themeManager,
            streamClient: streamClient,
            chatStore: chatStore,
            userDefaults: defaults,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }
}

private enum MockError: Error {
    case forced
}

private final class MockChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    func disconnect() {
    }
}

private struct MockConversationsAPI: ConversationsAPIProviding {
    let listResult: Result<[Conversation], Error>
    let getResult: Result<ConversationWithMessages, Error>
    let searchResult: Result<[Conversation], Error>
    let deleteResult: Result<Conversation, Error>
    let createResult: Result<Conversation, Error>
    let addMessageResult: Result<Conversation, Error>
    let updateResult: Result<Conversation, Error>

    init(
        listResult: Result<[Conversation], Error>,
        getResult: Result<ConversationWithMessages, Error> = .failure(MockError.forced),
        searchResult: Result<[Conversation], Error> = .success([]),
        deleteResult: Result<Conversation, Error> = .success(Conversation(
            id: "deleted",
            title: "Deleted",
            titleGenerated: false,
            createdAt: "",
            updatedAt: "",
            messageCount: 0,
            firstMessage: nil,
            isArchived: true
        )),
        createResult: Result<Conversation, Error> = .failure(MockError.forced),
        addMessageResult: Result<Conversation, Error> = .failure(MockError.forced),
        updateResult: Result<Conversation, Error> = .failure(MockError.forced)
    ) {
        self.listResult = listResult
        self.getResult = getResult
        self.searchResult = searchResult
        self.deleteResult = deleteResult
        self.createResult = createResult
        self.addMessageResult = addMessageResult
        self.updateResult = updateResult
    }

    func list() async throws -> [Conversation] {
        try listResult.get()
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        return try getResult.get()
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return try searchResult.get()
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        return try deleteResult.get()
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        return try createResult.get()
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        _ = message
        return try addMessageResult.get()
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        return try updateResult.get()
    }
}
