import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class PasswordResetAPITests: XCTestCase {
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

    func testRequestPasswordResetPostsEmailPayloadToResetEndpoint() async throws {
        let api = PasswordResetAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/auth/password-reset/request") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(request.httpBodyData())
            let payload = try JSONDecoder().decode(PasswordResetRequestPayload.self, from: body)
            XCTAssertEqual(payload.email, "person@example.com")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"status":"accepted"}"#.utf8))
        }

        try await api.requestPasswordReset(email: "person@example.com")
    }

    private func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { nil }
        )
        return APIClient(config: config, session: resolvedRouter.makeSession())
    }
}

private struct PasswordResetRequestPayload: Decodable {
    let email: String
}
