import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testHandleSignedInActivationDoesNotWaitForQueuedWebsiteReplay() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let website = WebsiteDetail(
            id: "website-\(UUID().uuidString)",
            title: "Saved",
            url: url,
            urlFull: url,
            domain: "example.com",
            content: "Saved content",
            source: "web",
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
        let replayGate = AsyncReplayGate()
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(WebsiteSaveResponse(success: true, website: website)),
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

        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(storage.pendingShareStore.loadAll().contains(where: { $0.url == url }))

        await replayGate.open()
        _ = await activationTask.value
        await waitForSavedWebsite(id: website.id, url: url, in: environment)

        XCTAssertEqual(environment.websitesViewModel.items.first?.url, url)
        XCTAssertTrue(storage.pendingShareStore.loadAll().isEmpty)
    }
}

private actor AsyncReplayGate {
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
