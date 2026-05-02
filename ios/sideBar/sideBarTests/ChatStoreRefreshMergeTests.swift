import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class ChatStoreRefreshMergeTests: XCTestCase {
    func testUpdateConversationMessagesRefreshesMessageCount() async {
        let cache = TestCacheClient()
        let api = ChatStoreMockConversationsAPI(
            listResult: .success([]),
            getResult: .failure(ChatStoreMockError.forced)
        )
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
            ),
            Message(
                id: "m2",
                role: .assistant,
                content: "",
                status: .error,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2024-01-01T00:00:01Z",
                error: "The response hit an error. Please try again."
            )
        ]

        store.updateConversationMessages(id: "c1", messages: messages, persist: true)

        XCTAssertEqual(store.conversationDetails["c1"]?.messageCount, 2)
        let cachedDetail: ConversationWithMessages? = cache.get(key: CacheKeys.conversation(id: "c1"))
        XCTAssertEqual(cachedDetail?.messageCount, 2)
    }

    func testLoadConversationPreservesLocalFailedTurnWhenServerSnapshotIsMissingIt() async throws {
        let serverMessages = [
            Message(
                id: "m1",
                role: .assistant,
                content: "Earlier reply",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2024-01-01T00:00:00Z",
                error: nil
            )
        ]
        let localMessages = serverMessages + [
            Message(
                id: "m2",
                role: .user,
                content: "Done",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2024-01-01T00:01:00Z",
                error: nil
            ),
            Message(
                id: "m3",
                role: .assistant,
                content: "",
                status: .error,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2024-01-01T00:01:01Z",
                error: "The response hit an error. Please try again."
            )
        ]
        let cached = ConversationWithMessages(
            id: "c1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-01",
            messageCount: localMessages.count,
            firstMessage: "Earlier reply",
            isArchived: false,
            messages: localMessages
        )
        let fresh = ConversationWithMessages(
            id: "c1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2024-01-01",
            updatedAt: "2024-01-01",
            messageCount: serverMessages.count,
            firstMessage: "Earlier reply",
            isArchived: false,
            messages: serverMessages
        )
        let cache = TestCacheClient()
        let api = ChatStoreMockConversationsAPI(
            listResult: .failure(ChatStoreMockError.forced),
            getResult: .success(fresh)
        )
        let store = ChatStore(conversationsAPI: api, cache: cache)
        store.upsertConversationDetail(cached, persist: true)

        try await store.loadConversation(id: "c1", force: true)

        XCTAssertEqual(store.conversationDetails["c1"]?.messages.map(\.id), ["m1", "m2", "m3"])
        XCTAssertEqual(store.conversationDetails["c1"]?.messageCount, 3)
        let cachedDetail: ConversationWithMessages? = cache.get(key: CacheKeys.conversation(id: "c1"))
        XCTAssertEqual(cachedDetail?.messages.map(\.id), ["m1", "m2", "m3"])
    }
}
