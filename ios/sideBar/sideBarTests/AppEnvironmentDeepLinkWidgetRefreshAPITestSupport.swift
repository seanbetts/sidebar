import Foundation
@testable import sideBar

final class WidgetRefreshWebsitesAPI: WebsitesProviding {
    let items: [WebsiteItem]

    init(items: [WebsiteItem]) {
        self.items = items
    }

    func list() async throws -> WebsitesResponse {
        WebsitesResponse(items: items, archivedCount: 0)
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return WebsitesResponse(items: [], archivedCount: 0)
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw WidgetRefreshWebsitesAPIError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw WidgetRefreshWebsitesAPIError.forced
    }
}

private enum WidgetRefreshWebsitesAPIError: Error {
    case forced
}
