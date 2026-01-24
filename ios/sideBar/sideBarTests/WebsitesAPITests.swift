import XCTest
@testable import sideBar

final class WebsitesAPITests: XCTestCase {
    override func tearDown() {
        WebsitesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testSaveUsesPostAndDecodesResponse() async throws {
        let api = WebsitesAPI(client: makeClient())
        WebsitesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("websites/save") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"success":true,"data":{"id":"w1","title":"Site","url":"https://example.com","domain":"example.com"}}
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.save(url: "https://example.com")

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?.id, "w1")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebsitesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class WebsitesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = WebsitesURLProtocolMock.requestHandler else {
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
