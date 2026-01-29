import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesStoreTests: XCTestCase {
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
            youtubeTranscripts: nil,
            updatedAt: "2024-01-01",
            lastOpenedAt: nil
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
            youtubeTranscripts: nil,
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
}

private enum MockError: Error {
    case forced
}

private final class MockWebsitesAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>

    init(listResult: Result<WebsitesResponse, Error>, getResult: Result<WebsiteDetail, Error>) {
        self.listResult = listResult
        self.getResult = getResult
    }

    func list() async throws -> WebsitesResponse {
        try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        _ = url
        throw MockError.forced
    }

    func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        throw MockError.forced
    }

    func rename(id: String, title: String) async throws -> WebsiteItem {
        _ = id
        _ = title
        throw MockError.forced
    }

    func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        _ = id
        _ = archived
        throw MockError.forced
    }

    func delete(id: String) async throws {
        _ = id
        throw MockError.forced
    }
}
