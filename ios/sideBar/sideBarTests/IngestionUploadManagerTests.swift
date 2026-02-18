import Foundation
import sideBarShared
import OSLog
import XCTest
@testable import sideBar

final class IngestionUploadManagerTests: XCTestCase {
    private static let protocolIsolationLock = NSLock()

    override func setUp() {
        super.setUp()
        Self.protocolIsolationLock.lock()
        URLProtocol.registerClass(IngestionUploadURLProtocolMock.self)
        IngestionUploadURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/files")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"file_id\":\"mock-file\"}".utf8))
        }
    }

    override func tearDown() {
        IngestionUploadURLProtocolMock.requestHandler = nil
        URLProtocol.unregisterClass(IngestionUploadURLProtocolMock.self)
        Self.protocolIsolationLock.unlock()
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

        let runs = 4
        let uploadPairsPerRun = 60

        for run in 0..<runs {
            let completionExpectation = expectation(description: "Run \(run) uploads complete")
            completionExpectation.expectedFulfillmentCount = uploadPairsPerRun
            let group = DispatchGroup()

            for uploadIndex in 0..<uploadPairsPerRun {
                let uploadId = "stress-\(run)-\(uploadIndex)"

                group.enter()
                DispatchQueue.global().async {
                    usleep(UInt32.random(in: 500...3_000))
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
                DispatchQueue.global().async {
                    usleep(UInt32.random(in: 500...3_000))
                    manager.cancelUpload(uploadId: uploadId)
                    group.leave()
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

    private func makeManager() -> IngestionUploadManager {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
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
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = IngestionUploadURLProtocolMock.requestHandler else {
            XCTFail("IngestionUploadURLProtocolMock requestHandler not set")
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
