import Foundation
import XCTest
@testable import sideBar

@MainActor
final class WebsitesStoreOfflineDetailTests: XCTestCase {
    func testLoadDetailOfflineArchivedShowsError() async {
        let item = makeItem(id: "w1", title: "Archived", archived: true)
        let cache = TestCacheClient()
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: makeWidgetDataManager(),
            offlineStore: offlineStore,
            networkStatus: WebsitesStoreTestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
        store.updateListItem(item, persist: false)

        do {
            try await store.loadDetail(id: "w1")
            XCTFail("Expected offline detail error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "This archived website hasn't been cached yet. Go online to load it."
            )
        }
    }

    func testLoadDetailTreatsServerUnreachableAsOfflineWhenDetailMissing() async {
        let item = makeItem(id: "w1", title: "Offline")
        let cache = TestCacheClient()
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: makeWidgetDataManager(),
            offlineStore: offlineStore,
            networkStatus: WebsitesStoreTestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )
        store.updateListItem(item, persist: false)

        do {
            try await store.loadDetail(id: "w1")
            XCTFail("Expected offline detail error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "This website isn't available offline."
            )
        }
    }

    private func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "WebsitesStoreOfflineDetailTests.\(UUID().uuidString)"
            )!
        )
    }

    private func makeItem(id: String, title: String, archived: Bool = false) -> WebsiteItem {
        WebsiteItem(
            id: id,
            title: title,
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: archived,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }
}
