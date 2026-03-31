import XCTest
import sideBarShared
@testable import sideBar

final class PasswordResetErrorPresentationTests: XCTestCase {
    func testMaps404ToGenericUnavailableMessage() {
        let message = PasswordResetErrorPresentation.message(
            for: APIClientError.requestFailed(404)
        )

        XCTAssertEqual(
            message,
            "Password reset is temporarily unavailable. Please try again shortly."
        )
    }

    func testMapsTransportFailureToGenericUnavailableMessage() {
        let message = PasswordResetErrorPresentation.message(
            for: URLError(.cannotConnectToHost)
        )

        XCTAssertEqual(
            message,
            "Password reset is temporarily unavailable. Please try again shortly."
        )
    }
}
