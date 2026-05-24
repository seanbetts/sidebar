// swiftlint:disable file_length
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
// swiftlint:disable:next type_body_length
final class AppEnvironmentPendingWebsiteQueueTests: XCTestCase {
    var retainedEnvironments: [AppEnvironment] = []
    var environment: AppEnvironment!
    var storage: AppEnvironmentStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var baseDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "AppEnvironmentPendingWebsiteQueueTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        let widgetDataManager = WidgetDataManager(userDefaults: defaults)
        let extensionEventStore = ExtensionEventStore(userDefaults: defaults)
        let pendingShareStore = PendingShareStore(baseDirectory: baseDirectory, userDefaults: defaults)
        storage = AppEnvironmentStorage(
            userDefaults: defaults,
            widgetDataManager: widgetDataManager,
            extensionEventStore: extensionEventStore,
            pendingShareStore: pendingShareStore
        )
        retainedEnvironments.removeAll()
        environment = makeEnvironment(storage: storage)
        clearWidgetPendingOperations()
        clearExtensionEvents()
        resetDeepLinkState(environment)
    }

    override func tearDown() {
        resetDeepLinkState(environment)
        environment = nil
        retainedEnvironments.removeAll()
        clearWidgetPendingOperations()
        clearExtensionEvents()
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let baseDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        storage = nil
        environment = nil
        defaults = nil
        suiteName = nil
        baseDirectory = nil
        super.tearDown()
    }

    func testConsumePendingSharesPrunesQueuedWebsiteAlreadySavedInList() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let savedItem = WebsiteItem(
            id: "website-\(UUID().uuidString)",
            title: "Already Saved",
            url: url,
            domain: "example.com",
            savedAt: "2026-03-16T15:37:50Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-16T15:37:50Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 1)),
            listResult: .success(WebsitesResponse(items: [savedItem], archivedCount: 0))
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        _ = storage.pendingShareStore.enqueueWebsite(url: url)
        await environment.websitesViewModel.load(force: true)
        await environment.consumePendingShares()

        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
        XCTAssertEqual(environment.websitesViewModel.items.first?.url, url)
    }

    func testHasPendingWebsiteCoordinatorWorkIncludesQueuedExtensionWebsiteEvents() {
        let environment = requireEnvironment()

        XCTAssertFalse(environment.hasPendingWebsiteCoordinatorWork)

        storage.extensionEventStore.recordWebsiteSaved(
            url: "https://example.com/articles/\(UUID().uuidString)"
        )

        XCTAssertTrue(environment.hasPendingWebsiteCoordinatorWork)
        XCTAssertFalse(environment.hasPendingWebsiteBackgroundWork)
    }

    func testConsumePendingSharesWhenBiometricUnlockRequiredDefersUntilUnlock() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI, hasAuthToken: false)
        let environment = requireEnvironment()
        storage.userDefaults.set(true, forKey: AppStorageKeys.biometricUnlockEnabled)
        environment.authState = .active
        environment.isBiometricUnlocked = false

        _ = storage.pendingShareStore.enqueueWebsite(url: url)

        await environment.consumePendingShares()

        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(storage.pendingShareStore.loadAll().count, 1)

        await environment.completeBiometricUnlock()

        for _ in 0..<20 where websitesAPI.saveCallCount == 0 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(websitesAPI.saveCallCount, 1)
    }

    func testRemovePendingQueuedWebsiteDoesNotResurrectFailedItem() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let gate = AsyncGate()
        let saveStarted = expectation(description: "queued website save started")
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 2)),
            onSave: { _ in
                saveStarted.fulfill()
                await gate.wait()
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)

        let consumeTask = Task {
            await environment.consumePendingShares()
        }

        await fulfillment(of: [saveStarted], timeout: 1.0)
        environment.removePendingQueuedWebsite(queuedItem!.id)
        await gate.open()
        await consumeTask.value

        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
    }

    func testCancelPendingWebsiteCancelsBackendJobAndClearsQueuedState() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 3)),
            cancelResult: .success(())
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)
        environment.websitesViewModel.pendingWebsites = [
            WebsitesViewModel.PendingWebsiteItem(
                id: "pending-1",
                title: "Reading...",
                domain: "example.com",
                url: url,
                canonicalURL: url,
                source: .queuedShare,
                queueItemId: queuedItem?.id,
                jobId: "job-1",
                status: .reading
            )
        ]
        environment.websitesViewModel.selectedWebsiteId = "pending-1"
        environment.websitesViewModel.isLoadingDetail = true
        environment.websitesViewModel.isSavingWebsite = true
        environment.websitesViewModel.jobPollingTasks["job-1"] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }

        await environment.cancelPendingWebsite(environment.websitesViewModel.pendingWebsites[0])

        XCTAssertEqual(websitesAPI.canceledJobIds, ["job-1"])
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
        XCTAssertTrue(environment.websitesViewModel.jobPollingTasks.isEmpty)
        XCTAssertFalse(environment.websitesViewModel.isLoadingDetail)
        XCTAssertFalse(environment.websitesViewModel.isSavingWebsite)
    }

    func testRemoveFailedQueuedWebsiteLeavesOtherFailedRowsVisible() async {
        let firstURL = "https://example.com/articles/\(UUID().uuidString)"
        let secondURL = "https://example.com/articles/\(UUID().uuidString)"
        let environment = requireEnvironment()

        let firstQueued = storage.pendingShareStore.enqueueWebsite(url: firstURL)
        let secondQueued = storage.pendingShareStore.enqueueWebsite(url: secondURL)
        XCTAssertNotNil(firstQueued)
        XCTAssertNotNil(secondQueued)

        let now = Date()
        storage.pendingShareStore.replaceAll([
            PendingShareItem(
                id: firstQueued!.id,
                kind: .website,
                createdAt: now,
                url: firstURL,
                retryCount: pendingWebsiteQueueMaxRetryCount,
                nextRetryAt: nil,
                lastError: "Request failed (HTTP 503)."
            ),
            PendingShareItem(
                id: secondQueued!.id,
                kind: .website,
                createdAt: now,
                url: secondURL,
                retryCount: pendingWebsiteQueueMaxRetryCount,
                nextRetryAt: nil,
                lastError: "Request failed (HTTP 503)."
            )
        ])
        environment.websitesViewModel.syncPendingWebsitesFromQueuedShares(
            storage.pendingShareStore.loadAll()
        )

        environment.removePendingQueuedWebsite(firstQueued!.id)

        let remainingQueue = storage.pendingShareStore.loadAll()
        XCTAssertEqual(remainingQueue.count, 1)
        XCTAssertEqual(remainingQueue.first?.id, secondQueued!.id)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.count, 1)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.queueItemId, secondQueued!.id)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.status, .failed)
    }

    func testRemoveFailedQueuedWebsiteAfterHandoffRemovesOnlyMatchingFailedRow() async {
        let firstURL = "https://example.com/articles/\(UUID().uuidString)"
        let secondURL = "https://example.com/articles/\(UUID().uuidString)"
        let environment = requireEnvironment()

        let firstQueued = storage.pendingShareStore.enqueueWebsite(url: firstURL)
        let secondQueued = storage.pendingShareStore.enqueueWebsite(url: secondURL)
        XCTAssertNotNil(firstQueued)
        XCTAssertNotNil(secondQueued)

        environment.websitesViewModel.pendingWebsites = [
            WebsitesViewModel.PendingWebsiteItem(
                id: "pending-first",
                title: "Reading...",
                domain: "example.com",
                url: firstURL,
                canonicalURL: firstURL,
                source: .directSave,
                queueItemId: firstQueued!.id,
                jobId: "job-first",
                status: .failed
            ),
            WebsitesViewModel.PendingWebsiteItem(
                id: "pending-second",
                title: "Reading...",
                domain: "example.com",
                url: secondURL,
                canonicalURL: secondURL,
                source: .directSave,
                queueItemId: secondQueued!.id,
                jobId: "job-second",
                status: .failed
            )
        ]

        environment.removePendingQueuedWebsite(firstQueued!.id)

        let remainingQueue = storage.pendingShareStore.loadAll()
        XCTAssertEqual(remainingQueue.count, 1)
        XCTAssertEqual(remainingQueue.first?.id, secondQueued!.id)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.count, 1)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.id, "pending-second")
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.queueItemId, secondQueued!.id)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.status, .failed)
    }

    func testSavedWebsiteListUpdatePrunesMatchingQueuedWebsiteState() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 4))
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)
        environment.websitesViewModel.syncPendingWebsitesFromQueuedShares(
            storage.pendingShareStore.loadAll()
        )
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.url, url)

        environment.websitesStore.insertItemAtTop(
            WebsiteItem(
                id: "saved-\(UUID().uuidString)",
                title: "Saved",
                url: url,
                domain: "example.com",
                savedAt: "2026-03-20T23:41:37Z",
                publishedAt: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-20T23:41:37Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            persist: false
        )
        for _ in 0..<20
            where !storage.pendingShareStore.loadAll().isEmpty
            || !environment.websitesViewModel.pendingWebsites.isEmpty {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
    }

    func testApplySyncItemsPrunesMatchingQueuedWebsiteStateAfterBulkSync() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)
        environment.websitesViewModel.syncPendingWebsitesFromQueuedShares(
            storage.pendingShareStore.loadAll()
        )
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.url, url)

        environment.websitesStore.applySyncItems([
            WebsiteItem(
                id: "saved-\(UUID().uuidString)",
                title: "Saved",
                url: url,
                domain: "example.com",
                savedAt: "2026-03-20T23:41:37Z",
                publishedAt: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-20T23:41:37Z",
                lastOpenedAt: nil,
                deletedAt: nil
            ),
            WebsiteItem(
                id: "other-\(UUID().uuidString)",
                title: "Other",
                url: "https://other.example/articles/\(UUID().uuidString)",
                domain: "other.example",
                savedAt: "2026-03-20T23:41:37Z",
                publishedAt: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: false,
                faviconUrl: nil,
                faviconR2Key: nil,
                youtubeTranscripts: nil,
                readingTime: nil,
                updatedAt: "2026-03-20T23:41:37Z",
                lastOpenedAt: nil,
                deletedAt: nil
            )
        ])

        for _ in 0..<20
            where !storage.pendingShareStore.loadAll().isEmpty
            || !environment.websitesViewModel.pendingWebsites.isEmpty {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
    }

    func testEnqueueWebsiteSaveDoesNotReplaySameURLThroughPendingQueue() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let gate = AsyncGate()
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-1", status: "queued")
            ),
            onSave: { _ in
                await gate.wait()
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let saveTask = Task {
            await environment.enqueueWebsiteSave(url: url, selectAfterSave: true)
        }

        for _ in 0..<20 where websitesAPI.saveCallCount < 1 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let consumeTask = Task {
            await environment.consumePendingShares()
        }

        for _ in 0..<20 where websitesAPI.saveCallCount < 2 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)

        await gate.open()
        let saveResult = await saveTask.value
        XCTAssertTrue(saveResult)
        await consumeTask.value
        XCTAssertEqual(websitesAPI.saveCallCount, 1)
    }

    func testPerformBackgroundWebsiteContinuationProcessesQueuedWebsiteSave() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let completedDetail = WebsiteDetail(
            id: "saved-1",
            title: "Saved",
            url: url,
            urlFull: url,
            domain: "example.com",
            content: "Saved content",
            source: "web",
            savedAt: "2026-03-20T23:41:37Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-20T23:41:37Z",
            lastOpenedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
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
        environment = makeEnvironment(
            storage: storage,
            websitesAPI: websitesAPI,
            authSessionState: .active
        )
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)

        let completed = await environment.performBackgroundWebsiteContinuation(maxDuration: 2)

        XCTAssertTrue(completed)
        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.websitesViewModel.pendingWebsites.isEmpty)
        XCTAssertEqual(environment.websitesViewModel.items.first?.id, "saved-1")
    }

    func testBackgroundWebsiteContinuationCancellationDuringQueuedSavePreservesOriginalItem() async throws {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let gate = AsyncGate()
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(CancellationError()),
            onSave: { _ in
                await gate.wait()
            }
        )
        environment = makeEnvironment(
            storage: storage,
            websitesAPI: websitesAPI,
            authSessionState: .active
        )
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        let originalItem = try XCTUnwrap(queuedItem)

        let task = Task {
            await environment.performBackgroundWebsiteContinuation(maxDuration: 2)
        }
        for _ in 0..<20 where websitesAPI.saveCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(websitesAPI.saveCallCount, 1)

        task.cancel()
        await gate.open()
        let completed = await task.value

        let retainedItem = storage.pendingShareStore.loadAll().first
        XCTAssertFalse(completed)
        XCTAssertEqual(retainedItem?.id, originalItem.id)
        XCTAssertEqual(retainedItem?.retryCount, originalItem.retryCount)
        XCTAssertEqual(retainedItem?.nextRetryAt, originalItem.nextRetryAt)
        XCTAssertEqual(retainedItem?.lastError, originalItem.lastError)
        XCTAssertEqual(retainedItem?.websiteJobId, originalItem.websiteJobId)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.status, .queued)
    }

    func testBackgroundWebsiteContinuationResumesAcceptedQueuedJobAfterRelaunch() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let acceptedAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-accepted", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: acceptedAPI)
        let firstEnvironment = requireEnvironment()
        firstEnvironment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)

        await firstEnvironment.consumePendingShares()

        let persistedJob = storage.pendingShareStore.loadAll().first
        XCTAssertEqual(persistedJob?.id, queuedItem?.id)
        XCTAssertEqual(persistedJob?.websiteJobId, "job-accepted")
        XCTAssertEqual(firstEnvironment.websitesViewModel.pendingWebsites.first?.jobId, "job-accepted")
        firstEnvironment.websitesViewModel.jobPollingTasks["job-accepted"]?.cancel()
        firstEnvironment.websitesViewModel.jobPollingTasks.removeValue(forKey: "job-accepted")

        let completedDetail = WebsiteDetail(
            id: "saved-after-relaunch",
            title: "Saved after relaunch",
            url: url,
            urlFull: url,
            domain: "example.com",
            content: "Saved content",
            source: "web",
            savedAt: "2026-03-20T23:41:37Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-20T23:41:37Z",
            lastOpenedAt: nil
        )
        let resumedAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 4)),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-accepted",
                    status: "completed",
                    website: completedDetail,
                    error: nil
                )
            )
        )
        environment = makeEnvironment(
            storage: storage,
            websitesAPI: resumedAPI,
            authSessionState: .active
        )
        let resumedEnvironment = requireEnvironment()
        resumedEnvironment.authState = .active

        let completed = await resumedEnvironment.performBackgroundWebsiteContinuation(maxDuration: 2)

        XCTAssertTrue(completed)
        XCTAssertEqual(resumedAPI.saveCallCount, 0)
        XCTAssertEqual(resumedAPI.jobStatusCallIds, ["job-accepted"])
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(resumedEnvironment.websitesViewModel.pendingWebsites.isEmpty)
        XCTAssertEqual(resumedEnvironment.websitesViewModel.items.first?.id, "saved-after-relaunch")
    }

    func testBackgroundWebsiteContinuationSkipsPersistedJobWhenFallbackPolicyDenies() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(NSError(domain: "AppEnvironmentPendingWebsiteQueueTests", code: 5)),
            jobStatusResult: .success(
                WebsiteJobStatusResponse(
                    jobId: "job-persisted",
                    status: "completed",
                    website: nil,
                    error: nil
                )
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI, hasAuthToken: false)
        let environment = requireEnvironment()
        environment.authState = .active
        storage.pendingShareStore.replaceAll([
            PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: Date(),
                url: url,
                websiteJobId: "job-persisted"
            )
        ])

        let completed = await environment.performBackgroundWebsiteContinuation(maxDuration: 2)

        XCTAssertFalse(completed)
        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertTrue(websitesAPI.jobStatusCallIds.isEmpty)
        XCTAssertEqual(storage.pendingShareStore.loadAll().first?.websiteJobId, "job-persisted")
    }

    func testRefreshAuthStateDelegatesRunnableWebsiteReplayToCoordinator() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let authSession = PlaceholderAuthSession(authState: .active)
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
            )
        )
        let container = makeNoNetworkServiceContainer(
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI
        )
        environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        let environment = requireEnvironment()
        let coordinator = WebsiteQueueCoordinatorSpy()
        environment.websiteQueueCoordinator = coordinator.makeCoordinator()

        _ = storage.pendingShareStore.enqueueWebsite(url: url)

        environment.refreshAuthState()
        await coordinator.waitForReplayCount(1)

        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(storage.pendingShareStore.loadAll().count, 1)
    }

    func testCompleteBiometricUnlockDelegatesDeferredWebsiteReplayToCoordinator() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        let coordinator = WebsiteQueueCoordinatorSpy()
        environment.websiteQueueCoordinator = coordinator.makeCoordinator()
        environment.authState = .active
        storage.userDefaults.set(true, forKey: AppStorageKeys.biometricUnlockEnabled)
        environment.isBiometricUnlocked = false

        _ = storage.pendingShareStore.enqueueWebsite(url: url)

        await environment.completeBiometricUnlock()
        await coordinator.waitForReplayCount(1)

        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(storage.pendingShareStore.loadAll().count, 1)
    }

    func testWebsiteContinuationExpirationCompletionReportsFailureWhenExpirationWins() async {
        let state = BackgroundProcessingTaskExpirationState()
        let processingTask = Task { true }

        state.markExpired(canceling: processingTask)
        let completed = await processingTask.value

        XCTAssertFalse(state.completedSuccessfully(workSucceeded: completed))
    }

    func testWriteQueueFlushExpirationCompletionReportsFailureWhenExpirationWins() async {
        let state = BackgroundProcessingTaskExpirationState()
        let processingTask = Task { true }

        state.markExpired(canceling: processingTask)
        let completed = await processingTask.value

        XCTAssertFalse(state.completedSuccessfully(workSucceeded: completed))
    }
}

@MainActor
extension AppEnvironmentPendingWebsiteQueueTests {
    func clearWidgetPendingOperations() {
        _ = storage.widgetDataManager.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
    }

    func clearExtensionEvents() {
        _ = storage.extensionEventStore.consumeEvents()
        storage.pendingShareStore.replaceAll([])
    }

    func makeEnvironment(
        storage: AppEnvironmentStorage,
        websitesAPI: (any WebsitesProviding)? = nil,
        hasAuthToken: Bool = true,
        authSessionState: AuthState = .signedOut
    ) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(
            accessToken: hasAuthToken ? "access-token" : nil,
            userId: hasAuthToken ? "user-1" : nil,
            authState: authSessionState
        )
        let container = makeNoNetworkServiceContainer(
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        return environment
    }

    func requireEnvironment(
        storage: AppEnvironmentStorage? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        guard let environment else {
            XCTFail("Expected test environment", file: file, line: line)
            return AppEnvironment.shared!
        }
        if let storage, environment.storage.userDefaults != storage.userDefaults {
            XCTFail("Expected environment storage to match test storage", file: file, line: line)
        }
        return environment
    }

    func resetDeepLinkState(_ environment: AppEnvironment) {
        environment.authState = .signedOut
        environment.isMacSettingsPresented = false
        environment.commandSelection = nil
        environment.focusedSection = nil
        environment.isTasksFocused = false
        environment.pendingSidebarDeepLink = nil
        environment.tasksPhoneDetailRouteId = nil
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
        environment.websitesViewModel.pendingWebsite = nil
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class WebsiteQueueCoordinatorSpy {
    private(set) var replayCount = 0

    func makeCoordinator() -> WebsiteQueueCoordinator {
        WebsiteQueueCoordinator(
            hasPendingWork: { true },
            hasBackgroundContinuationWork: { true },
            canReplayNow: { true },
            replay: { [weak self] in
                self?.replayCount += 1
            }
        )
    }

    func waitForReplayCount(_ expected: Int, attempts: Int = 40) async {
        for _ in 0..<attempts where replayCount < expected {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(replayCount, expected)
    }
}
