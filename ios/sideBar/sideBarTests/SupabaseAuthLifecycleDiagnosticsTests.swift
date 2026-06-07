import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthLifecycleDiagnosticsTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testTransientRefreshFailureRecordsRedactedDiagnostic() async throws {
        let exp = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp, subject: "sensitive-user-id")
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "sensitive-user-id", expiresAt: exp)
        client.refreshResult = .failure(URLError(.notConnectedToInternet))
        let adapter = makeAdapter(authClient: client, diagnostics: diagnostics)

        await adapter.refreshSession()

        XCTAssertEqual(adapter.authState, .staleRecoverable)
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "refresh_failed" &&
                $0.metadata["classification"] == "transient" &&
                $0.metadata["auth_state"] == "staleRecoverable"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue("sensitive-user-id"))
    }

    func testInvalidRefreshFailureRecordsRedactedDiagnostic() async throws {
        let exp = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp, subject: "sensitive-user-id")
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "sensitive-user-id", expiresAt: exp)
        client.refreshResult = .failure(
            NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh token revoked"])
        )
        let adapter = makeAdapter(authClient: client, diagnostics: diagnostics)

        await adapter.refreshSession()

        XCTAssertEqual(adapter.authState, .signedOut)
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "refresh_failed" &&
                $0.metadata["classification"] == "invalid_auth" &&
                $0.metadata["auth_state"] == "signedOut"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue("sensitive-user-id"))
    }

    func testRestoreOfflineSessionWithMissingStoredUserRecordsRedactedDiagnostic() throws {
        let token = "sensitive-access-token"
        let diagnostics = RecordingAuthDiagnostics()
        let store = InMemoryAuthStateStore()
        try store.saveAccessToken(token)
        let adapter = makeAdapter(stateStore: store, diagnostics: diagnostics)

        XCTAssertFalse(adapter.restoreOfflineSession())

        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "restore_offline_session_failed" &&
                $0.metadata["reason"] == "missing_stored_credentials"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
    }

    func testRecoveryTransientFailureRecordsRedactedDiagnostic() async throws {
        let exp = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp, subject: "sensitive-user-id")
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        client.currentSession = SupabaseSessionInfo(accessToken: token, userId: "sensitive-user-id", expiresAt: exp)
        client.refreshResult = .failure(URLError(.timedOut))
        let adapter = makeAdapter(authClient: client, startAuthStateTask: true, diagnostics: diagnostics)

        XCTAssertEqual(adapter.authState, .active)
        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) { adapter.authState == .staleRecoverable }
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "session_recovery_failed" &&
                $0.metadata["classification"] == "transient" &&
                $0.metadata["auth_state"] == "staleRecoverable"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue("sensitive-user-id"))
    }

    func testRecoveryMissingCurrentSessionRecordsDiagnostic() async throws {
        let diagnostics = RecordingAuthDiagnostics()
        let client = FakeSupabaseAuthClient()
        let adapter = makeAdapter(authClient: client, startAuthStateTask: true, diagnostics: diagnostics)

        try await waitUntil(timeoutSeconds: 2.0) { client.hasSubscriber }
        adapter.restoreSession(accessToken: "sensitive-access-token", userId: "sensitive-user-id")
        client.yield(event: .other("TOKEN_REFRESHED"), session: nil)

        try await waitUntil(timeoutSeconds: 5.0) {
            diagnostics.snapshot().contains {
                $0.name == "session_recovery_failed" &&
                    $0.metadata["reason"] == "missing_current_session"
            }
        }
        XCTAssertEqual(adapter.authState, .signedOut)
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "session_recovery_failed" &&
                $0.metadata["reason"] == "missing_current_session"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue("sensitive-access-token"))
        XCTAssertFalse(diagnostics.containsSensitiveValue("sensitive-user-id"))
    }

    func testAuthDiagnosticEventAllowsClassificationAndDropsUnallowlistedMetadata() {
        let event = AuthDiagnosticsEvent(
            name: "refresh_failed",
            metadata: [
                "classification": "invalid_auth",
                "auth_state": "signedOut",
                "token": "sensitive-access-token",
                "user_id": "sensitive-user-id",
                "error": "Refresh token revoked"
            ]
        )

        XCTAssertEqual(event.metadata["classification"], "invalid_auth")
        XCTAssertEqual(event.metadata["auth_state"], "signedOut")
        XCTAssertNil(event.metadata["token"])
        XCTAssertNil(event.metadata["user_id"])
        XCTAssertNil(event.metadata["error"])
        XCTAssertFalse(event.metadata.description.contains("sensitive-access-token"))
        XCTAssertFalse(event.metadata.description.contains("sensitive-user-id"))
    }

    func testAuthDiagnosticEventAllowsRestoreAndRecoveryReasons() {
        let restoreEvent = AuthDiagnosticsEvent(
            name: "restore_offline_session_failed",
            metadata: ["reason": "store_read_failed"]
        )
        let recoveryEvent = AuthDiagnosticsEvent(
            name: "session_recovery_failed",
            metadata: ["reason": "missing_current_session"]
        )

        XCTAssertEqual(restoreEvent.metadata["reason"], "store_read_failed")
        XCTAssertEqual(recoveryEvent.metadata["reason"], "missing_current_session")
    }

    private func makeAdapter(
        authClient: FakeSupabaseAuthClient = FakeSupabaseAuthClient(),
        stateStore: AuthStateStore = InMemoryAuthStateStore(),
        startAuthStateTask: Bool = false,
        diagnostics: AuthDiagnosticsRecording
    ) -> SupabaseAuthAdapter {
        SupabaseAuthAdapter(
            authClient: authClient,
            stateStore: stateStore,
            startAuthStateTask: startAuthStateTask,
            userDefaults: makeUserDefaults(),
            diagnostics: diagnostics
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthLifecycleDiagnosticsTests")
        isolatedDefaults.append(isolated)
        return isolated.defaults
    }

    private func makeJwt(exp: TimeInterval, subject: String) -> String {
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": subject])
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
