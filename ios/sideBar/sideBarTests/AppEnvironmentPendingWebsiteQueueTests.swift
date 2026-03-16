import XCTest
import sideBarShared
@testable import sideBar

@MainActor
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
}

@MainActor
extension AppEnvironmentPendingWebsiteQueueTests {
    func clearWidgetPendingOperations() {
        _ = storage.widgetDataManager.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
        _ = storage.widgetDataManager.consumePendingQuickSave()
    }

    func clearExtensionEvents() {
        _ = storage.extensionEventStore.consumeEvents()
        storage.pendingShareStore.replaceAll([])
    }

    func makeEnvironment(
        storage: AppEnvironmentStorage,
        websitesAPI: (any WebsitesProviding)? = nil
    ) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
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
