import Foundation
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages memory list and selection state.
public final class MemoriesViewModel: LoadableViewModel {
    @Published public private(set) var items: [MemoryItem] = []
    @Published public private(set) var active: MemoryItem?
    @Published public private(set) var selectedMemoryId: String?
    @Published public private(set) var isLoadingDetail: Bool = false

    private let api: any MemoriesProviding
    private let cache: CacheClient

    public init(api: any MemoriesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.memoriesList,
            ttl: CachePolicy.memoriesList
        ) { [api] in
            try await api.list()
        }
        await withLoading({
            try await loader.load(onRefresh: { [weak self] fresh in
                self?.items = fresh
            })
        }, onSuccess: { [weak self] (response, _) in
            self?.items = response
        })
    }

    public func selectMemory(id: String) async {
        clearError()
        selectedMemoryId = id
        if let cached = items.first(where: { $0.id == id }) {
            active = cached
            return
        }
        isLoadingDetail = true
        do {
            active = try await api.get(id: id)
        } catch {
            setError(error)
        }
        isLoadingDetail = false
    }
}
