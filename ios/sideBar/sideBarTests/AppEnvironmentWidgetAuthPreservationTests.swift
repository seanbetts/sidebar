import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvWidgetAuthPreservationTests: XCTestCase {
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
        resetDeepLinkState(requireEnvironment())
    }

    override func tearDown() {
        if let environment {
            resetDeepLinkState(environment)
        }
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

    func testSignedOutTaskDeepLinkDoesNotMutateVisibleTaskState() {
        let environment = requireEnvironment()
        environment.authState = .signedOut
        environment.isTasksFocused = true

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.pendingSidebarDeepLink)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
        XCTAssertEqual(environment.queuedProtectedDeepLinks.count, 1)
    }

    func testSignedOutNoteDeepLinkDoesNotMutateVisibleNoteState() {
        let environment = requireEnvironment()
        environment.authState = .signedOut

        environment.handleDeepLink(URL(string: "sidebar://notes/new")!)

        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.pendingSidebarDeepLink)
        XCTAssertNil(environment.notesViewModel.selectedNoteId)
        XCTAssertEqual(environment.queuedProtectedDeepLinks.count, 1)
    }

    func testSignedOutWebsiteSaveDeepLinkDoesNotStartSaveUntilAuthenticated() async {
        let savedURL = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "test-job-id", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .signedOut

        environment.handleDeepLink(Self.quickSaveDeepLink(url: savedURL))

        XCTAssertNil(environment.commandSelection)
        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(environment.queuedProtectedDeepLinks.count, 1)

        environment.authState = .active
        await environment.replayProtectedDeferredActionsIfReady()

        await waitForWebsiteSave(url: savedURL, in: websitesAPI)

        XCTAssertEqual(websitesAPI.saveCallCount, 1)
        XCTAssertEqual(websitesAPI.lastSavedURL, savedURL)
    }

    private func makeEnvironment(
        storage: AppEnvironmentStorage,
        websitesAPI: DeepLinkWebsitesAPI? = nil
    ) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI ?? DeepLinkWebsitesAPI(
                saveResult: .failure(NSError(domain: "AppEnvWidgetAuthPreservationTests", code: 1))
            )
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
        environment.pendingSidebarDeepLink = nil
        environment.tasksPhoneDetailRouteId = nil
        environment.queuedProtectedDeepLinks.removeAll()
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
        environment.websitesViewModel.pendingWebsite = nil
    }

    private func waitForWebsiteSave(
        url: String,
        in websitesAPI: DeepLinkWebsitesAPI,
        attempts: Int = 40
    ) async {
        for _ in 0..<attempts where websitesAPI.lastSavedURL != url {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func quickSaveDeepLink(url: String) -> URL {
        var components = URLComponents()
        components.scheme = "sidebar"
        components.host = "websites"
        components.path = "/save"
        components.queryItems = [
            URLQueryItem(name: "url", value: url)
        ]
        return components.url!
    }
}
