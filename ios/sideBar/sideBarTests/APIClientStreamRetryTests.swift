import XCTest
import sideBarShared
@testable import sideBar

final class APIClientStreamRetryTests: XCTestCase {
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

    func testExecuteStreamRetriesUnauthorizedBeforeConsumingStreamBytes() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String
            init(_ token: String) { self.token = token }
        }
        final class Counter: @unchecked Sendable {
            var value: Int = 0
        }

        let tokenBox = TokenBox("token-1")
        let refreshCalls = Counter()
        let requestCount = Counter()
        let intent = RequestIntent(
            operation: "chat.stream",
            path: "chat/stream",
            method: .post,
            requestKind: .sseStream,
            authRequirement: .required,
            replaySafety: .notReplaySafe,
            timeoutClass: .long
        )
        let client = APIClient(
            config: APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { tokenBox.token },
                refreshAuthIfNeeded: {
                    refreshCalls.value += 1
                    tokenBox.token = "token-2"
                    return true
                }
            ),
            session: router.makeSession()
        )
        var request = try client.buildRequest(
            intent.path,
            method: intent.method,
            headers: ["Accept": "text/event-stream"]
        )
        request.httpBody = Data("{\"message\":\"Hello\"}".utf8)

        router.setHandler { request in
            requestCount.value += 1
            if requestCount.value == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("event: complete\ndata: {}\n\n".utf8))
        }

        let (bytes, response) = try await client.executeStream(request, intent: intent)
        let data = try await collectStreamData(bytes)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "event: complete\ndata: {}\n\n")
        XCTAssertEqual(refreshCalls.value, 1)
        XCTAssertEqual(requestCount.value, 2)
    }

    private func collectStreamData(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}
