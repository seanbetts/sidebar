import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testHandleSignedInActivationNotifiesRefreshCoordinator() async {
        let refreshCoordinator = RefreshCoordinatorSpy()
        environment = makeEnvironment(storage: storage, refreshCoordinator: refreshCoordinator)
        let environment = requireEnvironment()
        environment.authState = .active

        await environment.handleSignedInActivation(includeDeferredRefresh: false)

        let requests = await refreshCoordinator.activationRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.includeDeferredRefresh, false)
        XCTAssertEqual(requests.first?.activeSection, environment.activeSection)
    }

    func testHandleSignedInActivationConsumesPendingWidgetCompletionFallbackWhenOffline() async {
        let environment = requireEnvironment()
        environment.authState = .active

        let taskId = UUID().uuidString
        let task = TaskItem(
            id: taskId,
            title: "Offline fallback task",
            status: "todo",
            updatedAt: "2026-04-01T12:00:00Z"
        )
        environment.container.cacheClient.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: TaskListResponse(
                scope: "today",
                generatedAt: nil,
                tasks: [task],
                projects: nil,
                groups: nil
            ),
            ttlSeconds: 60
        )
        environment.container.cacheClient.set(
            key: CacheKeys.tasksCounts,
            value: TaskCountsResponse(
                generatedAt: nil,
                counts: TaskCounts(today: 1, upcoming: 0, completed: 0),
                projects: [],
                groups: []
            ),
            ttlSeconds: 60
        )

        await forceTasksOffline(in: environment)
        await environment.tasksViewModel.load(selection: .today)

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete),
            for: .tasks
        )

        await environment.handleSignedInActivation(includeDeferredRefresh: false)

        let remaining = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(environment.tasksStore.tasks.contains(where: { $0.id == taskId }))
    }

    func testHandleSignedInActivationDoesNotWaitForQueuedWebsiteReplay() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let replayGate = AsyncReplayGate()
        let completion = AsyncCompletionFlag()
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")),
            onSave: { _ in
                await replayGate.wait()
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        storage.extensionEventStore.recordWebsiteSaved(url: url)

        let activationTask = Task {
            await environment.handleSignedInActivation(includeDeferredRefresh: false)
            await completion.markFinished()
        }

        for _ in 0..<20 where !storage.pendingShareStore.loadAll().contains(where: { $0.url == url }) {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await waitForWebsiteSaveCallCount(1, in: websitesAPI)
        let activationFinished = await waitForCompletion(completion)

        XCTAssertTrue(activationFinished)
        XCTAssertTrue(storage.pendingShareStore.loadAll().contains(where: { $0.url == url }))

        await replayGate.open()
        _ = await activationTask.value
        await waitForWebsiteEventSurface(url, in: environment)
        for _ in 0..<20 where !storage.pendingShareStore.loadAll().isEmpty {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertTrue(websiteEventIsSurfaced(url, in: environment))
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
    }

    func testHandleSignedInActivationLoadsWebsiteListWhileQueuedReplayIsInFlight() async {
        let queuedURL = "https://example.com/articles/\(UUID().uuidString)"
        let replayGate = AsyncReplayGate()
        let existingItem = WebsiteItem(
            id: "website-existing",
            title: "Existing Website",
            url: "https://example.com/already-saved",
            domain: "example.com",
            savedAt: "2026-03-17T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-17T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            ),
            listResult: .success(WebsitesResponse(items: [existingItem], archivedCount: 0)),
            onSave: { _ in
                await replayGate.wait()
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        storage.extensionEventStore.recordWebsiteSaved(url: queuedURL)

        let activationTask = Task {
            await environment.handleSignedInActivation(includeDeferredRefresh: false)
        }

        for _ in 0..<40 where environment.websitesViewModel.items.first?.url != existingItem.url {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(environment.websitesViewModel.items.first?.url, existingItem.url)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, queuedURL)
        await waitForWebsiteSaveCallCount(1, in: websitesAPI)
        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertGreaterThan(websitesAPI.listCallCount, 0)

        await replayGate.open()
        _ = await activationTask.value
        await waitForWebsiteEventSurface(queuedURL, in: environment)
    }

    func testConsumeExtensionEventsStartsQueuedReplayBeforeImmediateWebsiteRefresh() async {
        let queuedURL = "https://example.com/articles/\(UUID().uuidString)"
        let replayGate = AsyncReplayGate()
        let existingItem = WebsiteItem(
            id: "website-existing",
            title: "Existing Website",
            url: "https://example.com/already-saved",
            domain: "example.com",
            savedAt: "2026-03-17T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-17T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            ),
            listResult: .success(WebsitesResponse(items: [existingItem], archivedCount: 0)),
            onSave: { _ in
                await replayGate.wait()
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        storage.extensionEventStore.recordWebsiteSaved(url: queuedURL)

        await environment.consumeExtensionEvents(awaitPendingShareReplay: false)
        await environment.websitesViewModel.refreshFromExtension()

        XCTAssertEqual(environment.websitesViewModel.items.first?.url, existingItem.url)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, queuedURL)
        await waitForWebsiteSaveCallCount(1, in: websitesAPI)
        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertGreaterThan(websitesAPI.listCallCount, 0)

        await replayGate.open()
        await waitForWebsiteEventSurface(queuedURL, in: environment)
    }
}

actor AsyncReplayGate {
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

actor AsyncCompletionFlag {
    private var isFinished = false

    func markFinished() {
        isFinished = true
    }

    func finished() -> Bool {
        isFinished
    }
}

@MainActor
final class RefreshCoordinatorSpy: RefreshCoordinatorType {
    private var requests: [ActivationRefreshRequest] = []

    func handleActivation(_ request: ActivationRefreshRequest) async {
        requests.append(request)
    }

    func visibleSectionDidChange(to section: AppSection?) {
        _ = section
    }

    func activationRequests() -> [ActivationRefreshRequest] {
        requests
    }
}
