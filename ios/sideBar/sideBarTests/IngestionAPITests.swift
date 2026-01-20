import XCTest
@testable import sideBar

final class IngestionAPITests: XCTestCase {
    override func tearDown() {
        IngestionURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testGetContentSetsRangeHeader() async throws {
        let api = IngestionAPI(client: makeClient())
        let expected = Data([0x01])
        IngestionURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-10")
            XCTAssertTrue(request.url?.absoluteString.contains("files/file-id/content") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await api.getContent(fileId: "file-id", kind: "text", range: "bytes=0-10")

        XCTAssertEqual(data, expected)
    }

    func testListDecodesResponse() async throws {
        let api = IngestionAPI(client: makeClient())
        IngestionURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"items":[{"file":{"id":"f1","filename_original":"doc.txt","path":null,"mime_original":"text/plain","size_bytes":1,"sha256":null,"pinned":null,"pinned_order":null,"category":null,"source_url":null,"source_metadata":null,"created_at":"2024-01-01"},"job":{"status":null,"stage":null,"error_code":null,"error_message":null,"user_message":null,"progress":null,"attempts":0,"updated_at":null},"recommended_viewer":null}]}
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.list()

        XCTAssertEqual(response.items.first?.file.id, "f1")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IngestionURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class IngestionURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = IngestionURLProtocolMock.requestHandler else {
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
