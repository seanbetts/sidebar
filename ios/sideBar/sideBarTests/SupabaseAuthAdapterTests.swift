import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthAdapterTests: XCTestCase {
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp

    private final class FakeSupabaseAuthClient: SupabaseAuthClientProtocol, @unchecked Sendable {
        var currentSession: SupabaseSessionInfo?
        var refreshResult: Result<SupabaseSessionInfo, Error>?

        private var continuation: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)>.Continuation?

        var authStateChanges: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)> {
            AsyncStream { continuation in
                self.continuation = continuation
            }
        }

        func yield(event: SupabaseAuthEvent, session: SupabaseSessionInfo?) {
            continuation?.yield((event, session))
        }

        func finish() {
            continuation?.finish()
        }

        func signIn(email: String, password: String) async throws {
            _ = email
            _ = password
        }

        func refreshSession() async throws -> SupabaseSessionInfo {
            guard let refreshResult else {
                throw NSError(domain: "FakeSupabaseAuthClient", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No refresh result configured"
                ])
            }
            switch refreshResult {
            case .success(let session):
                currentSession = session
                return session
            case .failure(let error):
                throw error
            }
        }

        func signOut() async throws {
            currentSession = nil
        }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: lastAuthTimestampKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastAuthTimestampKey)
        super.tearDown()
    }

    func testJwtExpiryDateUsesExpClaim() {
        let exp: TimeInterval = 1_800_000_000
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        let token = "\(header).\(payload)."

        let date = SupabaseAuthAdapter.jwtExpiryDate(from: token)
        XCTAssertEqual(date, Date(timeIntervalSince1970: exp))
    }

    func testJwtExpiryDateReturnsNilForInvalidToken() {
        let date = SupabaseAuthAdapter.jwtExpiryDate(from: "invalid-token")
        XCTAssertNil(date)
    }

    func testOfflineAccessAllowsStoredCredentialsWithinWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-12 * 60 * 60)
        UserDefaults.standard.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertEqual(adapter.accessToken, "token")
        XCTAssertEqual(adapter.userId, "user")
    }

    func testOfflineAccessRejectsStoredCredentialsOutsideWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        UserDefaults.standard.set(outsideWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertNil(adapter.accessToken)
        XCTAssertNil(adapter.userId)
    }

    func testCanRestoreOfflineSessionRespectsWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-2 * 60 * 60)
        UserDefaults.standard.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertTrue(adapter.canRestoreOfflineSession)
        XCTAssertTrue(adapter.restoreOfflineSession())
        XCTAssertEqual(adapter.accessToken, "token")
        XCTAssertEqual(adapter.userId, "user")
    }

    func testRestoreOfflineSessionFailsOutsideWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        UserDefaults.standard.set(outsideWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertFalse(adapter.restoreOfflineSession())
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
        let adapter = SupabaseAuthAdapter(authClient: client, stateStore: store, startAuthStateTask: false)

        XCTAssertEqual(adapter.authState, .stale)
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
        let adapter = SupabaseAuthAdapter(authClient: client, stateStore: store, startAuthStateTask: true)

        XCTAssertEqual(adapter.authState, .active)
        client.yield(event: .initialSession, session: nil)

        try await waitUntil(timeoutSeconds: 1.0) { adapter.authState == .active }
        XCTAssertEqual(adapter.authState, .active)
    }

    func testNilSessionWithTransientRefreshFailureBecomesStaleNotSignedOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(URLError(.notConnectedToInternet))

        let store = InMemoryAuthStateStore()
        let adapter = SupabaseAuthAdapter(authClient: client, stateStore: store, startAuthStateTask: true)

        XCTAssertEqual(adapter.authState, .active)
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 2.0) { adapter.authState == .stale }
        XCTAssertEqual(adapter.authState, .stale)
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
        let adapter = SupabaseAuthAdapter(authClient: client, stateStore: store, startAuthStateTask: true)

        XCTAssertEqual(adapter.authState, .active)
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 2.0) { adapter.authState == .signedOut }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    private func base64UrlEncode(_ payload: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let encoded = data?.base64EncodedString() ?? ""
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeJwt(exp: TimeInterval) -> String {
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        return "\(header).\(payload)."
    }

    private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
