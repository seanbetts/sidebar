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
private final class ObservableAuthSessionDouble: AuthSession, AuthSessionObserving {
    private let accessTokenSubject: CurrentValueSubject<String?, Never>
    private let authStateSubject: CurrentValueSubject<AuthState, Never>
    private let authErrorSubject = PassthroughSubject<AuthErrorEvent, Never>()

    private(set) var accessToken: String?
    private(set) var userId: String?
    private(set) var authState: AuthState
    private(set) var clearAuthErrorCallCount = 0

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
