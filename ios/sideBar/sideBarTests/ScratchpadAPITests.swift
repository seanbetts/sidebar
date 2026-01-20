import XCTest
@testable import sideBar

private typealias URLProtocolMock = ScratchpadURLProtocolMock

final class ScratchpadAPITests: XCTestCase {
    override func tearDown() {
        ScratchpadURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testUpdatePostsThenFetches() async throws {
        let client = makeClient()
        let api = ScratchpadAPI(client: client)
        var requestCount = 0
        ScratchpadURLProtocolMock.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if requestCount == 1 {
                XCTAssertEqual(request.httpMethod, "POST")
                return (response, Data("{\"success\":true,\"id\":\"s1\"}".utf8))
            }
            let payload = "{\"id\":\"s1\",\"title\":\"Scratchpad\",\"content\":\"Hello\",\"updated_at\":null}"
            return (response, Data(payload.utf8))
        }

        let response = try await api.update(content: "Hello", mode: .replace)

        XCTAssertEqual(response.content, "Hello")
        XCTAssertEqual(requestCount, 2)
    }

    func testClearIssuesDelete() async throws {
        let client = makeClient()
        let api = ScratchpadAPI(client: client)
        ScratchpadURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.clear()
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScratchpadURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class ScratchpadURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ScratchpadURLProtocolMock.requestHandler else {
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
