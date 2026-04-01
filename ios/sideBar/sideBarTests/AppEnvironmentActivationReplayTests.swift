import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
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
        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        let activationTask = Task {
            await environment.handleSignedInActivation(includeDeferredRefresh: false)
        }

        for _ in 0..<20 where !environment.pendingNewTaskDeepLink {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(environment.pendingNewTaskDeepLink)
        XCTAssertEqual(environment.commandSelection, .tasks)
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
