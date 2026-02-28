import XCTest
import sideBarShared
@testable import sideBar

final class ErrorMappingTests: XCTestCase {
    func testMapsApiErrorMessage() {
        let message = ErrorMapping.message(for: APIClientError.apiError("Bad request"))
        XCTAssertEqual(message, "Bad request")
    }

    func testMapsAuthErrorDescription() {
        let message = ErrorMapping.message(for: AuthAdapterError.invalidCredentials)
        XCTAssertEqual(message, AuthAdapterError.invalidCredentials.errorDescription)
    }

    func testMapsNetworkError() {
        let message = ErrorMapping.message(for: URLError(.notConnectedToInternet))
        XCTAssertEqual(message, "Network connection failed. Please check your internet.")
    }

    func testMapsTimeoutError() {
        let message = ErrorMapping.message(for: URLError(.timedOut))
        XCTAssertEqual(message, "Server took too long to respond. Please try again.")
    }

    func testMapsSecureConnectionError() {
        let message = ErrorMapping.message(for: URLError(.secureConnectionFailed))
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsCancelledRequestError() {
        let message = ErrorMapping.message(for: URLError(.cancelled))
        XCTAssertEqual(message, "Request was interrupted. Please try again.")
    }

    func testMapsCancelledRequestWithPeerTrustAsSecureConnectionError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cancelled.rawValue,
            userInfo: [NSURLErrorFailingURLPeerTrustErrorKey: "peer-trust"]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsCancelledRequestWithRegistryAsCertPinError() {
        // Simulate a cert-pinning cancellation recorded in the registry.
        let host = "api.trysidebar.ai"
        CertPinCancellationRegistry.shared.record(host: host)
        let error = URLError(
            .cancelled,
            userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://\(host)/v1/test")!]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsCancelledRequestWithoutRegistryEntryStaysCancelled() {
        // A plain cancellation with no registry entry stays as .cancelled.
        let error = URLError(
            .cancelled,
            userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://unknown-host.example.com/v1/test")!]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(message, "Request was interrupted. Please try again.")
    }

    func testMapsOperationMessage() {
        let message = ErrorMapping.message(for: APIClientError.invalidUrl, during: "load settings")
        XCTAssertEqual(message, "Failed to load settings: Invalid request URL.")
    }

    func testMapsRequestTimeoutStatus() {
        let message = ErrorMapping.message(for: APIClientError.requestFailed(408))
        XCTAssertEqual(message, "Network connection failed. Please check your internet.")
    }

    func testMapsGatewayTimeoutStatus() {
        let message = ErrorMapping.message(for: APIClientError.requestFailed(504))
        XCTAssertEqual(message, "Network connection failed. Please check your internet.")
    }

    func testMapsBadRequestStatusToAttachmentGuidance() {
        let message = ErrorMapping.message(for: APIClientError.requestFailed(400))
        XCTAssertEqual(
            message,
            "Request was rejected by the server. If this includes attachments, remove one and try again."
        )
    }

    func testMapsAuthSignalFromAPIErrorMessage() {
        let message = ErrorMapping.message(for: APIClientError.apiError("Not authenticated"))
        XCTAssertEqual(message, "Session expired. Please sign in again.")
    }

    func testMapsPromptTooLargeApiErrorToHelpfulMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("System prompt exceeds maximum size (50001 > 40000)")
        )
        XCTAssertEqual(
            message,
            "Attachment and context are too large for one message. Remove some attachments or close open items and try again."
        )
    }
}
