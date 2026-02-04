import XCTest
import sideBarShared
@testable import sideBar

final class APIClientTests: XCTestCase {
    private struct EmptyResponse: Decodable {}

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
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

        let _: EmptyResponse = try await client.request("ping", method: "GET")
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
