import Foundation
import sideBarShared
import OSLog
import XCTest
@testable import sideBar

final class IngestionUploadManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        IngestionUploadURLProtocolMock.resetHandler()
    }

    override func tearDown() {
        IngestionUploadURLProtocolMock.resetHandler()
        super.tearDown()
    }

    func testParseUploadResponseUsesTopLevelFileId() throws {
        let data = Data("{\"file_id\":\"f1\"}".utf8)

        let fileId = try IngestionUploadHelpers.parseUploadResponse(data: data)

        XCTAssertEqual(fileId, "f1")
    }

    func testParseUploadResponseUsesNestedFileId() throws {
        let data = Data("{\"data\":{\"file_id\":\"f2\"}}".utf8)

        let fileId = try IngestionUploadHelpers.parseUploadResponse(data: data)

        XCTAssertEqual(fileId, "f2")
    }

    func testParseUploadResponseThrowsWhenMissing() {
        let data = Data("{}".utf8)

        XCTAssertThrowsError(try IngestionUploadHelpers.parseUploadResponse(data: data))
    }

    // MARK: - Concurrency regression (Phase 2.2)

    func testConcurrentCancelUploadsDoNotDeadlock() {
        let manager = makeManager()
        let group = DispatchGroup()

        for uploadIndex in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                manager.cancelUpload(uploadId: "upload-\(uploadIndex)")
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success, "Concurrent cancel calls should not deadlock")
    }

    func testConcurrentStartAndCancelDoNotCrash() {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-upload-\(UUID().uuidString)")
        try? Data("data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let completionExpectation = expectation(description: "All uploads complete")
        completionExpectation.expectedFulfillmentCount = 20

        let group = DispatchGroup()
        for uploadIndex in 0..<20 {
            let uploadId = "upload-\(uploadIndex)"
            group.enter()
            DispatchQueue.global().async {
                manager.startUpload(
                    request: UploadRequest(
                        uploadId: uploadId,
                        fileURL: fileURL,
                        filename: "test.txt",
                        mimeType: "text/plain",
                        folder: "test"
                    ),
                    onProgress: { _ in },
                    onCompletion: { _ in completionExpectation.fulfill() }
                )
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                manager.cancelUpload(uploadId: uploadId)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Concurrent start+cancel should not crash or deadlock")
        wait(for: [completionExpectation], timeout: 10)
    }

    func testConcurrentStartAndCancelStressIsStableAcrossRuns() {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("stress-upload-\(UUID().uuidString)")
        try? Data("data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let startQueue = DispatchQueue(label: "IngestionUploadManagerTests.start", qos: .userInitiated, attributes: .concurrent)
        let cancelQueue = DispatchQueue(label: "IngestionUploadManagerTests.cancel", qos: .userInitiated, attributes: .concurrent)

        let runs = 4
        let uploadPairsPerRun = 60

        for run in 0..<runs {
            let completionExpectation = expectation(description: "Run \(run) uploads complete")
            completionExpectation.expectedFulfillmentCount = uploadPairsPerRun
            let group = DispatchGroup()

            for uploadIndex in 0..<uploadPairsPerRun {
                let uploadId = "stress-\(run)-\(uploadIndex)"

                group.enter()
                let startBlock = {
                    manager.startUpload(
                        request: UploadRequest(
                            uploadId: uploadId,
                            fileURL: fileURL,
                            filename: "stress.txt",
                            mimeType: "text/plain",
                            folder: "test"
                        ),
                        onProgress: { _ in },
                        onCompletion: { _ in completionExpectation.fulfill() }
                    )
                    group.leave()
                }

                group.enter()
                let cancelBlock = {
                    manager.cancelUpload(uploadId: uploadId)
                    group.leave()
                }

                if (run + uploadIndex).isMultiple(of: 2) {
                    startQueue.async(execute: startBlock)
                    cancelQueue.async(execute: cancelBlock)
                } else {
                    cancelQueue.async(execute: cancelBlock)
                    startQueue.async(execute: startBlock)
                }
            }

            let result = group.wait(timeout: .now() + 20)
            XCTAssertEqual(
                result,
                .success,
                "Run \(run) should complete without deadlock during concurrent start/cancel stress"
            )
            wait(for: [completionExpectation], timeout: 10)
        }
    }

    @MainActor
    func testBackgroundUploadEmitsFailureSignalClassifiedAsServerBusy() async throws {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("signal-upload-\(UUID().uuidString)")
        try Data("data".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let signalExpectation = expectation(description: "Background upload failure signal")
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
            signalExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        IngestionUploadURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/files")!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"detail\":\"Try again later\"}".utf8))
        }

        manager.startUpload(
            request: UploadRequest(
                uploadId: "bg-upload",
                fileURL: fileURL,
                filename: "signal.txt",
                mimeType: "text/plain",
                folder: "docs"
            ),
            onProgress: { _ in },
            onCompletion: { _ in completionExpectation.fulfill() }
        )

        await fulfillment(of: [completionExpectation, signalExpectation], timeout: 2.0)
        XCTAssertEqual(receivedSignal?.requestKind, .backgroundUpload)
        XCTAssertEqual(receivedSignal?.errorCategory, .serverBusy)
    }

    @MainActor
    func testBackgroundUploadDoesNotEmitSuccessSignalWhenResponseParsingFails() async throws {
        let manager = makeManager()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("signal-upload-\(UUID().uuidString)")
        try Data("data".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let successSignalExpectation = expectation(description: "No background upload success signal")
        successSignalExpectation.isInverted = true
        let completionExpectation = expectation(description: "Background upload completion")
        let observer = NotificationCenter.default.addObserver(
            forName: .apiClientRequestSucceeded,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
                  signal.operation == "files.backgroundUpload" else {
                return
            }
            successSignalExpectation.fulfill()
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

        var completionResult: Result<String, Error>?
        manager.startUpload(
            request: UploadRequest(
                uploadId: "bg-upload-invalid",
                fileURL: fileURL,
                filename: "signal.txt",
                mimeType: "text/plain",
                folder: "docs"
            ),
            onProgress: { _ in },
            onCompletion: { result in
                completionResult = result
                completionExpectation.fulfill()
            }
        )

        await fulfillment(of: [completionExpectation, successSignalExpectation], timeout: 2.0)
        guard case .failure = completionResult else {
            return XCTFail("Expected parsing failure")
        }
    }

    // MARK: - Helpers

    func testWriteMultipartBodyIncludesFields() throws {
        let boundary = "Boundary-Test"
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Data("Hello".utf8).write(to: inputURL)

        let payload = UploadPayload(
            fileURL: inputURL,
            filename: "hello.txt",
            mimeType: "text/plain",
            folder: "docs"
        )
        try IngestionUploadHelpers.writeMultipartBody(
            to: outputURL,
            boundary: boundary,
            payload: payload,
            logger: Logger(subsystem: "sideBar", category: "Test")
        )

        let output = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(output.contains("--\(boundary)"))
        XCTAssertTrue(output.contains("name=\"folder\""))
        XCTAssertTrue(output.contains("docs"))
        XCTAssertTrue(output.contains("filename=\"hello.txt\""))
        XCTAssertTrue(output.contains("Content-Type: text/plain"))
        XCTAssertTrue(output.contains("Hello"))
    }

    func testURLProtocolMockUsesDefaultResponseAfterHandlerReset() {
        IngestionUploadURLProtocolMock.requestHandler = nil
        let request = URLRequest(url: URL(string: "https://example.com/files")!)
        let client = URLProtocolClientSpy()
        let mock = IngestionUploadURLProtocolMock(request: request, cachedResponse: nil, client: client)

        mock.startLoading()

        XCTAssertEqual(client.response?.statusCode, 200)
        XCTAssertEqual(client.loadedData, Data("{\"file_id\":\"mock-file\"}".utf8))
        XCTAssertTrue(client.didFinishLoading)
        XCTAssertNil(client.failure)
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

class IngestionUploadURLProtocolMock: URLProtocol {
    private static let handlerLock = NSLock()
    private static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? = defaultHandler

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return _requestHandler
        }
        set {
            handlerLock.lock()
            _requestHandler = newValue
            handlerLock.unlock()
        }
    }

    static func resetHandler() {
        requestHandler = defaultHandler
    }

    private static func defaultHandler(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/files")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data("{\"file_id\":\"mock-file\"}".utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = IngestionUploadURLProtocolMock.requestHandler ?? IngestionUploadURLProtocolMock.defaultHandler
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

private final class URLProtocolClientSpy: NSObject, URLProtocolClient {
    var response: HTTPURLResponse?
    var loadedData = Data()
    var didFinishLoading = false
    var failure: Error?

    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
    }

    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {
    }

    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
        self.response = response as? HTTPURLResponse
    }

    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
        loadedData.append(data)
    }

    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
        didFinishLoading = true
    }

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
        failure = error
    }

    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {
        challenge.sender?.cancel(challenge)
    }

    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {
    }
}
