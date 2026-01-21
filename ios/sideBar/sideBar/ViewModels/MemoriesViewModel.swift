import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages memory list and selection state.
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
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.memoriesList,
            ttl: CachePolicy.memoriesList
        ) { [api] in
            try await api.list()
        }
        do {
            let (response, _) = try await loader.load(onRefresh: { [weak self] fresh in
                self?.items = fresh
            })
            items = response
        } catch {
            errorMessage = error.localizedDescription
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
