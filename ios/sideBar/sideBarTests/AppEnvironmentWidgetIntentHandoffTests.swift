import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testActiveEnvironmentConsumesQueuedAddTaskAfterLiveHandoffNotification() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.isTasksFocused = false

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )
        WidgetIntentHandoffNotifier.post()

        await waitForTaskDeepLink(in: environment)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
    }

    func testActiveEnvironmentConsumesQueuedAddNoteAfterLiveHandoffNotification() async {
        let environment = requireEnvironment()
        environment.authState = .active

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew),
            for: .notes
        )
        WidgetIntentHandoffNotifier.post()

        await waitForNoteDeepLink(in: environment)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testActiveEnvironmentConsumesQueuedQuickSaveAfterLiveHandoffNotification() async {
        let url = URL(string: "https://example.com/articles/\(UUID().uuidString)")!
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        storage.widgetDataManager.recordPendingQuickSave(url: url)
        WidgetIntentHandoffNotifier.post()

        await waitForWebsiteEventSurface(url.absoluteString, in: environment)

        XCTAssertEqual(environment.commandSelection, .websites)
        XCTAssertEqual(websitesAPI.lastSavedURL, url.absoluteString)
        XCTAssertTrue(websiteEventIsSurfaced(url.absoluteString, in: environment))
    }

    private func waitForTaskDeepLink(in environment: AppEnvironment, attempts: Int = 20) async {
        for _ in 0..<attempts where !environment.pendingNewTaskDeepLink {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForNoteDeepLink(in environment: AppEnvironment, attempts: Int = 20) async {
        for _ in 0..<attempts where !environment.pendingNewNoteDeepLink {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
