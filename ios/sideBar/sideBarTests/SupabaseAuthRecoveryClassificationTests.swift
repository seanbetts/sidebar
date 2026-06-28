import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthRecoveryClassificationTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testGenericUnauthorizedRefreshFailureBecomesStaleRecoverable() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .staleRecoverable)
    }

    func testGenericForbiddenRefreshFailureBecomesStaleRecoverable() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Forbidden"])
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .staleRecoverable)
    }

    func testSessionSpecificUnauthorizedRefreshFailureSignsOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unauthorized session"])
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    func testRevokedRefreshTokenFailureSignsOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh token revoked"])
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    func testSessionExpiredFailureSignsOut() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session expired"])
        )
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: makeUserDefaults()
        )

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState != .active }
        XCTAssertEqual(adapter.authState, .signedOut)
    }

    private func makeUserDefaults() -> UserDefaults {
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthRecoveryClassificationTests")
        isolatedDefaults.append(isolated)
        return isolated.defaults
    }

    private func makeJwt(exp: TimeInterval) -> String {
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        return "\(header).\(payload)."
    }

    private func base64UrlEncode(_ payload: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let encoded = data?.base64EncodedString() ?? ""
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }
}
