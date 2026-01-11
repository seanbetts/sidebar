import XCTest
@testable import sideBar

@MainActor
final class WebsitesViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cached = WebsitesResponse(items: [makeItem(id: "cached")])
        let cache = InMemoryCacheClient()
        cache.set(key: CacheKeys.websitesList, value: cached, ttlSeconds: 60)
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.id, "cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectWebsiteLoadsDetail() async {
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(getResult: .success(detail))
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        await viewModel.selectWebsite(id: "site-1")

        XCTAssertEqual(viewModel.selectedWebsiteId, "site-1")
        XCTAssertEqual(viewModel.active?.id, "site-1")
    }

    func testApplyRealtimeDeleteClearsActive() async {
        let item = makeItem(id: "site-1")
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [item])),
            getResult: .success(detail)
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        await viewModel.load()
        await viewModel.selectWebsite(id: "site-1")

        let payload = RealtimePayload(
            eventType: .delete,
            table: RealtimeTable.websites,
            schema: "public",
            record: nil,
            oldRecord: WebsiteRealtimeRecord(
                id: "site-1",
                title: "Site",
                url: "https://example.com",
                domain: "example.com",
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                updatedAt: nil,
                lastOpenedAt: nil,
                deletedAt: nil
            )
        )

        await viewModel.applyRealtimeEvent(payload)

        XCTAssertNil(viewModel.active)
        XCTAssertNil(viewModel.selectedWebsiteId)
        XCTAssertTrue(viewModel.items.isEmpty)
    }
}

private enum MockError: Error {
    case forced
}

private struct MockWebsitesAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>
    let pinResult: Result<WebsiteItem, Error>

    init(
        listResult: Result<WebsitesResponse, Error> = .failure(MockError.forced),
        getResult: Result<WebsiteDetail, Error> = .failure(MockError.forced),
        pinResult: Result<WebsiteItem, Error> = .failure(MockError.forced)
    ) {
        self.listResult = listResult
        self.getResult = getResult
        self.pinResult = pinResult
    }

    func list() async throws -> WebsitesResponse {
        try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try getResult.get()
    }

    func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        return try pinResult.get()
    }
}

private func makeItem(id: String) -> WebsiteItem {
    WebsiteItem(
        id: id,
        title: "Site",
        url: "https://example.com",
        domain: "example.com",
        savedAt: nil,
        publishedAt: nil,
        pinned: false,
        pinnedOrder: nil,
        archived: false,
        youtubeTranscripts: nil,
        updatedAt: nil,
        lastOpenedAt: nil
    )
}

private func makeDetail(id: String) -> WebsiteDetail {
    WebsiteDetail(
        id: id,
        title: "Site",
        url: "https://example.com",
        urlFull: nil,
        domain: "example.com",
        content: "Example",
        source: nil,
        savedAt: nil,
        publishedAt: nil,
        pinned: false,
        pinnedOrder: nil,
        archived: false,
        youtubeTranscripts: nil,
        updatedAt: nil,
        lastOpenedAt: nil
    )
}
