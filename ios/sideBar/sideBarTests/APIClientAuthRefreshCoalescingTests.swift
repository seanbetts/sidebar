import XCTest
import sideBarShared
@testable import sideBar

final class APIClientAuthRefreshCoalescingTests: XCTestCase {
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
        let client = APIClient(config: config, session: router.makeSession())

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
            let waveRouter = ScopedURLProtocolRouter()
            defer { waveRouter.invalidate() }

            let config = APIClientConfig(
                baseUrl: waveRouter.baseURL,
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
            let client = APIClient(config: config, session: waveRouter.makeSession())

            waveRouter.setHandler { request in
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
