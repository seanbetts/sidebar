import Foundation
import sideBarShared
import XCTest
@testable import sideBar

final class IngestionUploadManagerLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        IngestionUploadURLProtocolMock.resetHandler()
    }

    override func tearDown() {
        IngestionUploadURLProtocolMock.resetHandler()
        super.tearDown()
    }

    @MainActor
    func testBackgroundUploadRefreshesAuthBeforeStartingRequiredUpload() async throws {
        final class TokenBox: @unchecked Sendable {
            var token: String?
            var refreshCount = 0
        }
        let tokenBox = TokenBox()
        let manager = makeManager(
            accessTokenProvider: { tokenBox.token },
            refreshAuthIfNeeded: {
                tokenBox.refreshCount += 1
                tokenBox.token = "refreshed-token"
                return true
            }
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("auth-upload-\(UUID().uuidString)")
        try Data("data".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let completionExpectation = expectation(description: "Background upload completion")
        var observedAuthorization: String?
        IngestionUploadURLProtocolMock.requestHandler = { request in
            observedAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/files")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"file_id\":\"file-1\"}".utf8))
        }

        manager.startUpload(
            request: UploadRequest(
                uploadId: "bg-upload-auth",
                fileURL: fileURL,
                filename: "auth.txt",
                mimeType: "text/plain",
                folder: "docs"
            ),
            onProgress: { _ in },
            onCompletion: { _ in completionExpectation.fulfill() }
        )

        await fulfillment(of: [completionExpectation], timeout: 2.0)
        XCTAssertEqual(tokenBox.refreshCount, 1)
        XCTAssertEqual(observedAuthorization, "Bearer refreshed-token")
    }

    @MainActor
    func testBackgroundUploadHTTPFailureCompletesWithTypedAppError() async throws {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("typed-upload-\(UUID().uuidString)")
        try Data("data".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let completionExpectation = expectation(description: "Background upload completion")
        var completionResult: Result<String, Error>?
        IngestionUploadURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/files")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Raw backend rejection\"}".utf8))
        }

        manager.startUpload(
            request: UploadRequest(
                uploadId: "bg-upload-typed",
                fileURL: fileURL,
                filename: "typed.txt",
                mimeType: "text/plain",
                folder: "docs"
            ),
            onProgress: { _ in },
            onCompletion: { result in
                completionResult = result
                completionExpectation.fulfill()
            }
        )

        await fulfillment(of: [completionExpectation], timeout: 2.0)
        guard case .failure(APIClientError.appError(let appError)) = completionResult else {
            return XCTFail("Expected typed app error, got \(String(describing: completionResult))")
        }
        XCTAssertEqual(appError.category, .requestRejected)
        XCTAssertEqual(appError.requestKind, .backgroundUpload)
    }

    @MainActor
    func testBackgroundUploadEmitsDecodingFailureSignalWhenResponseParsingFails() async throws {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("decode-upload-\(UUID().uuidString)")
        try Data("data".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let failureSignalExpectation = expectation(description: "Background upload decoding failure signal")
        let completionExpectation = expectation(description: "Background upload completion")
        var receivedSignal: RequestLifecycleSignal?
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestFailed,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "files.backgroundUpload" else {
                return
            }
            receivedSignal = signal
            failureSignalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        IngestionUploadURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/files")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"missing file id\"}".utf8))
        }

        manager.startUpload(
            request: UploadRequest(
                uploadId: "bg-upload-decode",
                fileURL: fileURL,
                filename: "decode.txt",
                mimeType: "text/plain",
                folder: "docs"
            ),
            onProgress: { _ in },
            onCompletion: { _ in completionExpectation.fulfill() }
        )

        await fulfillment(of: [completionExpectation, failureSignalExpectation], timeout: 2.0)
        XCTAssertEqual(receivedSignal?.requestKind, .backgroundUpload)
        XCTAssertEqual(receivedSignal?.errorCategory, .decoding)
    }

    private func makeManager(
        accessTokenProvider: @escaping () -> String? = { "token" },
        refreshAuthIfNeeded: (() async -> Bool)? = nil
    ) -> IngestionUploadManager {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: accessTokenProvider,
            refreshAuthIfNeeded: refreshAuthIfNeeded
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [IngestionUploadURLProtocolMock.self]
        sessionConfig.waitsForConnectivity = false
        sessionConfig.timeoutIntervalForRequest = 5
        sessionConfig.timeoutIntervalForResource = 5
        let session = URLSession(configuration: sessionConfig)
        return IngestionUploadManager(config: config, session: session)
    }
}
