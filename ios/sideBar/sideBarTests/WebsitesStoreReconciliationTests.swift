import XCTest
@testable import sideBar

@MainActor
extension WebsitesStoreTests {
    func testApplyListUpdatePreservesLocallyInsertedWebsiteUntilServerListCatchesUp() async {
        let api = ReconciliationMockWebsitesAPI()
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: makeWidgetDataManager(),
            localListReconciliationWindow: 30
        )
        let local = WebsiteItem(
            id: "local",
            title: "Local Save",
            url: "https://example.com/local",
            domain: "example.com",
            savedAt: "2026-03-13T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "3 min",
            updatedAt: "2026-03-13T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let remote = WebsiteItem(
            id: "remote",
            title: "Remote",
            url: "https://example.com/remote",
            domain: "example.com",
            savedAt: "2026-03-12T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "2 min",
            updatedAt: "2026-03-12T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )

        store.insertItemAtTop(local, persist: false)
        store.applyListUpdate([remote], persist: false)

        XCTAssertEqual(store.items.map(\.id), ["local", "remote"])

        store.applyListUpdate([local, remote], persist: false)

        XCTAssertEqual(store.items.map(\.id), ["local", "remote"])
        XCTAssertTrue(store.reconciliationState.expirations.isEmpty)
    }
}

private final class ReconciliationMockWebsitesAPI: WebsitesProviding {
    func list() async throws -> WebsitesResponse {
        throw ReconciliationMockError.forced
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        throw ReconciliationMockError.forced
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        throw ReconciliationMockError.forced
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw ReconciliationMockError.forced
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw ReconciliationMockError.forced
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw ReconciliationMockError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw ReconciliationMockError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw ReconciliationMockError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw ReconciliationMockError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw ReconciliationMockError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw ReconciliationMockError.forced
    }
}

private enum ReconciliationMockError: Error {
    case forced
}
