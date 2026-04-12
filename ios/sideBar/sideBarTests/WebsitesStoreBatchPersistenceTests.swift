import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension WebsitesStoreTests {
    func testApplySyncItemsPersistsListCacheOnceForBatchedUpdates() async throws {
        let api = WebsitesStoreMockWebsitesAPI(
            listResult: .failure(WebsitesStoreMockError.forced),
            getResult: .failure(WebsitesStoreMockError.forced)
        )
        let cache = CountingCacheClient()
        let widgetDataManager = makeWidgetDataManager()
        let store = WebsitesStore(
            api: api,
            cache: cache,
            widgetDataManager: widgetDataManager
        )

        let first = makeBatchWebsiteItem(
            id: "website-1",
            archived: false,
            updatedAt: "2026-04-12T10:00:00Z"
        )
        let second = makeBatchWebsiteItem(
            id: "website-2",
            archived: false,
            updatedAt: "2026-04-12T10:00:01Z"
        )

        store.applySyncItems([first, second])

        try await waitUntilWebsitesStoreConditionMet(timeoutSeconds: 1.0) {
            cache.setCountSnapshot() >= 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(cache.setCountSnapshot(), 1)
        let snapshot: WidgetWebsiteData = widgetDataManager.load(for: .websites)
        XCTAssertEqual(snapshot.websites.map(\.id), ["website-1", "website-2"])
    }

    private func makeBatchWebsiteItem(id: String, archived: Bool, updatedAt: String?) -> WebsiteItem {
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
}

final class CountingCacheClient: CacheClient, @unchecked Sendable {
    private let backing = TestCacheClient()
    private let lock = NSLock()
    private var setCount = 0

    func get<T: Codable>(key: String) -> T? {
        backing.get(key: key)
    }

    func setEncoded(key: String, payload data: Data, typeName: String, ttlSeconds: TimeInterval) {
        lock.lock()
        setCount += 1
        lock.unlock()
        backing.setEncoded(key: key, payload: data, typeName: typeName, ttlSeconds: ttlSeconds)
    }

    func remove(key: String) {
        backing.remove(key: key)
    }

    func clear() {
        backing.clear()
    }

    func setCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return setCount
    }
}
