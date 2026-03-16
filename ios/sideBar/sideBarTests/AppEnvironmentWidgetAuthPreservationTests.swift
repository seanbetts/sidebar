import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentWidgetAuthPreservationTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var environment: AppEnvironment!
    private var storage: AppEnvironmentStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var baseDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "AppEnvironmentWidgetAuthPreservationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            suiteName,
            isDirectory: true
        )

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
        resetDeepLinkState(requireEnvironment())
    }

    override func tearDown() {
        if let environment {
            resetDeepLinkState(environment)
        }
        clearWidgetPendingOperations()
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let baseDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        environment = nil
        retainedEnvironments.removeAll()
        storage = nil
        defaults = nil
        suiteName = nil
        baseDirectory = nil
        super.tearDown()
    }

    func testConsumeWidgetAddTaskPreservesPendingOperationWhenSignedOut() {
        let environment = requireEnvironment()

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        environment.authState = .signedOut
        environment.consumeWidgetAddTask()

        let remaining = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.action, .addNew)
    }

    func testConsumeWidgetAddNotePreservesPendingOperationWhenSignedOut() {
        let environment = requireEnvironment()

        storage.widgetDataManager.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew),
            for: .notes
        )

        environment.authState = .signedOut
        environment.consumeWidgetAddNote()

        let remaining = storage.widgetDataManager.consumePendingOperations(
            for: .notes,
            actionType: NoteWidgetAction.self
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.action, .addNew)
    }

    func testConsumeWidgetQuickSavePreservesPendingURLWhenSignedOut() async {
        let environment = requireEnvironment()
        let url = URL(string: "https://example.com/articles/\(UUID().uuidString)")!

        storage.widgetDataManager.recordPendingQuickSave(url: url)

        environment.authState = .signedOut
        await environment.consumeWidgetQuickSave()

        XCTAssertEqual(storage.widgetDataManager.consumePendingQuickSave(), url)
    }

    private func clearWidgetPendingOperations() {
        _ = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )
        _ = storage.widgetDataManager.consumePendingOperations(
            for: .notes,
            actionType: NoteWidgetAction.self
        )
        _ = storage.widgetDataManager.consumePendingQuickSave()
    }

    private func makeEnvironment(storage: AppEnvironmentStorage) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        return environment
    }

    private func requireEnvironment(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        guard let environment else {
            XCTFail("Expected test environment", file: file, line: line)
            return AppEnvironment.shared!
        }
        return environment
    }

    private func resetDeepLinkState(_ environment: AppEnvironment) {
        environment.authState = .signedOut
        environment.isMacSettingsPresented = false
        environment.commandSelection = nil
        environment.focusedSection = nil
        environment.isTasksFocused = false
        environment.pendingNewTaskDeepLink = false
        environment.pendingNewNoteDeepLink = false
        environment.pendingScratchpadDeepLink = false
        environment.tasksPhoneDetailRouteId = nil
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
        environment.websitesViewModel.pendingWebsite = nil
    }
}
