import XCTest
import sideBarShared
@testable import sideBar

final class APIClientAuthPreflightTests: XCTestCase {
    private struct EmptyResponse: Decodable {}

    private var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testRequiredRequestRefreshesBeforeFirstNetworkAttemptWhenTokenMissing() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String?
            init(_ token: String?) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox(nil)
        let refreshCalls = Counter()
        let requestCount = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("ping", method: "GET")
        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 1)
    }

    func testRequiredRequestWithoutTokenAfterRefreshFailsBeforeNetwork() async {
        final class TokenBox: @unchecked Sendable {
            var token: String?
            init(_ token: String?) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox(nil)
        let refreshCalls = Counter()
        let requestCount = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return false
            }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("ping", method: "GET")
            XCTFail("Expected request to fail before transport")
        } catch APIClientError.missingToken {
            // Expected.
        } catch {
            XCTFail("Expected missingToken, got \(error)")
        }

        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 0)
    }

    func testFixedAuthorizationRequestNeverUsesOrRefreshesCurrentSessionToken() async {
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let refreshCalls = Counter()
        let requestCount = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { "account-b-token" },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return true
            }
        )
        let client = APIClient(config: config, session: router.makeSession())
        router.setHandler { request in
            requestCount.value += 1
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer account-a-token"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.requestWithFixedAuthorization(
                "tasks/sync",
                method: "POST",
                authorizationToken: "account-a-token"
            )
            XCTFail("Expected the rejected fixed-token request to fail")
        } catch {
            // Expected: fixed-token requests do not refresh or retry with another account.
        }

        XCTAssertEqual(refreshCalls.value, 0)
        XCTAssertEqual(requestCount.value, 1)
    }

    func testWeatherRequestDoesNotAttachAuthorizationOrRefreshAuth() async throws {
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let refreshCalls = Counter()
        let requestCount = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { "stale-token" },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return false
            }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("weather?lat=1&lon=2", method: "GET")
        XCTAssertEqual(refreshCalls.value, 0)
        XCTAssertEqual(requestCount.value, 1)
    }

    func testPrebuiltProtectedRequestDropsStaleAuthorizationWhenTokenBecomesUnavailable() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String?
            init(_ token: String?) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("stale-token")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return false
            }
        )
        let client = APIClient(config: config, session: router.makeSession())
        let request = try client.buildRequest("tasks/lists/today", method: .get)
        let intent = RequestIntent(
            operation: "get.tasks.lists.today",
            path: "tasks/lists/today",
            method: .get,
            requestKind: .foregroundRead,
            authRequirement: .required,
            replaySafety: .safeToReplayAlways,
            timeoutClass: .standard
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer stale-token")
        tokenBox.token = nil

        router.setHandler { request in
            requestCount.value += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await client.execute(request, intent: intent)
            XCTFail("Expected protected request to fail before transport")
        } catch APIClientError.missingToken {
            // Expected.
        } catch {
            XCTFail("Expected missingToken, got \(error)")
        }

        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 0)
    }
}
