import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelRealtimeEventTests: ChatViewModelTestCase {
    func testConversationTitleUpdatedEventRefreshesConversationTitleAndOrdering() async throws {
        let fixture = makeConversationTitleUpdateFixture()
        let scheduled = expectation(description: "scheduled conversation invalidation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }

        fixture.viewModel.handle(event: try makeConversationTitleUpdatedEvent())

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(
            fixture.viewModel.chatStore.conversations.first(where: { $0.id == "conv-1" })?.title,
            "Renamed"
        )
        XCTAssertEqual(fixture.viewModel.chatStore.conversationDetails["conv-1"]?.title, "Renamed")
        XCTAssertEqual(fixture.viewModel.groupedConversations.first?.conversations.first?.id, "conv-1")
        XCTAssertEqual(
            fixture.viewModel.conversationUpdatedAtDates["conv-1"],
            DateParsing.parseISO8601("2026-04-19T12:00:00Z")
        )
        XCTAssertEqual(
            fixture.refreshCoordinator.realtimeInvalidations.map(\.change),
            [
                DomainSyncChange(
                    section: .chat,
                    entityId: "conv-1",
                    kind: .detailRefresh,
                    updatedAt: DateParsing.parseISO8601("2026-04-19T12:00:00Z"),
                    requiresListRefresh: true,
                    requiresDetailRefresh: true,
                    canPatchMetadata: false
                )
            ]
        )
        XCTAssertEqual(fixture.refreshCoordinator.realtimeInvalidations.map(\.context), [fixture.refreshContext])
    }

    func testTerminalStreamCompletionSchedulesSharedChatReconciliation() async throws {
        let refreshCoordinator = RecordingRefreshCoordinator()
        let refreshContext = RefreshContext(
            visibleSection: .chat,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )
        let scheduled = expectation(description: "scheduled realtime invalidation")
        refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conv-1"
        viewModel.streamingConversationId = "conv-1"
        viewModel.configureRefreshCoordinator(refreshCoordinator) {
            refreshContext
        }
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Done",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil,
                errorDetails: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.handle(event: ChatStreamEvent(type: .complete, data: nil))

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(
            refreshCoordinator.realtimeInvalidations.map(\.change),
            [
                DomainSyncChange(
                    section: .chat,
                    entityId: "conv-1",
                    kind: .detailRefresh,
                    updatedAt: nil,
                    requiresListRefresh: true,
                    requiresDetailRefresh: true,
                    canPatchMetadata: false
                )
            ]
        )
        XCTAssertEqual(refreshCoordinator.realtimeInvalidations.map(\.context), [refreshContext])
    }

    func testConversationCollectionInvalidationSchedulesChatListRefresh() async throws {
        let fixture = makeRealtimeInvalidationFixture(selectedConversationId: "conv-1")
        let scheduled = expectation(description: "scheduled conversations invalidation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }

        fixture.viewModel.handle(
            event: try makeCollectionInvalidatedEvent(targets: ["conversations"])
        )

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(
            fixture.refreshCoordinator.realtimeInvalidations.map(\.change),
            [
                DomainSyncChange(
                    section: .chat,
                    entityId: nil,
                    kind: .listRefresh,
                    updatedAt: nil,
                    requiresListRefresh: true,
                    requiresDetailRefresh: false,
                    canPatchMetadata: false
                )
            ]
        )
    }

    func testSelectedConversationInvalidationSchedulesChatDetailRefresh() async throws {
        let fixture = makeRealtimeInvalidationFixture(selectedConversationId: "conv-1")
        let scheduled = expectation(description: "scheduled selected conversation invalidation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }

        fixture.viewModel.handle(
            event: try makeCollectionInvalidatedEvent(targets: ["conversation:conv-1"])
        )

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(
            fixture.refreshCoordinator.realtimeInvalidations.map(\.change),
            [
                DomainSyncChange(
                    section: .chat,
                    entityId: "conv-1",
                    kind: .detailRefresh,
                    updatedAt: nil,
                    requiresListRefresh: true,
                    requiresDetailRefresh: true,
                    canPatchMetadata: false
                )
            ]
        )
    }

    func testUnselectedConversationInvalidationSchedulesChatListRefresh() async throws {
        let fixture = makeRealtimeInvalidationFixture(selectedConversationId: "conv-1")
        let scheduled = expectation(description: "scheduled unselected conversation invalidation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }

        fixture.viewModel.handle(
            event: try makeCollectionInvalidatedEvent(targets: ["conversation:conv-2"])
        )

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(
            fixture.refreshCoordinator.realtimeInvalidations.map(\.change),
            [
                DomainSyncChange(
                    section: .chat,
                    entityId: "conv-2",
                    kind: .listRefresh,
                    updatedAt: nil,
                    requiresListRefresh: true,
                    requiresDetailRefresh: false,
                    canPatchMetadata: false
                )
            ]
        )
    }

    func testSuppressedTerminalStreamErrorSchedulesSharedChatReconciliation() async throws {
        let fixture = makeStreamingRealtimeFixture()
        let scheduled = expectation(description: "scheduled suppressed error reconciliation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }
        fixture.viewModel.currentStreamMessageVisibility = .hidden
        fixture.viewModel.currentAssistantInitiatedStreamSuppressesErrors = true

        fixture.viewModel.handle(event: ChatStreamEvent(type: .error, data: AnyCodable(["error": "hidden failure"])))

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertTrue(fixture.viewModel.messages.isEmpty)
        XCTAssertNil(fixture.viewModel.errorMessage)
        XCTAssertEqual(fixture.refreshCoordinator.realtimeInvalidations.map(\.change), [terminalDetailChange()])
    }

    func testDiscardedEmptyTerminalErrorSchedulesSharedChatReconciliation() async throws {
        let fixture = makeStreamingRealtimeFixture()
        let scheduled = expectation(description: "scheduled empty error reconciliation")
        fixture.refreshCoordinator.onRealtimeInvalidation = {
            scheduled.fulfill()
        }

        fixture.viewModel.finalizeStreaming(status: .error)

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertTrue(fixture.viewModel.messages.isEmpty)
        XCTAssertEqual(fixture.refreshCoordinator.realtimeInvalidations.map(\.change), [terminalDetailChange()])
    }

    private func makeConversationTitleUpdateFixture() -> ConversationTitleUpdateFixture {
        let refreshCoordinator = RecordingRefreshCoordinator()
        let refreshContext = chatRefreshContext()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conv-1"
        viewModel.configureRefreshCoordinator(refreshCoordinator) {
            refreshContext
        }
        seedConversationTitleUpdateFixture(in: viewModel)
        return ConversationTitleUpdateFixture(
            viewModel: viewModel,
            refreshCoordinator: refreshCoordinator,
            refreshContext: refreshContext
        )
    }

    private func makeRealtimeInvalidationFixture(selectedConversationId: String?) -> RealtimeInvalidationFixture {
        let refreshCoordinator = RecordingRefreshCoordinator()
        let refreshContext = chatRefreshContext()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = selectedConversationId
        viewModel.configureRefreshCoordinator(refreshCoordinator) {
            refreshContext
        }
        return RealtimeInvalidationFixture(
            viewModel: viewModel,
            refreshCoordinator: refreshCoordinator,
            refreshContext: refreshContext
        )
    }

    private func makeStreamingRealtimeFixture() -> RealtimeInvalidationFixture {
        let fixture = makeRealtimeInvalidationFixture(selectedConversationId: "conv-1")
        fixture.viewModel.streamingConversationId = "conv-1"
        fixture.viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil,
                errorDetails: nil
            )
        ]
        fixture.viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")
        return fixture
    }

    private func seedConversationTitleUpdateFixture(in viewModel: ChatViewModel) {
        viewModel.chatStore.upsertConversation(
            conversation(id: "conv-1", title: "Old title", updatedAt: "2026-01-01T00:00:00Z"),
            persist: false
        )
        viewModel.chatStore.upsertConversation(
            conversation(id: "conv-2", title: "Keep title", updatedAt: "2026-01-02T00:00:00Z"),
            persist: false
        )
        viewModel.chatStore.upsertConversationDetail(
            ConversationWithMessages(
                id: "conv-1",
                title: "Old title",
                titleGenerated: true,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z",
                messageCount: 1,
                firstMessage: "Hello",
                isArchived: nil,
                messages: []
            ),
            persist: false
        )
    }

    private func makeCollectionInvalidatedEvent(targets: [String]) throws -> ChatStreamEvent {
        let encodedTargets = targets.map { #""\#($0)""# }.joined(separator: ",")
        var parser = ChatStreamParser()
        return try XCTUnwrap(
            parser.ingest(
                Data("event: collection_invalidated\ndata: {\"targets\":[\(encodedTargets)]}\n\n".utf8)
            ).first
        )
    }

    private func terminalDetailChange() -> DomainSyncChange {
        DomainSyncChange(
            section: .chat,
            entityId: "conv-1",
            kind: .detailRefresh,
            updatedAt: nil,
            requiresListRefresh: true,
            requiresDetailRefresh: true,
            canPatchMetadata: false
        )
    }

    private func makeConversationTitleUpdatedEvent() throws -> ChatStreamEvent {
        let payload =
            #"{"entity_type":"conversation","entity_id":"conv-1","change":"renamed","# +
            #""patch":{"title":"Renamed","titleGenerated":false,"updatedAt":"2026-04-19T12:00:00Z"},"# +
            #""invalidate":["conversations","conversation:conv-1"]}"#
        var parser = ChatStreamParser()
        return try XCTUnwrap(
            parser.ingest(Data("event: entity_changed\ndata: \(payload)\n\n".utf8)).first
        )
    }

    private func conversation(id: String, title: String, updatedAt: String) -> Conversation {
        Conversation(
            id: id,
            title: title,
            titleGenerated: id == "conv-1",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            messageCount: 1,
            firstMessage: id == "conv-1" ? "Hello" : "Hello again",
            isArchived: nil
        )
    }

    private func chatRefreshContext() -> RefreshContext {
        RefreshContext(
            visibleSection: .chat,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )
    }

    func testWebsiteRenamedEventInvalidatesWebsiteCaches() async throws {
        let cache = TestCacheClient()
        let item = WebsiteItem(
            id: "website-1",
            title: "Old title",
            url: "https://example.com/website-1",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-01-01T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let detail = WebsiteDetail(
            id: "website-1",
            title: "Old title",
            url: "https://example.com/website-1",
            urlFull: nil,
            domain: "example.com",
            content: "Body",
            source: nil,
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-01-01T00:00:00Z",
            lastOpenedAt: nil
        )
        cache.set(
            key: CacheKeys.websitesList,
            value: WebsitesResponse(items: [item], archivedCount: nil, archivedLastUpdated: nil),
            ttlSeconds: 60
        )
        cache.set(
            key: CacheKeys.websiteDetail(id: "website-1"),
            value: detail,
            ttlSeconds: 60
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        let payload =
            #"{"entity_type":"website","entity_id":"website-1","change":"renamed","# +
            #""patch":{"title":"Renamed website"},"invalidate":["websites","website:website-1"]}"#
        var parser = ChatStreamParser()
        let event = try XCTUnwrap(
            parser.ingest(
                Data(
                    """
                    event: entity_changed
                    data: \(payload)


                    """.utf8
                )
            ).first
        )

        viewModel.handle(event: event)

        let cachedList: WebsitesResponse? = cache.get(key: CacheKeys.websitesList)
        let cachedDetail: WebsiteDetail? = cache.get(
            key: CacheKeys.websiteDetail(id: "website-1")
        )
        XCTAssertNil(cachedList)
        XCTAssertNil(cachedDetail)
    }
}

@MainActor
private struct RealtimeInvalidationFixture {
    let viewModel: ChatViewModel
    let refreshCoordinator: RecordingRefreshCoordinator
    let refreshContext: RefreshContext
}

@MainActor
private struct ConversationTitleUpdateFixture {
    let viewModel: ChatViewModel
    let refreshCoordinator: RecordingRefreshCoordinator
    let refreshContext: RefreshContext
}

@MainActor
private final class RecordingRefreshCoordinator: RefreshCoordinatorType {
    private(set) var realtimeInvalidations: [(change: DomainSyncChange, context: RefreshContext)] = []
    var onRealtimeInvalidation: (() -> Void)?

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
        realtimeInvalidations.append((change, context))
        onRealtimeInvalidation?()
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
