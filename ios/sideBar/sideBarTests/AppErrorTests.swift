import XCTest
import sideBarShared

final class AppErrorTests: XCTestCase {
    func testHTTP401MapsToAuthenticationAppError() {
        let error = AppError.classify(
            operation: "chat.send",
            requestKind: .foregroundMutation,
            responseStatus: 401,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(error.category, .authentication)
        XCTAssertEqual(error.recommendedSurface, .alert)
    }

    func testCancelledTransportDoesNotUseLocalizedDescriptionAsSecureSignal() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cancelled.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "TLS certificate validation failed"]
        )

        let classified = AppError.classify(
            operation: "chat.send",
            requestKind: .foregroundMutation,
            responseStatus: nil,
            backendMessage: nil,
            transportError: error
        )

        XCTAssertEqual(classified.category, .cancelled)
        XCTAssertEqual(classified.recommendedSurface, .silent)
    }

    func testClassifyAPIClientStatusErrorUsesSharedHTTPClassification() {
        let classified = AppError.classify(
            error: APIClientError.requestFailed(503),
            operation: "widget.files.refresh",
            requestKind: .foregroundRead
        )

        XCTAssertEqual(classified.category, .serverBusy)
        XCTAssertEqual(classified.retryability, .retryable)
        XCTAssertEqual(classified.diagnostics["statusCode"], "503")
    }

    func testClassifyAPIClientMessageUsesAuthenticationClassification() {
        let classified = AppError.classify(
            error: APIClientError.apiError("Session expired, please sign in again."),
            operation: "share_extension.upload_file",
            requestKind: .multipartUpload
        )

        XCTAssertEqual(classified.category, .authentication)
        XCTAssertEqual(classified.retryability, .userActionRequired)
        XCTAssertEqual(classified.diagnostics["backendHint"], "authentication")
    }
}
