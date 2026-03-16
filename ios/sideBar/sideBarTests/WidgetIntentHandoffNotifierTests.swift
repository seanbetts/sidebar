import XCTest
@testable import sideBarShared

final class WidgetIntentHandoffNotifierTests: XCTestCase {
    func testNotifierDeliversCallbackAfterPost() {
        let expectation = expectation(description: "widget intent handoff received")
        let observer = WidgetIntentHandoffNotifier.observe {
            expectation.fulfill()
        }

        WidgetIntentHandoffNotifier.post()

        wait(for: [expectation], timeout: 1.0)
        WidgetIntentHandoffNotifier.removeObserver(observer)
    }
}
