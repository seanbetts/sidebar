import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class URLSessionChatStreamClientTests: XCTestCase {
    private static let protocolIsolationLock = NSLock()

    override func setUp() {
        super.setUp()
        Self.protocolIsolationLock.lock()
    }

    override func tearDown() {
        URLProtocolStreamingMock.requestHandler = nil
        URLProtocolStreamingMock.dataChunks = []
        URLProtocolStreamingMock.statusCode = 200
        URLProtocolStreamingMock.resetLoadTracking()
        Self.protocolIsolationLock.unlock()
        super.tearDown()
    }

    func testConnectStreamsEvents() async throws {
        let expectation = expectation(description: "events")
        expectation.expectedFulfillmentCount = 2
        let handler = RecordingHandler(expectation: expectation)
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token" },
            session: session,
            parser: ChatStreamParser(),
            handler: handler
        )
        let event1 = "event: token\ndata: {\"text\":\"hi\"}\n\n"
        let event2 = "event: complete\ndata: {}\n\n"
        URLProtocolStreamingMock.dataChunks = [Data(event1.utf8), Data(event2.utf8)]
        URLProtocolStreamingMock.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(request.httpMethod, "POST")
            return HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        try await client.connect(request: ChatStreamRequest(message: "Hello"))

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(handler.events.count, 2)
        XCTAssertEqual(handler.events.first?.type, .token)
    }

    func testConnectDeliversBufferedEventsBeforeReturning() async throws {
        let expectation = expectation(description: "events")
        expectation.expectedFulfillmentCount = 2
        let handler = RecordingHandler(expectation: expectation)
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token" },
            session: session,
            parser: ChatStreamParser(),
            handler: handler
        )
        URLProtocolStreamingMock.dataChunks = [
            Data("event: token\ndata: {\"content\":\"Hello\"}\n\n".utf8),
            Data("event: complete\ndata: {}\n\n".utf8)
        ]
        URLProtocolStreamingMock.requestHandler = { request in
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        try await client.connect(request: ChatStreamRequest(message: "Hello"))

        XCTAssertEqual(handler.events.map(\.type), [.token, .complete])
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testConnectThrowsOnNon200() async {
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil },
            session: session
        )
        URLProtocolStreamingMock.statusCode = 500
        URLProtocolStreamingMock.requestHandler = { request in
            HTTPURLResponse(
                url: request.url!,
                statusCode: URLProtocolStreamingMock.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        do {
            try await client.connect(request: ChatStreamRequest(message: "Hello"))
            XCTFail("Expected error")
        } catch let error as APIClientError {
            switch error {
            case .requestFailed(let status):
                XCTAssertEqual(status, 500)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectHandlesNon200WithErrorEnvelope() async {
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil },
            session: session
        )
        URLProtocolStreamingMock.statusCode = 400
        URLProtocolStreamingMock.dataChunks = [
            Data("{\"error\":{\"message\":\"Message context is too large.\"}}".utf8)
        ]
        URLProtocolStreamingMock.requestHandler = { request in
            HTTPURLResponse(
                url: request.url!,
                statusCode: URLProtocolStreamingMock.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        do {
            try await client.connect(request: ChatStreamRequest(message: "Hello"))
            XCTFail("Expected error")
        } catch let error as APIClientError {
            switch error {
            case .apiError(let message):
                XCTAssertEqual(message, "Message context is too large.")
            case .requestFailed(let status):
                // URLProtocol + URLSession.AsyncBytes can surface empty body data on non-2xx responses.
                // In that case, the client should still expose the HTTP status fallback.
                XCTAssertEqual(status, 400)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectEmitsFailureSignalClassifiedBeforeReturningChatError() async {
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil },
            session: session
        )
        let signalExpectation = expectation(description: "Chat stream failure signal")
        var receivedSignal: RequestLifecycleSignal?
        var receivedSignalCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "chat.stream" else {
                return
            }
            receivedSignalCount += 1
            receivedSignal = signal
            signalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        URLProtocolStreamingMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            throw URLError(.cannotConnectToHost)
        }

        do {
            try await client.connect(request: ChatStreamRequest(message: "Hello"))
            XCTFail("Expected error")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(receivedSignalCount, 1)
        XCTAssertEqual(receivedSignal?.requestKind, .sseStream)
        XCTAssertEqual(receivedSignal?.errorCategory, .serverUnreachable)
    }

    func testDefaultSessionDoesNotUseSharedSingleton() {
        XCTAssertFalse(URLSessionChatStreamClient.defaultSession() === URLSession.shared)
    }

    // MARK: - Concurrency regression (Phase 2.5)

    func testDisconnectDuringConnectDoesNotCrash() async throws {
        URLProtocolStreamingMock.dataChunks = (0..<100).map { _ in
            Data("event: token\ndata: {\"text\":\"hi\"}\n\n".utf8)
        }
        URLProtocolStreamingMock.requestHandler = { request in
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        let initialLoadCount = URLProtocolStreamingMock.loadStartCount
        let connectTask = Task {
            try? await client.connect(request: ChatStreamRequest(message: "Hello"))
        }
        try await waitForLoadStart(after: initialLoadCount)
        client.disconnect()

        await connectTask.value
        session.invalidateAndCancel()
        XCTAssertTrue(URLProtocolStreamingMock.waitForIdle(timeout: 1.0))
    }

    func testRapidConnectDisconnectCyclesDoNotCrash() async throws {
        URLProtocolStreamingMock.dataChunks = [
            Data("event: token\ndata: {\"text\":\"hi\"}\n\n".utf8)
        ]
        URLProtocolStreamingMock.requestHandler = { request in
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token" },
            session: session
        )

        for _ in 0..<10 {
            let initialLoadCount = URLProtocolStreamingMock.loadStartCount
            let task = Task {
                try? await client.connect(request: ChatStreamRequest(message: "Hello"))
            }
            try await waitForLoadStart(after: initialLoadCount)
            client.disconnect()
            await task.value
        }

        session.invalidateAndCancel()
        XCTAssertTrue(URLProtocolStreamingMock.waitForIdle(timeout: 1.0))
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStreamingMock.self]
        return URLSession(configuration: configuration)
    }

    private func waitForLoadStart(after initialCount: Int) async throws {
        try await waitUntil(timeoutSeconds: 1.0) {
            URLProtocolStreamingMock.loadStartCount > initialCount
        }
    }
}

private final class RecordingHandler: ChatStreamEventHandler {
    private let expectation: XCTestExpectation
    private let lock = NSLock()
    private(set) var events: [ChatStreamEvent] = []

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func handle(event: ChatStreamEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
        expectation.fulfill()
    }
}

private final class URLProtocolStreamingMock: URLProtocol {
    private static let stateCondition = NSCondition()
    private static var activeLoads = 0
    private static var startedLoads = 0
    static var requestHandler: ((URLRequest) throws -> HTTPURLResponse)?
    static var dataChunks: [Data] = []
    static var statusCode: Int = 200

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    static var loadStartCount: Int {
        stateCondition.lock()
        defer { stateCondition.unlock() }
        return startedLoads
    }

    static func waitForIdle(timeout: TimeInterval) -> Bool {
        stateCondition.lock()
        defer { stateCondition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while activeLoads > 0 {
            if !stateCondition.wait(until: deadline) {
                return false
            }
        }
        return true
    }

    static func resetLoadTracking() {
        stateCondition.lock()
        activeLoads = 0
        startedLoads = 0
        stateCondition.broadcast()
        stateCondition.unlock()
    }

    override func startLoading() {
        Self.beginLoad()
        defer { Self.endLoad() }

        guard let handler = URLProtocolStreamingMock.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        do {
            let response = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in URLProtocolStreamingMock.dataChunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }

    private static func beginLoad() {
        stateCondition.lock()
        activeLoads += 1
        startedLoads += 1
        stateCondition.broadcast()
        stateCondition.unlock()
    }

    private static func endLoad() {
        stateCondition.lock()
        activeLoads = max(0, activeLoads - 1)
        if activeLoads == 0 {
            stateCondition.broadcast()
        }
        stateCondition.unlock()
    }
}

private func waitUntil(
    timeoutSeconds: TimeInterval,
    condition: @escaping () -> Bool
) async throws {
    let timeout = Date().addingTimeInterval(timeoutSeconds)
    while Date() < timeout {
        if condition() {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for condition")
}
