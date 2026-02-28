import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentAuthCacheScopeTests: XCTestCase {
    private static var retainedEnvironments: [AppEnvironment] = []
    private let cacheScopeKey = AppStorageKeys.cacheScopeUserId

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: cacheScopeKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheScopeKey)
        super.tearDown()
    }

    func testRefreshAuthStateKeepsCachedDataWhenUserScopeUnchanged() {
        let userId = "user-123"
        UserDefaults.standard.set(userId, forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: userId)
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(UserDefaults.standard.string(forKey: cacheScopeKey), userId)
        assertCachedDataPresent(environment)
    }

    func testRefreshAuthStateClearsCachedDataWhenUserScopeChanges() {
        UserDefaults.standard.set("user-old", forKey: cacheScopeKey)
        let environment = makeEnvironment(authState: .active, userId: "user-new")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(UserDefaults.standard.string(forKey: cacheScopeKey), "user-new")
        assertCachedDataCleared(environment)
    }

    func testRefreshAuthStatePerformsOneTimeMigrationClearWhenScopeMissingAndActive() {
        let environment = makeEnvironment(authState: .active, userId: "user-migrated")
        primeCachedData(environment)

        environment.refreshAuthState()

        XCTAssertEqual(UserDefaults.standard.string(forKey: cacheScopeKey), "user-migrated")
        assertCachedDataCleared(environment)
    }

    private func makeEnvironment(authState: AuthState, userId: String?) -> AppEnvironment {
        let authSession = MutableAuthSession(authState: authState, userId: userId)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        Self.retainedEnvironments.append(environment)
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
