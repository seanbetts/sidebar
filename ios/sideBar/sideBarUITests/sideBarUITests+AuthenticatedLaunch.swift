import Foundation
import XCTest

extension SideBarUITests {
    private static let authenticatedSessionCacheLock = NSLock()
    private static var authenticatedSessionCache: [String: UITestSeededSession] = [:]

    @MainActor
    func launchApp(with config: UITestLaunchConfig) -> XCUIApplication {
        let app = XCUIApplication()
        app.applyUITestLaunchEnvironment(
            credentials: config.credentials,
            backend: config.backend
        )
        app.launch()
        dismissSystemAlertsIfPresent(in: app, timeout: 4)
        return app
    }

    @MainActor
    func launchAuthenticatedApp(with config: UITestLaunchConfig) throws -> XCUIApplication {
        let session = try authenticatedSession(for: config)
        let app = XCUIApplication()
        app.applyUITestLaunchEnvironment(
            credentials: config.credentials,
            backend: config.backend
        )
        app.launchEnvironment[SideBarUITestConstants.uiTestAccessTokenKey] = session.accessToken
        app.launchEnvironment[SideBarUITestConstants.uiTestUserIdKey] = session.userId
        app.launch()
        dismissSystemAlertsIfPresent(in: app, timeout: 4)
        return app
    }

    @MainActor
    func launchLocallyAuthenticatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.applyUITestLaunchEnvironment(
            credentials: .localFixture,
            backend: .localFixture
        )
        app.launchEnvironment[SideBarUITestConstants.uiTestAccessTokenKey] = "local-ui-test-token"
        app.launchEnvironment[SideBarUITestConstants.uiTestUserIdKey] = "00000000-0000-4000-8000-000000000001"
        app.launch()
        dismissSystemAlertsIfPresent(in: app, timeout: 4)
        return app
    }

    private func authenticatedSession(
        for config: UITestLaunchConfig
    ) throws -> UITestSeededSession {
        let cacheKey = [
            config.backend.supabaseUrl,
            config.credentials.email
        ].joined(separator: "|")

        Self.authenticatedSessionCacheLock.lock()
        if let cached = Self.authenticatedSessionCache[cacheKey] {
            Self.authenticatedSessionCacheLock.unlock()
            return cached
        }
        Self.authenticatedSessionCacheLock.unlock()

        let session = try requestSeededSession(for: config)

        Self.authenticatedSessionCacheLock.lock()
        Self.authenticatedSessionCache[cacheKey] = session
        Self.authenticatedSessionCacheLock.unlock()
        return session
    }

    private func requestSeededSession(
        for config: UITestLaunchConfig
    ) throws -> UITestSeededSession {
        let endpoint = try XCTUnwrap(
            URL(string: "\(config.backend.supabaseUrl)/auth/v1/token?grant_type=password"),
            "Supabase auth endpoint URL could not be constructed."
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.backend.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.backend.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            SupabasePasswordGrantRequest(
                email: config.credentials.email,
                password: config.credentials.password
            )
        )

        let expectation = expectation(description: "Fetch seeded UI auth session")
        let state = SeededSessionRequestState()
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { expectation.fulfill() }

            if let error {
                state.complete(with: .failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                state.complete(with: .failure(SeededSessionRequestError.invalidResponse))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let payload = data.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? "<empty>"
                state.complete(with: .failure(
                    SeededSessionRequestError.httpFailure(
                        statusCode: httpResponse.statusCode,
                        payload: payload
                    )
                ))
                return
            }

            guard let data else {
                state.complete(with: .failure(SeededSessionRequestError.invalidResponse))
                return
            }

            do {
                let response = try JSONDecoder().decode(SupabasePasswordGrantResponse.self, from: data)
                state.complete(with: .success(UITestSeededSession(
                    accessToken: response.accessToken,
                    userId: response.user.id
                )))
            } catch {
                state.complete(with: .failure(error))
            }
        }.resume()

        wait(for: [expectation], timeout: 30)
        return try state.result.get()
    }
}

enum SideBarUITestConstants {
    static let uiTestEmailKey = "SIDEBAR_UI_TEST_EMAIL"
    static let uiTestPasswordKey = "SIDEBAR_UI_TEST_PASSWORD"
    static let uiTestSecretsFileKey = "SIDEBAR_UI_TEST_SECRETS_FILE"
    static let uiTestInMemoryAuthKey = "SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH"
    static let uiTestBootstrapAuthKey = "SIDEBAR_UI_TEST_BOOTSTRAP_AUTH"
    static let uiTestExposeChatScrollAnchorKey = "SIDEBAR_UI_TEST_EXPOSE_CHAT_SCROLL_ANCHOR"
    static let uiTestForceCompletedOnboardingKey = "SIDEBAR_UI_TEST_FORCE_COMPLETED_ONBOARDING"
    static let uiTestChatConversationTitleKey = "SIDEBAR_UI_TEST_CHAT_CONVERSATION_TITLE"
    static let uiTestApiBaseUrlKey = "SIDEBAR_UI_TEST_API_BASE_URL"
    static let uiTestSupabaseUrlKey = "SIDEBAR_UI_TEST_SUPABASE_URL"
    static let uiTestSupabaseAnonKey = "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY"
    static let uiTestAccessTokenKey = "SIDEBAR_UI_TEST_ACCESS_TOKEN"
    static let uiTestUserIdKey = "SIDEBAR_UI_TEST_USER_ID"
    static let runLiveUITestsKey = "SIDEBAR_RUN_LIVE_UI_TESTS"
    static let runExtendedLiveUITestsKey = "SIDEBAR_RUN_EXTENDED_LIVE_UI_TESTS"
}

struct UITestCredentials {
    let email: String
    let password: String

    static let localFixture = UITestCredentials(
        email: "local-ui@example.test",
        password: "local-ui-password"
    )
}

struct UITestBackendConfig {
    let apiBaseUrl: String
    let supabaseUrl: String
    let supabaseAnonKey: String

    static let localFixture = UITestBackendConfig(
        apiBaseUrl: "http://127.0.0.1:9/api/v1",
        supabaseUrl: "http://127.0.0.1:9",
        supabaseAnonKey: "local-ui-test-anon-key"
    )
}

struct UITestLaunchConfig {
    let credentials: UITestCredentials
    let backend: UITestBackendConfig
}

extension XCUIApplication {
    func applyUITestLaunchEnvironment(
        credentials: UITestCredentials,
        backend: UITestBackendConfig
    ) {
        launchEnvironment[SideBarUITestConstants.uiTestEmailKey] = credentials.email
        launchEnvironment[SideBarUITestConstants.uiTestPasswordKey] = credentials.password
        launchEnvironment["API_BASE_URL"] = backend.apiBaseUrl
        launchEnvironment["SUPABASE_URL"] = backend.supabaseUrl
        launchEnvironment["SUPABASE_ANON_KEY"] = backend.supabaseAnonKey
        launchEnvironment[SideBarUITestConstants.uiTestInMemoryAuthKey] = "1"
        launchEnvironment[SideBarUITestConstants.uiTestBootstrapAuthKey] = "1"
        launchEnvironment[SideBarUITestConstants.uiTestExposeChatScrollAnchorKey] = "1"
        launchEnvironment[SideBarUITestConstants.uiTestForceCompletedOnboardingKey] = "1"
    }
}

private struct UITestSeededSession {
    let accessToken: String
    let userId: String
}

private struct SupabasePasswordGrantRequest: Encodable {
    let email: String
    let password: String
}

private struct SupabasePasswordGrantResponse: Decodable {
    struct User: Decodable {
        let id: String
    }

    let accessToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case user
    }
}

private final class SeededSessionRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<UITestSeededSession, Error>?

    var result: Result<UITestSeededSession, Error> {
        lock.lock()
        defer { lock.unlock() }
        return storage ?? .failure(SeededSessionRequestError.missingResult)
    }

    func complete(with result: Result<UITestSeededSession, Error>) {
        lock.lock()
        storage = result
        lock.unlock()
    }
}

private enum SeededSessionRequestError: LocalizedError {
    case invalidResponse
    case httpFailure(statusCode: Int, payload: String)
    case missingResult

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Supabase auth bootstrap returned an invalid response."
        case .httpFailure(let statusCode, let payload):
            return "Supabase auth bootstrap failed with status \(statusCode): \(payload)"
        case .missingResult:
            return "Supabase auth bootstrap did not return a result."
        }
    }
}
