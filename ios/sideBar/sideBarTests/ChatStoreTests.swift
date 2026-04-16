import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class ChatStoreTests: XCTestCase {
    func testLoadConversationsUsesCacheThenRefreshes() async {
        let cached = [
            Conversation(
                id: "c1",
                title: "Cached",
                titleGenerated: false,
                createdAt: "2024-01-01",
                updatedAt: "2024-01-01",
                messageCount: 1,
                firstMessage: "Hello",
                isArchived: false
            )
        ]
        let fresh = [
            Conversation(
                id: "c1",
                title: "Fresh",
                titleGenerated: false,
                createdAt: "2024-01-01",
                updatedAt: "2024-01-02",
                messageCount: 2,
                firstMessage: "Hi",
                isArchived: false
            )
        ]
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversationsList, value: cached, ttlSeconds: 60)
        let api = MockConversationsAPI(listResult: .success(fresh), getResult: .failure(MockError.forced))
        api.listDelay = 0.05
        let listExpectation = expectation(description: "list refresh")
        api.onList = {
            listExpectation.fulfill()
        }
        let store = ChatStore(conversationsAPI: api, cache: cache)

        try? await store.loadConversations()

        XCTAssertEqual(store.conversations.first?.title, "Cached")
        await fulfillment(of: [listExpectation], timeout: 1.0)
        XCTAssertEqual(store.conversations.first?.title, "Fresh")
    }

    func testLoadConversationUsesCacheThenRefreshes() async throws {
        let cached = ConversationWithMessages(
            id: "c1",
            title: "Cached",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-01",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: false,
            messages: []
        )
        let fresh = ConversationWithMessages(
            id: "c1",
            title: "Fresh",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-02",
            messageCount: 2,
            firstMessage: "Hello",
            isArchived: false,
            messages: []
        )
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversation(id: "c1"), value: cached, ttlSeconds: 60)
        let api = MockConversationsAPI(listResult: .failure(MockError.forced), getResult: .success(fresh))
        api.getDelay = 0.05
        let getExpectation = expectation(description: "detail refresh")
        api.onGet = {
            getExpectation.fulfill()
        }
        let store = ChatStore(conversationsAPI: api, cache: cache)

        try await store.loadConversation(id: "c1")

        XCTAssertEqual(store.conversationDetails["c1"]?.title, "Cached")
        await fulfillment(of: [getExpectation], timeout: 1.0)
        XCTAssertEqual(store.conversationDetails["c1"]?.title, "Fresh")
    }

    func testLoadConversationRefreshesWhenCachedMessagesAreEmptyButMetadataMatches() async throws {
        let cached = ConversationWithMessages(
            id: "c1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-02",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: false,
            messages: []
        )
        let fresh = ConversationWithMessages(
            id: "c1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-02",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: false,
            messages: [
                Message(
                    id: "m1",
                    role: .assistant,
                    content: "Hello from server",
                    status: .complete,
                    toolCalls: nil,
                    needsNewline: nil,
                    timestamp: "2024-01-02T00:00:00Z",
                    error: nil
                )
            ]
        )
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversation(id: "c1"), value: cached, ttlSeconds: 60)
        let api = MockConversationsAPI(listResult: .failure(MockError.forced), getResult: .success(fresh))
        api.getDelay = 0.05
        let getExpectation = expectation(description: "detail refresh")
        api.onGet = {
            getExpectation.fulfill()
        }
        let store = ChatStore(conversationsAPI: api, cache: cache)

        try await store.loadConversation(id: "c1")

        XCTAssertTrue(store.conversationDetails["c1"]?.messages.isEmpty == true)
        await fulfillment(of: [getExpectation], timeout: 1.0)
        XCTAssertEqual(store.conversationDetails["c1"]?.messages.count, 1)
        XCTAssertEqual(store.conversationDetails["c1"]?.messages.first?.content, "Hello from server")
    }

    func testUpdateConversationMessagesPersistsMessagesCache() async {
        let cache = TestCacheClient()
        let api = MockConversationsAPI(listResult: .success([]), getResult: .failure(MockError.forced))
        let store = ChatStore(conversationsAPI: api, cache: cache)
        let detail = ConversationWithMessages(
            id: "c1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-01",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false,
            messages: []
        )
        store.upsertConversationDetail(detail, persist: true)

        let messages = [
            Message(
                id: "m1",
                role: .user,
                content: "Hello",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2024-01-01T00:00:00Z",
                error: nil
            )
        ]
        store.updateConversationMessages(id: "c1", messages: messages, persist: true)

        let cached: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "c1"))
        XCTAssertEqual(cached?.count, 1)
        XCTAssertEqual(cached?.first?.id, "m1")
        XCTAssertEqual(cached?.first?.content, "Hello")
    }

    func testConcurrentLoadConversationsSharesOneUnderlyingListRequest() async {
        let conversations = [
            Conversation(
                id: "c1",
                title: "Fresh",
                titleGenerated: false,
                createdAt: "2024-01-01",
                updatedAt: "2024-01-02",
                messageCount: 1,
                firstMessage: "Hi",
                isArchived: false
            )
        ]
        let cache = TestCacheClient()
        let api = MockConversationsAPI(listResult: .success(conversations), getResult: .failure(MockError.forced))
        api.listDelay = 0.05
        let store = ChatStore(conversationsAPI: api, cache: cache)

        async let first: Void = store.loadConversations()
        async let second: Void = store.loadConversations()
        _ = try? await (first, second)

        XCTAssertEqual(api.listCallCount, 1)
        XCTAssertEqual(store.conversations.map(\.id), ["c1"])
    }

    func testLoadConversationsUsesOfflineSnapshotWhenServerUnreachable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cached = [
            Conversation(
                id: "c-offline",
                title: "Offline",
                titleGenerated: false,
                createdAt: "2024-01-01",
                updatedAt: "2024-01-01",
                messageCount: 1,
                firstMessage: "Hello",
                isArchived: false
            )
        ]
        offlineStore.set(
            key: CacheKeys.conversationsList,
            entityType: "conversationsList",
            value: cached,
            lastSyncAt: nil
        )
        let api = MockConversationsAPI(listResult: .success([]), getResult: .failure(MockError.forced))
        let store = ChatStore(
            conversationsAPI: api,
            cache: TestCacheClient(),
            offlineStore: offlineStore,
            networkStatus: StoreNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )

        try await store.loadConversations()

        XCTAssertEqual(store.conversations.first?.id, "c-offline")
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testLoadConversationUsesOfflineSnapshotWhenServerUnreachable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let detail = ConversationWithMessages(
            id: "c-offline",
            title: "Offline",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-01",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: false,
            messages: [
                Message(
                    id: "m1",
                    role: .assistant,
                    content: "Hello",
                    status: .complete,
                    toolCalls: nil,
                    needsNewline: nil,
                    timestamp: "2024-01-01T00:00:00Z",
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
        let api = MockConversationsAPI(listResult: .success([]), getResult: .failure(MockError.forced))
        let store = ChatStore(
            conversationsAPI: api,
            cache: TestCacheClient(),
            offlineStore: offlineStore,
            networkStatus: StoreNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )

        try await store.loadConversation(id: detail.id)

        XCTAssertEqual(store.conversationDetails[detail.id]?.messages.first?.content, "Hello")
        XCTAssertEqual(api.getCallCount, 0)
    }
}

private enum MockError: Error {
    case forced
}

private struct StoreNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool
}

private final class MockConversationsAPI: ConversationsProviding {
    let listResult: Result<[Conversation], Error>
    let getResult: Result<ConversationWithMessages, Error>
    var listCallCount = 0
    var getCallCount = 0
    var onList: (() -> Void)?
    var onGet: (() -> Void)?
    var listDelay: TimeInterval?
    var getDelay: TimeInterval?

    init(
        listResult: Result<[Conversation], Error>,
        getResult: Result<ConversationWithMessages, Error>
    ) {
        self.listResult = listResult
        self.getResult = getResult
    }

    func list() async throws -> [Conversation] {
        listCallCount += 1
        if let listDelay {
            try? await Task.sleep(nanoseconds: UInt64(listDelay * 1_000_000_000))
        }
        onList?()
        return try listResult.get()
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        getCallCount += 1
        if let getDelay {
            try? await Task.sleep(nanoseconds: UInt64(getDelay * 1_000_000_000))
        }
        onGet?()
        return try getResult.get()
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return []
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        throw MockError.forced
    }
}
