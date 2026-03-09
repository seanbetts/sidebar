import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentAuthCacheScopeTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let cacheScopeKey = AppStorageKeys.cacheScopeUserId
    private let lastSignInEmailKey = AppStorageKeys.lastSignInEmail
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp

    override func setUp() {
        super.setUp()
        suiteName = "AppEnvironmentAuthCacheScopeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        retainedEnvironments.removeAll()
        defaults.removeObject(forKey: cacheScopeKey)
        defaults.removeObject(forKey: lastSignInEmailKey)
        defaults.removeObject(forKey: lastAuthTimestampKey)
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRefreshAuthStateKeepsCachedDataWhenUserScopeUnchanged() {
        let userId = "user-123"
        defaults.set(userId, forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: userId)
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(defaults.string(forKey: cacheScopeKey), userId)
        assertCachedDataPresent(environment)
    }

    func testRefreshAuthStateClearsCachedDataWhenUserScopeChanges() {
        defaults.set("user-old", forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: "user-new")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(defaults.string(forKey: cacheScopeKey), "user-new")
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStatePerformsOneTimeMigrationClearWhenScopeMissingAndActive() {
        let environment = makeEnvironment(authState: .active, userId: "user-migrated")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(defaults.string(forKey: cacheScopeKey), "user-migrated")
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStateClearsCachedDataWhenSignedOutWithStoredScope() {
        defaults.set("user-old", forKey: cacheScopeKey)
        defaults.set("person@example.com", forKey: lastSignInEmailKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastAuthTimestampKey)
        let environment = makeEnvironment(authState: .signedOut, userId: nil)
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertNil(defaults.string(forKey: cacheScopeKey))
        XCTAssertNil(defaults.string(forKey: lastSignInEmailKey))
        XCTAssertNil(defaults.object(forKey: lastAuthTimestampKey))
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStateClearsSettingsViewModelWhenUserScopeChanges() {
        defaults.set("user-old", forKey: cacheScopeKey)
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

    private func makeEnvironment(authState: AuthState, userId: String?) -> AppEnvironment {
        let authSession = MutableAuthSession(authState: authState, userId: userId)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(
                userDefaults: defaults
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
}

private struct CacheScopePayload: Codable, Equatable {
    let value: String
}

private final class MutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
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
