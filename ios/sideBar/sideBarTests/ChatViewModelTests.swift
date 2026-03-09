import XCTest
import sideBarShared
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

    override func tearDown() {
        ChatViewModelTestsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }
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
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .failure(ChatViewModelTestsSupport.MockError.forced))
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
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        let event = ChatStreamEvent(
            type: .toolCall,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Search",
                "parameters": ["query": "hello"],
                "status": "pending",
                "skill_id": "web-search",
                "icon_key": "web-search"
            ])
        )
        viewModel.handle(event: event)
        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(toolCall?.id, "tool-1")
        XCTAssertEqual(toolCall?.name, "Search")
        XCTAssertEqual(toolCall?.status, .pending)
        XCTAssertEqual(toolCall?.skillId, "web-search")
        XCTAssertEqual(toolCall?.iconKey, "web-search")
    }
    func testHandleToolResultPreservesSkillMetadataFromExistingToolCall() async {
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
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        viewModel.handle(event: ChatStreamEvent(
            type: .toolCall,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Create Note",
                "parameters": [:],
                "status": "pending",
                "skill_id": "notes",
                "icon_key": "notes"
            ])
        ))
        viewModel.handle(event: ChatStreamEvent(
            type: .toolResult,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Create Note",
                "result": ["success": true],
                "status": "success"
            ])
        ))
        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(toolCall?.status, .success)
        XCTAssertEqual(toolCall?.skillId, "notes")
        XCTAssertEqual(toolCall?.iconKey, "notes")
    }
    func testNoteUpdateClearsCache() async {
        let cache = TestCacheClient()
        let note = NotePayload(id: "note-1", name: "Test.md", content: "Hello", path: "note-1", modified: nil, created: nil)
        cache.set(key: CacheKeys.notesTree, value: FileTree(children: []), ttlSeconds: 60)
        cache.set(key: CacheKeys.note(id: "note-1"), value: note, ttlSeconds: 60)
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        let event = ChatStreamEvent(type: .noteUpdated, data: AnyCodable(["id": "note-1"]))
        viewModel.handle(event: event)
        let cachedNote: NotePayload? = cache.get(key: CacheKeys.note(id: "note-1"))
        let cachedTree: FileTree? = cache.get(key: CacheKeys.notesTree)
        XCTAssertNil(cachedNote)
        XCTAssertNil(cachedTree)
    }
    func testScratchpadUpdateClearsCacheAndBumpsStore() async {
        let cache = TestCacheClient()
        let store = ScratchpadStore()
        let cached = ScratchpadResponse(id: "s1", title: ScratchpadConstants.title, content: "Cached", updatedAt: nil)
        cache.set(key: CacheKeys.scratchpad, value: cached, ttlSeconds: 60)
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            scratchpadStore: store
        )
        let initialVersion = store.version
        let event = ChatStreamEvent(type: .scratchpadUpdated, data: nil)
        viewModel.handle(event: event)
        let cachedScratchpad: ScratchpadResponse? = cache.get(key: CacheKeys.scratchpad)
        XCTAssertNil(cachedScratchpad)
        XCTAssertEqual(store.version, initialVersion + 1)
    }
    func testMemoryEventClearsMemoriesCache() async {
        let cache = TestCacheClient()
        let memory = MemoryItem(
            id: "memory-1",
            path: "memory.md",
            content: "Remember this",
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z"
        )
        cache.set(key: CacheKeys.memoriesList, value: [memory], ttlSeconds: 60)
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        viewModel.handle(event: ChatStreamEvent(type: .memoryCreated, data: AnyCodable(["id": "memory-1"])))
        let cachedMemories: [MemoryItem]? = cache.get(key: CacheKeys.memoriesList)
        XCTAssertNil(cachedMemories)
    }
    func testWorkspacePatchEventDispatchesValidatedWorkspaceActions() {
        let cache = TestCacheClient()
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )
        viewModel.handle(event: ChatStreamEvent(
            type: .workspacePatch,
            data: AnyCodable([
                "version": 1,
                "operations": [
                    ["op": "swap_panes"],
                    ["op": "unknown_op"],
                    [
                        "op": "upsert_agent_surface",
                        "pane": "secondary",
                        "surface": [
                            "type": "map",
                            "surface_id": "surface-map-1",
                            "title": "Delivery map",
                            "payload": [
                                "location": "London",
                                "zoom": 8
                            ],
                            "capabilities": ["can_refresh": false],
                            "is_pinned": true
                        ]
                    ]
                ]
            ])
        ))
        XCTAssertEqual(dispatchedActions.count, 2)
        XCTAssertEqual(dispatchedActions.first, .swapPanes)
        guard case .presentAgentSurface(let surface, let pane) = dispatchedActions[1] else {
            return XCTFail("Expected upsert operation to map to presentAgentSurface")
        }
        XCTAssertEqual(pane, .secondary)
        XCTAssertEqual(surface.type, "map")
        XCTAssertEqual(surface.surfaceId, "surface-map-1")
        XCTAssertEqual(surface.title, "Delivery map")
        XCTAssertEqual(surface.payload["location"], "London")
        XCTAssertEqual(surface.payload["zoom"], "8")
        XCTAssertFalse(surface.capabilities.canRefresh)
        XCTAssertTrue(surface.isPinned)
    }
    func testWorkspacePatchEventRejectsUnsupportedVersion() {
        let cache = TestCacheClient()
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )
        viewModel.handle(event: ChatStreamEvent(
            type: .workspacePatch,
            data: AnyCodable([
                "version": 2,
                "operations": [["op": "swap_panes"]]
            ])
        ))
        XCTAssertTrue(dispatchedActions.isEmpty)
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
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        XCTAssertEqual(viewModel.messages.first?.id, "msg-1")
        XCTAssertEqual(viewModel.messages.last?.id, "msg-2")
    }
    func testPersistMessageSetsErrorOnFailure() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            addMessageResult: .failure(ChatViewModelTestsSupport.MockError.forced)
        )
        let viewModel = makeViewModel(api: api, cache: cache)
        let message = Message(
            id: "m1",
            role: .user,
            content: "Hello",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-01T00:00:00Z",
            error: nil
        )
        await viewModel.persistMessage(conversationId: "c1", message: message)
        XCTAssertNotNil(viewModel.errorMessage)
    }
    func testLoadConversationOfflineWithoutCacheSetsError() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.ConversationsAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
        await viewModel.loadConversation(id: "conv-1")
        XCTAssertEqual(viewModel.errorMessage, "This chat isn't available offline yet.")
        XCTAssertEqual(api.getCallCount, 0)
    }
    func testStartNewConversationCreatesAndSelectsConversation() async {
        let cache = TestCacheClient()
        let created = Conversation(
            id: "conv-new",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            createResult: .success(created)
        )
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.startNewConversation()
        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.conversations.first?.id, created.id)
    }
    func testOpenDraftConversationClearsSelectionAndActivatesDraft() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.selectedConversationId = "conv-1"
        viewModel.messages = [
            Message(
                id: "msg-1",
                role: .assistant,
                content: "Hello",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]
        viewModel.attachments = [
            ChatAttachmentItem(
                id: "attachment-1",
                name: "report.pdf",
                status: .ready,
                stage: "complete",
                fileId: "file-1"
            )
        ]
        viewModel.userDefaults.set("conv-1", forKey: AppStorageKeys.lastConversationId)
        await viewModel.openDraftConversation()
        XCTAssertNil(viewModel.selectedConversationId)
        XCTAssertTrue(viewModel.isDraftConversationActive)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertNil(viewModel.userDefaults.string(forKey: AppStorageKeys.lastConversationId))
    }
    func testSelectConversationNilClearsDraftState() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.isDraftConversationActive = true
        await viewModel.selectConversation(id: nil)
        XCTAssertFalse(viewModel.isDraftConversationActive)
    }

}
extension ChatViewModelTests {
    func makeViewModel<API: ConversationsProviding & ConversationsAPIProviding>(
        api: API,
        cache: CacheClient,
        networkStatus: ChatViewModelTestsSupport.TestNetworkStatus? = nil,
        scratchpadStore: ScratchpadStore? = nil,
        ingestionAPI: IngestionAPI? = nil,
        streamClient: ChatViewModelTestsSupport.MockChatStreamClient? = nil,
        requestContextProvider: (() -> ChatRequestContext?)? = nil,
        workspaceActionDispatcher: ((WorkspaceAction) -> Void)? = nil,
        attachmentPollingInitialDelayNanoseconds: UInt64 = 1_500_000_000,
        attachmentPollingIntervalNanoseconds: UInt64 = 5_000_000_000
    ) -> ChatViewModel {
        let chatAPI = ChatAPI(client: Self.sharedAPIClient)
        let themeManager = Self.sharedThemeManager
        let defaults = UserDefaults(suiteName: "ChatViewModelTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelTests")
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let resolvedIngestionAPI = ingestionAPI ?? IngestionAPI(client: Self.sharedAPIClient)
        let effectiveNetworkStatus = networkStatus ?? ChatViewModelTestsSupport.TestNetworkStatus(isNetworkAvailable: true)
        let resolvedStreamClient = streamClient ?? ChatViewModelTestsSupport.MockChatStreamClient()
        let viewModel = ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: chatAPI,
                conversationsAPI: api,
                ingestionAPI: resolvedIngestionAPI,
                streamClient: resolvedStreamClient,
                networkStatus: effectiveNetworkStatus
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore,
                notesStore: nil,
                websitesStore: nil,
                ingestionStore: nil,
                scratchpadStore: scratchpadStore
            ),
            ui: ChatUICoordinator(
                themeManager: themeManager,
                userDefaults: defaults,
                clock: { Date(timeIntervalSince1970: 0) },
                requestContextProvider: requestContextProvider,
                attachmentPollingInitialDelayNanoseconds: attachmentPollingInitialDelayNanoseconds,
                attachmentPollingIntervalNanoseconds: attachmentPollingIntervalNanoseconds
            )
        )
        viewModel.workspaceActionDispatcher = workspaceActionDispatcher
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }
    func makeIngestionAPIForAttachmentPollingTest(
        statusCode: Int = 500,
        responseBody: String = "{\"detail\":\"internal\"}"
    ) -> IngestionAPI {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ChatViewModelTestsURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfig)
        ChatViewModelTestsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("files/file-1/meta") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseBody.utf8))
        }
        return IngestionAPI(client: APIClient(config: config, session: session), session: session)
    }
    func makeIngestionAPIForAttachmentCancelTest(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> IngestionAPI {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ChatViewModelTestsURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfig)
        ChatViewModelTestsURLProtocolMock.requestHandler = requestHandler
        return IngestionAPI(client: APIClient(config: config, session: session), session: session)
    }
}
