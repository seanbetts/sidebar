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
        isolatedDefaults.defaults.removeObject(
            forKey: AppStorageKeys.taskNotificationAccountGenerationId
        )
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

    func testRefreshAuthStateKeepsCachedDataWhenUUIDScopeOnlyChangesCase() {
        isolatedDefaults.defaults.set(
            "1A70528D-778E-4CEE-A17B-C7DF94C5AB20",
            forKey: cacheScopeKey
        )
        let environment = makeEnvironment(
            authState: .active,
            userId: "REDACTED_FOR_PUBLIC_RELEASE"
        )
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(
            isolatedDefaults.defaults.string(forKey: cacheScopeKey),
            "REDACTED_FOR_PUBLIC_RELEASE"
        )
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

    func testRefreshAuthStateClearsDeliveredTaskActionsWhenUserScopeChanges() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        var cleanupCalls = 0
        let environment = makeEnvironment(
            authState: .active,
            userId: "user-new",
            clearDeliveredActionableTaskNotifications: { cleanupCalls += 1 }
        )

        environment.refreshAuthState()

        XCTAssertEqual(cleanupCalls, 1)
    }

    func testRefreshAuthStateRotatesNotificationScopeAcrossAccountSwitch() throws {
        let firstAccountId = UUID().uuidString
        let secondAccountId = UUID().uuidString
        isolatedDefaults.defaults.set(firstAccountId, forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: firstAccountId)

        environment.refreshAuthState()
        let firstContext = try XCTUnwrap(environment.taskNotificationAuthContext)

        let authSession = try XCTUnwrap(environment.container.authSession as? MutableAuthSession)
        authSession.userId = secondAccountId
        environment.refreshAuthState()
        let secondContext = try XCTUnwrap(environment.taskNotificationAuthContext)

        XCTAssertEqual(firstContext.accountId, firstAccountId.lowercased())
        XCTAssertEqual(secondContext.accountId, secondAccountId.lowercased())
        XCTAssertNotEqual(firstContext.generationId, secondContext.generationId)
    }

    func testNotificationScopeGenerationSurvivesRecreationForSameAccount() throws {
        let accountId = UUID().uuidString
        isolatedDefaults.defaults.set(accountId, forKey: cacheScopeKey)
        let firstEnvironment = makeEnvironment(authState: .active, userId: accountId)

        firstEnvironment.refreshAuthState()
        let firstContext = try XCTUnwrap(firstEnvironment.taskNotificationAuthContext)

        let recreatedEnvironment = makeEnvironment(authState: .active, userId: accountId)
        recreatedEnvironment.refreshAuthState()
        let recreatedContext = try XCTUnwrap(recreatedEnvironment.taskNotificationAuthContext)

        XCTAssertEqual(recreatedContext.accountId, firstContext.accountId)
        XCTAssertEqual(recreatedContext.generationId, firstContext.generationId)
    }

    func testNotificationCompletionDeclinesDuringUnreconciledAccountTransition() async throws {
        let previousAccountId = UUID().uuidString
        let nextAccountId = UUID().uuidString
        isolatedDefaults.defaults.set(previousAccountId, forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: previousAccountId)
        let authSession = try XCTUnwrap(environment.container.authSession as? MutableAuthSession)
        authSession.userId = nextAccountId
        let initialSnapshot = WidgetTaskData(
            tasks: [WidgetTask(id: "visible", title: "Visible")],
            totalCount: 1
        )
        environment.storage.widgetDataManager.storeTaskData(initialSnapshot, for: .today)
        var queuedTaskIds: [String] = []
        let handler = TaskNotificationResponseHandler(
            authContext: { environment.taskNotificationAuthContext },
            refresh: { _ in XCTFail("Account transition must not refresh") },
            openRoute: { _ in XCTFail("Account transition must not navigate") },
            completeTask: { taskId in
                queuedTaskIds.append(taskId)
                environment.storage.widgetDataManager.storeTaskData(.empty, for: .today)
                return .queued
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: [
                "aps": ["category": "TASK_REMINDER_ACTIONABLE"],
                "notification_metadata": [
                    "task_id": UUID().uuidString,
                    "account_id": nextAccountId
                ]
            ],
            completion: {}
        )

        XCTAssertEqual(result, .completionDeclined)
        XCTAssertTrue(queuedTaskIds.isEmpty)
        let storedSnapshot = environment.storage.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(storedSnapshot.tasks, initialSnapshot.tasks)
        XCTAssertEqual(storedSnapshot.totalCount, initialSnapshot.totalCount)
        XCTAssertEqual(
            storedSnapshot.optimisticallyCompletedTaskIds,
            initialSnapshot.optimisticallyCompletedTaskIds
        )
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

    func testRefreshAuthStatePreservesExtensionHandoffsWhenSignedOutWithStoredScope() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        isolatedDefaults.defaults.set("person@example.com", forKey: lastSignInEmailKey)
        isolatedDefaults.defaults.set(Date().timeIntervalSince1970, forKey: lastAuthTimestampKey)
        isolatedDefaults.defaults.set(true, forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
        let environment = makeEnvironment(authState: .signedOut, userId: nil)
        primeCachedData(environment)
        let queuedURL = "https://example.com/articles/sign-out"
        let queuedItem = environment.storage.pendingShareStore.enqueueWebsite(url: queuedURL)
        environment.storage.extensionEventStore.recordWebsiteSaved(url: queuedURL)

        environment.refreshAuthState()

        XCTAssertNil(isolatedDefaults.defaults.string(forKey: cacheScopeKey))
        XCTAssertNil(isolatedDefaults.defaults.string(forKey: lastSignInEmailKey))
        XCTAssertNil(isolatedDefaults.defaults.object(forKey: lastAuthTimestampKey))
        XCTAssertNil(isolatedDefaults.defaults.object(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted))
        XCTAssertEqual(environment.storage.pendingShareStore.loadAll().map(\.id), [queuedItem?.id].compactMap { $0 })
        XCTAssertEqual(environment.storage.pendingShareStore.loadAll().first?.url, queuedURL)
        XCTAssertTrue(environment.storage.extensionEventStore.consumeEvents().contains { event in
            event.websiteUrl == queuedURL
        })
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStateClearsDeliveredTaskActionsOnSignedOutReset() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        var cleanupCalls = 0
        let environment = makeEnvironment(
            authState: .signedOut,
            userId: nil,
            clearDeliveredActionableTaskNotifications: { cleanupCalls += 1 }
        )

        environment.refreshAuthState()

        XCTAssertEqual(cleanupCalls, 1)
    }

    func testRefreshAuthStatePreservesCachedDataWhenSignedOutStateIsOfflineRecoverable() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        isolatedDefaults.defaults.set("person@example.com", forKey: lastSignInEmailKey)
        isolatedDefaults.defaults.set(Date().timeIntervalSince1970, forKey: lastAuthTimestampKey)
        let environment = makeEnvironment(
            authState: .signedOut,
            userId: nil,
            canRestoreOfflineSession: true
        )
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: cacheScopeKey), "user-old")
        XCTAssertEqual(isolatedDefaults.defaults.string(forKey: lastSignInEmailKey), "person@example.com")
        XCTAssertNotNil(isolatedDefaults.defaults.object(forKey: lastAuthTimestampKey))
        assertCachedDataPresent(environment)
    }

    func testRefreshAuthStateKeepsDeliveredTaskActionsForOfflineRecoverableSession() {
        isolatedDefaults.defaults.set("user-old", forKey: cacheScopeKey)
        var cleanupCalls = 0
        let environment = makeEnvironment(
            authState: .signedOut,
            userId: nil,
            canRestoreOfflineSession: true,
            clearDeliveredActionableTaskNotifications: { cleanupCalls += 1 }
        )

        environment.refreshAuthState()

        XCTAssertEqual(cleanupCalls, 0)
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

    private func makeEnvironment(
        authState: AuthState,
        userId: String?,
        canRestoreOfflineSession: Bool = false,
        websitesAPI: (any WebsitesProviding)? = nil,
        deviceTokensAPI: DeviceTokensAPI? = nil,
        clearDeliveredActionableTaskNotifications: (() -> Void)? = nil
    ) -> AppEnvironment {
        let authSession = MutableAuthSession(
            authState: authState,
            userId: userId,
            canRestoreOfflineSession: canRestoreOfflineSession
        )
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
                userDefaults: isolatedDefaults.defaults,
                clearDeliveredActionableTaskNotifications: clearDeliveredActionableTaskNotifications
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
}

private struct CacheScopePayload: Codable, Equatable {
    let value: String
}

private final class MutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState
    let canRestoreOfflineSession: Bool

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(authState: AuthState, userId: String?, canRestoreOfflineSession: Bool = false) {
        self.authState = authState
        self.userId = userId
        self.canRestoreOfflineSession = canRestoreOfflineSession
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

extension MutableAuthSession: OfflineAccessRestoring {
    func restoreOfflineSession() -> Bool {
        canRestoreOfflineSession
    }
}
