import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthSignUpTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []

    private final class FakeSupabaseAuthClient: SupabaseAuthClientProtocol, @unchecked Sendable {
        var currentSession: SupabaseSessionInfo?
        var signUpResult: Result<Void, Error>
        var verifyOTPResult: Result<SupabaseSessionInfo, Error>

        init(
            signUpResult: Result<Void, Error> = .success(()),
            verifyOTPResult: Result<SupabaseSessionInfo, Error> = .failure(AuthAdapterError.invalidCredentials)
        ) {
            self.signUpResult = signUpResult
            self.verifyOTPResult = verifyOTPResult
        }

        var authStateChanges: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)> {
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func signIn(email: String, password: String) async throws {
            _ = email
            _ = password
        }

        func signUp(email: String, password: String) async throws {
            _ = email
            _ = password
            try signUpResult.get()
        }

        func verifyOTP(email: String, code: String) async throws -> SupabaseSessionInfo {
            _ = email
            _ = code
            let session = try verifyOTPResult.get()
            currentSession = session
            return session
        }

        func refreshSession() async throws -> SupabaseSessionInfo {
            throw AuthAdapterError.sessionRefreshFailed
        }

        func signOut() async throws {
            currentSession = nil
        }
    }

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testSignUpSetsPendingVerificationEmail() async throws {
        let adapter = makeAdapter(
            authClient: FakeSupabaseAuthClient(signUpResult: .success(()))
        )

        try await adapter.signUp(email: "test@example.com", password: "StrongPass123!")

        XCTAssertEqual(adapter.pendingVerificationEmail, "test@example.com")
    }

    func testSignUpRejectsWeakPassword() async {
        let adapter = makeAdapter(
            authClient: FakeSupabaseAuthClient(signUpResult: .success(()))
        )

        do {
            try await adapter.signUp(email: "test@example.com", password: "123")
            XCTFail("Expected weak password error")
        } catch let error as AuthAdapterError {
            XCTAssertEqual(error, .weakPassword)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVerifyOTPSignsInOnSuccess() async throws {
        let adapter = makeAdapter(
            authClient: FakeSupabaseAuthClient(
                signUpResult: .success(()),
                verifyOTPResult: .success(
                    SupabaseSessionInfo(
                        accessToken: makeJwt(sub: "u1"),
                        userId: "u1",
                        expiresAt: 4_102_444_800
                    )
                )
            )
        )

        try await adapter.signUp(email: "test@example.com", password: "StrongPass123!")
        try await adapter.verifyOTP(email: "test@example.com", code: "482159")

        XCTAssertEqual(adapter.authState, .active)
        XCTAssertEqual(adapter.userId, "u1")
        XCTAssertNil(adapter.pendingVerificationEmail)
    }

    func testVerifyOTPRejectsInvalidCode() async throws {
        let adapter = makeAdapter(
            authClient: FakeSupabaseAuthClient(
                signUpResult: .success(()),
                verifyOTPResult: .failure(AuthAdapterError.invalidCredentials)
            )
        )

        try await adapter.signUp(email: "test@example.com", password: "StrongPass123!")

        do {
            try await adapter.verifyOTP(email: "test@example.com", code: "000000")
            XCTFail("Expected invalid credentials error")
        } catch let error as AuthAdapterError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeAdapter(authClient: FakeSupabaseAuthClient) -> SupabaseAuthAdapter {
        SupabaseAuthAdapter(
            authClient: authClient,
            stateStore: InMemoryAuthStateStore(),
            userDefaults: makeUserDefaults()
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthSignUpTests")
        isolatedDefaults.append(isolated)
        return isolated.defaults
    }

    private func makeJwt(sub: String) -> String {
        let header = Data("{\"alg\":\"none\",\"typ\":\"JWT\"}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"sub\":\"\(sub)\",\"exp\":4102444800}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload)."
    }
}
