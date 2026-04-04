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
        assertSingleHandoffDelivery(
            in: self,
            description: "task completion handoff notification received",
            observe: WidgetTaskCompletionHandoffNotifier.observe,
            post: WidgetTaskCompletionHandoffNotifier.post,
            removeObserver: WidgetTaskCompletionHandoffNotifier.removeObserver
        )
    }
}
