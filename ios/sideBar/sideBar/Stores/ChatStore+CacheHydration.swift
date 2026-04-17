import Foundation

extension ChatStore {
    func hydrateConversationsFromCache() async {
        if let cached: [Conversation] = cache.get(key: cacheKey) {
            applyData(cached, persist: false)
            return
        }
        await loadFromOffline()
    }
}
