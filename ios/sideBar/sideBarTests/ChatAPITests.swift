import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatAPITests: XCTestCase {
    override func tearDown() {
        ChatURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testGenerateTitlePostsConversationId() async throws {
        let api = ChatAPI(client: makeClient())
        ChatURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["conversation_id"] as? String, "c1")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = "{\"title\":\"Hello\",\"fallback\":false}"
            return (response, Data(payload.utf8))
        }

        let response = try await api.generateTitle(conversationId: "c1")

        XCTAssertEqual(response.title, "Hello")
        XCTAssertFalse(response.fallback)
    }

    func testResolveToolConfirmationDecodesActionResponseWithoutRootSuccess() async throws {
        let api = ChatAPI(client: makeClient())
        ChatURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/chat/tool-confirmations/confirm-1")
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["decision"] as? String, "accept")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "confirmation_id": "confirm-1",
              "decision": "accept",
              "tool_result": {
                "type": "tool_result",
                "id": "tool-1",
                "name": "Delete Note",
                "result": {"success": true, "summary": "Deleted note"},
                "status": "success",
                "skill_id": "notes",
                "icon_key": "notes"
              },
              "events": [
                {
                  "type": "tool_confirmation_resolved",
                  "data": {
                    "confirmation_id": "confirm-1",
                    "tool_call_id": "tool-1",
                    "decision": "accept"
                  }
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.resolveToolConfirmation(
            confirmationId: "confirm-1",
            decision: .accept
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.toolResult?.type, "tool_result")
        let toolPayload = response.toolResult?.data?.value as? [String: Any]
        XCTAssertEqual(toolPayload?["id"] as? String, "tool-1")
        XCTAssertEqual(toolPayload?["status"] as? String, "success")
        XCTAssertEqual(response.events.first?.type, "tool_confirmation_resolved")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token-123" }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class ChatURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ChatURLProtocolMock.requestHandler else {
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
