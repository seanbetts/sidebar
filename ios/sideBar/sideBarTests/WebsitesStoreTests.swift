import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesStoreTests: XCTestCase {
    func testLoadListUsesOfflineStoreWhenCacheMissing() async {
        let item = WebsiteItem(
            id: "w1",
            title: "Offline",
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let response = WebsitesResponse(items: [item], archivedCount: nil, archivedLastUpdated: nil)
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(key: CacheKeys.websitesList, entityType: "websitesList", value: response, lastSyncAt: nil)
        let cache = TestCacheClient()
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = WebsitesStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        try? await store.loadList()

        XCTAssertEqual(store.items.first?.id, "w1")
    }

    func testLoadDetailOfflineArchivedShowsError() async {
        let item = WebsiteItem(
            id: "w1",
            title: "Archived",
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: true,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let cache = TestCacheClient()
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let store = WebsitesStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
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

    func testConcurrentArchivedRefreshTimesOutInsteadOfWaitingIndefinitely() async {
        let item = WebsiteItem(
            id: "w1",
            title: "Example",
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let response = WebsitesResponse(items: [item], archivedCount: 1, archivedLastUpdated: "2024-01-01")
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: 60)
        let api = MockWebsitesAPI(listResult: .success(response), getResult: .failure(MockError.forced))
        api.archivedListDelay = 0.12

        let store = WebsitesStore(
            api: api,
            cache: cache,
            archivedRefreshWaitTimeoutNanoseconds: 50_000_000,
            archivedRefreshPollIntervalNanoseconds: 10_000_000
        )

        let firstRefresh = Task {
            await store.loadArchivedList(force: true)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        let start = Date()
        await store.loadArchivedList()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1)
        await firstRefresh.value
    }

    func testApplyRealtimeDeleteRemovesItemAndCache() async {
        let item = WebsiteItem(
            id: "w1",
            title: "Example",
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let detail = WebsiteDetail(
            id: "w1",
            title: "Example",
            url: "https://example.com",
            urlFull: nil,
            domain: "example.com",
            content: "Body",
            source: nil,
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil
        )
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.websitesList, value: WebsitesResponse(items: [item]), ttlSeconds: 60)
        cache.set(key: CacheKeys.websiteDetail(id: "w1"), value: detail, ttlSeconds: 60)
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: cache)
        store.updateListItem(item, persist: false)
        try? await store.loadDetail(id: "w1")

        let payload = RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .delete,
            table: RealtimeTable.websites,
            schema: "public",
            record: nil,
            oldRecord: WebsiteRealtimeRecord(
                id: "w1",
                title: nil,
                url: nil,
                domain: nil,
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: nil,
                lastOpenedAt: nil,
                deletedAt: nil
            )
        )

        store.applyRealtimeEvent(payload)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.active)
        let cached: WebsiteDetail? = cache.get(key: CacheKeys.websiteDetail(id: "w1"))
        XCTAssertNil(cached)
    }

    func testApplyRealtimeUpdatePreservesPinnedAndArchivedWhenMetadataMissing() async {
        let existing = WebsiteItem(
            id: "w1",
            title: "Original",
            url: "https://example.com/original",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: true,
            pinnedOrder: 7,
            archived: true,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: TestCacheClient())
        store.updateListItem(existing, persist: false)

        let payload = RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "w1",
                title: "Updated",
                url: "https://example.com/updated",
                domain: "example.com",
                metadata: nil,
                savedAt: "2024-01-02",
                publishedAt: nil,
                readingTime: "5 min",
                updatedAt: "2024-01-02",
                lastOpenedAt: "2024-01-02",
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyRealtimeEvent(payload)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].title, "Updated")
        XCTAssertEqual(store.items[0].pinned, true)
        XCTAssertEqual(store.items[0].pinnedOrder, 7)
        XCTAssertEqual(store.items[0].archived, true)
    }

    func testApplyRealtimeUpdateUsesExplicitPinnedMetadataAndPreservesArchivedWhenMissing() async {
        let existing = WebsiteItem(
            id: "w1",
            title: "Original",
            url: "https://example.com/original",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: true,
            pinnedOrder: 3,
            archived: true,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: TestCacheClient())
        store.updateListItem(existing, persist: false)

        let payload = RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "w1",
                title: "Updated",
                url: "https://example.com/updated",
                domain: "example.com",
                metadata: [
                    "pinned": AnyCodable(false),
                    "pinned_order": AnyCodable(NSNull())
                ],
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2024-01-02",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyRealtimeEvent(payload)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].pinned, false)
        XCTAssertNil(store.items[0].pinnedOrder)
        XCTAssertEqual(store.items[0].archived, true)
    }

    func testApplyRealtimeUpdateUsesExplicitArchivedMetadata() async {
        let existing = WebsiteItem(
            id: "w1",
            title: "Original",
            url: "https://example.com/original",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: true,
            pinnedOrder: 3,
            archived: true,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced), getResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: TestCacheClient())
        store.updateListItem(existing, persist: false)

        let payload = RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "w1",
                title: "Updated",
                url: "https://example.com/updated",
                domain: "example.com",
                metadata: [
                    "archived": AnyCodable(false)
                ],
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2024-01-02",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyRealtimeEvent(payload)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].pinned, true)
        XCTAssertEqual(store.items[0].pinnedOrder, 3)
        XCTAssertEqual(store.items[0].archived, false)
    }
}

private enum MockError: Error {
    case forced
}

private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
}

private final class MockWebsitesAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>
    var archivedListDelay: TimeInterval?

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
        if let archivedListDelay {
            try? await Task.sleep(nanoseconds: UInt64(archivedListDelay * 1_000_000_000))
        }
        return try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        _ = url
        throw MockError.forced
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw MockError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw MockError.forced
    }
}
