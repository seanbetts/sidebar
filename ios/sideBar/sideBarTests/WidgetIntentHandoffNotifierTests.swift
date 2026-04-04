import XCTest
@testable import sideBarShared

final class WidgetIntentHandoffNotifierTests: XCTestCase {
    func testNotifierDeliversCallbackAfterPost() {
        assertSingleHandoffDelivery(
            in: self,
            description: "widget intent handoff received",
            observe: WidgetIntentHandoffNotifier.observe,
            post: WidgetIntentHandoffNotifier.post,
            removeObserver: WidgetIntentHandoffNotifier.removeObserver
        )
    }
}
