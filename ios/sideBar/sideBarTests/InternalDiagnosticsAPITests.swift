import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class InternalDiagnosticsAPITests: XCTestCase {
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

    func testGetSnapshotDecodesDiagnosticsPayload() async throws {
        let api = InternalDiagnosticsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("notification-diagnostics") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "can_access_internal_diagnostics": true,
              "account_summary": {
                "user_id": "user-123"
              },
              "installations": [
                {
                  "installation_id": "install-123",
                  "user_id": "user-123",
                  "platform": "ios",
                  "token_suffix": "abcdef",
                  "is_foreground": true
                }
              ],
              "recent_delivery": [
                {
                  "created_at": "2026-04-19T10:00:00Z",
                  "user_id": "user-123",
                  "installation_id": "install-123",
                  "notification_kind": "reminder",
                  "platform": "ios",
                  "token_suffix": "abcdef",
                  "delivery_result": "sent"
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let snapshot = try await api.getSnapshot()

        XCTAssertTrue(snapshot.canAccessInternalDiagnostics)
        XCTAssertEqual(snapshot.accountSummary?.userId, "user-123")
        XCTAssertEqual(snapshot.installations.count, 1)
        XCTAssertEqual(snapshot.recentDelivery.count, 1)
        XCTAssertEqual(snapshot.installations.first?.tokenSuffix, "abcdef")
    }

    func testSendTestPushPostsInstallationId() async throws {
        let api = InternalDiagnosticsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("installations/install-123/test-push") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"installation_id":"install-123","accepted":true}"#.utf8))
        }

        let response = try await api.sendTestPush(installationId: "install-123")

        XCTAssertEqual(response.installationId, "install-123")
        XCTAssertTrue(response.accepted)
    }

    private func makeClient() -> APIClient {
        APIClient(
            config: APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { nil }
            ),
            session: router.makeSession()
        )
    }
}
