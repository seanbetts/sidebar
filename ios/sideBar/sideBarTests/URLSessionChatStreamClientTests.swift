import Foundation
import XCTest
@testable import sideBar

final class URLSessionChatStreamClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStreamingMock.requestHandler = nil
        URLProtocolStreamingMock.dataChunks = []
        URLProtocolStreamingMock.statusCode = 200
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

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStreamingMock.self]
        return URLSession(configuration: configuration)
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
    static var requestHandler: ((URLRequest) throws -> HTTPURLResponse)?
    static var dataChunks: [Data] = []
    static var statusCode: Int = 200

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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
}
