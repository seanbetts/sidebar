import Foundation
// swiftlint:disable file_length type_body_length
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
        let networkError = URLError(.notConnectedToInternet)
        let api = MockIngestionAPI(
            listResult: .failure(networkError),
            metaResult: .failure(networkError),
            contentResult: .failure(networkError),
            pinResult: .failure(networkError),
            youtubeResult: .failure(networkError)
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

    func testCancelIngestionCancelsLocalUploadImmediately() async {
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let uploadManager = MockIngestionUploadManager()
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: uploadManager,
            toastCenter: ToastCenter()
        )
        let item = makeListItem(id: "local-1", status: "uploading", stage: "uploading")
        store.addLocalUpload(item, bookmarkData: nil)

        viewModel.cancelIngestion(fileId: "local-1")

        XCTAssertEqual(uploadManager.canceledUploadIds, ["local-1"])
        XCTAssertFalse(viewModel.items.contains(where: { $0.file.id == "local-1" }))
    }

    func testCancelIngestionCallsAPIAndMarksCanceledForRemoteProcessingItem() async {
        let processingItem = makeListItem(id: "file-1", status: "processing", stage: "extracting")
        final class CancelCallTracker {
            var fileIds: [String] = []
        }
        let tracker = CancelCallTracker()
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [processingItem])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced),
            onCancel: { tracker.fileIds.append($0) }
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
        await viewModel.load()

        viewModel.cancelIngestion(fileId: "file-1")

        for _ in 0..<10 {
            if viewModel.items.first(where: { $0.file.id == "file-1" })?.job.status == "canceled" {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(tracker.fileIds, ["file-1"])
        XCTAssertEqual(viewModel.items.first(where: { $0.file.id == "file-1" })?.job.status, "canceled")
    }

    func testCancelIngestionShowsToastWhenRemoteCancelFails() async {
        let processingItem = makeListItem(id: "file-1", status: "processing", stage: "extracting")
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [processingItem])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            cancelResult: .failure(MockError.forced),
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

        viewModel.cancelIngestion(fileId: "file-1")

        for _ in 0..<10 {
            if toastCenter.toast?.message == "Failed to cancel ingestion" {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(toastCenter.toast?.message, "Failed to cancel ingestion")
        XCTAssertEqual(viewModel.items.first(where: { $0.file.id == "file-1" })?.job.status, "processing")
    }

    func testCanRetryFailedUploadTrueForLocalFailedWithBookmark() async throws {
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
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
        let bookmarkData = try makeRetryBookmarkData()
        store.addLocalUpload(makeListItem(id: "local-1", status: "failed", stage: "failed"), bookmarkData: bookmarkData)

        XCTAssertTrue(viewModel.canRetryFailedUpload(fileId: "local-1"))
    }

    func testRetryFailedUploadStartsUploadForRetryableLocalItem() async throws {
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let uploadManager = MockIngestionUploadManager()
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: uploadManager,
            toastCenter: ToastCenter()
        )
        let bookmarkData = try makeRetryBookmarkData()
        store.addLocalUpload(makeListItem(id: "local-1", status: "failed", stage: "failed"), bookmarkData: bookmarkData)

        viewModel.retryFailedUpload(fileId: "local-1")

        XCTAssertEqual(uploadManager.startedRequests.count, 1)
        XCTAssertEqual(uploadManager.startedRequests.first?.uploadId, "local-1")
        XCTAssertEqual(viewModel.items.first(where: { $0.file.id == "local-1" })?.job.status, "uploading")
    }

    func testRetryAllFailedUploadsRetriesOnlyRetryableItems() async throws {
        let remoteFailed = makeListItem(id: "file-2", status: "failed", stage: "failed")
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [remoteFailed])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let uploadManager = MockIngestionUploadManager()
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: uploadManager,
            toastCenter: ToastCenter()
        )
        await viewModel.load()
        let bookmarkData = try makeRetryBookmarkData()
        store.addLocalUpload(makeListItem(id: "local-1", status: "failed", stage: "failed"), bookmarkData: bookmarkData)

        let retriedCount = viewModel.retryAllFailedUploads()

        XCTAssertEqual(retriedCount, 1)
        XCTAssertEqual(uploadManager.startedRequests.count, 1)
        XCTAssertEqual(uploadManager.startedRequests.first?.uploadId, "local-1")
    }

    func testExtractYouTubeVideoIdSupportsCanonicalForms() async {
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

    func testExtractYouTubeVideoIdRejectsInvalidHostsAndIds() async {
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

    func testNormalizeYouTubeUrlCandidateRejectsInvalidHosts() async {
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

    // MARK: - Concurrency regression (Phase 2.8)

    func testStartJobPollingDoesNotCreateDuplicateTasks() async {
        let vm = makePollingViewModel(fileId: "file-1", jobStatus: "processing")

        vm.startJobPollingIfNeeded(fileId: "file-1")
        vm.startJobPollingIfNeeded(fileId: "file-1")

        XCTAssertEqual(vm.jobPollingTasks.count, 1, "Duplicate polling tasks should be prevented")
    }

    func testCancelJobPollingClearsAllTasksAndTokens() async {
        let vm = makePollingViewModel(fileId: "file-1", jobStatus: "processing")

        vm.startJobPollingIfNeeded(fileId: "file-1")
        XCTAssertEqual(vm.jobPollingTasks.count, 1)
        XCTAssertEqual(vm.jobPollingTaskTokens.count, 1)

        vm.cancelJobPolling()

        XCTAssertTrue(vm.jobPollingTasks.isEmpty)
        XCTAssertTrue(vm.jobPollingTaskTokens.isEmpty)
    }

    func testCancelJobPollingByFileIdLeavesOtherTasks() async {
        let vm = makePollingViewModel(fileId: "file-1", jobStatus: "processing")

        vm.startJobPollingIfNeeded(fileId: "file-1")
        // Manually add a second file's polling state
        vm.selectedFileId = "file-2"
        vm.activeMeta = IngestionMetaResponse(
            file: makeFile(id: "file-2"),
            job: makeJob(status: "processing"),
            derivatives: [],
            recommendedViewer: nil
        )
        vm.startJobPollingIfNeeded(fileId: "file-2")
        XCTAssertEqual(vm.jobPollingTasks.count, 2)

        vm.cancelJobPolling(fileId: "file-1")

        XCTAssertNil(vm.jobPollingTasks["file-1"])
        XCTAssertNotNil(vm.jobPollingTasks["file-2"])
    }

    func testNewPollingTokenReplacesOldToken() async {
        let vm = makePollingViewModel(fileId: "file-1", jobStatus: "processing")

        vm.startJobPollingIfNeeded(fileId: "file-1")
        let firstToken = vm.jobPollingTaskTokens["file-1"]
        XCTAssertNotNil(firstToken)

        vm.cancelJobPolling(fileId: "file-1")
        vm.startJobPollingIfNeeded(fileId: "file-1")
        let secondToken = vm.jobPollingTaskTokens["file-1"]
        XCTAssertNotNil(secondToken)

        XCTAssertNotEqual(firstToken, secondToken, "Restarted polling should get a fresh token")
    }

    func testJobPollingStopsAfterRepeatedFailuresAndSetsTerminalError() async {
        let fileId = "file-1"
        let meta = IngestionMetaResponse(
            file: makeFile(id: fileId),
            job: makeJob(status: "processing"),
            derivatives: [],
            recommendedViewer: nil
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: makeDefaults())
        let vm = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            jobPollingBaseInterval: 0.01,
            jobPollingMaxInterval: 0.01,
            jobPollingMaxConsecutiveFailures: 2,
            jobPollingJitterWindow: 0
        )
        vm.selectedFileId = fileId
        vm.activeMeta = meta

        vm.startJobPollingIfNeeded(fileId: fileId)

        for _ in 0..<120 where vm.errorMessage == nil || vm.jobPollingTasks[fileId] != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(vm.errorMessage, "Could not refresh file status. Re-open the file to retry.")
        XCTAssertNil(vm.jobPollingTasks[fileId])
    }

    private func makePollingViewModel(fileId: String, jobStatus: String) -> IngestionViewModel {
        let meta = IngestionMetaResponse(
            file: makeFile(id: fileId),
            job: makeJob(status: jobStatus),
            derivatives: [],
            recommendedViewer: nil
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .success(meta),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced)
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let vm = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )
        vm.selectedFileId = fileId
        vm.activeMeta = meta
        return vm
    }

    // MARK: - Helpers

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

    private func makeRetryBookmarkData() throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("retry".utf8).write(to: url)
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        return try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
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
    let cancelResult: Result<Void, Error>
    let pinResult: Result<Void, Error>
    let youtubeResult: Result<String, Error>
    let onCancel: ((String) -> Void)?

    init(
        listResult: Result<IngestionListResponse, Error>,
        metaResult: Result<IngestionMetaResponse, Error>,
        contentResult: Result<Data, Error>,
        cancelResult: Result<Void, Error> = .success(()),
        pinResult: Result<Void, Error>,
        youtubeResult: Result<String, Error>,
        onCancel: ((String) -> Void)? = nil
    ) {
        self.listResult = listResult
        self.metaResult = metaResult
        self.contentResult = contentResult
        self.cancelResult = cancelResult
        self.pinResult = pinResult
        self.youtubeResult = youtubeResult
        self.onCancel = onCancel
    }

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

    func cancel(fileId: String) async throws {
        onCancel?(fileId)
        return try cancelResult.get()
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
    private(set) var startedRequests: [UploadRequest] = []
    private(set) var canceledUploadIds: [String] = []

    func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        startedRequests.append(request)
        _ = onProgress
        _ = onCompletion
    }

    func cancelUpload(uploadId: String) {
        canceledUploadIds.append(uploadId)
    }
}
// swiftlint:enable file_length type_body_length
