import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesStoreWidgetDataTests: XCTestCase {
    private func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "WebsitesStoreWidgetDataTests.\(UUID().uuidString)"
            )!
        )
    }

    func testUpdateWidgetDataPrefersPinnedSitesAndFallsBackToRecentSavedSites() async {
        let api = WebsitesWidgetDataMockAPI(
            listResult: .failure(WebsitesWidgetDataMockError.forced),
            getResult: .failure(WebsitesWidgetDataMockError.forced)
        )
        let store = WebsitesStore(api: api, cache: TestCacheClient())
        let items = [
            WebsiteItem(
                id: "recent",
                title: "Recent",
                url: "https://example.com/recent",
                domain: "example.com",
                savedAt: "2026-03-12T11:00:00Z",
                publishedAt: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-12T11:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            WebsiteItem(
                id: "pinned",
                title: "Pinned",
                url: "https://example.com/pinned",
                domain: "example.com",
                savedAt: "2026-03-11T10:00:00Z",
                publishedAt: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-11T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            )
        ]

        let snapshot = store.makeWidgetData(from: items)

        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.websites.map(\.id), ["pinned", "recent"])
    }

    func testApplyListUpdateRepairsWidgetSnapshotEvenWhenListIsUnchanged() async {
        let api = WebsitesWidgetDataMockAPI(
            listResult: .failure(WebsitesWidgetDataMockError.forced),
            getResult: .failure(WebsitesWidgetDataMockError.forced)
        )
        let widgetDataManager = makeWidgetDataManager()
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: widgetDataManager
        )
        let items = [
            WebsiteItem(
                id: "pinned",
                title: "Pinned",
                url: "https://example.com/pinned",
                domain: "example.com",
                savedAt: "2026-03-11T10:00:00Z",
                publishedAt: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-11T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            )
        ]

        store.applyListUpdate(items, persist: false)
        widgetDataManager.store(WidgetWebsiteData.empty, for: .websites)

        store.applyListUpdate(items, persist: false)

        let snapshot: WidgetWebsiteData = widgetDataManager.load(for: .websites)
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.websites.map(\.id), ["pinned"])
    }
}

private enum WebsitesWidgetDataMockError: Error {
    case forced
}

private final class WebsitesWidgetDataMockAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>

    init(listResult: Result<WebsitesResponse, Error>, getResult: Result<WebsiteDetail, Error>) {
        self.listResult = listResult
        self.getResult = getResult
    }

    func list() async throws -> WebsitesResponse {
        try listResult.get()
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        _ = url
        throw WebsitesWidgetDataMockError.forced
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw WebsitesWidgetDataMockError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw WebsitesWidgetDataMockError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw WebsitesWidgetDataMockError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw WebsitesWidgetDataMockError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw WebsitesWidgetDataMockError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw WebsitesWidgetDataMockError.forced
    }
}
