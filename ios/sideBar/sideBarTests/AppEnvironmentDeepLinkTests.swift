import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentDeepLinkTests: XCTestCase {
    var retainedEnvironments: [AppEnvironment] = []
    var environment: AppEnvironment!
    var storage: AppEnvironmentStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var baseDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "AppEnvironmentDeepLinkTests.\(UUID().uuidString)"
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

    func testHandleNotesNewDeepLinkSetsPendingFlagAndSelection() async {
        let environment = requireEnvironment()
        environment.handleDeepLink(URL(string: "sidebar://notes/new")!)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testHandleTasksNewDeepLinkWhenNotFocusedSetsPendingFlag() async {
        let environment = requireEnvironment()
        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
    }

    func testHandleTasksNewDeepLinkWhenFocusedStartsNewTaskImmediately() async {
        let environment = requireEnvironment()
        environment.isTasksFocused = true

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testHandleTasksTodayDeepLinkSelectsTasksSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://tasks/today")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
    }

    func testHandleNotesRootDeepLinkSelectsNotesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://notes")!)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertFalse(environment.pendingNewNoteDeepLink)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.notes)
        )
    }

    func testHandleNoteDeepLinkDecodesPercentEncodedPath() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://notes/Folder/My%20Note.md")!)

        for _ in 0..<20 where environment.notesViewModel.selectedNoteId != "Folder/My Note.md" {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertEqual(environment.notesViewModel.selectedNoteId, "Folder/My Note.md")
    }

    func testHandleWebsitesRootDeepLinkSelectsWebsitesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://websites")!)

        XCTAssertEqual(environment.commandSelection, .websites)
    }

    func testHandleFilesRootDeepLinkSelectsFilesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://files")!)

        XCTAssertEqual(environment.commandSelection, .files)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.files)
        )
    }

    func testConsumeWidgetAddTaskStartsTaskImmediatelyWhenTasksFocused() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.isTasksFocused = true

        let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
        storage.widgetDataManager.recordPendingOperation(operation, for: .tasks)

        environment.consumeWidgetAddTask()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.tasks)
        )
    }

    func testConsumeWidgetCompletionsPreservesPendingAddTaskOperation() async {
        let environment = requireEnvironment()

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "task-complete", action: TaskWidgetAction.complete),
            for: .tasks
        )
        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        // Signed out avoids any server completion sync while validating queue behavior.
        environment.authState = .signedOut
        await environment.consumeWidgetCompletions()

        environment.authState = .active
        environment.isTasksFocused = false
        environment.consumeWidgetAddTask()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
    }

    func testConsumeWidgetCompletionsPreservesPendingCompletionWhenSignedOut() async {
        let environment = requireEnvironment()
        let taskId = UUID().uuidString

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete),
            for: .tasks
        )

        environment.authState = .signedOut
        await environment.consumeWidgetCompletions()

        let remaining = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.action, .complete)
        XCTAssertEqual(remaining.first?.itemId, taskId)
    }

    func testWidgetPendingTaskSanitizationRemovesInvalidCompletionID() async {
        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "task_1", action: TaskWidgetAction.complete),
            for: .tasks
        )
        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        storage.widgetDataManager.sanitizePendingTaskCompletions()
        let remaining = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.action, .addNew)
        XCTAssertEqual(remaining.first?.itemId, "")
    }

    func testConsumeWidgetAddNoteSetsPendingFlagAndSelection() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
        storage.widgetDataManager.recordPendingOperation(operation, for: .notes)

        environment.consumeWidgetAddNote()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.notes)
        )
    }

    func testConsumeExtensionEventsWhenActiveShowsPendingWebsite() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        storage.extensionEventStore.recordWebsiteSaved(url: url)
        await environment.consumeExtensionEvents()

        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testActiveEnvironmentConsumesQueuedWebsiteAfterLiveHandoffNotification() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        _ = storage.pendingShareStore.enqueueWebsite(url: url)
        await waitForPendingWebsite(url, in: environment)

        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testConsumePendingSharesPreservesWebsiteQueuedDuringInFlightSave() async {
        let firstURL = "https://example.com/articles/\(UUID().uuidString)"
        let secondURL = "https://example.com/articles/\(UUID().uuidString)"
        let savedWebsite = WebsiteDetail(
            id: "website-\(UUID().uuidString)",
            title: "Saved First Website",
            url: firstURL,
            urlFull: firstURL,
            domain: "example.com",
            content: "Saved content",
            source: "web",
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
            lastOpenedAt: nil
        )
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            ),
            onSave: { [storage = storage!] url in
                guard url == firstURL else { return }
                _ = storage.pendingShareStore.enqueueWebsite(url: secondURL)
            }
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        _ = storage.pendingShareStore.enqueueWebsite(url: firstURL)

        await environment.consumePendingShares()

        XCTAssertEqual(environment.websitesViewModel.items.first?.url, firstURL)
        XCTAssertEqual(storage.pendingShareStore.loadAll().compactMap(\.url), [secondURL])
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, secondURL)
    }

    func testConsumeWebsiteSaveHandoffRefreshesListAfterQueuedWebsiteEventOnMacOS() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let savedItem = WebsiteItem(
            id: "website-\(UUID().uuidString)",
            title: "Saved by Refresh",
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
            saveResult: .failure(NSError(domain: "AppEnvironmentDeepLinkTests", code: 1)),
            listResult: .success(WebsitesResponse(items: [savedItem], archivedCount: 0))
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        storage.extensionEventStore.recordWebsiteSaved(url: url)

        await environment.consumeWebsiteSaveHandoff()

        XCTAssertGreaterThan(websitesAPI.listCallCount, 0)
        XCTAssertEqual(environment.websitesViewModel.items.first?.url, url)
        XCTAssertNil(environment.websitesViewModel.pendingWebsite)
    }

    func testConsumeExtensionEventsWhenInactivePreservesEvents() async {
        let environment = requireEnvironment()
        let url = "https://www.youtube.com/watch?v=abc123xyzAA"

        environment.authState = .signedOut
        storage.extensionEventStore.recordWebsiteSaved(url: url)
        await environment.consumeExtensionEvents()
        XCTAssertNil(environment.websitesViewModel.pendingWebsite)

        environment.authState = .active
        await environment.consumeExtensionEvents()
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testHandleSignedInActivationConsumesExtensionEvents() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        storage.extensionEventStore.recordWebsiteSaved(url: url)

        await environment.handleSignedInActivation()

        XCTAssertTrue(
            websiteEventIsSurfaced(url, in: environment),
            "Expected signed-in activation to surface the extension website event."
        )
        XCTAssertTrue(storage.extensionEventStore.consumeEvents().isEmpty)
    }

    func testHandleSignedInActivationConsumesWidgetAddTask() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.isTasksFocused = false

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        await environment.handleSignedInActivation()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
    }

    func testHandleSignedInActivationConsumesWidgetQuickSave() async {
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

        await environment.handleSignedInActivation()
        await waitForWebsiteEventSurface(url.absoluteString, in: environment)

        XCTAssertEqual(environment.commandSelection, .websites)
        XCTAssertEqual(websitesAPI.lastSavedURL, url.absoluteString)
        XCTAssertTrue(
            websiteEventIsSurfaced(url.absoluteString, in: environment),
            "Expected widget quick save to surface the queued website URL."
        )
    }

    func testAddTaskIntentRoutesImmediatelyWhenAppEnvironmentIsAvailable() async throws {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.isTasksFocused = false

        _ = try await AddTaskIntent().perform()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
    }

    func testCreateNoteIntentRoutesImmediatelyWhenAppEnvironmentIsAvailable() async throws {
        let environment = requireEnvironment()
        environment.authState = .active

        _ = try await CreateNoteIntent().perform()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testHandleSignedInActivationRefreshesWebsiteWidgetSnapshot() async {
        let item = WebsiteItem(
            id: "website-1",
            title: "Example",
            url: "https://example.com/articles/1",
            domain: "example.com",
            savedAt: "2026-03-12T17:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-12T17:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let websitesAPI = WidgetRefreshWebsitesAPI(items: [item])
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let before: WidgetWebsiteData = storage.widgetDataManager.load(for: .websites)
        XCTAssertEqual(before.totalCount, 0)

        await environment.handleSignedInActivation()

        let after: WidgetWebsiteData = storage.widgetDataManager.load(for: .websites)
        XCTAssertEqual(after.totalCount, 1)
        XCTAssertEqual(after.websites.first?.url, item.url)
    }

}
