import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class MemoriesViewModel: ObservableObject {
    @Published public private(set) var items: [MemoryItem] = []
    @Published public private(set) var active: MemoryItem? = nil
    @Published public private(set) var selectedMemoryId: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingDetail: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any MemoriesProviding
    private let cache: CacheClient

    public init(api: any MemoriesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        errorMessage = nil
        isLoading = true
        let cached: [MemoryItem]? = cache.get(key: CacheKeys.memoriesList)
        if let cached {
            items = cached
        }
        do {
            let response = try await api.list()
            items = response
            cache.set(key: CacheKeys.memoriesList, value: response, ttlSeconds: CachePolicy.memoriesList)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func selectMemory(id: String) async {
        errorMessage = nil
        selectedMemoryId = id
        if let cached = items.first(where: { $0.id == id }) {
            active = cached
            return
        }
        isLoadingDetail = true
        do {
            active = try await api.get(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingDetail = false
    }
}
