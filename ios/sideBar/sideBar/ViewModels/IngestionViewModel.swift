import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class IngestionViewModel: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: any IngestionProviding
    private let cache: CacheClient

    public init(api: any IngestionProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        errorMessage = nil
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        if let cached {
            items = cached.items
        }
        do {
            let response = try await api.list()
            items = response.items
            cache.set(key: CacheKeys.ingestionList, value: response, ttlSeconds: CachePolicy.ingestionList)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadMeta(fileId: String) async {
        errorMessage = nil
        do {
            activeMeta = try await api.getMeta(fileId: fileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
