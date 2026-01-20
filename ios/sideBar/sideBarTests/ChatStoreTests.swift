import Foundation
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

    func testLoadConversationUsesCache() async throws {
        let detail = ConversationWithMessages(
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
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversation(id: "c1"), value: detail, ttlSeconds: 60)
        let api = MockConversationsAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = ChatStore(conversationsAPI: api, cache: cache)

        try await store.loadConversation(id: "c1")

        XCTAssertEqual(store.conversationDetails["c1"]?.title, "Cached")
        XCTAssertEqual(api.getCallCount, 0)
    }
}

private enum MockError: Error {
    case forced
}

private final class MockConversationsAPI: ConversationsProviding {
    let listResult: Result<[Conversation], Error>
    let getResult: Result<ConversationWithMessages, Error>
    var listCallCount = 0
    var getCallCount = 0
    var onList: (() -> Void)? = nil
    var listDelay: TimeInterval? = nil

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
