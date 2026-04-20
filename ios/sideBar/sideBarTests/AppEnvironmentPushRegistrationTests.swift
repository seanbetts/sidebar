import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentPushRegistrationTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var isolatedDefaults: TestIsolation.IsolatedUserDefaults!
    private var router: ScopedURLProtocolRouter!
    private let deviceInstallationIdKey = AppStorageKeys.deviceInstallationId

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
        isolatedDefaults = TestIsolation.makeUserDefaults(prefix: "AppEnvironmentPushRegistrationTests")
        retainedEnvironments.removeAll()
        isolatedDefaults.defaults.removeObject(forKey: deviceInstallationIdKey)
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        router.invalidate()
        router = nil
        isolatedDefaults?.tearDown()
        isolatedDefaults = nil
        super.tearDown()
    }

    func testRegisterDeviceTokenIfNeededCoalescesInFlightRegistrationForSameToken() async throws {
        let requestCounter = LockedCounter()
        let firstRequestStarted = DispatchSemaphore(value: 0)
        let releaseRequests = DispatchSemaphore(value: 0)
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let path = request.url?.path

            if path?.hasSuffix("/device-tokens/presence") == true {
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data("{}".utf8))
            }

            XCTAssertTrue(path?.hasSuffix("/device-tokens") == true)

            let count = requestCounter.increment()
            if count == 1 {
                firstRequestStarted.signal()
            }

            XCTAssertEqual(releaseRequests.wait(timeout: .now() + 2), .success)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let environment = makeEnvironment(userId: "user-123")

        environment.updateDeviceToken("device-token-123")
        let firstRequestResult = await waitForSignal(firstRequestStarted, timeout: 1.0)
        XCTAssertEqual(firstRequestResult, .success)

        environment.registerDeviceTokenIfNeeded()
        await waitForRequestCount(requestCounter, expected: 1)
        XCTAssertEqual(requestCounter.value, 1)

        releaseRequests.signal()
        await waitForRegistrationState(
            environment,
            token: "device-token-123",
            userId: "user-123"
        )
        XCTAssertEqual(environment.lastRegisteredDeviceToken, "device-token-123")
        XCTAssertEqual(environment.lastRegisteredUserId, "user-123")
    }

    func testRegisterDeviceTokenIfNeededSendsPersistedInstallationIdentifier() async throws {
        let registration = expectation(description: "registration")
        let presence = expectation(description: "presence")
        let registerInstallationIds = LockedStringArray()
        let presenceInstallationIds = LockedStringArray()

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try Self.jsonBody(from: request)
            let installationId = try XCTUnwrap(payload["installation_id"] as? String)

            if request.url?.path.hasSuffix("/device-tokens/presence") == true {
                presenceInstallationIds.append(installationId)
                presence.fulfill()
                return (response, Data("{}".utf8))
            }

            registerInstallationIds.append(installationId)
            registration.fulfill()
            return (response, Data("{}".utf8))
        }

        let firstEnvironment = makeEnvironment(userId: "user-123")

        firstEnvironment.updateDeviceToken("device-token-123")
        await fulfillment(of: [registration, presence], timeout: 2.0)

        let storedInstallationId = isolatedDefaults.defaults.string(forKey: deviceInstallationIdKey)
        XCTAssertEqual(registerInstallationIds.value.count, 1)
        XCTAssertEqual(presenceInstallationIds.value.count, 1)
        XCTAssertEqual(registerInstallationIds.value.first, storedInstallationId)
        XCTAssertEqual(presenceInstallationIds.value.first, storedInstallationId)

        let secondEnvironment = makeEnvironment(userId: "user-456")
        _ = secondEnvironment
        XCTAssertEqual(
            isolatedDefaults.defaults.string(forKey: deviceInstallationIdKey),
            storedInstallationId
        )
    }

    func testDisableDeviceTokenIfNeededClearsRegistrationCache() async {
        let disableRequest = expectation(description: "disable request")

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.httpMethod == "DELETE" {
                let payload = try Self.jsonBody(from: request)
                XCTAssertEqual(payload["installation_id"] as? String, "install-123")
                XCTAssertEqual(payload["token"] as? String, "device-token-123")
                disableRequest.fulfill()
            }
            return (response, Data("{}".utf8))
        }

        let environment = makeEnvironment(userId: "user-123")
        isolatedDefaults.defaults.set("install-123", forKey: deviceInstallationIdKey)
        environment.deviceToken = "device-token-123"
        environment.lastRegisteredDeviceInstallationId = "install-123"
        environment.lastRegisteredDeviceToken = "device-token-123"
        environment.lastRegisteredUserId = "user-123"
        environment.inFlightDeviceInstallationId = "install-123"
        environment.inFlightDeviceToken = "device-token-123"
        environment.inFlightDeviceTokenUserId = "user-123"

        await environment.disableDeviceTokenIfNeeded()
        await fulfillment(of: [disableRequest], timeout: 2.0)

        XCTAssertNil(environment.lastRegisteredDeviceInstallationId)
        XCTAssertNil(environment.lastRegisteredDeviceToken)
        XCTAssertNil(environment.lastRegisteredUserId)
        XCTAssertNil(environment.inFlightDeviceInstallationId)
        XCTAssertNil(environment.inFlightDeviceToken)
        XCTAssertNil(environment.inFlightDeviceTokenUserId)
    }

    func testRegisterDeviceTokenIfNeededRecordsLifecycleStateOnSuccess() async throws {
        let requestCompleted = expectation(description: "request completed")

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path.hasSuffix("/device-tokens/presence") == true {
                requestCompleted.fulfill()
            }
            return (response, Data("{}".utf8))
        }

        let environment = makeEnvironment(userId: "user-123")
        let token = "device-token-abcdef"

        environment.updateDeviceToken(token)
        await fulfillment(of: [requestCompleted], timeout: 2.0)
        await waitForRegistrationState(
            environment,
            token: token,
            userId: "user-123"
        )

        XCTAssertEqual(environment.pushDiagnosticsState.currentDeviceTokenSuffix, "abcdef")
        XCTAssertNotNil(environment.pushDiagnosticsState.currentDeviceInstallationId)
        XCTAssertNotNil(environment.pushDiagnosticsState.lastDeviceRegistrationAttemptAt)
        XCTAssertEqual(environment.pushDiagnosticsState.lastDeviceRegistrationResult, .success)
        XCTAssertNotNil(environment.pushDiagnosticsState.lastDevicePresenceUpdateAt)
        XCTAssertNotNil(environment.pushDiagnosticsState.currentDevicePresenceIsForeground)
    }

    func testRegisterDeviceTokenIfNeededRecordsLifecycleStateOnFailure() async throws {
        let registrationFailed = expectation(description: "registration failed")

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path.hasSuffix("/device-tokens") == true {
                registrationFailed.fulfill()
            }
            return (response, Data("{}".utf8))
        }

        let environment = makeEnvironment(userId: "user-123")

        environment.updateDeviceToken("device-token-abcdef")
        await fulfillment(of: [registrationFailed], timeout: 2.0)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(environment.pushDiagnosticsState.lastDeviceRegistrationAttemptAt)
        XCTAssertEqual(environment.pushDiagnosticsState.lastDeviceRegistrationResult, .failure)
        XCTAssertNil(environment.pushDiagnosticsState.lastDevicePresenceUpdateAt)
    }

    func testRefreshAuthStateHydratesInstallationIdAndRequestsRemoteRegistration() {
        let authSession = PushMutableAuthSession(authState: .signedOut, userId: "user-123")
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        isolatedDefaults.defaults.set("install-123", forKey: deviceInstallationIdKey)
        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(userDefaults: isolatedDefaults.defaults)
        )
        retainedEnvironments.append(environment)
        let registrationCount = LockedCounter()
        environment.remoteNotificationRegistrar = {
            _ = registrationCount.increment()
        }

        XCTAssertEqual(
            environment.pushDiagnosticsState.currentDeviceInstallationId,
            "install-123"
        )

        authSession.authState = .active
        environment.refreshAuthState()

        XCTAssertEqual(registrationCount.value, 1)
        XCTAssertEqual(
            environment.pushDiagnosticsState.currentDeviceInstallationId,
            "install-123"
        )
    }

    private func makeEnvironment(userId: String) -> AppEnvironment {
        let authSession = PushMutableAuthSession(authState: .active, userId: userId)
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { nil }
        )
        let deviceTokensAPI = DeviceTokensAPI(
            client: APIClient(config: config, session: router.makeSession())
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            deviceTokensAPI: deviceTokensAPI
        )
        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(
                userDefaults: isolatedDefaults.defaults
            )
        )
        retainedEnvironments.append(environment)
        return environment
    }

    private func waitForRequestCount(
        _ counter: LockedCounter,
        expected: Int,
        attempts: Int = 20
    ) async {
        for _ in 0..<attempts where counter.value < expected {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForRegistrationState(
        _ environment: AppEnvironment,
        token: String,
        userId: String,
        attempts: Int = 40
    ) async {
        for _ in 0..<attempts
        where environment.lastRegisteredDeviceToken != token
            || environment.lastRegisteredUserId != userId {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForSignal(
        _ semaphore: DispatchSemaphore,
        timeout seconds: TimeInterval
    ) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: semaphore.wait(timeout: .now() + seconds)
                )
            }
        }
    }

    private static func jsonBody(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBodyData())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        return object
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
        return storage
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var value: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class PushMutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(authState: AuthState, userId: String?) {
        self.authState = authState
        self.userId = userId
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

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
