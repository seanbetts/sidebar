import XCTest
import sideBarShared
import Supabase
@testable import sideBar

@MainActor
final class SupabaseAuthAdapterTests: XCTestCase {
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp
    private let failedLoginAttemptsKey = "sidebar.auth.failedLoginAttempts"
    private let lockoutEndTimeKey = "sidebar.auth.lockoutEndTime"
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testJwtExpiryDateUsesExpClaim() async {
        let exp: TimeInterval = 1_800_000_000
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        let token = "\(header).\(payload)."

        let date = SupabaseAuthAdapter.jwtExpiryDate(from: token)
        XCTAssertEqual(date, Date(timeIntervalSince1970: exp))
    }

    func testJwtExpiryDateReturnsNilForInvalidToken() async {
        let date = SupabaseAuthAdapter.jwtExpiryDate(from: "invalid-token")
        XCTAssertNil(date)
    }

    func testJwtSubjectUsesSubClaim() async {
        let exp: TimeInterval = 1_800_000_000
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user-123"])
        let token = "\(header).\(payload)."

        let subject = SupabaseAuthAdapter.jwtSubject(from: token)

        XCTAssertEqual(subject, "user-123")
    }

    func testMakeAuthOptionsUsesInMemoryStorageForNonKeychainStore() {
        let options = SupabaseAuthAdapter.makeAuthOptions(stateStore: InMemoryAuthStateStore())
        XCTAssertTrue(options.storage is SupabaseInMemoryStorage)
    }

    func testMakeAuthOptionsUsesImplicitFlowForRecoveryCallbacks() {
        let options = SupabaseAuthAdapter.makeAuthOptions(stateStore: InMemoryAuthStateStore())
        XCTAssertEqual(options.flowType, .implicit)
    }

    func testMakeAuthOptionsUsesKeychainStorageForKeychainStore() {
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        let options = SupabaseAuthAdapter.makeAuthOptions(stateStore: store)
        XCTAssertTrue(options.storage is SupabaseKeychainStorage)
    }

    func testInMemoryAuthStateStoreSupportsConcurrentAccess() async throws {
        let store = InMemoryAuthStateStore()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for iteration in 0..<50 {
                group.addTask {
                    try store.saveAccessToken("token-\(iteration)")
                }
                group.addTask {
                    try store.saveUserId("user-\(iteration)")
                }
                group.addTask {
                    _ = try store.loadAccessToken()
                    _ = try store.loadUserId()
                }
            }

            try await group.waitForAll()
        }

        let accessToken = try store.loadAccessToken()
        let userId = try store.loadUserId()
        XCTAssertNotNil(accessToken)
        XCTAssertNotNil(userId)
    }

    func testSignInLockoutPersistsAcrossAdapterRecreation() async throws {
        let defaults = makeUserDefaults()
        let failingClient = FakeSupabaseAuthClient()
        failingClient.signInResult = .failure(AuthAdapterError.invalidCredentials)

        let firstAdapter = SupabaseAuthAdapter(
            authClient: failingClient,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: defaults
        )

        for _ in 0..<5 {
            await XCTAssertThrowsErrorAsync {
                try await firstAdapter.signIn(email: "test@example.com", password: "wrong-password")
            }
        }

        XCTAssertTrue(firstAdapter.isLockedOut)
        XCTAssertEqual(defaults.integer(forKey: failedLoginAttemptsKey), 5)
        XCTAssertGreaterThan(defaults.double(forKey: lockoutEndTimeKey), Date().timeIntervalSince1970)

        let secondAdapter = SupabaseAuthAdapter(
            authClient: FakeSupabaseAuthClient(),
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: defaults
        )

        XCTAssertTrue(secondAdapter.isLockedOut)
        XCTAssertNotNil(secondAdapter.lockoutRemainingSeconds)
    }

    func testOfflineAccessAllowsStoredCredentialsWithinWindow() async {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-12 * 60 * 60)
        let defaults = makeUserDefaults()
        defaults.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: defaults
        )

        XCTAssertTrue(adapter.canRestoreOfflineSession)
        XCTAssertTrue(adapter.restoreOfflineSession())
        XCTAssertEqual(adapter.accessToken, "token")
        XCTAssertEqual(adapter.userId, "user")
    }

    func testOfflineAccessRejectsExpiredTimestampStoredInAuthStateStore() async throws {
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        try store.saveAuthMetadataValue(
            String(outsideWindow.timeIntervalSince1970),
            forKey: lastAuthTimestampKey
        )

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: makeUserDefaults()
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertFalse(adapter.restoreOfflineSession())
    }

    func testOfflineAccessMigratesLegacyTimestampFromUserDefaultsIntoAuthStateStore() async throws {
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-2 * 60 * 60)
        let defaults = makeUserDefaults()
        defaults.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: defaults
        )

        XCTAssertTrue(adapter.canRestoreOfflineSession)
        XCTAssertNil(defaults.object(forKey: lastAuthTimestampKey))
        let migratedTimestampString = try XCTUnwrap(store.loadAuthMetadataValue(forKey: lastAuthTimestampKey))
        let migratedTimestamp = try XCTUnwrap(TimeInterval(migratedTimestampString))
        XCTAssertEqual(migratedTimestamp, withinWindow.timeIntervalSince1970, accuracy: 0.001)
    }

    func testOfflineAccessRejectsStoredCredentialsOutsideWindow() async {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        let defaults = makeUserDefaults()
        defaults.set(outsideWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: defaults
        )

        XCTAssertNil(adapter.accessToken)
        XCTAssertNil(adapter.userId)
    }

    func testCanRestoreOfflineSessionRespectsWindow() async {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-2 * 60 * 60)
        let defaults = makeUserDefaults()
        defaults.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: defaults
        )

        XCTAssertTrue(adapter.canRestoreOfflineSession)
        XCTAssertTrue(adapter.restoreOfflineSession())
        XCTAssertEqual(adapter.accessToken, "token")
        XCTAssertEqual(adapter.userId, "user")
    }

    func testMapAuthErrorUsesSecureConnectionMessageForTLSFailures() async {
        let adapter = SupabaseAuthAdapter(
            authClient: FakeSupabaseAuthClient(),
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: makeUserDefaults()
        )

        let mapped = adapter.mapAuthError(URLError(.secureConnectionFailed))

        guard case .unknown(let message) = mapped else {
            XCTFail("Expected TLS failures to avoid the offline bucket")
            return
        }

        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testRestoreOfflineSessionFailsOutsideWindow() async {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        let defaults = makeUserDefaults()
        defaults.set(outsideWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store,
            userDefaults: defaults
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertFalse(adapter.restoreOfflineSession())
    }

    func testFreshAdapterDoesNotInheritLastAuthTimestampFromAnotherTestScope() async {
        let firstStore = InMemoryAuthStateStore()
        try? firstStore.saveAccessToken("token-1")
        try? firstStore.saveUserId("user-1")
        let withinWindow = Date().addingTimeInterval(-48 * 60 * 60)
        let firstDefaults = makeUserDefaults()
        firstDefaults.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let firstAdapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: firstStore,
            userDefaults: firstDefaults
        )
        XCTAssertFalse(firstAdapter.canRestoreOfflineSession)

        let secondStore = InMemoryAuthStateStore()
        try? secondStore.saveAccessToken("token-2")
        try? secondStore.saveUserId("user-2")

        let secondDefaults = makeUserDefaults()
        let secondAdapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: secondStore,
            userDefaults: secondDefaults
        )

        XCTAssertTrue(secondAdapter.canRestoreOfflineSession)
        XCTAssertGreaterThan(secondDefaults.double(forKey: lastAuthTimestampKey), withinWindow.timeIntervalSince1970)
    }

    func testColdLaunchExpiredSessionRefreshesAndBecomesActive() async throws {
        let nowExp: TimeInterval = Date().addingTimeInterval(-60).timeIntervalSince1970
        let expiredToken = makeJwt(exp: nowExp)
        let futureExp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let refreshedToken = makeJwt(exp: futureExp)

        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: expiredToken, userId: "user-1", expiresAt: nowExp)
        client.refreshResult = .success(
            SupabaseSessionInfo(accessToken: refreshedToken, userId: "user-1", expiresAt: futureExp)
        )

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: false,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .staleRecoverable)
        XCTAssertNil(adapter.authorizationToken)

        try await waitUntil(timeoutSeconds: 2.0) { adapter.authState == .active }
        XCTAssertEqual(adapter.authorizationToken, refreshedToken)
    }

    func testInitialSessionNilDoesNotSignOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .success(client.currentSession!)

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .initialSession, session: nil)

        // Ensure the event has a chance to be processed before asserting state remains active.
        await drainAuthEventLoop()
        XCTAssertEqual(adapter.authState, .active)
    }

    func testNilSessionWithTransientRefreshFailureBecomesStaleNotSignedOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(URLError(.notConnectedToInternet))

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .staleRecoverable)
    }

    func testNilSessionWithAuthInvalidRefreshFailureSignsOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh token"])
        )

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    func testNilSessionWithTypedAuthSessionExpiredErrorSignsOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            AuthError.api(
                message: "Session expired",
                errorCode: .sessionExpired,
                underlyingData: Data(),
                underlyingResponse: HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        )

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    func testSignOutClearsSupabaseSessionStorageKeysWhenAuthClientSignOutFails() async throws {
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        try store.saveAuthMetadataValue(String(Date().timeIntervalSince1970), forKey: lastAuthTimestampKey)
        try store.saveSessionData(Data("session".utf8), forKey: "supabase.auth.token")
        try store.saveSessionData(Data("legacy".utf8), forKey: "supabase.session")

        let client = FakeSupabaseAuthClient()
        client.signOutError = NSError(
            domain: "Auth",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Sign-out transport failure"]
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: false,
            userDefaults: makeUserDefaults()
        )
        adapter.restoreSession(accessToken: "token", userId: "user")

        await adapter.signOut()

        XCTAssertEqual(adapter.authState, .signedOut)
        XCTAssertNil(try store.loadAccessToken())
        XCTAssertNil(try store.loadUserId())
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: lastAuthTimestampKey))
        XCTAssertNil(try store.loadSessionData(forKey: "supabase.auth.token"))
        XCTAssertNil(try store.loadSessionData(forKey: "supabase.session"))
    }

    func makeUserDefaults() -> UserDefaults {
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterTests")
        isolatedDefaults.append(isolated)
        return isolated.defaults
    }
}
