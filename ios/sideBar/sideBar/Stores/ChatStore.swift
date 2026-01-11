import Foundation
import Combine

@MainActor
public final class ChatStore: ObservableObject {
    @Published public private(set) var conversations: [Conversation] = []
    @Published public private(set) var conversationDetails: [String: ConversationWithMessages] = [:]

    private let conversationsAPI: ConversationsProviding
    private let cache: CacheClient
    private var isRefreshingList = false

    public init(conversationsAPI: ConversationsProviding, cache: CacheClient) {
        self.conversationsAPI = conversationsAPI
        self.cache = cache
    }

    public func loadConversations(force: Bool = false) async throws {
        let cached: [Conversation]? = force ? nil : cache.get(key: CacheKeys.conversationsList)
        if let cached {
            applyConversationListUpdate(cached, persist: false)
            Task { [weak self] in
                await self?.refreshConversationsList()
            }
            return
        }

        let response = try await conversationsAPI.list()
        let filtered = response.filter { $0.isArchived != true }
        applyConversationListUpdate(filtered, persist: true)
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

    private func refreshConversationsList() async {
        guard !isRefreshingList else {
            return
        }
        isRefreshingList = true
        defer { isRefreshingList = false }
        do {
            let response = try await conversationsAPI.list()
            let filtered = response.filter { $0.isArchived != true }
            applyConversationListUpdate(filtered, persist: true)
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    private func applyConversationListUpdate(_ incoming: [Conversation], persist: Bool) {
        guard shouldUpdateConversationList(incoming) else {
            return
        }
        conversations = incoming
        if persist {
            cache.set(key: CacheKeys.conversationsList, value: incoming, ttlSeconds: CachePolicy.conversationsList)
        }
    }

    private func shouldUpdateConversationList(_ incoming: [Conversation]) -> Bool {
        guard conversations.count == incoming.count else {
            return true
        }
        let existing = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        for item in incoming {
            guard let current = existing[item.id] else {
                return true
            }
            if current.updatedAt != item.updatedAt
                || current.messageCount != item.messageCount
                || current.title != item.title
                || current.isArchived != item.isArchived
                || current.firstMessage != item.firstMessage {
                return true
            }
        }
        return false
    }
}
