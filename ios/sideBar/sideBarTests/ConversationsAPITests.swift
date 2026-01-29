import XCTest
import sideBarShared
@testable import sideBar

final class ConversationsAPITests: XCTestCase {
    override func tearDown() {
        ConversationsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testListDecodesResponse() async throws {
        let api = ConversationsAPI(client: makeClient())
        ConversationsURLProtocolMock.requestHandler = { request in
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
        ConversationsURLProtocolMock.requestHandler = { request in
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
        ConversationsURLProtocolMock.requestHandler = { request in
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
        ConversationsURLProtocolMock.requestHandler = { request in
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

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConversationsURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class ConversationsURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ConversationsURLProtocolMock.requestHandler else {
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
