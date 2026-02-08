import Foundation
import sideBarShared
import OSLog
import XCTest
@testable import sideBar

final class IngestionUploadManagerTests: XCTestCase {
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
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let manager = IngestionUploadManager(config: config)
        let group = DispatchGroup()

        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                manager.cancelUpload(uploadId: "upload-\(i)")
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success, "Concurrent cancel calls should not deadlock")
    }

    func testConcurrentStartAndCancelDoNotCrash() {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let manager = IngestionUploadManager(config: config)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-upload-\(UUID().uuidString)")
        try? Data("data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let group = DispatchGroup()
        for i in 0..<20 {
            let uploadId = "upload-\(i)"
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
                    onCompletion: { _ in }
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
}
