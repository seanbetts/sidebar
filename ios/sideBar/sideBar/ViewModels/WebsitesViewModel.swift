import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WebsitesViewModel: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any WebsitesProviding
    private let cache: CacheClient

    public init(api: any WebsitesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        let cached: WebsitesResponse? = cache.get(key: CacheKeys.websitesList)
        if let cached {
            items = cached.items
        }
        do {
            let response = try await api.list()
            items = response.items
            cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadById(id: String) async {
        errorMessage = nil
        let cacheKey = CacheKeys.websiteDetail(id: id)
        let cached: WebsiteDetail? = cache.get(key: cacheKey)
        if let cached {
            active = cached
        }
        do {
            let response = try await api.get(id: id)
            active = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.websiteDetail)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}
