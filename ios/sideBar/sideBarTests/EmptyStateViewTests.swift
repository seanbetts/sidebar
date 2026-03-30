import XCTest
@testable import sideBar

final class EmptyStateViewTests: XCTestCase {
    func testInitializerStoresIconAndCopy() {
        let view = EmptyStateView(
            title: "No conversations",
            subtitle: "Start a new chat to begin.",
            systemImage: "bubble.left.and.bubble.right"
        )

        XCTAssertEqual(view.title, "No conversations")
        XCTAssertEqual(view.subtitle, "Start a new chat to begin.")
        XCTAssertEqual(view.systemImage, "bubble.left.and.bubble.right")
    }
}
