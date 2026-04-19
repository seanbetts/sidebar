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

    func testLoadMapsTypedFailureMessageWhenNoContentIsAvailable() async {
        let api = MockIngestionAPI(
            listResult: .failure(APIClientError.requestFailed(503)),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced),
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

        await viewModel.load()

        XCTAssertEqual(viewModel.errorMessage, "Server is busy right now. Please try again.")
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

    func testSelectingDifferentFileClearsStaleActiveMetaBeforeOfflineUnavailableFailure() async {
        let existingFile = makeFile(id: "file-existing")
        let unavailableFile = makeFile(id: "file-unavailable")
        let existingMeta = IngestionMetaResponse(
            file: existingFile,
            job: makeJob(),
            derivatives: [],
            recommendedViewer: nil
        )
        let defaults = makeDefaults()
        let cache = TestCacheClient()
        let networkStatus = TestNetworkStatus(
            isNetworkAvailable: false,
            isOffline: true
        )
        let store = IngestionStore(
            api: MockIngestionAPI(
                listResult: .success(IngestionListResponse(items: [])),
                metaResult: .failure(MockError.forced),
                contentResult: .failure(MockError.forced),
                pinResult: .success(()),
                youtubeResult: .failure(MockError.forced)
            ),
            cache: cache,
            offlineStore: OfflineStore(container: PersistenceController(inMemory: true).container),
            networkStatus: networkStatus,
            userDefaults: defaults
        )
        store.applyListUpdate(
            [
                makeListItem(id: existingFile.id),
                makeListItem(id: unavailableFile.id)
            ],
            persist: false
        )
        store.applyMetaUpdate(existingMeta, persist: false)
        let viewModel = IngestionViewModel(
            api: MockIngestionAPI(
                listResult: .success(IngestionListResponse(items: [])),
                metaResult: .failure(MockError.forced),
                contentResult: .failure(MockError.forced),
                pinResult: .success(()),
                youtubeResult: .failure(MockError.forced)
            ),
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: networkStatus
        )
        viewModel.selectedFileId = existingFile.id

        await viewModel.selectFile(fileId: unavailableFile.id)

        XCTAssertEqual(viewModel.selectedFileId, unavailableFile.id)
        XCTAssertNil(viewModel.activeMeta)
    }

    func testSelectFileOfflineUnavailableSetsSelectionWithoutEnteringVisibleLoadState() async {
        let unavailableFile = makeFile(id: "file-unavailable")
        let defaults = makeDefaults()
        let cache = TestCacheClient()
        let networkStatus = TestNetworkStatus(
            isNetworkAvailable: false,
            isOffline: true
        )
        let store = IngestionStore(
            api: MockIngestionAPI(
                listResult: .success(IngestionListResponse(items: [])),
                metaResult: .failure(MockError.forced),
                contentResult: .failure(MockError.forced),
                pinResult: .success(()),
                youtubeResult: .failure(MockError.forced)
            ),
            cache: cache,
            offlineStore: OfflineStore(container: PersistenceController(inMemory: true).container),
            networkStatus: networkStatus,
            userDefaults: defaults
        )
        let viewModel = IngestionViewModel(
            api: MockIngestionAPI(
                listResult: .success(IngestionListResponse(items: [])),
                metaResult: .failure(MockError.forced),
                contentResult: .failure(MockError.forced),
                pinResult: .success(()),
                youtubeResult: .failure(MockError.forced)
            ),
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: networkStatus
        )

        await viewModel.selectFile(fileId: unavailableFile.id)

        XCTAssertEqual(viewModel.selectedFileId, unavailableFile.id)
        XCTAssertNil(viewModel.activeMeta)
        XCTAssertFalse(viewModel.isSelecting)
        XCTAssertEqual(viewModel.errorMessage, "This file isn't available offline yet.")
    }

    func testSelectVideoFileLoadsTranscriptFromAiMarkdown() async {
        let file = makeVideoFile(id: "file-video-1")
        let viewModel = makeVideoViewModel(
            file: file,
            aiMarkdown: "---\nkey: value\n---\n\nTranscript line"
        )

        await viewModel.selectFile(fileId: file.id)

        XCTAssertEqual(viewModel.viewerState?.kind, .video)
        XCTAssertEqual(viewModel.viewerState?.text, "Transcript line")
        XCTAssertNotNil(viewModel.viewerState?.fileURL)
    }

    func testSelectVideoFileSanitizesTranscriptTitleAndMetadata() async {
        let file = makeVideoFile(id: "file-video-2")
        let aiMarkdown = """
        ---
        file_id: file-video-2
        ---

        # YouTube URL: https://www.youtube.com/watch?v=abc123
        # Video title: Demo video
        # Generated: 2026-02-23 20:00:00
        ---
        # Demo video

        ## Metadata
        - Duration: 3:12
        - Model: gpt-4o-transcribe

        ## Transcript
        First line
        """
        let viewModel = makeVideoViewModel(file: file, aiMarkdown: aiMarkdown)

        await viewModel.selectFile(fileId: file.id)

        let transcript = viewModel.viewerState?.text ?? ""
        XCTAssertEqual(viewModel.viewerState?.kind, .video)
        XCTAssertTrue(transcript.hasPrefix("## Demo video"))
        XCTAssertTrue(transcript.contains("## Transcript"))
        XCTAssertTrue(transcript.contains("First line"))
        XCTAssertFalse(transcript.contains("## Metadata"))
        XCTAssertFalse(transcript.contains("YouTube URL:"))
        XCTAssertFalse(transcript.contains("Generated:"))
    }

    func testSelectVideoFileStripsDownloadSummaryAndKeepsTranscriptBody() async {
        let file = makeVideoFile(id: "file-video-3")
        let aiMarkdown = """
        # Demo video

        - Source: https://www.youtube.com/watch?v=abc123
        - Type: Video (MP4)
        - Filename: demo.mp4
        - Download Duration (seconds): 42
        - Generated: 2026-02-23T20:00:00Z

        Download completed successfully.

        ## Transcript
        Transcript line
        """
        let viewModel = makeVideoViewModel(file: file, aiMarkdown: aiMarkdown)

        await viewModel.selectFile(fileId: file.id)

        let transcript = viewModel.viewerState?.text ?? ""
        XCTAssertEqual(viewModel.viewerState?.kind, .video)
        XCTAssertTrue(transcript.hasPrefix("## Demo video"))
        XCTAssertTrue(transcript.contains("## Transcript"))
        XCTAssertTrue(transcript.contains("Transcript line"))
        XCTAssertFalse(transcript.contains("Source:"))
        XCTAssertFalse(transcript.contains("Type:"))
        XCTAssertFalse(transcript.contains("Filename:"))
        XCTAssertFalse(transcript.contains("Download Duration"))
        XCTAssertFalse(transcript.contains("Generated:"))
        XCTAssertFalse(transcript.contains("Download completed successfully"))
    }

    func testSelectVideoFileTreatsSummaryOnlyAiMarkdownAsNoTranscript() async {
        let file = makeVideoFile(id: "file-video-4")
        let aiMarkdown = """
        # Demo video

        - Source: https://www.youtube.com/watch?v=abc123
        - Type: Video (MP4)
        - Filename: demo.mp4
        - Download Duration (seconds): 42
        - Generated: 2026-02-23T20:00:00Z

        Download completed successfully.
        """
        let viewModel = makeVideoViewModel(file: file, aiMarkdown: aiMarkdown)

        await viewModel.selectFile(fileId: file.id)

        XCTAssertEqual(viewModel.viewerState?.kind, .video)
        XCTAssertNil(viewModel.viewerState?.text)
    }

    func testPreferredDownloadDerivativePrefersSourceOriginal() async {
        let viewModel = makeViewModelForYouTubeParsing()
        viewModel.selectedDerivativeKind = "text_original"
        let meta = IngestionMetaResponse(
            file: makeFile(id: "file-1"),
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d0",
                    kind: "source_original",
                    storageKey: "storage/source",
                    mime: "application/pdf",
                    sizeBytes: 200
                ),
                IngestionDerivative(
                    id: "d1",
                    kind: "text_original",
                    storageKey: "storage/text",
                    mime: "text/plain",
                    sizeBytes: 10
                ),
                IngestionDerivative(
                    id: "d2",
                    kind: "video_original",
                    storageKey: "storage/video",
                    mime: "video/mp4",
                    sizeBytes: 100
                )
            ],
            recommendedViewer: "viewer_video"
        )

        let preferred = viewModel.preferredDownloadDerivative(for: meta)

        XCTAssertEqual(preferred?.kind, "source_original")
    }

    func testPreferredDownloadDerivativeMapsViewerVideoToVideoOriginal() async {
        let viewModel = makeViewModelForYouTubeParsing()
        viewModel.selectedDerivativeKind = "viewer_video"
        let meta = IngestionMetaResponse(
            file: makeFile(id: "file-1"),
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d1",
                    kind: "video_original",
                    storageKey: "storage/video",
                    mime: "video/mp4",
                    sizeBytes: 100
                )
            ],
            recommendedViewer: "viewer_video"
        )

        let preferred = viewModel.preferredDownloadDerivative(for: meta)

        XCTAssertEqual(preferred?.kind, "video_original")
    }

    func testPreferredDownloadDerivativeFallsBackWhenViewerVideoDerivativeMissing() async {
        let viewModel = makeViewModelForYouTubeParsing()
        viewModel.selectedDerivativeKind = "viewer_video"
        let meta = IngestionMetaResponse(
            file: makeFile(id: "file-1"),
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d1",
                    kind: "text_original",
                    storageKey: "storage/text",
                    mime: "text/plain",
                    sizeBytes: 10
                )
            ],
            recommendedViewer: "viewer_video"
        )

        let preferred = viewModel.preferredDownloadDerivative(for: meta)

        XCTAssertEqual(preferred?.kind, "text_original")
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

        await waitUntilPolling(timeoutSeconds: 1.0) {
            viewModel.isOffline
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

    func testPanelPinnedItemsIncludesPinnedFileWithoutRecommendedViewer() async {
        let pinnedProcessingItem = IngestionListItem(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "file.txt",
                path: nil,
                mimeOriginal: "text/plain",
                sizeBytes: 10,
                sha256: nil,
                pinned: true,
                pinnedOrder: 0,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "extracting",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 1,
                updatedAt: nil
            ),
            recommendedViewer: nil
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [pinnedProcessingItem])),
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

        await viewModel.load()

        XCTAssertEqual(viewModel.panelPinnedItems.map(\.file.id), ["file-1"])
    }

    func testReorderPinnedFilesPersistsOptimisticOrder() async {
        let recorder = PinnedOrderRecorder()
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            updatePinnedOrderResult: .success(()),
            youtubeResult: .failure(MockError.forced),
            pinnedOrderRecorder: recorder
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        store.applyListUpdate(
            [
                makePinnedListItem(id: "file-a", pinnedOrder: 0),
                makePinnedListItem(id: "file-b", pinnedOrder: 1),
                makeListItem(id: "file-c")
            ],
            persist: false
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        let success = await viewModel.reorderPinnedFiles(ids: ["file-b", "file-a"])
        let recordedOrders = await recorder.snapshot()

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.panelPinnedItems.map(\.file.id), ["file-b", "file-a"])
        XCTAssertEqual(recordedOrders, [["file-b", "file-a"]])
    }

    func testReorderPinnedFilesRestoresPreviousOrderWhenRequestFails() async {
        let recorder = PinnedOrderRecorder()
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            updatePinnedOrderResult: .failure(MockError.forced),
            youtubeResult: .failure(MockError.forced),
            pinnedOrderRecorder: recorder
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        store.applyListUpdate(
            [
                makePinnedListItem(id: "file-a", pinnedOrder: 0),
                makePinnedListItem(id: "file-b", pinnedOrder: 1)
            ],
            persist: false
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )

        let success = await viewModel.reorderPinnedFiles(ids: ["file-b", "file-a"])
        let recordedOrders = await recorder.snapshot()

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.panelPinnedItems.map(\.file.id), ["file-a", "file-b"])
        XCTAssertEqual(viewModel.errorMessage, "Failed to reorder pinned files")
        XCTAssertEqual(recordedOrders, [["file-b", "file-a"]])
    }

    func testReorderPinnedFilesDoesNotCallAPIWhenOffline() async {
        let recorder = PinnedOrderRecorder()
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            updatePinnedOrderResult: .success(()),
            youtubeResult: .failure(MockError.forced),
            pinnedOrderRecorder: recorder
        )
        let defaults = makeDefaults()
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        store.applyListUpdate(
            [
                makePinnedListItem(id: "file-a", pinnedOrder: 0),
                makePinnedListItem(id: "file-b", pinnedOrder: 1)
            ],
            persist: false
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        let success = await viewModel.reorderPinnedFiles(ids: ["file-b", "file-a"])
        let updatePinnedOrderCallCount = await recorder.callCount()

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.panelPinnedItems.map(\.file.id), ["file-a", "file-b"])
        XCTAssertEqual(updatePinnedOrderCallCount, 0)
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

        await waitUntilPolling(timeoutSeconds: 0.5) {
            toastCenter.toast != nil
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

    func testCancelIngestionCallsAPIAndRemovesRemoteProcessingItem() async {
        let fileId = UUID().uuidString
        let processingItem = makeListItem(id: fileId, status: "processing", stage: "extracting")
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

        viewModel.cancelIngestion(fileId: fileId)

        await waitUntilPolling(timeoutSeconds: 0.5) {
            viewModel.items.contains(where: { $0.file.id == fileId }) == false
        }

        XCTAssertEqual(tracker.fileIds, [fileId])
        XCTAssertFalse(viewModel.items.contains(where: { $0.file.id == fileId }))
    }

    func testCancelIngestionShowsToastWhenRemoteCancelFails() async {
        let fileId = UUID().uuidString
        let processingItem = makeListItem(id: fileId, status: "processing", stage: "extracting")
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

        viewModel.cancelIngestion(fileId: fileId)

        await waitUntilPolling(timeoutSeconds: 0.5) {
            toastCenter.toast?.message == "Failed to cancel ingestion"
        }

        XCTAssertEqual(toastCenter.toast?.message, "Failed to cancel ingestion")
        XCTAssertEqual(viewModel.items.first(where: { $0.file.id == fileId })?.job.status, "processing")
    }

    func testCancelIngestionSkipsInvalidRemoteIdentifierWithoutAPIRequest() async {
        let processingItem = makeListItem(id: "file-1", status: "processing", stage: "extracting")
        final class CancelCallTracker {
            var count = 0
        }
        let tracker = CancelCallTracker()
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [processingItem])),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .success(()),
            youtubeResult: .failure(MockError.forced),
            onCancel: { _ in tracker.count += 1 }
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

        XCTAssertFalse(viewModel.canCancelIngestion(fileId: "file-1"))
        viewModel.cancelIngestion(fileId: "file-1")

        XCTAssertEqual(tracker.count, 0)
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

    func testStartUploadRejectsUnsupportedPlistBeforeQueueingLocalUpload() throws {
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
        let toastCenter = ToastCenter()
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: uploadManager,
            toastCenter: toastCenter
        )
        let plistURL = try makeTemporaryFileURL(
            filename: "0481BC53-E4E0-403F-976D-E5A11D13960B.plist"
        )

        viewModel.startUpload(url: plistURL)

        XCTAssertTrue(uploadManager.startedRequests.isEmpty)
        XCTAssertFalse(viewModel.items.contains(where: { $0.file.filenameOriginal == plistURL.lastPathComponent }))
        XCTAssertEqual(toastCenter.toast?.message, "That file type isn't supported yet.")
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

    func testRenameFileOnlineOptimisticallyUpdatesFilenameBeforeApiReturns() async throws {
        let originalItem = makeListItem(id: "file-1")
        let api = ControlledRenameIngestionAPI(
            listResult: .success(IngestionListResponse(items: [originalItem])),
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
        await viewModel.load()

        let renameTask = Task {
            await viewModel.renameFile(fileId: "file-1", filename: "Renamed.pdf")
        }

        await waitUntil(timeout: .milliseconds(200)) {
            viewModel.items.first?.file.filenameOriginal == "Renamed.pdf"
        }

        api.resumeRename()
        _ = await renameTask.value

        XCTAssertEqual(viewModel.items.first?.file.filenameOriginal, "Renamed.pdf")
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
        let sleepRecorder = PollingSleepRecorder()
        let vm = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter(),
            jobPollingBaseInterval: 0.01,
            jobPollingMaxInterval: 0.01,
            jobPollingMaxConsecutiveFailures: 2,
            jobPollingJitterWindow: 0,
            jobPollingSleep: { nanoseconds in
                await sleepRecorder.record(nanoseconds)
            }
        )
        vm.selectedFileId = fileId
        vm.activeMeta = meta

        vm.startJobPollingIfNeeded(fileId: fileId)

        await waitUntilPolling {
            vm.errorMessage != nil && vm.jobPollingTasks[fileId] == nil
        }

        XCTAssertEqual(vm.errorMessage, "Could not refresh file status. Re-open the file to retry.")
        XCTAssertNil(vm.jobPollingTasks[fileId])
        let recordedIntervals = await sleepRecorder.snapshot()
        XCTAssertEqual(recordedIntervals, [100_000_000, 100_000_000])
    }

    func testListPollingSkipsNonServerPlaceholderItems() async {
        let vm = makeViewModelForYouTubeParsing()
        let placeholder = makeListItem(id: "youtube-\(UUID().uuidString)", status: "processing", stage: "queued")

        vm.updateListPollingState(items: [placeholder])

        XCTAssertNil(vm.listPollingTask)
    }

    func testListPollingStartsForActiveServerItem() async {
        let vm = makeViewModelForYouTubeParsing()
        let serverID = UUID().uuidString
        let activeServerItem = makeListItem(id: serverID, status: "processing", stage: "extracting")

        vm.updateListPollingState(items: [activeServerItem])

        XCTAssertNotNil(vm.listPollingTask)
        vm.stopListPolling()
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

    private func makeVideoFile(id: String) -> IngestedFileMeta {
        IngestedFileMeta(
            id: id,
            filenameOriginal: "clip.mp4",
            path: nil,
            mimeOriginal: "video/mp4",
            sizeBytes: 1024,
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

    private func makeVideoViewModel(
        file: IngestedFileMeta,
        aiMarkdown: String
    ) -> IngestionViewModel {
        let meta = IngestionMetaResponse(
            file: file,
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d-video",
                    kind: "video_original",
                    storageKey: "storage/video",
                    mime: "video/mp4",
                    sizeBytes: 100
                ),
                IngestionDerivative(
                    id: "d-ai",
                    kind: "ai_md",
                    storageKey: "storage/ai",
                    mime: "text/markdown",
                    sizeBytes: aiMarkdown.utf8.count
                )
            ],
            recommendedViewer: "viewer_video"
        )
        let api = MockIngestionAPI(
            listResult: .success(
                IngestionListResponse(items: [makeListItem(id: file.id)])
            ),
            metaResult: .success(meta),
            contentResult: .failure(MockError.forced),
            contentResultsByKind: [
                "video_original": .success(Data([0x00, 0x00, 0x00, 0x00])),
                "ai_md": .success(Data(aiMarkdown.utf8))
            ],
            pinResult: .success(()),
            youtubeResult: .success("youtube")
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = TemporaryFileStore(directory: tempDirectory)
        let defaults = makeDefaults()
        let ingestionStore = IngestionStore(
            api: api,
            cache: TestCacheClient(),
            userDefaults: defaults
        )
        return IngestionViewModel(
            api: api,
            store: ingestionStore,
            temporaryStore: store,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )
    }

    private func makeListItem(id: String, status: String = "ready", stage: String = "done") -> IngestionListItem {
        IngestionListItem(
            file: makeFile(id: id),
            job: makeJob(status: status, stage: stage),
            recommendedViewer: "text_original"
        )
    }

    private func makePinnedListItem(id: String, pinnedOrder: Int) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: "\(id).txt",
                path: nil,
                mimeOriginal: "text/plain",
                sizeBytes: 10,
                sha256: nil,
                pinned: true,
                pinnedOrder: pinnedOrder,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: makeJob(),
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
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        return try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
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

private actor PinnedOrderRecorder {
    private var calls: [[String]] = []

    func record(_ ids: [String]) {
        calls.append(ids)
    }

    func snapshot() -> [[String]] {
        calls
    }

    func callCount() -> Int {
        calls.count
    }
}

private actor PollingSleepRecorder {
    private var recordedIntervals: [UInt64] = []

    func record(_ nanoseconds: UInt64) {
        recordedIntervals.append(nanoseconds)
    }

    func snapshot() -> [UInt64] {
        recordedIntervals
    }
}

@MainActor
private final class ControlledRenameIngestionAPI: IngestionProviding {
    let listResult: Result<IngestionListResponse, Error>
    let metaResult: Result<IngestionMetaResponse, Error>
    let contentResult: Result<Data, Error>
    let pinResult: Result<Void, Error>
    let youtubeResult: Result<String, Error>
    private var renameContinuation: CheckedContinuation<Void, Error>?

    init(
        listResult: Result<IngestionListResponse, Error>,
        metaResult: Result<IngestionMetaResponse, Error>,
        contentResult: Result<Data, Error>,
        pinResult: Result<Void, Error>,
        youtubeResult: Result<String, Error>
    ) {
        self.listResult = listResult
        self.metaResult = metaResult
        self.contentResult = contentResult
        self.pinResult = pinResult
        self.youtubeResult = youtubeResult
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

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw MockError.forced
    }

    func cancel(fileId: String) async throws {
        _ = fileId
        throw MockError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        try pinResult.get()
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
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
        try await withCheckedThrowingContinuation { continuation in
            renameContinuation = continuation
        }
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        return try youtubeResult.get()
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }

    func resumeRename() {
        guard let renameContinuation else { return }
        self.renameContinuation = nil
        renameContinuation.resume()
    }
}

private struct MockIngestionAPI: IngestionProviding {
    let listResult: Result<IngestionListResponse, Error>
    let metaResult: Result<IngestionMetaResponse, Error>
    let contentResult: Result<Data, Error>
    let contentResultsByKind: [String: Result<Data, Error>]
    let cancelResult: Result<Void, Error>
    let pinResult: Result<Void, Error>
    let updatePinnedOrderResult: Result<Void, Error>
    let youtubeResult: Result<String, Error>
    let onCancel: ((String) -> Void)?
    let pinnedOrderRecorder: PinnedOrderRecorder?

    init(
        listResult: Result<IngestionListResponse, Error>,
        metaResult: Result<IngestionMetaResponse, Error>,
        contentResult: Result<Data, Error>,
        contentResultsByKind: [String: Result<Data, Error>] = [:],
        cancelResult: Result<Void, Error> = .success(()),
        pinResult: Result<Void, Error>,
        updatePinnedOrderResult: Result<Void, Error> = .success(()),
        youtubeResult: Result<String, Error>,
        onCancel: ((String) -> Void)? = nil,
        pinnedOrderRecorder: PinnedOrderRecorder? = nil
    ) {
        self.listResult = listResult
        self.metaResult = metaResult
        self.contentResult = contentResult
        self.contentResultsByKind = contentResultsByKind
        self.cancelResult = cancelResult
        self.pinResult = pinResult
        self.updatePinnedOrderResult = updatePinnedOrderResult
        self.youtubeResult = youtubeResult
        self.onCancel = onCancel
        self.pinnedOrderRecorder = pinnedOrderRecorder
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
        _ = range
        if let contentResult = contentResultsByKind[kind] {
            return try contentResult.get()
        }
        return try contentResult.get()
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw MockError.forced
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

    func updatePinnedOrder(ids: [String]) async throws {
        await pinnedOrderRecorder?.record(ids)
        return try updatePinnedOrderResult.get()
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

private func makeTemporaryFileURL(filename: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    try Data("test".utf8).write(to: url, options: .atomic)
    return url
}

private func waitUntilPolling(
    timeoutSeconds: TimeInterval = 0.2,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while true {
        let isSatisfied = await condition()
        if isSatisfied {
            return
        }
        if Date() >= deadline {
            XCTFail("Timed out waiting for ingestion polling condition")
            return
        }
        await Task.yield()
    }
}
// swiftlint:enable file_length type_body_length
