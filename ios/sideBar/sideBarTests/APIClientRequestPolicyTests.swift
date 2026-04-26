import XCTest
import sideBarShared
@testable import sideBar

final class APIClientRequestPolicyTests: XCTestCase {
    private struct EmptyResponse: Decodable {}
    private struct MutationBody: Encodable {
        let value: String
    }

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

    func testFailedNotificationIncludesLifecycleSignalMetadata() async {
        let intent = RequestIntent(
            operation: "tasks.list",
            path: "tasks",
            method: .get,
            requestKind: .foregroundRead,
            authRequirement: .required,
            replaySafety: .safeToReplayAlways,
            timeoutClass: .standard
        )
        let client = makeClient(token: "token-123", requestIntent: intent)
        let signalExpectation = expectation(description: "Lifecycle failure signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            receivedSignal = notification.userInfo?["signal"] as? RequestLifecycleSignal
            if receivedSignal != nil {
                signalExpectation.fulfill()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Try again later\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("tasks")
            XCTFail("Expected request to fail")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.operation, intent.operation)
        XCTAssertEqual(receivedSignal?.requestKind, .foregroundRead)
        XCTAssertEqual(receivedSignal?.stage, .failed)
        XCTAssertEqual(receivedSignal?.errorCategory, .serverBusy)
    }

    func testSucceededNotificationIncludesLifecycleSignalMetadata() async throws {
        let intent = RequestIntent(
            operation: "tasks.list",
            path: "tasks",
            method: .get,
            requestKind: .foregroundRead,
            authRequirement: .required,
            replaySafety: .safeToReplayAlways,
            timeoutClass: .standard
        )
        let client = makeClient(token: "token-123", requestIntent: intent)
        let signalExpectation = expectation(description: "Lifecycle success signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestSucceeded,
            object: nil,
            queue: nil
        ) { notification in
            receivedSignal = notification.userInfo?["signal"] as? RequestLifecycleSignal
            if receivedSignal != nil {
                signalExpectation.fulfill()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("tasks")

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.operation, intent.operation)
        XCTAssertEqual(receivedSignal?.requestKind, .foregroundRead)
        XCTAssertEqual(receivedSignal?.stage, .succeeded)
        XCTAssertNil(receivedSignal?.errorCategory)
    }

    func test401DoesNotRetryPostWithoutInjectedIntent() async {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let client = APIClient(
            config: APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { tokenBox.token },
                refreshAuthIfNeeded: {
                    refreshCalls.value += 1
                    tokenBox.token = "token-2"
                    return true
                }
            ),
            session: router.makeSession()
        )

        router.setHandler { request in
            requestCount.value += 1
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            try await client.requestVoid("ping", method: "POST")
            XCTFail("Expected request to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(refreshCalls.value, 0)
        XCTAssertEqual(requestCount.value, 1)
    }

    func test401RetriesBodyBearingPatchWithoutInjectedIntent() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let client = APIClient(
            config: APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { tokenBox.token },
                refreshAuthIfNeeded: {
                    refreshCalls.value += 1
                    tokenBox.token = "token-2"
                    return true
                }
            ),
            session: router.makeSession()
        )

        router.setHandler { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await client.requestVoid(
            "ping",
            method: "PATCH",
            body: MutationBody(value: "updated")
        )

        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    func test401RetriesReplaySafePostWhenRequestPolicyAllowsRefresh() async throws {
        let intent = RequestIntent(
            operation: "files.upload",
            path: "files",
            method: .post,
            requestKind: .multipartUpload,
            authRequirement: .required,
            replaySafety: .safeToReplayBeforeBodyStarts,
            timeoutClass: .long
        )

        XCTAssertTrue(RequestExecutionPolicy.shouldAttemptAuthRefresh(for: intent))
        try await assertAuthRefreshRetry(for: intent)
    }

    func test401DoesNotRetryNonRepeatablePatchWhenRequestPolicyDisallowsRefresh() async {
        let intent = RequestIntent(
            operation: "files.upload",
            path: "files",
            method: .patch,
            requestKind: .multipartUpload,
            authRequirement: .required,
            replaySafety: .notReplaySafe,
            timeoutClass: .long
        )

        XCTAssertFalse(RequestExecutionPolicy.shouldAttemptAuthRefresh(for: intent))
        await assertNoAuthRefreshRetry(for: intent)
    }

    func test401DoesNotRetryWhenRefreshLeavesAuthorizationTokenUnchanged() async {
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let refreshCalls = Counter()
        let requestCount = Counter()
        let authRejectedCalls = Counter()
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { "token-1" },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return true
            },
            handleAuthRejected: {
                authRejectedCalls.value += 1
            }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("ping", method: "GET")
            XCTFail("Expected request to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(authRejectedCalls.value, 1)
    }

    private func assertAuthRefreshRetry(for intent: RequestIntent) async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let method = intent.method.rawValue
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            },
            requestIntentProvider: { _ in intent }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        if intent.method == .get {
            let _: EmptyResponse = try await client.request("ping", method: method)
        } else {
            try await client.requestVoid("ping", method: method)
        }

        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    private func assertNoAuthRefreshRetry(for intent: RequestIntent) async {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let method = intent.method.rawValue
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            },
            requestIntentProvider: { _ in intent }
        )
        let client = APIClient(config: config, session: router.makeSession())

        router.setHandler { request in
            requestCount.value += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
        }

        do {
            if intent.method == .get {
                let _: EmptyResponse = try await client.request("ping", method: method)
            } else {
                try await client.requestVoid("ping", method: method)
            }
            XCTFail("Expected error")
        } catch {
            // Expected.
        }

        XCTAssertEqual(refreshCalls.value, 0)
        XCTAssertEqual(requestCount.value, 1)
    }

    private func makeClient(
        token: String,
        requestIntent: RequestIntent
    ) -> APIClient {
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { token },
            requestIntentProvider: { _ in requestIntent }
        )
        return APIClient(config: config, session: router.makeSession())
    }
}
