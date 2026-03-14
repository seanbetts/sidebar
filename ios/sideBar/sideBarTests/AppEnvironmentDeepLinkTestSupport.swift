import Foundation
@testable import sideBar

final class DeepLinkWebsitesAPI: WebsitesProviding {
    let saveResult: Result<WebsiteSaveResponse, Error>
    let detailResult: Result<WebsiteDetail, Error>
    let listResult: Result<WebsitesResponse, Error>
    private(set) var lastSavedURL: String?
    private(set) var listCallCount = 0

    init(
        saveResult: Result<WebsiteSaveResponse, Error>,
        listResult: Result<WebsitesResponse, Error> = .success(
            WebsitesResponse(items: [], archivedCount: 0)
        ),
        detailResult: Result<WebsiteDetail, Error> = .failure(DeepLinkWebsitesAPIError.forced)
    ) {
        self.saveResult = saveResult
        self.listResult = listResult
        self.detailResult = detailResult
    }

    func list() async throws -> WebsitesResponse {
        listCallCount += 1
        return try listResult.get()
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return WebsitesResponse(items: [], archivedCount: 0)
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try detailResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        lastSavedURL = url
        return try saveResult.get()
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw DeepLinkWebsitesAPIError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw DeepLinkWebsitesAPIError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw DeepLinkWebsitesAPIError.forced
    }
}

private enum DeepLinkWebsitesAPIError: Error {
    case forced
}
