// swiftlint:disable file_length
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
// swiftlint:disable:next type_body_length
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true),
            transcriptPollInterval: 60
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true),
            transcriptPollInterval: 60
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

    func testReorderPinnedWebsitesOptimisticallyUpdatesStoreAndCallsAPI() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        api.updatePinnedOrderResult = .success(())
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w1", pinnedOrder: 0, updatedAt: "2026-03-21T10:00:00Z"),
            persist: false
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w2", pinnedOrder: 1, updatedAt: "2026-03-21T11:00:00Z"),
            persist: false
        )

        let success = await viewModel.reorderPinnedWebsites(ids: ["w2", "w1"])

        XCTAssertTrue(success)
        XCTAssertEqual(api.updatedPinnedOrderIDs, [["w2", "w1"]])
        XCTAssertEqual(viewModel.panelPinnedItemsSorted.map(\.id), ["w2", "w1"])
    }

    func testReorderPinnedWebsitesRollsBackAndShowsErrorWhenAPIFails() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        api.updatePinnedOrderResult = .failure(MockError.forced)
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w1", pinnedOrder: 0, updatedAt: "2026-03-21T10:00:00Z"),
            persist: false
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w2", pinnedOrder: 1, updatedAt: "2026-03-21T11:00:00Z"),
            persist: false
        )

        let success = await viewModel.reorderPinnedWebsites(ids: ["w2", "w1"])

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.panelPinnedItemsSorted.map(\.id), ["w1", "w2"])
        XCTAssertEqual(viewModel.errorMessage, "Failed to reorder pinned websites")
    }

    func testReorderPinnedWebsitesDoesNotCallAPIWhenOffline() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w1", pinnedOrder: 0, updatedAt: "2026-03-21T10:00:00Z"),
            persist: false
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w2", pinnedOrder: 1, updatedAt: "2026-03-21T11:00:00Z"),
            persist: false
        )

        let success = await viewModel.reorderPinnedWebsites(ids: ["w2", "w1"])

        XCTAssertFalse(success)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)
    }

    func testReorderPinnedWebsitesRejectsStalePinnedSetWithoutCallingAPI() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        api.updatePinnedOrderResult = .success(())
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w1", pinnedOrder: 0, updatedAt: "2026-03-21T10:00:00Z"),
            persist: false
        )
        store.updateListItem(
            makePinnedWebsiteItem(id: "w2", pinnedOrder: 1, updatedAt: "2026-03-21T11:00:00Z"),
            persist: false
        )
        let previousOrder = viewModel.panelPinnedItemsSorted.map(\.id)

        let success = await viewModel.reorderPinnedWebsites(ids: ["w2"])

        XCTAssertFalse(success)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)
        XCTAssertEqual(viewModel.panelPinnedItemsSorted.map(\.id), previousOrder)
    }

    func testRenameWebsiteQueuesUpdateEvenWhenOnline() async throws {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.updateListItem(makeItem(id: "site-1", updatedAt: "2026-01-01T00:00:00Z"), persist: false)

        await viewModel.renameWebsite(id: "site-1", title: "Queued title")

        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.website.rawValue)
        XCTAssertEqual(store.items.first?.title, "Queued title")
    }

    func testDeleteWebsiteQueuesUpdateEvenWhenOnlineAndClearsSelection() async throws {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        store.updateListItem(makeItem(id: "site-1", updatedAt: "2026-01-01T00:00:00Z"), persist: false)
        viewModel.selectedWebsiteId = "site-1"

        await viewModel.deleteWebsite(id: "site-1")

        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.website.rawValue)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(viewModel.selectedWebsiteId)
    }

    func testSaveWebsiteQueuesPendingSelectionUntilJobCompletes() async {
        let item = makeItem(id: "site-1")
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [item])),
            getResult: .success(detail),
            saveResult: .success(WebsiteSaveJobResponse(
                jobId: "test-job-id",
                status: "queued"
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
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.pendingWebsite?.url, "https://example.com")
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "test-job-id")
        XCTAssertEqual(viewModel.selectedWebsiteId, viewModel.pendingWebsite?.id)
        XCTAssertNil(viewModel.active)
    }

    func testSaveWebsiteNormalizesUrl() async {
        let item = makeItem(id: "site-1")
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [item])),
            getResult: .success(detail),
            saveResult: .success(WebsiteSaveJobResponse(
                jobId: "test-job-id",
                status: "queued"
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
        XCTAssertEqual(viewModel.pendingWebsite?.title, "Reading...")
        XCTAssertEqual(viewModel.pendingWebsite?.status, .queued)
        XCTAssertEqual(viewModel.detailLoadingMessage, "Queued to read...")
        XCTAssertEqual(viewModel.selectedWebsiteId, viewModel.pendingWebsite?.id)
        XCTAssertTrue(viewModel.isLoadingDetail)

        api.resumeSave(
            result: .success(WebsiteSaveJobResponse(
                jobId: "test-job-id",
                status: "queued"
            ))
        )

        _ = await saveTask.value
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "test-job-id")
        XCTAssertTrue(viewModel.isLoadingDetail)
    }

    func testSaveWebsiteSetsWatchingPendingTitleForYouTube() async {
        let cache = InMemoryCacheClient()
        let api = ControlledWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let saveTask = Task {
            await viewModel.saveWebsite(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        }
        await Task.yield()

        XCTAssertNotNil(viewModel.pendingWebsite)
        XCTAssertEqual(viewModel.pendingWebsite?.title, "Watching...")
        XCTAssertEqual(viewModel.pendingWebsite?.status, .queued)
        XCTAssertEqual(viewModel.pendingWebsite?.statusLabel, "Queued")
        XCTAssertEqual(viewModel.detailLoadingMessage, "Queued to watch...")
        XCTAssertEqual(viewModel.selectedWebsiteId, viewModel.pendingWebsite?.id)
        XCTAssertTrue(viewModel.isLoadingDetail)

        api.resumeSave(
            result: .success(WebsiteSaveJobResponse(
                jobId: "test-job-id",
                status: "queued"
            ))
        )

        _ = await saveTask.value
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "test-job-id")
        XCTAssertTrue(viewModel.isLoadingDetail)
    }

    func testSaveWebsiteTreatsStalledJobAsFailure() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "stalled",
                    website: nil,
                    error: WebsiteJobError(
                        message: "Website save is still waiting for a worker. Try again."
                    )
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

        let saved = await viewModel.saveWebsite(url: "https://example.com")

        XCTAssertTrue(saved)
        XCTAssertTrue(viewModel.isLoadingDetail)

        let failed = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.pendingWebsite?.status == .failed
        }

        XCTAssertTrue(failed)
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertEqual(
            viewModel.saveErrorMessage,
            "Website save is still waiting for a worker. Try again."
        )
        XCTAssertEqual(viewModel.pendingWebsite?.url, "https://example.com")
        XCTAssertEqual(viewModel.pendingWebsite?.status, .failed)
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "job-1")
    }

    func testSaveWebsiteCompletesViaPollingWithoutRealtimeJobUpdate() async {
        let savedDetail = makeDetail(
            id: "saved-1",
            url: "https://example.com",
            domain: "example.com"
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "completed",
                    website: savedDetail,
                    error: nil
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

        let saved = await viewModel.saveWebsite(url: "https://example.com")

        XCTAssertTrue(saved)
        let completed = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.pendingWebsite == nil && viewModel.selectedWebsiteId == "saved-1"
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(viewModel.items.first?.id, "saved-1")
        XCTAssertEqual(viewModel.active?.id, "saved-1")
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertFalse(viewModel.isSavingWebsite)
        XCTAssertTrue(viewModel.jobPollingTasks.isEmpty)
    }

    func testWebsiteRealtimeInsertDoesNotClearPendingSaveBeforePollCompletes() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "queued",
                    website: nil,
                    error: nil
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

        let saved = await viewModel.saveWebsite(url: "https://example.com")

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "job-1")

        let payload = RealtimePayload(
            eventType: .insert,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "saved-1",
                title: "Saved",
                url: "https://example.com",
                domain: "example.com",
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2026-03-21T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        await viewModel.applyRealtimeEvent(payload)
        await Task.yield()

        XCTAssertEqual(viewModel.items.first?.id, "saved-1")
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "job-1")
        XCTAssertEqual(viewModel.pendingWebsite?.status, .queued)

        viewModel.jobPollingTasks["job-1"]?.cancel()
        viewModel.jobPollingTasks.removeValue(forKey: "job-1")
    }

    func testSaveWebsitePollingCanceledClearsPendingState() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "canceled",
                    website: nil,
                    error: nil
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

        let saved = await viewModel.saveWebsite(url: "https://example.com")

        XCTAssertTrue(saved)
        let canceled = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.pendingWebsite == nil && viewModel.jobPollingTasks.isEmpty
        }

        XCTAssertTrue(canceled)
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertFalse(viewModel.isSavingWebsite)
        XCTAssertNil(viewModel.saveErrorMessage)
    }

    func testRetryPendingWebsiteResubmitsFailedDirectSave() async {
        let cache = InMemoryCacheClient()
        let api = ControlledWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        viewModel.pendingWebsite = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-1",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com",
            canonicalURL: "https://example.com",
            source: .directSave,
            jobId: "job-1",
            status: .failed
        )
        viewModel.saveErrorMessage = "Timed out"

        let retryTask = Task { await viewModel.retryPendingWebsite(id: "pending-1") }
        await Task.yield()

        XCTAssertEqual(viewModel.pendingWebsite?.status, .retrying)
        XCTAssertEqual(viewModel.pendingWebsite?.id, "pending-1")
        XCTAssertTrue(viewModel.isLoadingDetail)
        XCTAssertEqual(viewModel.detailLoadingMessage, "Retrying website save...")
        XCTAssertNil(viewModel.saveErrorMessage)

        api.resumeSave(
            result: .success(
                WebsiteSaveJobResponse(
                    jobId: "job-2",
                    status: "queued"
                )
            )
        )

        let retried = await retryTask.value
        XCTAssertTrue(retried)
        XCTAssertEqual(viewModel.pendingWebsite?.jobId, "job-2")
        XCTAssertEqual(api.savedURLs, ["https://example.com"])
    }

    func testCancelWebsiteSaveCallsAPIAndClearsPendingState() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            cancelResult: .success(())
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-1",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com",
            canonicalURL: "https://example.com",
            source: .directSave,
            jobId: "job-1",
            status: .reading
        )
        viewModel.pendingWebsite = pending
        viewModel.selectedWebsiteId = pending.id
        viewModel.isLoadingDetail = true
        viewModel.isSavingWebsite = true
        viewModel.jobPollingTasks["job-1"] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }

        await viewModel.cancelWebsiteSave()

        XCTAssertEqual(api.canceledJobIds, ["job-1"])
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertFalse(viewModel.isSavingWebsite)
        XCTAssertNil(viewModel.pendingWebsite)
        XCTAssertTrue(viewModel.jobPollingTasks.isEmpty)
    }

    func testContinuePendingWebsiteJobsInBackgroundCompletesSavedWebsite() async {
        let completedDetail = makeDetail(
            id: "saved-1",
            url: "https://example.com",
            domain: "example.com",
            content: "Saved content",
            updatedAt: "2026-03-21T10:00:00Z"
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "completed",
                    website: completedDetail,
                    error: nil
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
        viewModel.pendingWebsite = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-1",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com",
            canonicalURL: "https://example.com",
            source: .directSave,
            jobId: "job-1",
            status: .queued,
            selectionFallbackId: "site-existing"
        )

        let completed = await viewModel.continuePendingWebsiteJobsInBackground(maxDuration: 2)

        XCTAssertTrue(completed)
        XCTAssertTrue(viewModel.pendingWebsites.isEmpty)
        XCTAssertEqual(viewModel.items.first?.id, "saved-1")
        XCTAssertEqual(viewModel.selectedWebsiteId, "saved-1")
    }

    func testWebsiteRealtimeInsertDoesNotClearPendingYouTubeCandidate() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        viewModel.showPendingFromExtension(url: "https://youtu.be/abc123xyzAA?t=10&si=token")
        XCTAssertNotNil(viewModel.pendingWebsite)

        let payload = RealtimePayload(
            eventType: .insert,
            table: RealtimeTable.websites,
            schema: "public",
            record: WebsiteRealtimeRecord(
                id: "site-yt-1",
                title: "Video",
                url: "https://www.youtube.com/watch?v=abc123xyzAA",
                domain: "youtube.com",
                metadata: nil,
                savedAt: nil,
                publishedAt: nil,
                readingTime: nil,
                updatedAt: "2026-02-17T10:00:00Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        await viewModel.applyRealtimeEvent(payload)

        XCTAssertNotNil(viewModel.pendingWebsite)
        XCTAssertEqual(
            viewModel.pendingWebsite?.canonicalURL,
            "https://www.youtube.com/watch?v=abc123xyzAA"
        )
    }

    func testShowPendingFromExtensionAccumulatesMultipleQueuedWebsites() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        viewModel.showPendingFromExtension(url: "https://example.com/one")
        viewModel.showPendingFromExtension(url: "https://example.org/two")

        XCTAssertEqual(viewModel.pendingWebsites.count, 2)
        XCTAssertEqual(
            Set(viewModel.pendingWebsites.map(\.url)),
            Set(["https://example.com/one", "https://example.org/two"])
        )
        XCTAssertTrue(viewModel.pendingWebsites.allSatisfy { $0.source == .queuedShare })
    }

    func testShowPendingFromExtensionDeduplicatesCanonicalURL() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        viewModel.showPendingFromExtension(url: "https://youtu.be/abc123xyzAA?t=10")
        viewModel.showPendingFromExtension(url: "https://www.youtube.com/watch?v=abc123xyzAA")

        XCTAssertEqual(viewModel.pendingWebsites.count, 1)
    }

    func testSyncPendingWebsitesFromQueuedSharesReconcilesQueuedRows() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        viewModel.pendingWebsite = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-direct",
            title: "Reading...",
            domain: "manual.example",
            url: "https://manual.example",
            canonicalURL: "https://manual.example",
            source: .directSave
        )
        let queuedId = UUID()
        viewModel.syncPendingWebsitesFromQueuedShares([
            PendingShareItem(
                id: queuedId,
                kind: .website,
                createdAt: Date(),
                url: "https://queued.example/path"
            )
        ])
        XCTAssertEqual(viewModel.pendingWebsites.count, 2)
        XCTAssertTrue(
            viewModel.pendingWebsites.contains {
                $0.source == .queuedShare &&
                $0.queueItemId == queuedId &&
                $0.status == .queued
            }
        )

        viewModel.syncPendingWebsitesFromQueuedShares([])
        XCTAssertEqual(viewModel.pendingWebsites.count, 1)
        XCTAssertEqual(viewModel.pendingWebsites.first?.source, .directSave)
    }

    func testSyncPendingWebsitesFromQueuedSharesMapsRetryingAndFailedStates() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let queuedURL = "https://queued.example/path"
        let retryURL = "https://retry.example/path"
        let failedURL = "https://failed.example/path"
        let now = Date()
        viewModel.syncPendingWebsitesFromQueuedShares([
            PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: now,
                url: queuedURL
            ),
            PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: now,
                url: retryURL,
                retryCount: 1,
                nextRetryAt: now.addingTimeInterval(30)
            ),
            PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: now,
                url: failedURL,
                retryCount: pendingWebsiteQueueMaxRetryCount,
                nextRetryAt: nil,
                lastError: "Request failed (HTTP 503)."
            )
        ])

        let statusByURL = Dictionary(
            uniqueKeysWithValues: viewModel.pendingWebsites.map { ($0.url, $0.status) }
        )
        XCTAssertEqual(statusByURL[queuedURL], .queued)
        XCTAssertEqual(statusByURL[retryURL], .retrying)
        XCTAssertEqual(statusByURL[failedURL], .failed)
    }

    func testSyncPendingWebsitesFromQueuedSharesMarksProvidedItemAsReading() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let readingId = UUID()
        viewModel.syncPendingWebsitesFromQueuedShares(
            [
                PendingShareItem(
                    id: readingId,
                    kind: .website,
                    createdAt: Date(),
                    url: "https://reading.example/path"
                )
            ],
            readingQueueItemId: readingId
        )

        XCTAssertEqual(viewModel.pendingWebsites.first?.status, .reading)
    }

    func testSyncPendingWebsitesFromQueuedSharesSkipsWebsiteAlreadyInSavedList() async {
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let saved = makeItem(
            id: "site-existing",
            url: "https://example.com/articles/already-saved",
            domain: "example.com"
        )
        store.insertItemAtTop(saved, persist: false)

        viewModel.syncPendingWebsitesFromQueuedShares([
            PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: Date(),
                url: "https://example.com/articles/already-saved"
            )
        ])

        XCTAssertTrue(viewModel.pendingWebsites.isEmpty)
    }

    func testSaveWebsiteWithoutSelectionPreservesCurrentDetail() async {
        let existing = makeItem(id: "site-existing")
        let existingDetail = makeDetail(id: "site-existing")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [existing])),
            getResult: .success(existingDetail),
            saveResult: .success(WebsiteSaveJobResponse(
                jobId: "test-job-id",
                status: "queued"
            ))
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.load()
        await viewModel.selectWebsite(id: "site-existing")
        let saved = await viewModel.saveWebsite(url: "https://new.example", selectAfterSave: false)

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.selectedWebsiteId, "site-existing")
        XCTAssertEqual(viewModel.active?.id, "site-existing")
        XCTAssertEqual(viewModel.pendingWebsites.first?.url, "https://new.example")
        XCTAssertEqual(viewModel.pendingWebsites.first?.jobId, "test-job-id")
        XCTAssertFalse(viewModel.items.contains(where: { $0.url == "https://new.example" }))
    }

    func testSaveWebsiteWithoutSelectionKeepsQueuedPendingRowAfterAsyncEnqueue() async {
        let cache = InMemoryCacheClient()
        let api = ControlledWebsitesAPI()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let saveTask = Task {
            await viewModel.saveWebsite(url: "https://queued.example/path", selectAfterSave: false)
        }
        await Task.yield()

        XCTAssertEqual(viewModel.pendingWebsites.count, 1)
        XCTAssertEqual(viewModel.pendingWebsites.first?.source, .queuedShare)
        XCTAssertEqual(viewModel.pendingWebsites.first?.status, .queued)

        api.resumeSave(
            result: .success(
                WebsiteSaveJobResponse(
                    jobId: "test-job-id",
                    status: "queued"
                )
            )
        )

        _ = await saveTask.value
        XCTAssertEqual(viewModel.pendingWebsites.count, 1)
        XCTAssertEqual(viewModel.pendingWebsites.first?.jobId, "test-job-id")
    }

    func testSaveWebsiteWithoutSelectionKeepsPendingRowAfterAsyncAcceptance() async {
        let savedItem = makeItem(
            id: "site-queued-1",
            url: "https://queued.example/path",
            domain: "queued.example"
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [savedItem])),
            saveResult: .success(
                WebsiteSaveJobResponse(
                    jobId: "test-job-id",
                    status: "queued"
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

        let saved = await viewModel.saveWebsite(
            url: "https://queued.example/path",
            selectAfterSave: false
        )

        XCTAssertTrue(saved)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.pendingWebsites.first?.url, "https://queued.example/path")
        XCTAssertEqual(viewModel.pendingWebsites.first?.jobId, "test-job-id")
        XCTAssertNil(viewModel.saveErrorMessage)
    }

    func testSaveWebsiteWithoutSelectionDoesNotSelectSavedWebsiteOnPollCompletion() async {
        let existing = makeItem(id: "site-existing")
        let existingDetail = makeDetail(
            id: "site-existing",
            content: "Existing content",
            updatedAt: "2026-03-20T10:00:00Z"
        )
        let completedDetail = makeDetail(
            id: "saved-1",
            url: "https://new.example",
            domain: "new.example",
            content: "New saved content",
            updatedAt: "2026-03-21T10:00:00Z"
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [existing])),
            getResult: .success(existingDetail),
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-1",
                    status: "completed",
                    website: completedDetail,
                    error: nil
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

        await viewModel.load()
        await viewModel.selectWebsite(id: "site-existing")

        let saved = await viewModel.saveWebsite(
            url: "https://new.example",
            selectAfterSave: false
        )

        XCTAssertTrue(saved)
        let completed = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.pendingWebsites.isEmpty
                && viewModel.items.contains(where: { $0.id == "saved-1" })
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(viewModel.selectedWebsiteId, "site-existing")
        XCTAssertEqual(viewModel.active?.id, "site-existing")
        XCTAssertEqual(viewModel.active?.content, "Existing content")
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertFalse(viewModel.isSavingWebsite)
    }

    func testSaveWebsiteWithoutSelectionFailsWhenSaveRequestFailsEvenIfListCouldContainWebsite() async {
        let savedItem = makeItem(
            id: "site-queued-1",
            url: "https://queued.example/path",
            domain: "queued.example"
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [savedItem])),
            saveResult: .failure(MockError.forced)
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        let saved = await viewModel.saveWebsite(
            url: "https://queued.example/path",
            selectAfterSave: false
        )

        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.pendingWebsites.first?.url, "https://queued.example/path")
        XCTAssertEqual(viewModel.pendingWebsites.first?.status, .failed)
        XCTAssertEqual(viewModel.saveErrorMessage, ErrorMapping.message(for: MockError.forced))
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
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        await viewModel.deleteWebsite(id: "site-1")

        let pending = try? await writeQueue.fetchPendingWrites()
        XCTAssertNil(viewModel.selectedWebsiteId)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(pending?.count, 1)
    }

    func testArchiveWebsiteClearsSelectionWhenActiveMatches() async throws {
        let cache = InMemoryCacheClient()
        let archivedItem = WebsiteItem(
            id: "site-1",
            title: "Site",
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
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [makeItem(id: "site-1")])),
            getResult: .success(makeDetail(id: "site-1")),
            archiveResult: .success(archivedItem)
        )
        let store = WebsitesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.load()
        try await store.loadDetail(id: "site-1")
        XCTAssertEqual(viewModel.active?.id, "site-1")
        XCTAssertNil(viewModel.selectedWebsiteId)

        await viewModel.setArchived(id: "site-1", archived: true)

        let pending = try await writeQueue.fetchPendingWrites()
        XCTAssertNil(viewModel.active)
        XCTAssertNil(viewModel.selectedWebsiteId)
        XCTAssertEqual(pending.count, 1)
    }

    func testDeleteWebsiteQueuesWriteUsingListUpdatedAt() async throws {
        let staleUpdatedAt = "2026-02-08T14:19:25.939359+00:00"
        let staleItem = makeItem(id: "site-1", updatedAt: staleUpdatedAt)
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(listResult: .success(WebsitesResponse(items: [staleItem])))
        let store = WebsitesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.load(force: true)
        await viewModel.deleteWebsite(id: "site-1")

        let pendingWrites = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        let payload = try XCTUnwrap(pendingWrites.first?.payload)
        let operation = try JSONDecoder().decode(WebsiteOperationPayload.self, from: payload)
        XCTAssertEqual(operation.clientUpdatedAt, staleUpdatedAt)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteWebsiteUsesFreshestUpdatedAtFromActiveDetail() async throws {
        let staleUpdatedAt = "2026-02-08T14:19:25.939359+00:00"
        let freshUpdatedAt = "2026-02-08T14:20:06.958809+00:00"
        let staleItem = makeItem(id: "site-1", updatedAt: staleUpdatedAt)
        let detail = makeDetail(id: "site-1", updatedAt: freshUpdatedAt)
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            listResult: .success(WebsitesResponse(items: [staleItem])),
            getResult: .success(detail),
            deleteResult: .success(())
        )
        let store = WebsitesStore(api: api, cache: cache)
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.load(force: true)
        await viewModel.selectWebsite(id: "site-1")
        await viewModel.deleteWebsite(id: "site-1")

        let pendingWrites = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        let payload = try XCTUnwrap(pendingWrites.first?.payload)
        let operation = try JSONDecoder().decode(WebsiteOperationPayload.self, from: payload)
        XCTAssertEqual(operation.clientUpdatedAt, freshUpdatedAt)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
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
        for _ in 0..<10 where viewModel.active?.id != "site-1" {
            await Task.yield()
        }
        await viewModel.requestYouTubeTranscript(
            websiteId: "site-1",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        let queued = await waitForCondition {
            store.active?.youtubeTranscripts?["dQw4w9WgXcQ"] != nil
        }
        XCTAssertTrue(queued)

        XCTAssertEqual(
            store.active?.youtubeTranscripts?["dQw4w9WgXcQ"]?.status,
            "queued"
        )
        XCTAssertEqual(
            store.active?.youtubeTranscripts?["dQw4w9WgXcQ"]?.fileId,
            "file-1"
        )
    }

    func testTranscriptPendingUsesIngestionStoreJobState() async {
        let cache = InMemoryCacheClient()
        let websitesAPI = MockWebsitesAPI(getResult: .success(makeDetail(id: "site-1")))
        let websitesStore = WebsitesStore(api: websitesAPI, cache: cache)
        let ingestionStore = IngestionStore(
            api: MockIngestionAPI(),
            cache: InMemoryCacheClient()
        )
        let viewModel = WebsitesViewModel(
            api: websitesAPI,
            store: websitesStore,
            ingestionStore: ingestionStore,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        let pendingItem = IngestionListItem(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "YouTube transcript",
                path: nil,
                mimeOriginal: "video/youtube",
                sizeBytes: 0,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                sourceMetadata: [
                    "website_transcript": AnyCodable(true),
                    "website_id": AnyCodable("site-1"),
                    "video_id": AnyCodable("dQw4w9WgXcQ")
                ],
                createdAt: "2026-02-07T10:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "processing",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: 0.5,
                attempts: 0,
                updatedAt: "2026-02-07T10:00:00Z"
            ),
            recommendedViewer: nil
        )
        ingestionStore.addLocalUpload(pendingItem)
        await Task.yield()

        XCTAssertTrue(
            viewModel.isTranscriptPending(websiteId: "site-1", videoId: "dQw4w9WgXcQ")
        )
    }

    func testRequestYouTubeTranscriptSetsPendingStateWhileRequestInFlight() async {
        let detail = makeDetail(id: "site-1")
        let gate = ControlledTranscriptRequest()
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            getResult: .success(detail),
            transcribeHandler: { _, _ in
                try await gate.waitForResult()
            }
        )
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        let requestTask = Task {
            await viewModel.requestYouTubeTranscript(
                websiteId: "site-1",
                url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            )
        }

        for _ in 0..<10 where viewModel.isTranscriptPending(
            websiteId: "site-1",
            videoId: "dQw4w9WgXcQ"
        ) == false {
            await Task.yield()
        }
        XCTAssertTrue(
            viewModel.isTranscriptPending(websiteId: "site-1", videoId: "dQw4w9WgXcQ")
        )

        gate.resume(with: .failure(MockError.forced))
        _ = await requestTask.value
        XCTAssertFalse(
            viewModel.isTranscriptPending(websiteId: "site-1", videoId: "dQw4w9WgXcQ")
        )
    }

    func testRequestYouTubeTranscriptShowsFriendlyToastOnFailure() async {
        let detail = makeDetail(id: "site-1")
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            getResult: .success(detail),
            transcribeResult: .failure(MockError.forced)
        )
        let toastCenter = ToastCenter()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        await viewModel.requestYouTubeTranscript(
            websiteId: "site-1",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        XCTAssertEqual(
            toastCenter.toast?.message,
            "Couldn't get the transcript right now. Please try again."
        )
        if case .error? = toastCenter.toast?.style {
        } else {
            XCTFail("Expected transcript failure toast style to be error")
        }
    }

    func testTranscriptReadyStateOverridesStalePendingIngestionJob() async {
        let videoId = "dQw4w9WgXcQ"
        let readyEntry = WebsiteTranscriptEntry(
            status: "ready",
            fileId: "file-1",
            updatedAt: "2026-02-07T10:00:00Z",
            error: nil
        )
        let detail = makeDetail(
            id: "site-1",
            youtubeTranscripts: [videoId: readyEntry]
        )
        let cache = InMemoryCacheClient()
        let websitesAPI = MockWebsitesAPI(getResult: .success(detail))
        let websitesStore = WebsitesStore(api: websitesAPI, cache: cache)
        let ingestionStore = IngestionStore(
            api: MockIngestionAPI(),
            cache: InMemoryCacheClient()
        )
        let viewModel = WebsitesViewModel(
            api: websitesAPI,
            store: websitesStore,
            ingestionStore: ingestionStore,
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(isNetworkAvailable: true)
        )

        await viewModel.selectWebsite(id: "site-1")
        let pendingItem = IngestionListItem(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "YouTube transcript",
                path: nil,
                mimeOriginal: "video/youtube",
                sizeBytes: 0,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                sourceMetadata: [
                    "website_transcript": AnyCodable(true),
                    "website_id": AnyCodable("site-1"),
                    "video_id": AnyCodable("dQw4w9WgXcQ")
                ],
                createdAt: "2026-02-07T10:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "processing",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: 0.5,
                attempts: 0,
                updatedAt: "2026-02-07T10:00:00Z"
            ),
            recommendedViewer: nil
        )
        ingestionStore.addLocalUpload(pendingItem)
        await Task.yield()

        XCTAssertFalse(
            viewModel.isTranscriptPending(websiteId: "site-1", videoId: videoId)
        )
    }

    func testRequestYouTubeTranscriptPollsAndLoadsReadyTranscriptContent() async {
        let videoId = "dQw4w9WgXcQ"
        let queuedDetail = makeDetail(
            id: "site-1",
            content: "Before",
            youtubeTranscripts: [
                videoId: WebsiteTranscriptEntry(
                    status: "queued",
                    fileId: "file-1",
                    updatedAt: "2026-02-07T10:00:00Z",
                    error: nil
                )
            ]
        )
        let readyDetail = makeDetail(
            id: "site-1",
            content: "Before\n\n<!-- YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ -->\n\nTranscript",
            youtubeTranscripts: [
                videoId: WebsiteTranscriptEntry(
                    status: "ready",
                    fileId: "file-1",
                    updatedAt: "2026-02-07T10:00:05Z",
                    error: nil
                )
            ]
        )
        let cache = InMemoryCacheClient()
        let api = MockWebsitesAPI(
            getResult: .success(queuedDetail),
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
            networkStatus: TestNetworkStatus(isNetworkAvailable: true),
            transcriptPollInterval: 0,
            transcriptPollMaxInterval: 0,
            transcriptPollJitterWindow: 0,
            transcriptPollMinimumInterval: 0
        )

        await viewModel.selectWebsite(id: "site-1")
        api.enqueueGetResult(.success(readyDetail))

        await viewModel.requestYouTubeTranscript(
            websiteId: "site-1",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        let loadedTranscript = await waitForCondition {
            viewModel.active?.content.contains("YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ") == true
        }
        XCTAssertTrue(loadedTranscript)

        XCTAssertEqual(
            viewModel.active?.youtubeTranscripts?[videoId]?.status?.lowercased(),
            "ready"
        )
        XCTAssertTrue(viewModel.active?.content.contains("YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ") == true)
    }

    func testTranscriptPollingStopsAfterRepeatedFailuresAndMarksTranscriptFailed() async {
        let videoId = "dQw4w9WgXcQ"
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
        let toastCenter = ToastCenter()
        let store = WebsitesStore(api: api, cache: cache)
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: TestNetworkStatus(isNetworkAvailable: true),
            transcriptPollInterval: 0,
            transcriptPollMaxInterval: 0,
            transcriptPollMaxConsecutiveFailures: 2,
            transcriptPollJitterWindow: 0,
            transcriptPollMinimumInterval: 0
        )

        await viewModel.selectWebsite(id: "site-1")
        api.enqueueGetResult(.failure(MockError.forced))
        api.enqueueGetResult(.failure(MockError.forced))

        await viewModel.requestYouTubeTranscript(
            websiteId: "site-1",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )

        let failed = await waitForCondition {
            viewModel.active?.youtubeTranscripts?[videoId]?.status == "failed"
        }
        XCTAssertTrue(failed)

        XCTAssertEqual(
            viewModel.active?.youtubeTranscripts?[videoId]?.status,
            "failed"
        )
        XCTAssertEqual(
            viewModel.active?.youtubeTranscripts?[videoId]?.error,
            "Could not refresh transcript status. Retry transcription."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Could not refresh transcript status. Retry transcription."
        )
        XCTAssertEqual(
            toastCenter.toast?.message,
            "Couldn't get the transcript right now. Please try again."
        )
        XCTAssertTrue(viewModel.transcriptPollingTasks.isEmpty)
    }
}

extension WebsitesViewModelTests {
    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 250_000_000,
        pollNanoseconds: UInt64 = 1_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return true
            }
            if pollNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
        return condition()
    }
}

private enum MockError: Error {
    case forced
}

@MainActor
private final class ControlledTranscriptRequest {
    private var continuation: CheckedContinuation<WebsiteTranscriptResponse, Error>?

    func waitForResult() async throws -> WebsiteTranscriptResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: Result<WebsiteTranscriptResponse, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
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
    let saveResult: Result<WebsiteSaveJobResponse, Error>
    let jobStatusResult: Result<WebsiteJobStatusResponse, Error>
    let cancelResult: Result<Void, Error>
    let transcribeResult: Result<WebsiteTranscriptResponse, Error>
    let pinResult: Result<WebsiteItem, Error>
    let renameResult: Result<WebsiteItem, Error>
    let archiveResult: Result<WebsiteItem, Error>
    let deleteResult: Result<Void, Error>
    let syncResult: Result<WebsiteSyncResponse, Error>
    let transcribeHandler: ((_ id: String, _ url: String) async throws -> WebsiteTranscriptResponse)?
    private(set) var lastSavedUrl: String?
    private(set) var canceledJobIds: [String] = []
    private(set) var updatedPinnedOrderIDs: [[String]] = []
    private(set) var updatePinnedOrderCallCount = 0
    var updatePinnedOrderResult: Result<Void, Error> = .success(())
    private(set) var deleteRequestUpdatedAts: [String?] = []
    private var queuedListResults: [Result<WebsitesResponse, Error>] = []
    private var queuedGetResults: [Result<WebsiteDetail, Error>] = []
    private var queuedDeleteResults: [Result<Void, Error>] = []

    init(
        listResult: Result<WebsitesResponse, Error> = .failure(MockError.forced),
        getResult: Result<WebsiteDetail, Error> = .failure(MockError.forced),
        saveResult: Result<WebsiteSaveJobResponse, Error> = .failure(MockError.forced),
        jobStatusResult: Result<WebsiteJobStatusResponse, Error> = .failure(MockError.forced),
        cancelResult: Result<Void, Error> = .failure(MockError.forced),
        transcribeResult: Result<WebsiteTranscriptResponse, Error> = .failure(MockError.forced),
        transcribeHandler: ((_ id: String, _ url: String) async throws -> WebsiteTranscriptResponse)? = nil,
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
        self.jobStatusResult = jobStatusResult
        self.cancelResult = cancelResult
        self.transcribeResult = transcribeResult
        self.transcribeHandler = transcribeHandler
        self.pinResult = pinResult
        self.renameResult = renameResult
        self.archiveResult = archiveResult
        self.deleteResult = deleteResult
        self.syncResult = syncResult
    }

    func list() async throws -> WebsitesResponse {
        if !queuedListResults.isEmpty {
            return try queuedListResults.removeFirst().get()
        }
        return try listResult.get()
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return try listResult.get()
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        if !queuedGetResults.isEmpty {
            return try queuedGetResults.removeFirst().get()
        }
        return try getResult.get()
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        lastSavedUrl = url
        return try saveResult.get()
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        return try jobStatusResult.get()
    }

    func cancel(jobId: String) async throws {
        canceledJobIds.append(jobId)
        try cancelResult.get()
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        if let transcribeHandler {
            return try await transcribeHandler(id, url)
        }
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

    func updatePinnedOrder(ids: [String]) async throws {
        updatePinnedOrderCallCount += 1
        updatedPinnedOrderIDs.append(ids)
        try updatePinnedOrderResult.get()
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        deleteRequestUpdatedAts.append(clientUpdatedAt)
        if !queuedDeleteResults.isEmpty {
            try queuedDeleteResults.removeFirst().get()
            return
        }
        try deleteResult.get()
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        return try syncResult.get()
    }

    func enqueueGetResult(_ result: Result<WebsiteDetail, Error>) {
        queuedGetResults.append(result)
    }

    func enqueueListResult(_ result: Result<WebsitesResponse, Error>) {
        queuedListResults.append(result)
    }

    func enqueueDeleteResult(_ result: Result<Void, Error>) {
        queuedDeleteResults.append(result)
    }
}

private final class ControlledWebsitesAPI: WebsitesProviding {
    private var saveContinuation: CheckedContinuation<WebsiteSaveJobResponse, Error>?
    private(set) var savedURLs: [String] = []

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

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        savedURLs.append(url)
        return try await withCheckedThrowingContinuation { continuation in
            saveContinuation = continuation
        }
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw MockError.forced
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

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        return WebsiteSyncResponse(applied: [], websites: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }

    func resumeSave(result: Result<WebsiteSaveJobResponse, Error>) {
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

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw MockError.forced
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
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

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
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

private final class MockIngestionAPI: IngestionProviding {
    func list() async throws -> IngestionListResponse {
        IngestionListResponse(items: [])
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        throw MockError.forced
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw MockError.forced
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
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw MockError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }
}

private func makeItem(
    id: String,
    url: String = "https://example.com",
    domain: String = "example.com",
    updatedAt: String? = nil
) -> WebsiteItem {
    WebsiteItem(
        id: id,
        title: "Site",
        url: url,
        domain: domain,
        savedAt: nil,
        publishedAt: nil,
        pinned: false,
        pinnedOrder: nil,
        archived: false,
        faviconUrl: nil,
        faviconR2Key: nil,
        youtubeTranscripts: nil,
        readingTime: nil,
        updatedAt: updatedAt,
        lastOpenedAt: nil,
        deletedAt: nil
    )
}

private func makePinnedWebsiteItem(
    id: String,
    pinnedOrder: Int,
    updatedAt: String
) -> WebsiteItem {
    WebsiteItem(
        id: id,
        title: "Site",
        url: "https://example.com/\(id)",
        domain: "example.com",
        savedAt: updatedAt,
        publishedAt: nil,
        pinned: true,
        pinnedOrder: pinnedOrder,
        archived: false,
        faviconUrl: nil,
        faviconR2Key: nil,
        youtubeTranscripts: nil,
        readingTime: nil,
        updatedAt: updatedAt,
        lastOpenedAt: nil,
        deletedAt: nil
    )
}

private func makeDetail(
    id: String,
    title: String = "Site",
    url: String = "https://example.com",
    domain: String = "example.com",
    content: String = "Example",
    youtubeTranscripts: [String: WebsiteTranscriptEntry]? = nil,
    updatedAt: String? = nil
) -> WebsiteDetail {
    WebsiteDetail(
        id: id,
        title: title,
        url: url,
        urlFull: nil,
        domain: domain,
        content: content,
        source: nil,
        savedAt: nil,
        publishedAt: nil,
        pinned: false,
        pinnedOrder: nil,
        archived: false,
        faviconUrl: nil,
        faviconR2Key: nil,
        youtubeTranscripts: youtubeTranscripts,
        readingTime: nil,
        updatedAt: updatedAt,
        lastOpenedAt: nil
    )
}
