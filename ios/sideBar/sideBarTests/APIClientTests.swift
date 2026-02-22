import XCTest
import sideBarShared
@testable import sideBar

final class APIClientTests: XCTestCase {
    private struct EmptyResponse: Decodable {}
    private static let protocolIsolationLock = NSLock()

    override func setUp() {
        super.setUp()
        Self.protocolIsolationLock.lock()
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        Self.protocolIsolationLock.unlock()
        super.tearDown()
    }

    func testInjectsAuthorizationHeader() async throws {
        let token = "token-123"
        let client = makeClient(token: token)
        URLProtocolMock.requestHandler = { request in
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
        URLProtocolMock.requestHandler = { request in
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
        URLProtocolMock.requestHandler = { request in
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

    func test401TriggersRefreshAndRetriesGetOnce() async throws {
        try await assertAuthRefreshRetry(for: "GET")
    }

    func test401TriggersRefreshAndRetriesPutOnce() async throws {
        try await assertAuthRefreshRetry(for: "PUT")
    }

    func test401TriggersRefreshAndRetriesDeleteOnce() async throws {
        try await assertAuthRefreshRetry(for: "DELETE")
    }

    private func assertAuthRefreshRetry(for method: String) async throws {
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

        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            }
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(config: config, session: session)

        URLProtocolMock.requestHandler = { request in
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

        if method == "GET" {
            let _: EmptyResponse = try await client.request("ping", method: method)
        } else {
            try await client.requestVoid("ping", method: method)
        }
        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    func test401DoesNotRetryForPost() async {
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

        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            }
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(config: config, session: session)

        URLProtocolMock.requestHandler = { request in
            requestCount.value += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
        }

        do {
            try await client.requestVoid("ping", method: "POST")
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
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            }
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(config: config, session: session)

        URLProtocolMock.requestHandler = { request in
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
        let unauthorizedBarrier = TwoRequestBarrier()

        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.get() },
            refreshAuthIfNeeded: {
                _ = refreshCalls.increment()
                tokenBox.set("token-2")
                return true
            }
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(config: config, session: session)

        URLProtocolMock.requestHandler = { request in
            _ = requestCount.increment()
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer token-1" {
                _ = unauthorizedCount.increment()
                unauthorizedBarrier.waitForPair()
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
            }
            XCTAssertEqual(authHeader, "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        async let first: EmptyResponse = client.request("ping", method: "GET")
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

        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.get() },
            refreshAuthIfNeeded: {
                _ = refreshCalls.increment()
                usleep(UInt32.random(in: 1_000...6_000))
                tokenBox.set(nextRefreshedToken.get())
                return true
            }
        )

        let waves = 5
        let requestsPerWave = 10

        for wave in 0..<waves {
            let oldToken = "wave-\(wave)-old"
            let newToken = "wave-\(wave)-new"
            tokenBox.set(oldToken)
            nextRefreshedToken.set(newToken)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [URLProtocolMock.self]
            let session = URLSession(configuration: configuration)
            let client = APIClient(config: config, session: session)

            URLProtocolMock.requestHandler = { request in
                _ = requestCount.increment()
                let authHeader = request.value(forHTTPHeaderField: "Authorization")
                if authHeader == "Bearer \(oldToken)" {
                    _ = unauthorizedCount.increment()
                    usleep(UInt32.random(in: 1_000...4_000))
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

    private func makeClient(token: String) -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { token }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
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

private final class TwoRequestBarrier: @unchecked Sendable {
    private let arrivalsLock = NSLock()
    private let condition = NSCondition()
    private var arrivals = 0

    func waitForPair() {
        arrivalsLock.lock()
        arrivals += 1
        let currentArrivals = arrivals
        arrivalsLock.unlock()

        condition.lock()
        defer { condition.unlock() }
        if currentArrivals < 2 {
            _ = condition.wait(until: Date().addingTimeInterval(1))
            return
        }
        condition.broadcast()
    }
}

final class URLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = URLProtocolMock.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
