import XCTest
import sideBarShared
@testable import sideBar

final class WidgetDisplayAuthorizationTests: XCTestCase {
    func testAllowsDisplayingCachedSnapshotWhenAuthStateIsUnavailable() {
        XCTAssertTrue(
            WidgetDisplayAuthorization.canDisplayContent(
                isAuthenticated: false,
                hasCachedSnapshot: true
            )
        )
    }

    func testHidesContentWhenSignedOutAndNoCachedSnapshotExists() {
        XCTAssertFalse(
            WidgetDisplayAuthorization.canDisplayContent(
                isAuthenticated: false,
                hasCachedSnapshot: false
            )
        )
    }

    func testAllowsDisplayingContentWhenAuthenticatedWithoutCachedSnapshot() {
        XCTAssertTrue(
            WidgetDisplayAuthorization.canDisplayContent(
                isAuthenticated: true,
                hasCachedSnapshot: false
            )
        )
    }
}
