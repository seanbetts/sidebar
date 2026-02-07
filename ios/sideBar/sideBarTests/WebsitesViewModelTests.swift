import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cached = WebsitesResponse(items: [makeItem(id: "cached")])
        let cache = InMemoryCacheClient()
        cache.set(key: CacheKeys.websitesList, value: cached, ttlSeconds: 60)
        let api = MockWebsitesAPI(listResult: .failure(MockError.forced))
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.id, "cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectWebsiteLoadsDetail() async {
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(getResult: .success(detail))
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

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
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

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
                readingTime: nil,
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
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

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
                readingTime: nil,
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
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

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
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let saved = await viewModel.saveWebsite(url: "example.com")

        XCTAssertTrue(saved)
        XCTAssertEqual(api.lastSavedUrl, "https://example.com")
    }

    func testSaveWebsiteSetsPendingSelectionImmediately() async {
        let cache = InMemoryCacheClient()
        let api = ControlledWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

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

    func testLoadArchivedTracksLoadingState() async {
        let cache = InMemoryCacheClient()
        let api = ControlledArchivedWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let loadTask = Task { await viewModel.loadArchived() }
        await Task.yield()

        XCTAssertTrue(viewModel.isLoadingArchived)

        api.resumeListArchived(result: .success(WebsitesResponse(items: [])))
        await loadTask.value

        XCTAssertFalse(viewModel.isLoadingArchived)
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
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        await viewModel.deleteWebsite(id: "site-1")

        XCTAssertNil(viewModel.selectedWebsiteId)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testRequestYouTubeTranscriptQueuesLocalTranscriptState() async {
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            getResult: .success(detail),
            transcribeResult: .success(
                WebsiteTranscriptResponse(
                    readyWebsite: nil,
                    queuedStatus: "queued",
                    queuedFileId: "file-1"
                )
            )
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        await viewModel.requestYouTubeTranscript(
            websiteId: "site-1",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        XCTAssertEqual(
            viewModel.active?.youtubeTranscripts?["dQw4w9WgXcQ"]?.status,
            "queued"
        )
        XCTAssertEqual(
            viewModel.active?.youtubeTranscripts?["dQw4w9WgXcQ"]?.fileId,
            "file-1"
        )
        XCTAssertNil(viewModel.activeTranscriptVideoId)
    }
}

private enum MockError: Error {
    case forced
}

@MainActor
private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

private final class MockWebsitesAPI: WebsitesProviding {
    let listResult: Result<WebsitesResponse, Error>
    let getResult: Result<WebsiteDetail, Error>
    let saveResult: Result<WebsiteSaveResponse, Error>
    let transcribeResult: Result<WebsiteTranscriptResponse, Error>
    let pinResult: Result<WebsiteItem, Error>
    let renameResult: Result<WebsiteItem, Error>
    let archiveResult: Result<WebsiteItem, Error>
    let deleteResult: Result<Void, Error>
    let syncResult: Result<WebsiteSyncResponse, Error>
    private(set) var lastSavedUrl: String?

    init(
        listResult: Result<WebsitesResponse, Error> = .failure(MockError.forced),
        getResult: Result<WebsiteDetail, Error> = .failure(MockError.forced),
        saveResult: Result<WebsiteSaveResponse, Error> = .failure(MockError.forced),
        transcribeResult: Result<WebsiteTranscriptResponse, Error> = .failure(MockError.forced),
        pinResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        renameResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        archiveResult: Result<WebsiteItem, Error> = .failure(MockError.forced),
        deleteResult: Result<Void, Error> = .failure(MockError.forced),
        syncResult: Result<WebsiteSyncResponse, Error> = .success(
            WebsiteSyncResponse(applied: [], websites: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
        )
    ) {
        self.listResult = listResult
        self.getResult = getResult
        self.saveResult = saveResult
        self.transcribeResult = transcribeResult
        self.pinResult = pinResult
        self.renameResult = renameResult
        self.archiveResult = archiveResult
        self.deleteResult = deleteResult
        self.syncResult = syncResult
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
        lastSavedUrl = url
        return try saveResult.get()
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        return try transcribeResult.get()
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        return try pinResult.get()
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        return try renameResult.get()
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        return try archiveResult.get()
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        try deleteResult.get()
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        return try syncResult.get()
    }
}

private final class ControlledWebsitesAPI: WebsitesProviding {
    private var saveContinuation: CheckedContinuation<WebsiteSaveResponse, Error>?

    func list() async throws -> WebsitesResponse {
        WebsitesResponse(items: [])
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return WebsitesResponse(items: [])
    }

    func get(id: String) async throws -> WebsiteDetail {
        makeDetail(id: id)
    }

    func save(url: String) async throws -> WebsiteSaveResponse {
        try await withCheckedThrowingContinuation { continuation in
            saveContinuation = continuation
        }
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw MockError.forced
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        return WebsiteSyncResponse(applied: [], websites: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }

    func resumeSave(result: Result<WebsiteSaveResponse, Error>) {
        guard let continuation = saveContinuation else { return }
        saveContinuation = nil
        continuation.resume(with: result)
    }
}

private final class ControlledArchivedWebsitesAPI: WebsitesProviding {
    private var listArchivedContinuation: CheckedContinuation<WebsitesResponse, Error>?

    func list() async throws -> WebsitesResponse {
        WebsitesResponse(items: [])
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return try await withCheckedThrowingContinuation { continuation in
            listArchivedContinuation = continuation
        }
    }

    func get(id: String) async throws -> WebsiteDetail {
        makeDetail(id: id)
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
        _ = pinned
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = title
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = archived
        _ = clientUpdatedAt
        return makeItem(id: id)
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        return WebsiteSyncResponse(applied: [], websites: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }

    func resumeListArchived(result: Result<WebsitesResponse, Error>) {
        guard let continuation = listArchivedContinuation else { return }
        listArchivedContinuation = nil
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
        faviconUrl: nil,
        faviconR2Key: nil,
        youtubeTranscripts: nil,
        readingTime: nil,
        updatedAt: nil,
        lastOpenedAt: nil,
        deletedAt: nil
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
        faviconUrl: nil,
        faviconR2Key: nil,
        youtubeTranscripts: nil,
        readingTime: nil,
        updatedAt: nil,
        lastOpenedAt: nil
    )
}
