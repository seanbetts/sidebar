import XCTest
@testable import sideBar

final class MemoriesAPITests: XCTestCase {
    override func tearDown() {
        MemoriesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testListDecodesResponse() async throws {
        let api = MemoriesAPI(client: makeClient())
        MemoriesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            [{"id":"m1","path":"/memories/one.md","content":"Hi","created_at":"2024-01-01","updated_at":"2024-01-02"}]
            """
            return (response, Data(payload.utf8))
        }

        let memories = try await api.list()

        XCTAssertEqual(memories.first?.id, "m1")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MemoriesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class MemoriesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MemoriesURLProtocolMock.requestHandler else {
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
