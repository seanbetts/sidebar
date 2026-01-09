import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class ScratchpadViewModel: ObservableObject {
    @Published public private(set) var scratchpad: ScratchpadResponse? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: any ScratchpadProviding
    private let cache: CacheClient

    public init(api: any ScratchpadProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        errorMessage = nil
        let cached: ScratchpadResponse? = cache.get(key: CacheKeys.scratchpad)
        if let cached {
            scratchpad = cached
        }
        do {
            let response = try await api.get()
            scratchpad = response
            cache.set(key: CacheKeys.scratchpad, value: response, ttlSeconds: CachePolicy.scratchpad)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func update(content: String, mode: ScratchpadMode? = nil) async {
        errorMessage = nil
        do {
            let response = try await api.update(content: content, mode: mode)
            scratchpad = response
            cache.set(key: CacheKeys.scratchpad, value: response, ttlSeconds: CachePolicy.scratchpad)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
