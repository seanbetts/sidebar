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

    func testApplyRealtimeUpdateCachesList() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        let payload = RealtimePayload(
            eventType: .update,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "site-1",
                title: "Site",
                url: "https://example.com",
                domain: "example.com",
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                updatedAt: "2026-01-10T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        await viewModel.applyRealtimeEvent(payload)

        XCTAssertEqual(viewModel.items.first?.id, "site-1")
        let cached: WebsitesResponse? = cache.get(key: CacheKeys.websitesList)
        XCTAssertEqual(cached?.items.first?.id, "site-1")
    }

    func testSaveWebsiteLoadsDetailAndSelects() async {
        let item = makeItem(id: "site-1")
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [item])),
            getResult: .success(detail),
            saveResult: .success(WebsiteSaveResponse(
                success: true,
                data: WebsiteSaveData(id: "site-1", title: "Site", url: "https://example.com", domain: "example.com")
            ))
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        let saved = await viewModel.saveWebsite(url: "https://example.com")

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.items.first?.id, "site-1")
        XCTAssertEqual(viewModel.selectedWebsiteId, "site-1")
        XCTAssertEqual(viewModel.active?.id, "site-1")
    }

    func testSaveWebsiteNormalizesUrl() async {
        let item = makeItem(id: "site-1")
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [item])),
            getResult: .success(detail),
            saveResult: .success(WebsiteSaveResponse(
                success: true,
                data: WebsiteSaveData(id: "site-1", title: "Site", url: "https://example.com", domain: "example.com")
            ))
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        let saved = await viewModel.saveWebsite(url: "example.com")

        XCTAssertTrue(saved)
        XCTAssertEqual(api.lastSavedUrl, "https://example.com")
    }

    func testSaveWebsiteSetsPendingSelectionImmediately() async {
        let cache = InMemoryCacheClient()
        let api = ControlledWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        let saveTask = Task { await viewModel.saveWebsite(url: "https://example.com") }
        await Task.yield()

        XCTAssertNotNil(viewModel.pendingWebsite)
        XCTAssertEqual(viewModel.selectedWebsiteId, viewModel.pendingWebsite?.id)
        XCTAssertTrue(viewModel.isLoadingDetail)

        api.resumeSave(
            result: .success(WebsiteSaveResponse(
                success: true,
                data: WebsiteSaveData(id: "site-1", title: "Site", url: "https://example.com", domain: "example.com")
            ))
        )

        _ = await saveTask.value
        XCTAssertNil(viewModel.pendingWebsite)
    }

    func testDeleteWebsiteClearsSelection() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [makeItem(id: "site-1")])),
            getResult: .success(makeDetail(id: "site-1")),
            saveResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
            archiveResult: .failure(MockError.forced),
            deleteResult: .success(())
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(api: api, store: store)

        await viewModel.selectWebsite(id: "site-1")
        await viewModel.deleteWebsite(id: "site-1")

        XCTAssertNil(viewModel.selectedWebsiteId)
        XCTAssertTrue(viewModel.items.isEmpty)
    }
}

private enum MockError: Error {
    case forced
}

private final class MockWebsitesAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>
    let saveResult: Result<WebsiteSaveResponse, Error>
    let pinResult: Result<WebsiteItem, Error>
    let renameResult: Result<WebsiteItem, Error>
    let archiveResult: Result<WebsiteItem, Error>
    let deleteResult: Result<Void, Error>
    private(set) var lastSavedUrl: String?

    init(
        listResult: Result<WebsitesResponse, Error> = .failure(MockError.forced),
        getResult: Result<WebsiteDetail, Error> = .failure(MockError.forced),
        saveResult: Result<WebsiteSaveResponse, Error> = .failure(MockError.forced),
        pinResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        renameResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        archiveResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        deleteResult: Result<Void, Error> = .failure(MockError.forced)
    ) {
        self.listResult = listResult
        self.getResult = getResult
        self.saveResult = saveResult
        self.pinResult = pinResult
        self.renameResult = renameResult
        self.archiveResult = archiveResult
        self.deleteResult = deleteResult
    }

    func list() async throws -> WebsitesResponse {
        try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        lastSavedUrl = url
        return try saveResult.get()
    }

    func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        return try pinResult.get()
    }

    func rename(id: String, title: String) async throws -> WebsiteItem {
        _ = id
        _ = title
        return try renameResult.get()
    }

    func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        _ = id
        _ = archived
        return try archiveResult.get()
    }

    func delete(id: String) async throws {
        _ = id
        try deleteResult.get()
    }
}

private final class ControlledWebsitesAPI: WebsitesProviding {
    private var saveContinuation: CheckedContinuation<WebsiteSaveResponse, Error>?

    func list() async throws -> WebsitesResponse {
        WebsitesResponse(items: [])
    }

    func get(id: String) async throws -> WebsiteDetail {
        makeDetail(id: id)
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        try await withCheckedThrowingContinuation { continuation in
            saveContinuation = continuation
        }
    }

    func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        makeItem(id: id)
    }

    func rename(id: String, title: String) async throws -> WebsiteItem {
        makeItem(id: id)
    }

    func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        makeItem(id: id)
    }

    func delete(id: String) async throws {
        _ = id
    }

    func resumeSave(result: Result<WebsiteSaveResponse, Error>) {
        guard let continuation = saveContinuation else { return }
        saveContinuation = nil
        continuation.resume(with: result)
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
