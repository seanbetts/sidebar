import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ConversationsAPITests: XCTestCase {
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

    func testParallelConversationClientsRouteIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftAPI = ConversationsAPI(client: makeClient(router: leftRouter))
        let rightAPI = ConversationsAPI(client: makeClient(router: rightRouter))

        leftRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("conversations/left") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {
              "id":"left",
              "title":"Left",
              "title_generated":false,
              "created_at":"2024-01-01",
              "updated_at":"2024-01-02",
              "message_count":0,
              "first_message":null,
              "is_archived":false,
              "messages":[]
            }
            """
            return (response, Data(payload.utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("conversations/right") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {
              "id":"right",
              "title":"Right",
              "title_generated":false,
              "created_at":"2024-01-01",
              "updated_at":"2024-01-02",
              "message_count":0,
              "first_message":null,
              "is_archived":false,
              "messages":[]
            }
            """
            return (response, Data(payload.utf8))
        }

        async let left = leftAPI.get(id: "left")
        async let right = rightAPI.get(id: "right")
        let results = try await (left, right)

        XCTAssertEqual(results.0.id, "left")
        XCTAssertEqual(results.1.id, "right")
    }

    func testListDecodesResponse() async throws {
        let api = ConversationsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            [{
              "id":"c1",
              "title":"Chat",
              "title_generated":false,
              "created_at":"2024-01-01",
              "updated_at":"2024-01-02",
              "message_count":1,
              "first_message":"Hello",
              "is_archived":false
            }]
            """
            return (response, Data(payload.utf8))
        }

        let conversations = try await api.list()

        XCTAssertEqual(conversations.first?.id, "c1")
        XCTAssertEqual(conversations.first?.title, "Chat")
    }

    func testGetDecodesDetail() async throws {
        let api = ConversationsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("conversations/c1") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "id":"c1",
              "title":"Chat",
              "title_generated":false,
              "created_at":"2024-01-01",
              "updated_at":"2024-01-02",
              "message_count":1,
              "first_message":"Hello",
              "is_archived":false,
              "messages":[]
            }
            """
            return (response, Data(payload.utf8))
        }

        let detail = try await api.get(id: "c1")

        XCTAssertEqual(detail.id, "c1")
        XCTAssertEqual(detail.messages.count, 0)
    }

    func testSearchUsesPostAndQuery() async throws {
        let api = ConversationsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("conversations/search") == true)
            XCTAssertTrue(urlString.contains("query=hello") == true)
            XCTAssertTrue(urlString.contains("limit=5") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("[]".utf8))
        }

        let results = try await api.search(query: "hello", limit: 5)

        XCTAssertTrue(results.isEmpty)
    }

    func testDeleteUsesDelete() async throws {
        let api = ConversationsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("conversations/c1") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "id":"c1",
              "title":"Chat",
              "title_generated":false,
              "created_at":"2024-01-01",
              "updated_at":"2024-01-02",
              "message_count":0,
              "first_message":null,
              "is_archived":true
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.delete(conversationId: "c1")

        XCTAssertEqual(response.id, "c1")
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
