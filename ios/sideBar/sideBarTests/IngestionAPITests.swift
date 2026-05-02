import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionAPITests: XCTestCase {
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

    func testParallelUploadClientsRouteIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let (leftClient, leftSession) = makeClientAndSession(router: leftRouter, accessToken: "left-token")
        let (rightClient, rightSession) = makeClientAndSession(router: rightRouter, accessToken: "right-token")
        let leftAPI = IngestionAPI(client: leftClient, session: leftSession)
        let rightAPI = IngestionAPI(client: rightClient, session: rightSession)

        leftRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer left-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"file_id\":\"left-file\"}".utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer right-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"file_id\":\"right-file\"}".utf8))
        }

        async let left = leftAPI.ingestYouTube(url: "https://youtu.be/left")
        async let right = rightAPI.ingestYouTube(url: "https://youtu.be/right")
        let results = try await (left, right)

        XCTAssertEqual(results.0, "left-file")
        XCTAssertEqual(results.1, "right-file")
    }

    func testGetContentSetsRangeHeader() async throws {
        let api = IngestionAPI(client: makeClient())
        let expected = Data([0x01])
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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

        router.setHandler { request in
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

        router.setHandler { request in
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

    private func makeClientAndSession(
        router: ScopedURLProtocolRouter? = nil,
        accessToken: String? = "token-123"
    ) -> (APIClient, URLSession) {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { accessToken }
        )
        let session = resolvedRouter.makeSession()
        return (APIClient(config: config, session: session), session)
    }
}
