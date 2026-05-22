import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatRefreshAdapterTests: ChatViewModelTestCase {
    func testOpeningChatDoesNotStartRegularConversationPolling() async {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let refreshContext = RefreshContext(
            visibleSection: .chat,
            hasVisibleDetail: false,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )
        viewModel.configureRefreshCoordinator(NoopChatRefreshCoordinator()) {
            refreshContext
        }

        await viewModel.loadConversations()
        viewModel.startAutoRefresh()

        XCTAssertNoConversationPollingSource()
    }

    func testClassifyConversationChangeRefreshesChatListOnlyForUnselectedConversation() {
        let updatedAt = Date(timeIntervalSince1970: 1_800)
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let adapter = ChatRefreshAdapter(viewModel: viewModel)

        let change = adapter.classifyConversationChange(
            conversationId: "conversation-1",
            updatedAt: updatedAt,
            affectsSelectedConversation: false
        )

        XCTAssertEqual(
            change,
            DomainSyncChange(
                section: .chat,
                entityId: "conversation-1",
                kind: .listRefresh,
                updatedAt: updatedAt,
                requiresListRefresh: true,
                requiresDetailRefresh: false,
                canPatchMetadata: false
            )
        )
    }

    func testClassifyConversationChangeRefreshesChatListAndDetailForSelectedConversation() {
        let updatedAt = Date(timeIntervalSince1970: 1_900)
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let adapter = ChatRefreshAdapter(viewModel: viewModel)

        let change = adapter.classifyConversationChange(
            conversationId: "conversation-1",
            updatedAt: updatedAt,
            affectsSelectedConversation: true
        )

        XCTAssertEqual(
            change,
            DomainSyncChange(
                section: .chat,
                entityId: "conversation-1",
                kind: .detailRefresh,
                updatedAt: updatedAt,
                requiresListRefresh: true,
                requiresDetailRefresh: true,
                canPatchMetadata: false
            )
        )
    }

    func testActivationRefreshClearsPreviousConversationLoadError() async {
        let conversation = Conversation(
            id: "conversation-1",
            title: "Recovered chat",
            titleGenerated: false,
            createdAt: "2026-04-26T15:00:00Z",
            updatedAt: "2026-04-26T15:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        let api = SequencedConversationsAPI(results: [
            .failure(APIClientError.missingToken),
            .success([conversation])
        ])
        let viewModel = makeViewModel(api: api, cache: TestCacheClient())

        await viewModel.loadConversations(force: true)

        XCTAssertNotNil(viewModel.errorMessage)

        let adapter = ChatRefreshAdapter(viewModel: viewModel)
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .coldLaunch,
                targets: [.chatList],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.conversationsLoadState, .loaded)
        XCTAssertEqual(viewModel.conversations.map(\.id), ["conversation-1"])
    }

    func testSectionListChatPlanRefreshesConversationListFromServer() async {
        let cachedConversation = conversation(
            id: "conversation-1",
            title: "Cached chat",
            updatedAt: "2026-04-26T15:00:00Z"
        )
        let refreshedConversation = conversation(
            id: "conversation-2",
            title: "Refreshed chat",
            updatedAt: "2026-04-26T16:00:00Z"
        )
        let cache = TestCacheClient()
        cache.set(
            key: CacheKeys.conversationsList,
            value: [cachedConversation],
            ttlSeconds: 60
        )
        let api = SequencedConversationsAPI(results: [.success([refreshedConversation])])
        let viewModel = makeViewModel(api: api, cache: cache)
        let adapter = ChatRefreshAdapter(viewModel: viewModel)

        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .realtimeInvalidation,
                targets: [.sectionList(.chat)],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertEqual(viewModel.conversations.map(\.id), ["conversation-2"])
    }

    func testConversationLoadStateTracksFailureAndRecovery() async {
        let conversation = Conversation(
            id: "conversation-1",
            title: "Recovered chat",
            titleGenerated: false,
            createdAt: "2026-04-26T15:00:00Z",
            updatedAt: "2026-04-26T15:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        let api = SequencedConversationsAPI(results: [
            .failure(APIClientError.missingToken),
            .success([conversation])
        ])
        let viewModel = makeViewModel(api: api, cache: TestCacheClient())

        await viewModel.loadConversations(force: true)

        let expectedMessage = ErrorMapping.message(for: APIClientError.missingToken)
        XCTAssertEqual(viewModel.errorMessage, expectedMessage)
        XCTAssertEqual(viewModel.conversationsLoadState, .failed(expectedMessage))
        XCTAssertFalse(viewModel.conversationsLoadState.canShowEmptyState)

        await viewModel.loadConversations(force: true)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.conversationsLoadState, .loaded)
        XCTAssertEqual(viewModel.conversations.map(\.id), ["conversation-1"])
    }
}

private func conversation(id: String, title: String, updatedAt: String) -> Conversation {
    Conversation(
        id: id,
        title: title,
        titleGenerated: false,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        messageCount: 0,
        firstMessage: nil,
        isArchived: false
    )
}

private func XCTAssertNoConversationPollingSource(
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let chatViewModelDirectory = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("ViewModels")
        .appendingPathComponent("Chat")
    let sourceFiles = (try? FileManager.default.contentsOfDirectory(
        at: chatViewModelDirectory,
        includingPropertiesForKeys: nil
    )) ?? []
    let chatViewModelSources = sourceFiles.filter { $0.lastPathComponent.hasPrefix("ChatViewModel") }

    for sourceURL in chatViewModelSources {
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            XCTFail("Failed to read \(sourceURL.lastPathComponent)", file: file, line: line)
            continue
        }
        XCTAssertFalse(source.contains("PollingTask"), sourceURL.lastPathComponent, file: file, line: line)
        XCTAssertFalse(source.contains("refreshTask"), sourceURL.lastPathComponent, file: file, line: line)
        XCTAssertFalse(source.contains("intervalSeconds"), sourceURL.lastPathComponent, file: file, line: line)
        XCTAssertFalse(source.contains("TimeInterval = 30"), sourceURL.lastPathComponent, file: file, line: line)
    }
}

@MainActor
private final class NoopChatRefreshCoordinator: RefreshCoordinatorType {
    func handleActivation(_ request: ActivationRefreshRequest) async {
        _ = request
    }

    func prepareVisibleSectionForPresentation(_ section: AppSection?, canAttemptServerRead: Bool) async {
        _ = section
        _ = canAttemptServerRead
    }

    func hasVisibleDetail(for section: AppSection?) -> Bool {
        section == .chat
    }

    func pinnedSections() -> [AppSection] {
        []
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        _ = trigger
        _ = context
    }

    func scheduleRealtimeInvalidation(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func scheduleDecodeFailureRefresh(section: AppSection, context: RefreshContext) async {
        _ = section
        _ = context
    }

    func scheduleJobTerminalRefresh(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async {
        _ = section
        _ = context
    }
}

@MainActor
private final class SequencedConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    private var results: [Result<[Conversation], Error>]
    private(set) var listCallCount = 0

    init(results: [Result<[Conversation], Error>]) {
        self.results = results
    }

    func list() async throws -> [Conversation] {
        listCallCount += 1
        guard !results.isEmpty else { return [] }
        return try results.removeFirst().get()
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        throw APIClientError.unknown
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return []
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        throw APIClientError.unknown
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        throw APIClientError.unknown
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        _ = message
        throw APIClientError.unknown
    }

    func updateMessage(
        conversationId: String,
        messageId: String,
        message: ConversationMessageCreate
    ) async throws -> Conversation {
        _ = conversationId
        _ = messageId
        _ = message
        throw APIClientError.unknown
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        throw APIClientError.unknown
    }
}
