import Foundation
import XCTest
import sideBarShared
@testable import sideBarWidgetsExtension

final class WidgetRefreshEnvironmentTests: XCTestCase {
    func testEnvironmentFailsWhenNoSharedAccessTokenExists() {
        let store = KeychainAuthStateStore(
            service: "WidgetRefreshEnvironmentTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )

        XCTAssertThrowsError(
            try WidgetAPIEnvironment(
                configLoader: { .fallbackForTesting() },
                keychain: store,
                authRefresher: StubWidgetAuthRefresher()
            )
        ) { error in
            XCTAssertEqual(error as? WidgetAPIEnvironmentError, .notAuthenticated)
        }
    }

    func testEnvironmentBuildsAPIClientFromEnvironmentConfig() throws {
        let store = KeychainAuthStateStore(
            service: "WidgetRefreshEnvironmentTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token-123")

        let environment = try WidgetAPIEnvironment(
            configLoader: {
                EnvironmentConfig(
                    apiBaseUrl: URL(string: "https://api.example.com/api/v1")!,
                    supabaseUrl: URL(string: "https://supabase.example.com")!,
                    supabaseAnonKey: "anon"
                )
            },
            keychain: store,
            authRefresher: StubWidgetAuthRefresher()
        )

        XCTAssertEqual(
            environment.apiClient.config.baseUrl.absoluteString,
            "https://api.example.com/api/v1"
        )
        XCTAssertEqual(environment.apiClient.config.accessTokenProvider(), "token-123")
    }

    func testEnvironmentRefreshHookUsesInjectedAuthRefresher() async throws {
        let store = KeychainAuthStateStore(
            service: "WidgetRefreshEnvironmentTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token-123")
        let refresher = StubWidgetAuthRefresher(result: true)

        let environment = try WidgetAPIEnvironment(
            configLoader: { .fallbackForTesting() },
            keychain: store,
            authRefresher: refresher
        )

        let refreshed = await environment.apiClient.config.refreshAuthIfNeeded?()

        XCTAssertEqual(refresher.callCount, 1)
        XCTAssertEqual(refresher.forcedRefreshArguments, [false])
        XCTAssertEqual(refreshed, true)
    }

    func testAuthRefresherFailureReturnsFalse() async throws {
        let store = KeychainAuthStateStore(
            service: "WidgetRefreshEnvironmentTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("token-123")
        let refresher = StubWidgetAuthRefresher(result: false)

        let environment = try WidgetAPIEnvironment(
            configLoader: { .fallbackForTesting() },
            keychain: store,
            authRefresher: refresher
        )

        let refreshed = await environment.ensureValidAccessToken(forceRefresh: true)

        XCTAssertEqual(refresher.callCount, 1)
        XCTAssertEqual(refresher.forcedRefreshArguments, [true])
        XCTAssertFalse(refreshed)
    }
}

private final class StubWidgetAuthRefresher: WidgetAuthRefreshing {
    let result: Bool
    private(set) var callCount = 0
    private(set) var forcedRefreshArguments: [Bool] = []

    init(result: Bool = true) {
        self.result = result
    }

    func ensureValidSession(forceRefresh: Bool) async -> Bool {
        callCount += 1
        forcedRefreshArguments.append(forceRefresh)
        return result
    }
}
