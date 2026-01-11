import Foundation

@MainActor
public final class ChatStore: ObservableObject {
    @Published public private(set) var conversations: [Conversation] = []
    @Published public private(set) var conversationDetails: [String: ConversationWithMessages] = [:]

    private let conversationsAPI: ConversationsProviding
    private let cache: CacheClient

    public init(conversationsAPI: ConversationsProviding, cache: CacheClient) {
        self.conversationsAPI = conversationsAPI
        self.cache = cache
    }

    public func loadConversations(force: Bool = false) async throws {
        if !force, let cached: [Conversation] = cache.get(key: CacheKeys.conversationsList) {
            conversations = cached
            return
        }

        let response = try await conversationsAPI.list()
        let filtered = response.filter { $0.isArchived != true }
        conversations = filtered
        cache.set(key: CacheKeys.conversationsList, value: filtered, ttlSeconds: CachePolicy.conversationsList)
    }

    public func loadConversation(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.conversation(id: id)
        if !force, let cached: ConversationWithMessages = cache.get(key: cacheKey) {
            conversationDetails[id] = cached
            return
        }

        let response = try await conversationsAPI.get(id: id)
        if shouldApplyConversationUpdate(response, cached: conversationDetails[id]) {
            conversationDetails[id] = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.conversationDetail)
        }
    }

    public func reset() {
        conversations = []
        conversationDetails = [:]
    }

    public func updateConversationMessages(
        id: String,
        messages: [Message],
        persist: Bool = false
    ) {
        guard let existing = conversationDetails[id] else {
            return
        }
        let updated = ConversationWithMessages(
            id: existing.id,
            title: existing.title,
            titleGenerated: existing.titleGenerated,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            messageCount: existing.messageCount,
            firstMessage: existing.firstMessage,
            isArchived: existing.isArchived,
            messages: messages
        )
        conversationDetails[id] = updated
        if persist {
            let cacheKey = CacheKeys.conversation(id: id)
            cache.set(key: cacheKey, value: updated, ttlSeconds: CachePolicy.conversationDetail)
        }
    }

    private func shouldApplyConversationUpdate(
        _ response: ConversationWithMessages,
        cached: ConversationWithMessages?
    ) -> Bool {
        guard let cached else {
            return true
        }
        if response.updatedAt == cached.updatedAt && response.messageCount == cached.messageCount {
            return false
        }
        return true
    }
}
}
