import Foundation

@MainActor
public final class IngestionStore: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil

    private let api: any IngestionProviding
    private let cache: CacheClient

    public init(api: any IngestionProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadList(force: Bool = false) async throws {
        if !force, let cached: IngestionListResponse = cache.get(key: CacheKeys.ingestionList) {
            items = cached.items
            return
        }
        let response = try await api.list()
        items = response.items
        cache.set(key: CacheKeys.ingestionList, value: response, ttlSeconds: CachePolicy.ingestionList)
    }

    public func loadMeta(fileId: String) async throws {
        let response = try await api.getMeta(fileId: fileId)
        activeMeta = response
    }

    public func invalidateList() {
        cache.remove(key: CacheKeys.ingestionList)
    }

    public func clearActiveMeta() {
        activeMeta = nil
    }

    public func reset() {
        items = []
        activeMeta = nil
    }
}
