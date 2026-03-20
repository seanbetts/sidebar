import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
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
