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
}
