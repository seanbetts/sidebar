import Combine
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentAuthSessionInterfaceTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []

    func testConfigureSubscriptionsRefreshesAuthStateFromObservableAuthSession() async {
        let authSession = ObservableAuthSessionDouble(authState: .signedOut)
        let environment = makeEnvironment(authSession: authSession)

        environment.configureSubscriptions()
        authSession.update(
            accessToken: "access-token",
            userId: "user-123",
            authState: .active
        )

        await Task.yield()

        XCTAssertEqual(environment.authState, .active)
    }

    func testConfigureSubscriptionsShowsAuthErrorFromObservableAuthSession() async {
        let authSession = ObservableAuthSessionDouble(authState: .active)
        let environment = makeEnvironment(authSession: authSession)

        environment.configureSubscriptions()
        authSession.publishAuthError(message: "Session refresh failed.")

        await Task.yield()

        XCTAssertEqual(environment.toastCenter.toast?.message, "Session refresh failed.")
        XCTAssertEqual(authSession.clearAuthErrorCallCount, 1)
    }

    func testConfigureSubscriptionsRoutesProtectedAuthRejectionToReauthenticationRequired() async {
        let authSession = ObservableAuthSessionDouble(
            accessToken: "stale-token",
            userId: "user-123",
            authState: .active
        )
        let environment = makeEnvironment(authSession: authSession)
        environment.configureSubscriptions()
        environment.toastCenter.show(message: "Unable to load tasks")

        NotificationCenter.default.post(name: .apiClientAuthenticationRejected, object: nil)

        await Task.yield()

        XCTAssertEqual(environment.authState, .reauthenticationRequired)
        XCTAssertFalse(environment.isAuthenticated)
        XCTAssertFalse(environment.isProtectedContentReady)
        XCTAssertNil(environment.toastCenter.toast)
        XCTAssertEqual(authSession.reauthRequiredCallCount, 1)
    }

    func testConfigureSubscriptionsKeepsAuthRejectionIdempotentAfterReauthenticationRequired() async {
        let authSession = ObservableAuthSessionDouble(
            accessToken: "stale-token",
            userId: "user-123",
            authState: .active
        )
        let environment = makeEnvironment(authSession: authSession)
        environment.configureSubscriptions()

        NotificationCenter.default.post(name: .apiClientAuthenticationRejected, object: nil)
        NotificationCenter.default.post(name: .apiClientAuthenticationRejected, object: nil)

        await Task.yield()

        XCTAssertEqual(environment.authState, .reauthenticationRequired)
        XCTAssertEqual(authSession.reauthRequiredCallCount, 1)
    }

    func testConfigureSubscriptionsRoutesStaleProtectedAuthRejectionToReauthenticationRequired() async {
        let authSession = ObservableAuthSessionDouble(
            accessToken: "stale-token",
            userId: "user-123",
            authState: .staleRecoverable
        )
        let environment = makeEnvironment(authSession: authSession)
        environment.configureSubscriptions()
        environment.toastCenter.show(message: "Unable to load chats")

        NotificationCenter.default.post(name: .apiClientAuthenticationRejected, object: nil)

        await Task.yield()

        XCTAssertEqual(environment.authState, .reauthenticationRequired)
        XCTAssertFalse(environment.isAuthenticated)
        XCTAssertFalse(environment.isProtectedContentReady)
        XCTAssertNil(environment.toastCenter.toast)
        XCTAssertEqual(authSession.reauthRequiredCallCount, 1)
    }

    func testConfigureSubscriptionsRoutesSeededPlaceholderAuthRejectionToReauthenticationRequired() async {
        let authSession = PlaceholderAuthSession(
            accessToken: "stale-token",
            userId: "user-123",
            authState: .active
        )
        let environment = makeEnvironment(authSession: authSession)
        environment.configureSubscriptions()

        NotificationCenter.default.post(name: .apiClientAuthenticationRejected, object: nil)

        await Task.yield()

        XCTAssertEqual(environment.authState, .reauthenticationRequired)
        XCTAssertFalse(environment.isAuthenticated)
        XCTAssertFalse(environment.isProtectedContentReady)
        XCTAssertNil(authSession.authorizationToken)
    }

    func testConfigureSubscriptionsForwardsToastCenterObjectWillChange() async {
        let authSession = ObservableAuthSessionDouble(authState: .active)
        let environment = makeEnvironment(authSession: authSession)
        var forwardedChangeCount = 0
        let forwardedChange = expectation(description: "AppEnvironment forwards toast center changes")
        forwardedChange.assertForOverFulfill = false

        environment.configureSubscriptions()
        let cancellable = environment.objectWillChange.sink {
            forwardedChangeCount += 1
            forwardedChange.fulfill()
        }

        environment.toastCenter.show(message: "Text copied", style: .success)

        await fulfillment(of: [forwardedChange], timeout: 1.0)

        XCTAssertGreaterThan(forwardedChangeCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    private func makeEnvironment(authSession: AuthSession) -> AppEnvironment {
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        retainedEnvironments.append(environment)
        return environment
    }
}

@MainActor
private final class ObservableAuthSessionDouble: AuthSession, AuthSessionObserving, AuthSessionInvalidating {
    private let accessTokenSubject: CurrentValueSubject<String?, Never>
    private let authStateSubject: CurrentValueSubject<AuthState, Never>
    private let authErrorSubject = PassthroughSubject<AuthErrorEvent, Never>()

    private(set) var accessToken: String?
    private(set) var userId: String?
    private(set) var authState: AuthState
    private(set) var clearAuthErrorCallCount = 0
    private(set) var reauthRequiredCallCount = 0

    init(
        accessToken: String? = nil,
        userId: String? = nil,
        authState: AuthState
    ) {
        self.accessToken = accessToken
        self.userId = userId
        self.authState = authState
        self.accessTokenSubject = CurrentValueSubject(accessToken)
        self.authStateSubject = CurrentValueSubject(authState)
    }

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    var accessTokenPublisher: AnyPublisher<String?, Never> {
        accessTokenSubject.eraseToAnyPublisher()
    }

    var authStatePublisher: AnyPublisher<AuthState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    var authErrorPublisher: AnyPublisher<AuthErrorEvent, Never> {
        authErrorSubject.eraseToAnyPublisher()
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        update(accessToken: nil, userId: nil, authState: .signedOut)
    }

    func clearAuthError() {
        clearAuthErrorCallCount += 1
    }

    func markSessionReauthenticationRequiredAfterAuthorizationFailure() {
        guard authState == .active || authState == .staleRecoverable else { return }
        reauthRequiredCallCount += 1
        update(accessToken: accessToken, userId: userId, authState: .reauthenticationRequired)
    }

    func update(accessToken: String?, userId: String?, authState: AuthState) {
        self.accessToken = accessToken
        self.userId = userId
        self.authState = authState
        accessTokenSubject.send(accessToken)
        authStateSubject.send(authState)
    }

    func publishAuthError(message: String) {
        authErrorSubject.send(AuthErrorEvent(message: message))
    }
}
