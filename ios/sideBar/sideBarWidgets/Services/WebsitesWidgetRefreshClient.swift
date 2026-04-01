import Foundation
import sideBarShared

struct WebsitesWidgetRefreshClient {
    private let apiClient: APIClient

    init(environment: WidgetAPIEnvironment) {
        self.apiClient = environment.apiClient
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refreshSavedWebsites(now: Date = Date()) async throws -> WidgetWebsiteData {
        let response: WebsitesWidgetResponse = try await apiClient.request("websites")
        let activeItems = response.items.filter { !$0.archived && $0.deletedAt == nil }
        let pinnedSites = activeItems
            .filter(\.pinned)
            .sorted {
                if ($0.pinnedOrder ?? Int.max) != ($1.pinnedOrder ?? Int.max) {
                    return ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max)
                }
                return ($0.savedAt ?? "") > ($1.savedAt ?? "")
            }
        let recentSites = activeItems
            .filter { !$0.pinned }
            .sorted { ($0.savedAt ?? "") > ($1.savedAt ?? "") }

        return WidgetWebsiteData(
            websites: Array((pinnedSites + recentSites).map { WidgetWebsite(from: $0) }.prefix(10)),
            totalCount: activeItems.count,
            lastUpdated: now
        )
    }
}

private struct WebsitesWidgetResponse: Decodable {
    let items: [WebsitesWidgetItem]
}

private struct WebsitesWidgetItem: Decodable {
    let id: String
    let title: String
    let url: String
    let domain: String
    let savedAt: String?
    let pinned: Bool
    let pinnedOrder: Int?
    let archived: Bool
    let faviconUrl: String?
    let faviconR2Key: String?
    let deletedAt: String?
}

private extension WidgetWebsite {
    init(from item: WebsitesWidgetItem) {
        self.init(
            id: item.id,
            title: item.title,
            url: item.url,
            domain: item.domain,
            faviconUrl: item.faviconUrl,
            faviconR2Key: item.faviconR2Key,
            pinned: item.pinned,
            pinnedOrder: item.pinnedOrder,
            archived: item.archived
        )
    }
}
