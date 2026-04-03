import XCTest
@testable import sideBarShared
@testable import sideBar

extension APIClientTests {
    func testRequestVoidEncodesJSONBodyForPost() throws {
        struct MessageBody: Encodable {
            let message: String
        }

        let client = APIClient(
            config: APIClientConfig(
                baseUrl: URL(string: "https://example.com")!,
                accessTokenProvider: { "token-123" }
            )
        )

        let request = try client.buildRequest(
            "messages",
            method: "POST",
            body: MessageBody(message: "hello"),
            headers: [:],
            timeoutInterval: nil
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(payload["message"], "hello")
    }
}
