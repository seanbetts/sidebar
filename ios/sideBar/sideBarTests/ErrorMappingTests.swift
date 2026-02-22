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
        XCTAssertEqual(message, "Secure connection to server failed. The server certificate may have changed.")
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
        XCTAssertEqual(message, "Secure connection to server failed. The server certificate may have changed.")
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

    func testMapsAuthSignalFromAPIErrorMessage() {
        let message = ErrorMapping.message(for: APIClientError.apiError("Not authenticated"))
        XCTAssertEqual(message, "Session expired. Please sign in again.")
    }
}
