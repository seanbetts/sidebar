import XCTest
import sideBarShared
@testable import sideBar

final class APIClientTests: XCTestCase {
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

    private static func waitForSignal(
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

    func testInjectsAuthorizationHeader() async throws {
        let token = "token-123"
        let client = makeClient(token: token)
        router.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("ping")
    }

    func testDecodesApiErrorDetail() async {
        let client = makeClient(token: "token-123")
        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Bad request\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("ping")
            XCTFail("Expected error")
        } catch let error as APIClientError {
            switch error {
            case .apiError(let message):
                XCTAssertEqual(message, "Bad request")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestDataReturnsPayload() async throws {
        let client = makeClient(token: "token-123")
        let expected = Data([0x01, 0x02, 0x03])
        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await client.requestData("binary")
        XCTAssertEqual(data, expected)
    }

    func testDefaultSessionDisablesDiskCache() {
        let session = APIClient.makeDefaultSession()
        let cache = session.configuration.urlCache
        XCTAssertEqual(cache?.diskCapacity, 0)
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

        let session = router.makeSession()
        let client = APIClient(config: config, session: session)

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

        let session = router.makeSession()
        let client = APIClient(config: config, session: session)

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
            // Expected
        }
        XCTAssertEqual(refreshCalls.value, 0)
        XCTAssertEqual(requestCount.value, 1)
    }

    func test401RetriesGetEvenWhenInitialAuthorizationHeaderIsMissing() async throws {
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

        let session = router.makeSession()
        let client = APIClient(config: config, session: session)

        router.setHandler { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("ping", method: "GET")
        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    func testConcurrent401RequestsCoalesceAuthRefresh() async throws {
        let tokenBox = SynchronizedTokenBox("token-1")
        let refreshCalls = SynchronizedCounter()
        let requestCount = SynchronizedCounter()
        let unauthorizedCount = SynchronizedCounter()
        let firstUnauthorized = DispatchSemaphore(value: 0)
        let releaseRefresh = DispatchSemaphore(value: 0)

        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { tokenBox.get() },
            refreshAuthIfNeeded: {
                _ = refreshCalls.increment()
                let released = await Self.waitForSignal(releaseRefresh, timeout: 0.25)
                XCTAssertEqual(
                    released,
                    .success,
                    "Expected a second unauthorized response before refresh completed"
                )
                tokenBox.set("token-2")
                return true
            }
        )

        let session = router.makeSession()
        let client = APIClient(config: config, session: session)

        router.setHandler { request in
            _ = requestCount.increment()
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer token-1" {
                let unauthorizedOrdinal = unauthorizedCount.increment()
                if unauthorizedOrdinal == 1 {
                    firstUnauthorized.signal()
                } else if unauthorizedOrdinal == 2 {
                    releaseRefresh.signal()
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
            }
            XCTAssertEqual(authHeader, "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        async let first: EmptyResponse = client.request("ping", method: "GET")
        let firstUnauthorizedResult = await Self.waitForSignal(firstUnauthorized, timeout: 0.25)
        XCTAssertEqual(
            firstUnauthorizedResult,
            .success,
            "Expected the first request to reach the unauthorized response"
        )
        async let second: EmptyResponse = client.request("pong", method: "GET")
        _ = try await (first, second)

        XCTAssertEqual(unauthorizedCount.value(), 2)
        XCTAssertEqual(refreshCalls.value(), 1)
        XCTAssertEqual(requestCount.value(), 4)
    }

    func testConcurrent401StressCoalescesRefreshAcrossRepeatedRuns() async throws {
        let tokenBox = SynchronizedTokenBox("wave-0-old")
        let refreshCalls = SynchronizedCounter()
        let requestCount = SynchronizedCounter()
        let unauthorizedCount = SynchronizedCounter()
        let nextRefreshedToken = SynchronizedStringBox("wave-0-new")

        let waves = 5
        let requestsPerWave = 10

        for wave in 0..<waves {
            let oldToken = "wave-\(wave)-old"
            let newToken = "wave-\(wave)-new"
            tokenBox.set(oldToken)
            nextRefreshedToken.set(newToken)
            let waveUnauthorizedCount = SynchronizedCounter()
            let releaseRefresh = DispatchSemaphore(value: 0)
            let router = ScopedURLProtocolRouter()
            defer { router.invalidate() }
            let config = APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { tokenBox.get() },
                refreshAuthIfNeeded: {
                    _ = refreshCalls.increment()
                    let released = await Self.waitForSignal(releaseRefresh, timeout: 0.25)
                    XCTAssertEqual(
                        released,
                        .success,
                        "Expected multiple unauthorized responses to coalesce refresh"
                    )
                    tokenBox.set(nextRefreshedToken.get())
                    return true
                }
            )
            let session = router.makeSession()
            let client = APIClient(config: config, session: session)

            router.setHandler { request in
                _ = requestCount.increment()
                let authHeader = request.value(forHTTPHeaderField: "Authorization")
                if authHeader == "Bearer \(oldToken)" {
                    _ = unauthorizedCount.increment()
                    let waveUnauthorizedOrdinal = waveUnauthorizedCount.increment()
                    if waveUnauthorizedOrdinal == 2 {
                        releaseRefresh.signal()
                    }
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
                }
                XCTAssertEqual(authHeader, "Bearer \(newToken)")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data("{}".utf8))
            }

            try await withThrowingTaskGroup(of: EmptyResponse.self) { group in
                for requestIndex in 0..<requestsPerWave {
                    group.addTask {
                        try await client.request("stress-\(wave)-\(requestIndex)", method: "GET")
                    }
                }
                for try await _ in group {}
            }

            XCTAssertEqual(
                refreshCalls.value(),
                wave + 1,
                "Each wave should coalesce to exactly one refresh"
            )
        }

        XCTAssertEqual(refreshCalls.value(), waves)
        XCTAssertGreaterThanOrEqual(unauthorizedCount.value(), waves)
        XCTAssertGreaterThanOrEqual(requestCount.value(), waves * requestsPerWave)
    }

    func testScopedRoutersRouteConcurrentClientsIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftClient = makeClient(token: "left-token", router: leftRouter)
        let rightClient = makeClient(token: "right-token", router: rightRouter)

        leftRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer left-token")
            XCTAssertEqual(request.url?.absoluteString.contains(leftRouter.baseURL.absoluteString), true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer right-token")
            XCTAssertEqual(request.url?.absoluteString.contains(rightRouter.baseURL.absoluteString), true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        async let left: EmptyResponse = leftClient.request("left")
        async let right: EmptyResponse = rightClient.request("right")
        _ = try await (left, right)
    }

    private func makeClient(token: String, router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { token }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }
}

private final class SynchronizedTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var currentToken: String

    init(_ token: String) {
        currentToken = token
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return currentToken
    }

    func set(_ token: String) {
        lock.lock()
        currentToken = token
        lock.unlock()
    }
}

private final class SynchronizedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class SynchronizedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String

    init(_ value: String) {
        self.value = value
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: String) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}
