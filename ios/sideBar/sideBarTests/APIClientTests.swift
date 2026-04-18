import XCTest
import sideBarShared
@testable import sideBar

final class APIClientTests: XCTestCase {
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

    func testInjectsAuthorizationHeader() async throws {
        let token = "token-123"
        let client = makeClient(token: token)
        router.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let _: EmptyResponse = try await client.request("ping")
    }

    func testDecodesApiErrorDetail() async {
        let client = makeClient(token: "token-123")
        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Bad request\"}".utf8))
        }

        do {
            let _: EmptyResponse = try await client.request("ping")
            XCTFail("Expected error")
        } catch let error as APIClientError {
            switch error {
            case .apiError(let message):
                XCTAssertEqual(message, "Bad request")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestDataReturnsPayload() async throws {
        let client = makeClient(token: "token-123")
        let expected = Data([0x01, 0x02, 0x03])
        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await client.requestData("binary")
        XCTAssertEqual(data, expected)
    }

    func testDefaultSessionDisablesDiskCache() {
        let session = APIClient.makeDefaultSession()
        let cache = session.configuration.urlCache
        XCTAssertEqual(cache?.diskCapacity, 0)
    }

    func testScopedRoutersRouteConcurrentClientsIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftClient = makeClient(token: "left-token", router: leftRouter)
        let rightClient = makeClient(token: "right-token", router: rightRouter)

        leftRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer left-token")
            XCTAssertEqual(request.url?.absoluteString.contains(leftRouter.baseURL.absoluteString), true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer right-token")
            XCTAssertEqual(request.url?.absoluteString.contains(rightRouter.baseURL.absoluteString), true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        async let left: EmptyResponse = leftClient.request("left")
        async let right: EmptyResponse = rightClient.request("right")
        _ = try await (left, right)
    }

    func testProfileImageUploadEmitsFailureSignalClassifiedAsPayloadTooLarge() async {
        let api = SettingsAPI(client: makeClient(token: "token-123"), session: router.makeSession())
        let signalExpectation = expectation(description: "Profile image upload failure signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "settings.profileImage.upload" else {
                return
            }
            receivedSignal = signal
            signalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 413,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Image too large\"}".utf8))
        }

        do {
            try await api.uploadProfileImage(
                data: Data([0x01, 0x02]),
                contentType: "image/png",
                filename: "avatar.png"
            )
            XCTFail("Expected upload to fail")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.requestKind, .multipartUpload)
        XCTAssertEqual(receivedSignal?.errorCategory, .payloadTooLarge)
    }

    func testIngestionMultipartUploadEmitsFailureSignalClassifiedAsAuthentication() async {
        let api = IngestionAPI(client: makeClient(token: "token-123"), session: router.makeSession())
        let signalExpectation = expectation(description: "Ingestion upload failure signal")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "files.upload" else {
                return
            }
            receivedSignal = signal
            signalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).txt")
        try? Data("upload".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Unauthorized\"}".utf8))
        }

        do {
            _ = try await api.upload(
                fileURL: fileURL,
                filename: "upload.txt",
                mimeType: "text/plain",
                folder: "docs"
            )
            XCTFail("Expected upload to fail")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [signalExpectation], timeout: 1.0)
        XCTAssertEqual(receivedSignal?.requestKind, .multipartUpload)
        XCTAssertEqual(receivedSignal?.errorCategory, .authentication)
    }

    func testIngestionMultipartUploadDoesNotEmitSuccessSignalWhenResponseParsingFails() async throws {
        let api = IngestionAPI(client: makeClient(token: "token-123"), session: router.makeSession())
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).txt")
        try Data("upload".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let successSignalExpectation = expectation(description: "No upload success signal")
        successSignalExpectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestSucceeded,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "files.upload" else {
                return
            }
            successSignalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"missing file id\"}".utf8))
        }

        do {
            _ = try await api.upload(
                fileURL: fileURL,
                filename: "upload.txt",
                mimeType: "text/plain",
                folder: "docs"
            )
            XCTFail("Expected upload parsing to fail")
        } catch {
            // Expected failure.
        }

        await fulfillment(of: [successSignalExpectation], timeout: 0.2)
    }

    private func makeClient(
        token: String,
        router: ScopedURLProtocolRouter? = nil
    ) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { token }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }
}
