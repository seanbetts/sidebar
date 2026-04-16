import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class PendingWebsiteOfflineCapabilityTests: XCTestCase {
    var retainedEnvironments: [AppEnvironment] = []
    var environment: AppEnvironment!
    var storage: AppEnvironmentStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var baseDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "AppEnvironmentPendingWebsiteOfflineCapabilityTests.\(UUID().uuidString)"
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
    }

    override func tearDown() {
        environment = nil
        retainedEnvironments.removeAll()
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let baseDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        storage = nil
        defaults = nil
        suiteName = nil
        baseDirectory = nil
        super.tearDown()
    }

    func testConsumePendingSharesTreatsServerUnreachableAsQueuedOfflineState() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        let queuedItem = storage.pendingShareStore.enqueueWebsite(url: url)
        XCTAssertNotNil(queuedItem)

        await forceServerUnreachable(in: environment)
        await environment.consumePendingShares()

        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(storage.pendingShareStore.loadAll().count, 1)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.count, 1)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.queueItemId, queuedItem?.id)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsites.first?.url, url)
    }

    func testPerformBackgroundWebsiteContinuationSkipsWhenServerUnreachable() async {
        let url = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .success(
                WebsiteSaveJobResponse(jobId: "job-\(UUID().uuidString)", status: "queued")
            )
        )
        environment = makeEnvironment(storage: storage, websitesAPI: websitesAPI)
        let environment = requireEnvironment()
        environment.authState = .active

        _ = storage.pendingShareStore.enqueueWebsite(url: url)
        await forceServerUnreachable(in: environment)

        let completed = await environment.performBackgroundWebsiteContinuation(maxDuration: 2)

        XCTAssertFalse(completed)
        XCTAssertEqual(websitesAPI.saveCallCount, 0)
        XCTAssertEqual(storage.pendingShareStore.loadAll().count, 1)
        XCTAssertTrue(environment.websitesViewModel.items.isEmpty)
    }
}

@MainActor
private extension PendingWebsiteOfflineCapabilityTests {
    func makeEnvironment(
        storage: AppEnvironmentStorage,
        websitesAPI: (any WebsitesProviding)? = nil
    ) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(authState: .signedOut)
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        guard let environment else {
            XCTFail("Expected test environment", file: file, line: line)
            return AppEnvironment.shared!
        }
        return environment
    }

    func forceServerUnreachable(in environment: AppEnvironment, attempts: Int = 20) async {
        let error = URLError(.cannotConnectToHost)
        for _ in 0..<2 {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["error": error]
            )
        }

        guard let monitor = environment.tasksViewModel.networkStatus as? ConnectivityMonitor else {
            XCTFail("Expected connectivity monitor-backed task network status")
            return
        }

        for _ in 0..<attempts where monitor.isServerReachable {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(monitor.isNetworkAvailable)
        XCTAssertFalse(monitor.isOffline)
        XCTAssertFalse(monitor.isServerReachable)
    }
}
