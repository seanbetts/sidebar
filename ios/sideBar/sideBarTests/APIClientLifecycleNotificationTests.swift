import XCTest
import sideBarShared
@testable import sideBar

final class APIClientLifecycleNotificationTests: XCTestCase {
    private struct EmptyResponse: Decodable {}

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

    func testFailedNotificationIncludesLifecycleSignalMetadata() async {
        let intent = makeForegroundReadIntent()
        let client = makeClient(token: "token-123", requestIntent: intent)
        let signalExpectation = expectation(description: "Lifecycle failure signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            receivedSignal = notification.userInfo?["signal"] as? RequestLifecycleSignal
            if receivedSignal != nil {
                signalExpectation.fulfill()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Try again later\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("tasks")
            XCTFail("Expected request to fail")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.operation, intent.operation)
        XCTAssertEqual(receivedSignal?.requestKind, .foregroundRead)
        XCTAssertEqual(receivedSignal?.stage, .failed)
        XCTAssertEqual(receivedSignal?.errorCategory, .serverBusy)
    }

    func testSucceededNotificationIncludesLifecycleSignalMetadata() async throws {
        let intent = makeForegroundReadIntent()
        let client = makeClient(token: "token-123", requestIntent: intent)
        let signalExpectation = expectation(description: "Lifecycle success signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestSucceeded,
            object: nil,
            queue: nil
        ) { notification in
            receivedSignal = notification.userInfo?["signal"] as? RequestLifecycleSignal
            if receivedSignal != nil {
                signalExpectation.fulfill()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("tasks")

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.operation, intent.operation)
        XCTAssertEqual(receivedSignal?.requestKind, .foregroundRead)
        XCTAssertEqual(receivedSignal?.stage, .succeeded)
        XCTAssertNil(receivedSignal?.errorCategory)
    }

    private func makeForegroundReadIntent() -> RequestIntent {
        RequestIntent(
            operation: "tasks.list",
            path: "tasks",
            method: .get,
            requestKind: .foregroundRead,
            authRequirement: .required,
            replaySafety: .safeToReplayAlways,
            timeoutClass: .standard
        )
    }

    private func makeClient(
        token: String,
        requestIntent: RequestIntent
    ) -> APIClient {
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { token },
            requestIntentProvider: { _ in requestIntent }
        )
        return APIClient(config: config, session: router.makeSession())
    }
}
