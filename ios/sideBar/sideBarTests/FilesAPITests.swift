import XCTest
import sideBarShared
@testable import sideBar

final class FilesAPITests: XCTestCase {
    override func tearDown() {
        FilesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testDownloadBuildsEncodedPath() async throws {
        let api = FilesAPI(client: makeClient())
        let expected = Data([0x01, 0x02])
        FilesURLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("files/download"))
            XCTAssertTrue(urlString.contains("basePath=docs"))
            XCTAssertTrue(urlString.contains("path=folder%2Ffile.txt"))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await api.download(basePath: "docs", path: "folder/file.txt")

        XCTAssertEqual(data, expected)
    }

    func testSearchUsesPostAndQueryParams() async throws {
        let api = FilesAPI(client: makeClient())
        FilesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("files/search") == true)
            XCTAssertTrue(urlString.contains("query=hello") == true)
            XCTAssertTrue(urlString.contains("basePath=docs") == true)
            XCTAssertTrue(urlString.contains("limit=2") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = "{\"items\":[]}"
            return (response, Data(payload.utf8))
        }

        let items = try await api.search(query: "hello", basePath: "docs", limit: 2)

        XCTAssertTrue(items.isEmpty)
    }

    func testCreateFolderPostsBody() async throws {
        let api = FilesAPI(client: makeClient())
        FilesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/folder") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["basePath"] as? String, "docs")
            XCTAssertEqual(body?["path"] as? String, "New")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.createFolder(basePath: "docs", path: "New")
    }

    func testRenamePostsBody() async throws {
        let api = FilesAPI(client: makeClient())
        FilesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/rename") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["oldPath"] as? String, "/old.txt")
            XCTAssertEqual(body?["newName"] as? String, "new.txt")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.rename(basePath: "docs", oldPath: "/old.txt", newName: "new.txt")
    }

    func testMovePostsBody() async throws {
        let api = FilesAPI(client: makeClient())
        FilesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/move") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["path"] as? String, "/old.txt")
            XCTAssertEqual(body?["destination"] as? String, "/new")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.move(basePath: "docs", path: "/old.txt", destination: "/new")
    }

    func testDeletePostsBody() async throws {
        let api = FilesAPI(client: makeClient())
        FilesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/delete") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["path"] as? String, "/old.txt")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.delete(basePath: "docs", path: "/old.txt")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FilesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class FilesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = FilesURLProtocolMock.requestHandler else {
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
