import XCTest
import sideBarShared
import Supabase
@testable import sideBar

@MainActor
final class SupabaseAuthAdapterBackendRejectionTests: XCTestCase {
    func testBackendAuthorizationRejectionRequiresPrimaryReauthentication() {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        XCTAssertEqual(adapter.authState, .active)
        XCTAssertEqual(adapter.authorizationToken, token)

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()

        XCTAssertEqual(adapter.authState, .reauthenticationRequired)
        XCTAssertNil(adapter.authorizationToken)
    }

    func testBackendAuthorizationRejectionRequiresPrimaryReauthenticationWhenSessionIsRecoverablyStale() async {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        client.refreshResult = .failure(URLError(.notConnectedToInternet))
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        await adapter.refreshSession()

        XCTAssertEqual(adapter.authState, .staleRecoverable)

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()

        XCTAssertEqual(adapter.authState, .reauthenticationRequired)
        XCTAssertNil(adapter.authorizationToken)
    }

    func testBackendAuthorizationRejectionIgnoresLaterStoredSessionEvents() async {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: true,
            userDefaults: isolated.defaults
        )

        await waitForAuthStateSubscriber(client)

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()
        client.yield(event: .initialSession, session: SupabaseSessionInfo(
            accessToken: token,
            userId: "user-1",
            expiresAt: exp
        ))

        await Task.yield()

        XCTAssertEqual(adapter.authState, .reauthenticationRequired)
        XCTAssertNil(adapter.authorizationToken)
    }

    func testExplicitSignInCanRecoverAfterBackendAuthorizationRejection() async throws {
        let staleExp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let freshExp: TimeInterval = Date().addingTimeInterval(2 * 60 * 60).timeIntervalSince1970
        let staleToken = makeJwt(exp: staleExp)
        let freshToken = makeJwt(exp: freshExp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: staleToken, userId: "user-1", expiresAt: staleExp)
        client.signInResult = .success(())
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()
        client.currentSession = SupabaseSessionInfo(accessToken: freshToken, userId: "user-1", expiresAt: freshExp)

        try await adapter.signIn(email: "person@example.com", password: "password123")

        XCTAssertEqual(adapter.authState, .active)
        XCTAssertEqual(adapter.authorizationToken, freshToken)
    }

    func testBackendAuthorizationRejectionForPreviousTokenDoesNotInvalidateFreshSignIn() async throws {
        let staleExp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let freshExp: TimeInterval = Date().addingTimeInterval(2 * 60 * 60).timeIntervalSince1970
        let staleToken = makeJwt(exp: staleExp)
        let freshToken = makeJwt(exp: freshExp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: staleToken, userId: "user-1", expiresAt: staleExp)
        client.signInResult = .success(())
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()
        client.currentSession = SupabaseSessionInfo(accessToken: freshToken, userId: "user-1", expiresAt: freshExp)
        try await adapter.signIn(email: "person@example.com", password: "password123")
        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: staleToken)

        XCTAssertEqual(adapter.authState, .active)
        XCTAssertEqual(adapter.authorizationToken, freshToken)
    }

    func testBackendAuthorizationRejectionForPreviousTokenRecordsRedactedDiagnostic() async throws {
        let staleExp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let freshExp: TimeInterval = Date().addingTimeInterval(2 * 60 * 60).timeIntervalSince1970
        let staleToken = makeJwt(exp: staleExp)
        let freshToken = makeJwt(exp: freshExp)
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: staleToken, userId: "user-1", expiresAt: staleExp)
        client.signInResult = .success(())
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults,
            diagnostics: diagnostics
        )

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure()
        client.currentSession = SupabaseSessionInfo(accessToken: freshToken, userId: "user-1", expiresAt: freshExp)
        try await adapter.signIn(email: "person@example.com", password: "password123")
        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: staleToken)

        XCTAssertEqual(adapter.authState, .active)
        XCTAssertTrue(diagnostics.events.contains {
            $0.name == "backend_rejection_ignored" &&
                $0.metadata["reason"] == "previous_token"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(staleToken))
        XCTAssertFalse(diagnostics.containsSensitiveValue(freshToken))
        XCTAssertFalse(diagnostics.containsSensitiveValue("user-1"))
    }

    func testBackendAuthorizationRejectionForCurrentTokenRecordsRedactedDiagnostic() {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterBackendRejectionTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults,
            diagnostics: diagnostics
        )

        adapter.markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: token)

        XCTAssertEqual(adapter.authState, .reauthenticationRequired)
        XCTAssertTrue(diagnostics.events.contains {
            $0.name == "backend_rejection_accepted" &&
                $0.metadata["reason"] == "current_token"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue("user-1"))
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

    private func waitForAuthStateSubscriber(_ client: FakeSupabaseAuthClient) async {
        for _ in 0..<20 {
            if client.hasSubscriber {
                return
            }
            await Task.yield()
        }
    }
}
