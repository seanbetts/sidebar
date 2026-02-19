import Foundation
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages scratchpad content and updates.
public final class ScratchpadViewModel: ObservableObject {
    @Published public private(set) var scratchpad: ScratchpadResponse?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var refreshVersion: Int = 0

    private let api: any ScratchpadProviding
    private let cache: CacheClient
    private var cancellables = Set<AnyCancellable>()

    public init(
        api: any ScratchpadProviding,
        cache: CacheClient,
        scratchpadStore: ScratchpadStore? = nil
    ) {
        self.api = api
        self.cache = cache
        scratchpadStore?.$version
            .sink { [weak self] version in
                self?.refreshVersion = version
            }
            .store(in: &cancellables)
    }

    public func cachedScratchpad() -> ScratchpadResponse? {
        cache.get(key: CacheKeys.scratchpad)
    }

    public func load() async {
        errorMessage = nil
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.scratchpad,
            ttl: CachePolicy.scratchpad
        ) { [api] in
            try await api.get()
        }
        do {
            let (response, _) = try await loader.load(onRefresh: { [weak self] fresh in
                self?.scratchpad = fresh
            })
            scratchpad = response
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    public func update(content: String, mode: ScratchpadMode? = nil) async {
        errorMessage = nil
        do {
            let response = try await api.update(content: content, mode: mode)
            scratchpad = response
            cache.set(key: CacheKeys.scratchpad, value: response, ttlSeconds: CachePolicy.scratchpad)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}
