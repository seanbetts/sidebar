// swiftlint:disable file_length
import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesStoreTests: XCTestCase {
    func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "WebsitesStoreTests.\(UUID().uuidString)"
            )!
        )
    }

    func testApplyPinnedOrderUpdatesPinnedRowsAndWidgetOrder() async {
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let widgetDataManager = makeWidgetDataManager()
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: widgetDataManager
        )

        store.updateListItem(
            makeWebsiteItem(
                id: "w1",
                pinned: true,
                pinnedOrder: 0,
                savedAt: "2026-03-21T10:00:00Z"
            ),
            persist: false
        )
        store.updateListItem(
            makeWebsiteItem(
                id: "w2",
                pinned: true,
                pinnedOrder: 1,
                savedAt: "2026-03-21T11:00:00Z"
            ),
            persist: false
        )
        store.updateListItem(
            makeWebsiteItem(
                id: "w3",
                pinned: false,
                pinnedOrder: nil,
                savedAt: "2026-03-21T12:00:00Z"
            ),
            persist: false
        )

        let previousOrder = store.pinnedWebsiteOrder()

        store.applyPinnedOrder(["w2", "w1"])

        XCTAssertEqual(
            store.items.filter(\.pinned).sorted(by: byPinnedOrder).map(\.id),
            ["w2", "w1"]
        )
        let snapshot: WidgetWebsiteData = widgetDataManager.load(for: .websites)
        XCTAssertEqual(
            snapshot.websites.map(\.id),
            ["w2", "w1", "w3"]
        )

        store.applyPinnedOrder(previousOrder)

        let restoredSnapshot: WidgetWebsiteData = widgetDataManager.load(for: .websites)
        XCTAssertEqual(
            restoredSnapshot.websites.map(\.id),
            ["w1", "w2", "w3"]
        )
    }

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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: makeWidgetDataManager(),
            offlineStore: offlineStore,
            networkStatus: WebsitesStoreTestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        try? await store.loadList()

        XCTAssertEqual(store.items.first?.id, "w1")
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
        let api = WebsitesStoreMockWebsitesAPI(listResult: .success(response), getResult: .failure(WebsitesStoreMockError.forced))
        api.archivedListDelay = 0.5

        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: makeWidgetDataManager(),
            archivedRefreshWaitTimeoutNanoseconds: 50_000_000,
            archivedRefreshPollIntervalNanoseconds: 10_000_000
        )

        let firstRefresh = Task {
            await store.loadArchivedList(force: true)
        }
        try? await waitUntilWebsitesStoreConditionMet(timeoutSeconds: 1.0) {
            await api.archivedListCallCount > 0
        }

        let start = Date()
        await store.loadArchivedList()
        let elapsed = Date().timeIntervalSince(start)
        let archivedListCallCount = await api.archivedListCallCount

        XCTAssertLessThan(elapsed, 0.25)
        XCTAssertEqual(archivedListCallCount, 1)
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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
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

    func testApplyRealtimeSoftDeleteUpdateRemovesItemAndCache() async {
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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(api: api, cache: cache)
        store.updateListItem(item, persist: false)
        try? await store.loadDetail(id: "w1")

        let payload = RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "w1",
                title: "Example",
                url: "https://example.com",
                domain: "example.com",
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2024-01-02",
                lastOpenedAt: nil,
                deletedAt: "2024-01-02T00:00:00Z"
            ),
            oldRecord: nil
        )

        store.applyRealtimeEvent(payload)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.active)
        let cached: WebsiteDetail? = cache.get(key: CacheKeys.websiteDetail(id: "w1"))
        XCTAssertNil(cached)
    }

    func testPrefetchArchivedDetailsFetchesOnlyRetainedUncachedItems() async {
        let retainedUpdatedAt = ISO8601DateFormatter().string(from: Date())
        let expiredUpdatedAt = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        let retainedItem = makeWebsiteItem(id: "retained", archived: true, updatedAt: retainedUpdatedAt)
        let cachedRetainedItem = makeWebsiteItem(id: "cached", archived: true, updatedAt: retainedUpdatedAt)
        let expiredItem = makeWebsiteItem(id: "expired", archived: true, updatedAt: expiredUpdatedAt)
        let malformedItem = makeWebsiteItem(id: "malformed", archived: true, updatedAt: "not-a-date")
        let nilDateItem = makeWebsiteItem(id: "nil-date", archived: true, updatedAt: nil)
        let activeItem = makeWebsiteItem(id: "active", archived: false, updatedAt: retainedUpdatedAt)
        let detail = makeWebsiteDetail(id: "retained", archived: true, updatedAt: retainedUpdatedAt)
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.websiteDetail(id: "cached"), value: detail, ttlSeconds: 60)
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .success(detail)
        )
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: makeWidgetDataManager()
        )

        await store.prefetchArchivedDetails(from: [
            retainedItem,
            cachedRetainedItem,
            expiredItem,
            malformedItem,
            nilDateItem,
            activeItem
        ])

        let requestedIDs = await api.requestedDetailIDs
        XCTAssertEqual(requestedIDs, ["retained"])
    }

}

private extension WebsitesStoreTests {
    func byPinnedOrder(_ lhs: WebsiteItem, _ rhs: WebsiteItem) -> Bool {
        let leftOrder = lhs.pinnedOrder ?? Int.max
        let rightOrder = rhs.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return lhs.id < rhs.id
    }

    func makeWebsiteItem(id: String, archived: Bool, updatedAt: String?) -> WebsiteItem {
        WebsiteItem(
            id: id,
            title: id.capitalized,
            url: "https://example.com/\(id)",
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
            updatedAt: updatedAt,
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }

    func makeWebsiteItem(
        id: String,
        pinned: Bool,
        pinnedOrder: Int?,
        savedAt: String?
    ) -> WebsiteItem {
        WebsiteItem(
            id: id,
            title: id.capitalized,
            url: "https://example.com/\(id)",
            domain: "example.com",
            savedAt: savedAt,
            publishedAt: nil,
            pinned: pinned,
            pinnedOrder: pinnedOrder,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: savedAt,
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }

    func makeWebsiteDetail(id: String, archived: Bool, updatedAt: String?) -> WebsiteDetail {
        WebsiteDetail(
            id: id,
            title: id.capitalized,
            url: "https://example.com/\(id)",
            urlFull: nil,
            domain: "example.com",
            content: "Body",
            source: nil,
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: archived,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: updatedAt,
            lastOpenedAt: nil
        )
    }

    func makeTranscriptWebsiteItem(videoId: String) -> WebsiteItem {
        WebsiteItem(
            id: "w1",
            title: "Video",
            url: "https://www.youtube.com/watch?v=\(videoId)",
            domain: "youtube.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: [
                videoId: WebsiteTranscriptEntry(
                    status: "queued",
                    fileId: "file-1",
                    updatedAt: "2026-03-14T09:55:00Z",
                    error: nil
                )
            ],
            readingTime: nil,
            updatedAt: "2026-03-14T09:55:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }

    func makeTranscriptWebsiteDetail(
        videoId: String,
        transcripts: [String: WebsiteTranscriptEntry]?
    ) -> WebsiteDetail {
        WebsiteDetail(
            id: "w1",
            title: "Video",
            url: "https://www.youtube.com/watch?v=\(videoId)",
            urlFull: nil,
            domain: "youtube.com",
            content: "Before",
            source: "youtube",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: transcripts,
            readingTime: nil,
            updatedAt: "2026-03-14T09:55:00Z",
            lastOpenedAt: nil
        )
    }

    func makeTranscriptRealtimePayload(videoId: String) -> RealtimePayload<WebsiteRealtimeRecord> {
        RealtimePayload<WebsiteRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "w1",
                title: "Video",
                url: "https://www.youtube.com/watch?v=\(videoId)",
                domain: "youtube.com",
                metadata: [
                    "youtube_transcripts": AnyCodable([
                        videoId: [
                            "status": "ready",
                            "file_id": "file-1",
                            "updated_at": "2026-03-14T10:00:00Z",
                            "error": NSNull()
                        ]
                    ])
                ],
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2026-03-14T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )
    }
}

@MainActor
extension WebsitesStoreTests {
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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: makeWidgetDataManager()
        )
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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: makeWidgetDataManager()
        )
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
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: makeWidgetDataManager()
        )
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

    func testApplyRealtimeUpdateRefreshesActiveTranscriptMetadata() async {
        let videoId = "abc123xyzAA"
        let existingItem = makeTranscriptWebsiteItem(videoId: videoId)
        let existingDetail = makeTranscriptWebsiteDetail(
            videoId: videoId,
            transcripts: existingItem.youtubeTranscripts
        )
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let store = WebsitesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: makeWidgetDataManager()
        )
        store.updateListItem(existingItem, persist: false)
        store.applyDetailUpdate(existingDetail, persist: false)

        let payload = makeTranscriptRealtimePayload(videoId: videoId)

        store.applyRealtimeEvent(payload)

        XCTAssertEqual(store.items.first?.youtubeTranscripts?[videoId]?.status, "ready")
        XCTAssertEqual(store.active?.youtubeTranscripts?[videoId]?.status, "ready")
        XCTAssertEqual(store.active?.youtubeTranscripts?[videoId]?.fileId, "file-1")
    }

    func testApplySyncItemReturnsBeforeCachePersistenceCompletesAndKeepsWidgetSnapshotCurrent() async throws {
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let cache = BlockingCacheClient()
        cache.blockSet()
        defer { cache.releaseSet() }
        let widgetDataManager = makeWidgetDataManager()
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: widgetDataManager
        )
        let item = makeWebsiteItem(
            id: "website-1",
            archived: false,
            updatedAt: "2026-04-11T19:57:06Z"
        )

        let applyReturned = expectation(description: "apply sync item returned")
        Task { @MainActor in
            store.applySyncItem(item)
            applyReturned.fulfill()
        }

        await fulfillment(of: [applyReturned], timeout: 0.2)

        let snapshot: WidgetWebsiteData = widgetDataManager.load(for: .websites)
        XCTAssertEqual(snapshot.websites.map(\.id), ["website-1"])
    }
}

@MainActor
func waitUntilWebsitesStoreConditionMet(
    timeoutSeconds: TimeInterval,
    condition: @escaping () async -> Bool
) async throws {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if await condition() {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for websites store condition")
}

actor WebsitesStoreArchivedListCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var current: Int {
        count
    }
}

enum WebsitesStoreMockError: Error {
    case forced
}

struct WebsitesStoreTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool, isServerReachable: Bool = true) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
        self.isServerReachable = isServerReachable
    }
}

final class WebsitesStoreMockWebsitesAPI: WebsitesProviding {
    private let archivedListCounter = WebsitesStoreArchivedListCallCounter()
    private let requestedDetailIDStore = WebsitesStoreRequestedDetailIDStore()

    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>
    var archivedListDelay: TimeInterval?

    var archivedListCallCount: Int {
        get async {
            await archivedListCounter.current
        }
    }

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
        await archivedListCounter.increment()
        if let archivedListDelay {
            try? await Task.sleep(nanoseconds: UInt64(archivedListDelay * 1_000_000_000))
        }
        return try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        await requestedDetailIDStore.append(id)
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw WebsitesStoreMockError.forced
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw WebsitesStoreMockError.forced
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw WebsitesStoreMockError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw WebsitesStoreMockError.forced
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw WebsitesStoreMockError.forced
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw WebsitesStoreMockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw WebsitesStoreMockError.forced
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw WebsitesStoreMockError.forced
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw WebsitesStoreMockError.forced
    }

    var requestedDetailIDs: [String] {
        get async {
            await requestedDetailIDStore.current
        }
    }
}

actor WebsitesStoreRequestedDetailIDStore {
    private var ids: [String] = []

    func append(_ id: String) {
        ids.append(id)
    }

    var current: [String] {
        ids
    }
}

final class BlockingCacheClient: CacheClient, @unchecked Sendable {
    private let lock = NSLock()
    private let setSemaphore = DispatchSemaphore(value: 0)
    private let backing = TestCacheClient()
    private var shouldBlockSet = false

    func blockSet() {
        lock.lock()
        shouldBlockSet = true
        lock.unlock()
    }

    func releaseSet() {
        lock.lock()
        let wasBlocking = shouldBlockSet
        shouldBlockSet = false
        lock.unlock()
        if wasBlocking {
            setSemaphore.signal()
        }
    }

    func get<T: Codable>(key: String) -> T? {
        backing.get(key: key)
    }

    func setEncoded(key: String, payload data: Data, typeName: String, ttlSeconds: TimeInterval) {
        lock.lock()
        let shouldWait = shouldBlockSet
        lock.unlock()
        if shouldWait {
            _ = setSemaphore.wait(timeout: .now() + 5)
        }
        backing.setEncoded(key: key, payload: data, typeName: typeName, ttlSeconds: ttlSeconds)
    }

    func remove(key: String) {
        backing.remove(key: key)
    }

    func clear() {
        backing.clear()
    }
}
