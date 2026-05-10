import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelConversationLifecycleTests: ChatViewModelTestCase {
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

    func testRefreshActiveConversationAppliesServerSnapshotWithoutReplayingCachedMessages() async {
        let cache = TestCacheClient()
        let cachedMessage = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Cached local action state",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-05-10T12:00:00Z",
            error: nil
        )
        let serverMessage = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Canonical server state",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-05-10T12:00:00Z",
            error: nil
        )
        let cachedDetail = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:00:00Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: false,
            messages: [cachedMessage]
        )
        let serverDetail = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:00:01Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: false,
            messages: [serverMessage]
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            getResult: .success(serverDetail)
        )
        let viewModel = makeViewModel(api: api, cache: cache)
        viewModel.selectedConversationId = "conv-1"
        viewModel.chatStore.upsertConversationDetail(cachedDetail, persist: true)
        viewModel.messages = [cachedMessage]

        await viewModel.refreshActiveConversation(silent: true)

        XCTAssertEqual(viewModel.messages.map(\.content), ["Canonical server state"])
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

    func testStartNewConversationInsertsLocalConversationBeforeCreateReturns() async {
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
        let api = ControlledCreateConversationsAPI(created: created)
        let viewModel = makeViewModel(api: api, cache: cache)

        let startTask = Task {
            await viewModel.startNewConversation()
        }

        await waitUntil {
            viewModel.conversations.count == 1
        }

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNotNil(viewModel.selectedConversationId, "Create should establish local conversation selection before the API returns")

        api.resumeCreate()
        await startTask.value

        XCTAssertEqual(viewModel.selectedConversationId, created.id)
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

    func testIsBlankConversationReturnsFalseWhenSelectedConversationMetadataIsMissing() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conv-missing"
        viewModel.messages = []

        XCTAssertFalse(viewModel.isBlankConversation)
    }

    func testApplySelectionIfNeededPreservesSelectedConversationWhenListOmitsIt() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let selectedMessage = Message(
            id: "msg-1",
            role: .assistant,
            content: "Persisted reply",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil
        )
        viewModel.selectedConversationId = "conv-selected"
        viewModel.messages = [selectedMessage]

        viewModel.applySelectionIfNeeded(
            using: [
                Conversation(
                    id: "conv-other",
                    title: "Other chat",
                    titleGenerated: false,
                    createdAt: "2026-01-01T00:00:00Z",
                    updatedAt: "2026-01-01T00:00:00Z",
                    messageCount: 1,
                    firstMessage: "Hello",
                    isArchived: false
                )
            ]
        )

        XCTAssertEqual(viewModel.selectedConversationId, "conv-selected")
        XCTAssertEqual(viewModel.messages.map(\.id), [selectedMessage.id])
    }

    func testSendMessageRestoresDraftWhenStreamConnectionFails() async throws {
        let persistence = PersistenceController(inMemory: true)
        let draftStorage = DraftStorage(container: persistence.container)
        let conversationId = "conv-1"
        try draftStorage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.draftKey(for: conversationId),
            content: "Retry me"
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient(),
            persistence: persistence,
            draftStorage: draftStorage,
            streamClient: FailingChatStreamClient()
        )

        await viewModel.selectConversation(id: conversationId)
        await viewModel.sendMessage(text: viewModel.draftText, clearDraftOnDispatch: true)

        XCTAssertEqual(viewModel.draftText, "Retry me")
        await waitUntil(timeoutSeconds: 1.0) {
            (try? draftStorage.getDraft(
                entityType: ChatDraftController.entityType,
                entityId: ChatDraftController.draftKey(for: conversationId)
            )?.content) == "Retry me"
        }
    }
}

@MainActor
private final class ControlledCreateConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    private let created: Conversation
    private var createContinuation: CheckedContinuation<Conversation, Error>?

    init(created: Conversation) {
        self.created = created
    }

    func list() async throws -> [Conversation] {
        return [Conversation]()
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return [Conversation]()
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
        }
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        _ = message
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func updateMessage(
        conversationId: String,
        messageId: String,
        message: ConversationMessageCreate
    ) async throws -> Conversation {
        _ = conversationId
        _ = messageId
        _ = message
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func resumeCreate() {
        guard let createContinuation else { return }
        self.createContinuation = nil
        createContinuation.resume(returning: created)
    }
}

@MainActor
private func waitUntil(
    timeoutSeconds: TimeInterval = 0.2,
    condition: @escaping () -> Bool
) async {
    let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
    let started = DispatchTime.now().uptimeNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
            XCTFail("Condition was not met before timeout")
            return
        }
        await Task.yield()
    }
}
