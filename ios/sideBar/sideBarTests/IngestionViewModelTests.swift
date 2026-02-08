import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cachedItem = makeListItem(id: "cached")
        let cache = TestCacheClient()
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(items: [cachedItem]),
            ttlSeconds: 60
        )
        let api = MockIngestionAPI(
            listResult: .failure(MockError.forced),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: cache, userDefaults: defaults)
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.file.id, "cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectFileLoadsViewerState() async {
        let file = makeFile(id: "file-1")
        let meta = IngestionMetaResponse(
            file: file,
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d1",
                    kind: "text_original",
                    storageKey: "storage",
                    mime: "text/plain",
                    sizeBytes: 10
                )
            ],
            recommendedViewer: "text_original"
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [makeListItem(id: file.id)])),
            metaResult: .success(meta),
            contentResult: .success(Data("Hello".utf8)),
            pinResult: .success(()),
            youtubeResult: .success("youtube")
        )
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TemporaryFileStore(directory: tempDirectory)
        let defaults = makeDefaults()
        let ingestionStore = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let viewModel = IngestionViewModel(
            api: api,
            store: ingestionStore,
            temporaryStore: store,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        await viewModel.selectFile(fileId: file.id)

        XCTAssertEqual(viewModel.viewerState?.kind, .text)
        XCTAssertEqual(viewModel.viewerState?.text, "Hello")
        XCTAssertNotNil(viewModel.viewerState?.fileURL)
    }

    func testLoadMetaUsesCacheAndMarksOfflineOnRefreshFailure() async {
        let file = makeFile(id: "file-1")
        let meta = IngestionMetaResponse(
            file: file,
            job: makeJob(),
            derivatives: [],
            recommendedViewer: nil
        )
        let cache = TestCacheClient()
        cache.set(
            key: CacheKeys.ingestionMeta(fileId: file.id),
            value: meta,
            ttlSeconds: 60
        )
        let api = MockIngestionAPI(
            listResult: .failure(MockError.forced),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: cache, userDefaults: defaults)
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        await viewModel.loadMeta(fileId: file.id)

        for _ in 0..<10 {
            if viewModel.isOffline {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(viewModel.activeMeta?.file.id, file.id)
        XCTAssertTrue(viewModel.isOffline)
    }

    func testIngestYouTubeAddsLocalItemAndSelects() async {
        let file = IngestedFileMeta(
            id: "yt-1",
            filenameOriginal: "YouTube video",
            path: nil,
            mimeOriginal: "video/youtube",
            sizeBytes: 0,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: "https://www.youtube.com/watch?v=abc123",
            sourceMetadata: nil,
            createdAt: "2026-01-10T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
        let meta = IngestionMetaResponse(
            file: file,
            job: makeJob(),
            derivatives: [],
            recommendedViewer: nil
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .success(meta),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .success("yt-1")
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        let errorMessage = await viewModel.ingestYouTube(url: "https://www.youtube.com/watch?v=abc123")

        XCTAssertNil(errorMessage)
        XCTAssertEqual(viewModel.selectedFileId, "yt-1")
        XCTAssertTrue(viewModel.items.contains(where: { $0.file.id == "yt-1" }))
    }

    func testIngestYouTubeQueuesWhenOffline() async throws {
        let api = MockIngestionAPI(
            listResult: .failure(MockError.forced),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let pendingStore = PendingShareStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            userDefaults: defaults
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            pendingShareStore: pendingStore,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        let errorMessage = await viewModel.ingestYouTube(url: "https://www.youtube.com/watch?v=abc123", showQueuedToast: false)

        XCTAssertNil(errorMessage)
        let pending = pendingStore.loadAll()
        XCTAssertEqual(pending.first?.kind, .youtube)
    }

    func testIngestYouTubeQueuesWhenNetworkUnavailable() async throws {
        let api = MockIngestionAPI(
            listResult: .failure(MockError.forced),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let pendingStore = PendingShareStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            userDefaults: defaults
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            pendingShareStore: pendingStore,
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: false)
        )

        let errorMessage = await viewModel.ingestYouTube(url: "https://www.youtube.com/watch?v=abc123", showQueuedToast: false)

        XCTAssertNil(errorMessage)
        let pending = pendingStore.loadAll()
        XCTAssertEqual(pending.first?.kind, .youtube)
    }

    func testClearFailedUploadShowsToastWhenDeleteFails() async {
        let failedItem = makeListItem(id: "file-1", status: "failed", stage: "failed")
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [failedItem])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let toastCenter = ToastCenter()
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: toastCenter
        )

        await viewModel.load()
        viewModel.clearFailedUpload(fileId: "file-1")

        for _ in 0..<10 {
            if toastCenter.toast != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(toastCenter.toast?.message, "Failed to clear failed upload")
    }

    func testExtractYouTubeVideoIdSupportsCanonicalForms() {
        let viewModel = makeViewModelForYouTubeParsing()

        XCTAssertEqual(
            viewModel.extractYouTubeVideoId(from: "https://youtu.be/abc123xyzAA"),
            "abc123xyzAA"
        )
        XCTAssertEqual(
            viewModel.extractYouTubeVideoId(from: "https://www.youtube.com/watch?v=abc123xyzAA"),
            "abc123xyzAA"
        )
        XCTAssertEqual(
            viewModel.extractYouTubeVideoId(from: "https://www.youtube.com/shorts/abc123xyzAA"),
            "abc123xyzAA"
        )
        XCTAssertEqual(
            viewModel.extractYouTubeVideoId(from: "https://www.youtube.com/embed/abc123xyzAA"),
            "abc123xyzAA"
        )
        XCTAssertEqual(
            viewModel.extractYouTubeVideoId(from: "https://www.youtube.com/live/abc123xyzAA"),
            "abc123xyzAA"
        )
    }

    func testExtractYouTubeVideoIdRejectsInvalidHostsAndIds() {
        let viewModel = makeViewModelForYouTubeParsing()

        XCTAssertNil(
            viewModel.extractYouTubeVideoId(from: "https://example.com/watch?v=abc123xyzAA")
        )
        XCTAssertNil(
            viewModel.extractYouTubeVideoId(from: "https://youtube.com.evil.com/watch?v=abc123xyzAA")
        )
        XCTAssertNil(viewModel.extractYouTubeVideoId(from: "https://www.youtube.com/watch?v=a"))
        XCTAssertNil(viewModel.extractYouTubeVideoId(from: "not a url"))
    }

    func testNormalizeYouTubeUrlCandidateRejectsInvalidHosts() {
        let viewModel = makeViewModelForYouTubeParsing()

        XCTAssertNil(
            viewModel.normalizeYouTubeUrlCandidate("https://example.com/watch?v=abc123xyzAA")
        )
        XCTAssertNil(
            viewModel.normalizeYouTubeUrlCandidate(
                "https://youtube.com.evil.com/watch?v=abc123xyzAA"
            )
        )
        XCTAssertEqual(
            viewModel.normalizeYouTubeUrlCandidate("youtu.be/abc123xyzAA"),
            "https://youtu.be/abc123xyzAA"
        )
    }

    private func makeListItem(id: String, status: String = "ready", stage: String = "done") -> IngestionListItem {
        IngestionListItem(
            file: makeFile(id: id),
            job: makeJob(status: status, stage: stage),
            recommendedViewer: "text_original"
        )
    }

    private func makeFile(id: String) -> IngestedFileMeta {
        IngestedFileMeta(
            id: id,
            filenameOriginal: "file.txt",
            path: nil,
            mimeOriginal: "text/plain",
            sizeBytes: 10,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2026-01-10T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }

    private func makeJob(status: String = "ready", stage: String = "done") -> IngestionJob {
        IngestionJob(
            status: status,
            stage: stage,
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 1,
            updatedAt: nil
        )
    }

    private func makeViewModelForYouTubeParsing() -> IngestionViewModel {
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        return IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )
    }
}

private func makeDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "IngestionViewModelTests") ?? .standard
    defaults.removePersistentDomain(forName: "IngestionViewModelTests")
    return defaults
}

private enum MockError: Error {
    case forced
}

private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
}

private struct MockIngestionAPI: IngestionProviding {
    let listResult: Result<IngestionListResponse, Error>
    let metaResult: Result<IngestionMetaResponse, Error>
    let contentResult: Result<Data, Error>
    let pinResult: Result<Void, Error>
    let youtubeResult: Result<String, Error>

    func list() async throws -> IngestionListResponse {
        try listResult.get()
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        return try metaResult.get()
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        return try contentResult.get()
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        return try pinResult.get()
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        return try youtubeResult.get()
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }
}

private final class MockIngestionUploadManager: IngestionUploadManaging {
    func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        _ = request
        _ = onProgress
        _ = onCompletion
    }

    func cancelUpload(uploadId: String) {
        _ = uploadId
    }
}
