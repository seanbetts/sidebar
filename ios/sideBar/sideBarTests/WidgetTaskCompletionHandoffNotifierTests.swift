import XCTest
@testable import sideBar
@testable import sideBarShared

final class WidgetTaskCompletionHandoffNotifierTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WidgetTaskCompletionHandoffNotifierTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    func testNotifierDeliversCallbackAfterTaskCompletionPost() {
        let expectation = expectation(description: "task completion handoff notification received")
        let observer = WidgetTaskCompletionHandoffNotifier.observe {
            expectation.fulfill()
        }

        WidgetTaskCompletionHandoffNotifier.post()

        wait(for: [expectation], timeout: 1.0)
        WidgetTaskCompletionHandoffNotifier.removeObserver(observer)
    }
}
