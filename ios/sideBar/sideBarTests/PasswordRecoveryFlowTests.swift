import XCTest
import sideBarShared
@testable import sideBar

    @MainActor
    final class PasswordRecoveryFlowTests: XCTestCase {
    private let recoveryCallbackURLString =
        "https://sidebar.app/auth/callback#access_token=token-123&refresh_token=refresh-456" +
        "&expires_in=3600&token_type=bearer&type=recovery"

    func testRecoveryURLMatcherAcceptsImplicitGrantRecoveryLink() {
        let url = URL(string: recoveryCallbackURLString)!

        XCTAssertTrue(PasswordRecoveryURLMatcher.matches(url))
    }

    func testRecoveryURLMatcherRejectsRegularSidebarDeepLink() {
        let url = URL(string: "sidebar://tasks/new")!

        XCTAssertFalse(PasswordRecoveryURLMatcher.matches(url))
    }

    func testHandleDeepLinkWithRecoveryURLStartsPasswordResetFlow() async {
        let manager = FakePasswordRecoveryManager()
        let authSession = FakeAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            passwordRecoveryManager: manager
        )
        let defaults = TestIsolation.makeUserDefaults(prefix: "PasswordRecoveryFlowTests")
        let storage = AppEnvironmentStorage(
            userDefaults: defaults.defaults,
            widgetDataManager: WidgetDataManager(userDefaults: defaults.defaults),
            extensionEventStore: ExtensionEventStore(userDefaults: defaults.defaults),
            pendingShareStore: PendingShareStore(userDefaults: defaults.defaults)
        )
        let environment = AppEnvironment(container: container, storage: storage)

        let url = URL(string: recoveryCallbackURLString)!

        environment.handleDeepLink(url)
        await Task.yield()

        XCTAssertEqual(manager.startedURLs, [url])
        XCTAssertEqual(environment.passwordResetState, .enterNewPassword)
    }

    func testHandleDeepLinkWithRecoveryFailureLeavesResetFlowInactive() async {
        let manager = FakePasswordRecoveryManager()
        manager.startRecoveryError = NSError(domain: "PasswordRecoveryFlowTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Recovery callback was missing credentials."
        ])
        let authSession = FakeAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            passwordRecoveryManager: manager
        )
        let defaults = TestIsolation.makeUserDefaults(prefix: "PasswordRecoveryDiagnosticsTests")
        let storage = AppEnvironmentStorage(
            userDefaults: defaults.defaults,
            widgetDataManager: WidgetDataManager(userDefaults: defaults.defaults),
            extensionEventStore: ExtensionEventStore(userDefaults: defaults.defaults),
            pendingShareStore: PendingShareStore(userDefaults: defaults.defaults)
        )
        let environment = AppEnvironment(container: container, storage: storage)

        let url = URL(string: recoveryCallbackURLString)!

        environment.handleDeepLink(url)
        await Task.yield()

        XCTAssertNil(environment.passwordResetState)
    }

    func testCompletePasswordRecoveryClearsFlowAndReturnsToLogin() async throws {
        let manager = FakePasswordRecoveryManager()
        let authSession = FakeAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            passwordRecoveryManager: manager
        )
        let environment = AppEnvironment(container: container)
        environment.passwordResetState = .enterNewPassword
        environment.authState = .active

        try await environment.completePasswordRecovery(newPassword: "StrongPass123!")

        XCTAssertEqual(manager.completedPasswords, ["StrongPass123!"])
        XCTAssertEqual(authSession.signOutCallCount, 1)
        XCTAssertNil(environment.passwordResetState)
        XCTAssertEqual(environment.passwordResetSuccessMessage, "Password updated. Sign in with your new password.")
        XCTAssertEqual(environment.authState, .signedOut)
    }

    func testAppEnvironmentCanStartInPasswordResetMode() {
        let environment = AppEnvironment(
            container: ServiceContainer(
                config: .fallbackForTesting(),
                authSession: PlaceholderAuthSession(authState: .signedOut),
                cacheClient: InMemoryCacheClient()
            ),
            initialPasswordResetState: .enterNewPassword
        )

        XCTAssertEqual(environment.passwordResetState, .enterNewPassword)
    }

    func testCompleteSettingsPasswordChangeSignsOutWithSuccessNotice() async throws {
        let recoveryManager = FakePasswordRecoveryManager()
        let passwordChangeManager = FakePasswordChangeManager()
        let authSession = FakeAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            passwordRecoveryManager: recoveryManager,
            passwordChangeManager: passwordChangeManager
        )
        let environment = AppEnvironment(container: container)
        environment.authState = .active

        try await environment.completeSettingsPasswordChange(newPassword: "StrongPass123!")

        XCTAssertEqual(passwordChangeManager.completedPasswords, ["StrongPass123!"])
        XCTAssertEqual(authSession.signOutCallCount, 1)
        XCTAssertEqual(environment.passwordResetSuccessMessage, "Password updated. Sign in with your new password.")
        XCTAssertNil(environment.passwordResetSuccessDetail)
        XCTAssertEqual(environment.authState, .signedOut)
    }
}

private final class FakePasswordRecoveryManager: PasswordRecoveryManaging {
    private(set) var startedURLs: [URL] = []
    private(set) var completedPasswords: [String] = []
    var startRecoveryError: Error?

    func startRecoverySession(from url: URL) async throws {
        if let startRecoveryError {
            throw startRecoveryError
        }
        startedURLs.append(url)
    }

    func completePasswordReset(newPassword: String) async throws {
        completedPasswords.append(newPassword)
    }
}

private final class FakePasswordChangeManager: PasswordChanging {
    var completedPasswords: [String] = []

    func changePassword(newPassword: String) async throws {
        completedPasswords.append(newPassword)
    }
}

private final class FakeAuthSession: AuthSession {
    var accessToken: String?
    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }
    var userId: String?
    var authState: AuthState
    var pendingVerificationEmail: String?
    private(set) var signOutCallCount = 0

    init(authState: AuthState) {
        self.authState = authState
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

    func refreshSession() async {}

    func refreshSessionIfStale() async {}

    func signOut() async {
        signOutCallCount += 1
        authState = .signedOut
        accessToken = nil
        userId = nil
    }
}
