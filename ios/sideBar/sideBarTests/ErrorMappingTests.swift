import XCTest
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

    func testMapsOperationMessage() {
        let message = ErrorMapping.message(for: APIClientError.invalidUrl, during: "load settings")
        XCTAssertEqual(message, "Failed to load settings: Invalid request URL.")
    }
}
