import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatOfflineDraftAndCachingTests: ChatViewModelTestCase {
    func testConversationDraftRestoresWhileHistoryComesFromOfflineCache() async throws {
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let offlineStore = OfflineStore(container: persistence.container)
        let detail = ConversationWithMessages(
            id: "conv-1",
            title: "Cached chat",
            titleGenerated: false,
            createdAt: "2026-01-10T00:00:00Z",
            updatedAt: "2026-01-10T00:00:00Z",
            messageCount: 1,
            firstMessage: "Cached hello",
            isArchived: false,
            messages: [
                Message(
                    id: "msg-1",
                    role: .assistant,
                    content: "Cached hello",
                    status: .complete,
                    toolCalls: nil,
                    needsNewline: nil,
                    timestamp: "2026-01-10T00:00:00Z",
                    error: nil
                )
            ]
        )
        offlineStore.set(
            key: CacheKeys.conversation(id: detail.id),
            entityType: "conversation",
            value: detail,
            lastSyncAt: nil
        )
        try draftStorage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.draftKey(for: detail.id),
            content: "Offline draft"
        )
        let api = ChatViewModelTestsSupport.ConversationsAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: TestCacheClient(),
            networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            ),
            persistence: persistence,
            offlineStore: offlineStore,
            draftStorage: draftStorage
        )

        await viewModel.selectConversation(id: detail.id)

        XCTAssertEqual(viewModel.draftText, "Offline draft")
        XCTAssertEqual(viewModel.messages.first?.content, "Cached hello")
        XCTAssertEqual(api.getCallCount, 0)
    }

    func testConversationDraftRestoresWhenDetailIsUnavailableOffline() async throws {
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let conversation = Conversation(
            id: "conv-offline",
            title: "Offline unavailable",
            titleGenerated: false,
            createdAt: "2026-01-10T00:00:00Z",
            updatedAt: "2026-01-10T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        try draftStorage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.draftKey(for: conversation.id),
            content: "Unavailable offline draft"
        )
        let api = ChatViewModelTestsSupport.ConversationsAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: TestCacheClient(),
            networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(
                isNetworkAvailable: false,
                isOffline: true
            ),
            persistence: persistence,
            draftStorage: draftStorage
        )
        viewModel.conversations = [conversation]

        await viewModel.selectConversation(id: conversation.id)

        XCTAssertEqual(viewModel.selectedConversationId, conversation.id)
        XCTAssertEqual(viewModel.draftText, "Unavailable offline draft")
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "This chat isn't available offline yet.")
        XCTAssertEqual(api.getCallCount, 0)

        viewModel.updateDraftText("Unavailable offline draft updated")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(viewModel.draftText, "Unavailable offline draft updated")
        XCTAssertEqual(
            try draftStorage.getDraft(
                entityType: ChatDraftController.entityType,
                entityId: ChatDraftController.draftKey(for: conversation.id)
            )?.content,
            "Unavailable offline draft updated"
        )
    }

    func testNewChatDraftUsesFallbackSlotUntilServerConversationExists() async throws {
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        try draftStorage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.newChatKey,
            content: "Unsent draft"
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient(),
            persistence: persistence,
            draftStorage: draftStorage
        )

        await viewModel.openDraftConversation()

        XCTAssertNil(viewModel.selectedConversationId)
        XCTAssertTrue(viewModel.isDraftConversationActive)
        XCTAssertEqual(viewModel.draftText, "Unsent draft")
    }

    func testSendDraftClearsStoredDraftAfterSuccessfulCompletion() async throws {
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let createdConversation = Conversation(
            id: "conv-new",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-11T00:00:00Z",
            updatedAt: "2026-01-11T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        try draftStorage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.newChatKey,
            content: "Send me"
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(
                listResult: .success([]),
                createResult: .success(createdConversation)
            ),
            cache: TestCacheClient(),
            persistence: persistence,
            draftStorage: draftStorage,
            streamClient: CompletingChatStreamClient(responseText: "Done")
        )

        await viewModel.openDraftConversation()
        await viewModel.sendMessage(text: viewModel.draftText, clearDraftOnDispatch: true)

        XCTAssertEqual(viewModel.selectedConversationId, createdConversation.id)
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(
            try draftStorage.getDraft(
                entityType: ChatDraftController.entityType,
                entityId: ChatDraftController.newChatKey
            )
        )
        XCTAssertNil(
            try draftStorage.getDraft(
                entityType: ChatDraftController.entityType,
                entityId: ChatDraftController.draftKey(for: createdConversation.id)
            )
        )
    }
}
