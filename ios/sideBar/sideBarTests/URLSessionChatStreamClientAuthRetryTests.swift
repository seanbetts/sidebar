import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class URLSessionChatStreamClientAuthRetryTests: XCTestCase {
    override func tearDown() {
        URLProtocolChatStreamAuthRetryMock.requestHandler = nil
        URLProtocolChatStreamAuthRetryMock.dataChunks = []
        URLProtocolChatStreamAuthRetryMock.failureAfterChunks = nil
        super.tearDown()
    }

    func testConnectRetriesUnauthorizedBeforeEmittingEvents() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let expectation = expectation(description: "retried events")
        expectation.expectedFulfillmentCount = 2
        let handler = RecordingAuthRetryHandler(expectation: expectation)
        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                tokenBox.token = "token-2"
                return true
            },
            session: session,
            parser: ChatStreamParser(),
            handler: handler
        )
        URLProtocolChatStreamAuthRetryMock.requestHandler = { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
                URLProtocolChatStreamAuthRetryMock.dataChunks = []
                return HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            URLProtocolChatStreamAuthRetryMock.dataChunks = [
                Data("event: token\ndata: {\"content\":\"Hello\"}\n\n".utf8),
                Data("event: complete\ndata: {}\n\n".utf8)
            ]
            return HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        try await client.connect(request: ChatStreamRequest(message: "Hello"))

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(handler.events.map(\.type), [.token, .complete])
        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    func testConnectDoesNotRefreshAfterEstablishedStreamDrops() async {
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let refreshCalls = Counter()
        let requestCount = Counter()
        let session = makeSession()
        let client = URLSessionChatStreamClient(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token" },
            refreshAuthIfNeeded: {
                refreshCalls.value += 1
                return true
            },
            session: session,
            parser: ChatStreamParser()
        )
        URLProtocolChatStreamAuthRetryMock.dataChunks = [
            Data("event: token\ndata: {\"content\":\"Hello\"}\n\n".utf8)
        ]
        URLProtocolChatStreamAuthRetryMock.failureAfterChunks = URLError(.networkConnectionLost)
        URLProtocolChatStreamAuthRetryMock.requestHandler = { request in
            requestCount.value += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        do {
            try await client.connect(request: ChatStreamRequest(message: "Hello"))
            XCTFail("Expected dropped stream error")
        } catch {
            // Expected failure after bytes were consumed.
        }

        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(refreshCalls.value, 0)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolChatStreamAuthRetryMock.self]
        return URLSession(configuration: configuration)
    }
}

private final class RecordingAuthRetryHandler: ChatStreamEventHandler {
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

private final class URLProtocolChatStreamAuthRetryMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> HTTPURLResponse)?
    static var dataChunks: [Data] = []
    static var failureAfterChunks: Error?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = URLProtocolChatStreamAuthRetryMock.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        do {
            let response = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in URLProtocolChatStreamAuthRetryMock.dataChunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            if let failure = URLProtocolChatStreamAuthRetryMock.failureAfterChunks {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
