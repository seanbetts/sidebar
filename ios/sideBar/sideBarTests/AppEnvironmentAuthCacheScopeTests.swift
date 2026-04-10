import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentAuthCacheScopeTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var isolatedDefaults: TestIsolation.IsolatedUserDefaults!
    private var router: ScopedURLProtocolRouter!
    private let cacheScopeKey = AppStorageKeys.cacheScopeUserId
    private let lastSignInEmailKey = AppStorageKeys.lastSignInEmail
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
        isolatedDefaults = TestIsolation.makeUserDefaults(prefix: "AppEnvironmentAuthCacheScopeTests")
        retainedEnvironments.removeAll()
        isolatedDefaults.defaults.removeObject(forKey: cacheScopeKey)
        isolatedDefaults.defaults.removeObject(forKey: lastSignInEmailKey)
        isolatedDefaults.defaults.removeObject(forKey: lastAuthTimestampKey)
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        router.invalidate()
        router = nil
        isolatedDefaults?.tearDown()
        isolatedDefaults = nil
        super.tearDown()
    }

    func testRefreshAuthStateKeepsCachedDataWhenUserScopeUnchanged() {
        let userId = "user-123"
        isolatedDefaults.defaults.set(userId, forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: userId)
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), userId)
        assertCachedDataPresent(environment)
    }

    func testRefreshAuthStateClearsCachedDataWhenUserScopeChanges() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: "user-new")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), "user-new")
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStatePerformsOneTimeMigrationClearWhenScopeMissingAndActive() {
        let environment = makeEnvironment(authState: .active, userId: "user-migrated")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), "user-migrated")
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStatePreservesPendingShareQueueDuringActiveScopeMigration() {
        let queuedURL = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(
                NSError(domain: "AppEnvironmentAuthCacheScopeTests", code: 1)
            )
        )
        let environment = makeEnvironment(
            authState: .active,
            userId: "user-migrated",
            websitesAPI: websitesAPI
        )
        primeCachedData(environment)
        let queuedItem = environment.storage.pendingShareStore.enqueueWebsite(url: queuedURL)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), "user-migrated")
        XCTAssertEqual(environment.storage.pendingShareStore.loadAll().map(\.id), [queuedItem?.id].compactMap { $0 })
        XCTAssertEqual(environment.storage.pendingShareStore.loadAll().first?.url, queuedURL)
    }

    func testRefreshAuthStatePreservesExtensionEventsDuringActiveScopeMigration() {
        let queuedURL = "https://example.com/articles/\(UUID().uuidString)"
        let websitesAPI = DeepLinkWebsitesAPI(
            saveResult: .failure(
                NSError(domain: "AppEnvironmentAuthCacheScopeTests", code: 1)
            )
        )
        let environment = makeEnvironment(
            authState: .active,
            userId: "user-migrated",
            websitesAPI: websitesAPI
        )
        primeCachedData(environment)
        environment.storage.extensionEventStore.recordWebsiteSaved(url: queuedURL)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), "user-migrated")
        waitForQueuedWebsite(queuedURL, in: environment)
        XCTAssertTrue(
            environment.storage.pendingShareStore.loadAll().contains { $0.url == queuedURL }
        )
    }

    func testRefreshAuthStateClearsCachedDataWhenSignedOutWithStoredScope() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        isolatedDefaults.defaults.set("person@example.com", forKey: lastSignInEmailKey)
        isolatedDefaults.defaults.set(Date().timeIntervalSince1970, forKey: lastAuthTimestampKey)
        let environment = makeEnvironment(authState: .signedOut, userId: nil)
        primeCachedData(environment)
        _ = environment.storage.pendingShareStore.enqueueWebsite(url: "https://example.com/articles/sign-out")
        environment.storage.extensionEventStore.recordWebsiteSaved(url: "https://example.com/articles/sign-out")

        environment.refreshAuthState()

        XCTAssertNil(isolatedDefaults.defaults.string(forKey: cacheScopeKey))
        XCTAssertNil(isolatedDefaults.defaults.string(forKey: lastSignInEmailKey))
        XCTAssertNil(isolatedDefaults.defaults.object(forKey: lastAuthTimestampKey))
        XCTAssertTrue(environment.storage.pendingShareStore.loadAll().isEmpty)
        XCTAssertTrue(environment.storage.extensionEventStore.consumeEvents().isEmpty)
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStateClearsSettingsViewModelWhenUserScopeChanges() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: "user-new")
        let staleSettings = UserSettings(
            userId: "user-old",
            communicationStyle: "stale",
            workingRelationship: "stale",
            name: "Old User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            enabledSkills: []
        )
        environment.settingsViewModel.applySettingsResponse(staleSettings)

        environment.refreshAuthState()

        XCTAssertNil(environment.settingsViewModel.settings)
        XCTAssertTrue(environment.settingsViewModel.skills.isEmpty)
        XCTAssertEqual(environment.settingsViewModel.shortcutsToken, "")
    }

    func testRegisterDeviceTokenIfNeededCoalescesInFlightRegistrationForSameToken() async throws {
        let requestCounter = LockedCounter()
        let firstRequestStarted = DispatchSemaphore(value: 0)
        let releaseRequests = DispatchSemaphore(value: 0)
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let path = request.url?.path

            if path?.hasSuffix("/device-tokens/presence") == true {
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data("{}".utf8))
            }

            XCTAssertTrue(path?.hasSuffix("/device-tokens") == true)

            let count = requestCounter.increment()
            if count == 1 {
                firstRequestStarted.signal()
            }

            XCTAssertEqual(releaseRequests.wait(timeout: .now() + 2), .success)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { nil }
        )
        let deviceTokensAPI = DeviceTokensAPI(
            client: APIClient(config: config, session: router.makeSession())
        )
        let environment = makeEnvironment(
            authState: .active,
            userId: "user-123",
            deviceTokensAPI: deviceTokensAPI
        )

        environment.updateDeviceToken("device-token-123")
        let firstRequestResult = await waitForSignal(firstRequestStarted, timeout: 1.0)
        XCTAssertEqual(firstRequestResult, .success)

        environment.registerDeviceTokenIfNeeded()
        await waitForRequestCount(requestCounter, expected: 1)
        XCTAssertEqual(requestCounter.value, 1)

        releaseRequests.signal()
        await waitForRegistrationState(
            environment,
            token: "device-token-123",
            userId: "user-123"
        )
        XCTAssertEqual(environment.lastRegisteredDeviceToken, "device-token-123")
        XCTAssertEqual(environment.lastRegisteredUserId, "user-123")
    }

    private func makeEnvironment(
        authState: AuthState,
        userId: String?,
        websitesAPI: (any WebsitesProviding)? = nil,
        deviceTokensAPI: DeviceTokensAPI? = nil
    ) -> AppEnvironment {
        let authSession = MutableAuthSession(authState: authState, userId: userId)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            websitesAPI: websitesAPI,
            deviceTokensAPI: deviceTokensAPI
        )
        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(
                userDefaults: isolatedDefaults.defaults
            )
        )
        retainedEnvironments.append(environment)
        return environment
    }

    private func primeCachedData(_ environment: AppEnvironment) {
        environment.container.cacheClient.set(
            key: "tests.cache.scope",
            value: CacheScopePayload(value: "cache"),
            ttlSeconds: 60
        )
        environment.offlineStore.set(
            key: "tests.cache.scope.offline",
            entityType: "test",
            value: CacheScopePayload(value: "offline"),
            lastSyncAt: nil
        )
    }

    private func assertCachedDataPresent(_ environment: AppEnvironment) {
        let cachedPayload: CacheScopePayload? = environment.container.cacheClient.get(key: "tests.cache.scope")
        XCTAssertEqual(cachedPayload, CacheScopePayload(value: "cache"))
        let offlinePayload: CacheScopePayload? = environment.offlineStore.get(
            key: "tests.cache.scope.offline",
            as: CacheScopePayload.self
        )
        XCTAssertEqual(offlinePayload, CacheScopePayload(value: "offline"))
    }

    private func assertCachedDataCleared(_ environment: AppEnvironment) {
        let cachedPayload: CacheScopePayload? = environment.container.cacheClient.get(key: "tests.cache.scope")
        XCTAssertNil(cachedPayload)
        let offlinePayload: CacheScopePayload? = environment.offlineStore.get(
            key: "tests.cache.scope.offline",
            as: CacheScopePayload.self
        )
        XCTAssertNil(offlinePayload)
    }

    private func waitForQueuedWebsite(
        _ url: String,
        in environment: AppEnvironment,
        attempts: Int = 40
    ) {
        for _ in 0..<attempts where !environment.storage.pendingShareStore.loadAll().contains(where: { $0.url == url }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func waitForRequestCount(
        _ counter: LockedCounter,
        expected: Int,
        attempts: Int = 20
    ) async {
        for _ in 0..<attempts where counter.value < expected {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForRegistrationState(
        _ environment: AppEnvironment,
        token: String,
        userId: String,
        attempts: Int = 40
    ) async {
        for _ in 0..<attempts
        where environment.lastRegisteredDeviceToken != token
            || environment.lastRegisteredUserId != userId {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForSignal(
        _ semaphore: DispatchSemaphore,
        timeout seconds: TimeInterval
    ) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: semaphore.wait(timeout: .now() + seconds)
                )
            }
        }
    }
}

private struct CacheScopePayload: Codable, Equatable {
    let value: String
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
        return storage
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class MutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(authState: AuthState, userId: String?) {
        self.authState = authState
        self.userId = userId
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
