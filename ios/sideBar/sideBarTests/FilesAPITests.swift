import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class FilesAPITests: XCTestCase {
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

    func testDownloadBuildsEncodedPath() async throws {
        let api = FilesAPI(client: makeClient())
        let expected = Data([0x01, 0x02])
        router.setHandler { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(url.path.contains("files/download"))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(queryItems["basePath"], "docs")
            XCTAssertEqual(queryItems["path"], "folder/file.txt")
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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

    func testParallelFileClientsRouteIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftAPI = FilesAPI(client: makeClient(router: leftRouter))
        let rightAPI = FilesAPI(client: makeClient(router: rightRouter))

        let expectedLeft = Data([0x01])
        let expectedRight = Data([0x02])

        leftRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("basePath=left") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expectedLeft)
        }
        rightRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("basePath=right") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expectedRight)
        }

        async let left = leftAPI.download(basePath: "left", path: "file.txt")
        async let right = rightAPI.download(basePath: "right", path: "file.txt")
        let results = try await (left, right)

        XCTAssertEqual(results.0, expectedLeft)
        XCTAssertEqual(results.1, expectedRight)
    }

    private func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { "token-123" }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }
}
