import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelTests: ChatViewModelTestCase {
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

    func testHandleToolEndMarksNeedsNewlineAfterSuccessfulToolCompletion() async {
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
                content: "Found this",
                status: .streaming,
                toolCalls: [
                    ToolCall(id: "tool-1", name: "Search", parameters: [:], status: .pending)
                ],
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )]
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            getResult: .success(conversation)
        )
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.selectConversation(id: "conv-1")
        viewModel.handle(event: ChatStreamEvent(
            type: .toolEnd,
            data: AnyCodable([
                "name": "Search",
                "status": "success"
            ])
        ))

        XCTAssertEqual(viewModel.messages.first?.needsNewline, true)
    }
    func testNoteUpdateClearsCache() async {
        let cache = TestCacheClient()
        let note = NotePayload(id: "note-1", name: "Test.md", content: "Hello", path: "note-1", modified: nil, created: nil)
        cache.set(key: CacheKeys.notesTree, value: FileTree(children: []), ttlSeconds: 60)
        cache.set(key: CacheKeys.note(id: "note-1"), value: note, ttlSeconds: 60)
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        let event = ChatStreamEvent(
            type: .entityChanged,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "change": "updated",
                "patch": ["id": "note-1"],
                "invalidate": ["notes", "note:note-1"]
            ])
        )
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
        let event = ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["scratchpad"]
            ])
        )
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
        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["memory"]
            ])
        ))
        let cachedMemories: [MemoryItem]? = cache.get(key: CacheKeys.memoriesList)
        XCTAssertNil(cachedMemories)
    }

    func testTaskInvalidationRequestsTasksRefresh() {
        let cache = TestCacheClient()
        var refreshRequestCount = 0
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onTasksUpdated: {
                refreshRequestCount += 1
            }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["tasks"]
            ])
        ))

        XCTAssertEqual(refreshRequestCount, 1)
    }

    func testStreamEventHandlersBuildOnceAcrossMultipleEvents() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        XCTAssertEqual(viewModel.streamEventHandlersBuildCountForTesting, 0)

        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["scratchpad"]
            ])
        ))
        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["memory"]
            ])
        ))

        XCTAssertEqual(viewModel.streamEventHandlersBuildCountForTesting, 1)
    }

    func testOnboardingStreamEventRequestsOnboardingRefresh() {
        let cache = TestCacheClient()
        var refreshRequestCount = 0
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onOnboardingStateRefreshRequested: {
                refreshRequestCount += 1
            }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["onboarding_state"]
            ])
        ))

        XCTAssertEqual(refreshRequestCount, 1)
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

    func testLoadConversationPreservesBackendMessageOrder() async {
        let cache = TestCacheClient()
        let messages = [
            Message(
                id: "user-1",
                role: .user,
                content: "Let's delete this notge",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-05-10T14:53:02Z",
                error: nil
            ),
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Okay, I won't delete this note.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-05-10T14:53:01Z",
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
        XCTAssertEqual(viewModel.messages.map(\.id), ["user-1", "assistant-1"])
    }

}
