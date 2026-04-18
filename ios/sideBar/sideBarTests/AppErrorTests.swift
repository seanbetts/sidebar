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
}
