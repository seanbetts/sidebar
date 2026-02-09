import XCTest
import sideBarShared
@testable import sideBar

@MainActor
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
            {
              "items": [
                {
                  "file": {
                    "id": "f1",
                    "filename_original": "doc.txt",
                    "path": null,
                    "mime_original": "text/plain",
                    "size_bytes": 1,
                    "sha256": null,
                    "pinned": null,
                    "pinned_order": null,
                    "category": null,
                    "source_url": null,
                    "source_metadata": null,
                    "created_at": "2024-01-01"
                  },
                  "job": {
                    "status": null,
                    "stage": null,
                    "error_code": null,
                    "error_message": null,
                    "user_message": null,
                    "progress": null,
                    "attempts": 0,
                    "updated_at": null
                  },
                  "recommended_viewer": null
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.list()

        XCTAssertEqual(response.items.first?.file.id, "f1")
    }

    func testIngestYouTubePostsUrl() async throws {
        let api = IngestionAPI(client: makeClient())
        IngestionURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/youtube") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["url"] as? String, "https://youtu.be/123")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = "{\"file_id\":\"f9\"}"
            return (response, Data(payload.utf8))
        }

        let fileId = try await api.ingestYouTube(url: "https://youtu.be/123")

        XCTAssertEqual(fileId, "f9")
    }

    func testUploadFromFileUsesMultipartBodyAndAuthHeader() async throws {
        let (client, session) = makeClientAndSession(accessToken: "token-abc")
        let api = IngestionAPI(client: client, session: session)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingestion-upload-test-\(UUID().uuidString).txt")
        try Data("hello upload".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        IngestionURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-abc")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(String(bytes: bodyData, encoding: .utf8))
            XCTAssertTrue(body.contains("name=\"folder\""))
            XCTAssertTrue(body.contains("\r\nchat\r\n"))
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"hello.txt\""))
            XCTAssertTrue(body.contains("hello upload"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"file_id\":\"file-123\"}".utf8))
        }

        let fileId = try await api.upload(
            fileURL: tempURL,
            filename: "hello.txt",
            mimeType: "text/plain",
            folder: "chat"
        )

        XCTAssertEqual(fileId, "file-123")
    }

    func testUploadFromDataUsesMultipartBody() async throws {
        let (client, session) = makeClientAndSession()
        let api = IngestionAPI(client: client, session: session)

        IngestionURLProtocolMock.requestHandler = { request in
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(String(bytes: bodyData, encoding: .utf8))
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"data.txt\""))
            XCTAssertTrue(body.contains("payload-data"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"file_id\":\"file-data\"}".utf8))
        }

        let fileId = try await api.upload(
            fileData: Data("payload-data".utf8),
            filename: "data.txt",
            mimeType: "text/plain",
            folder: "docs"
        )

        XCTAssertEqual(fileId, "file-data")
    }

    private func makeClient() -> APIClient {
        makeClientAndSession().0
    }

    private func makeClientAndSession(accessToken: String? = nil) -> (APIClient, URLSession) {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { accessToken }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IngestionURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return (APIClient(config: config, session: session), session)
    }
}

final class IngestionURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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
