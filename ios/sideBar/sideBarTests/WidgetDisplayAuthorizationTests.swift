import XCTest
import sideBarShared
@testable import sideBar

final class WidgetDisplayAuthorizationTests: XCTestCase {
    func testAllowsDisplayingCachedSnapshotWhenAuthStateIsUnavailable() {
        XCTAssertTrue(
            WidgetDisplayAuthorization.canDisplayContent(for: .transientlyUnavailable)
        )
    }

    func testHidesContentWhenSignedOutAndNoCachedSnapshotExists() {
        XCTAssertFalse(
            WidgetDisplayAuthorization.canDisplayContent(for: .signedOut)
        )
    }

    func testHidesContentWhenReauthenticationIsRequired() {
        XCTAssertFalse(
            WidgetDisplayAuthorization.canDisplayContent(for: .reauthenticationRequired)
        )
    }

    func testAllowsDisplayingContentWhenAuthenticatedWithoutCachedSnapshot() {
        XCTAssertTrue(
            WidgetDisplayAuthorization.canDisplayContent(for: .authenticated)
        )
    }

    func testDerivesDisplayStateFromLegacyAuthAndCacheInputs() {
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(isAuthenticated: true, hasCachedSnapshot: false),
            .authenticated
        )
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(isAuthenticated: false, hasCachedSnapshot: true),
            .transientlyUnavailable
        )
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(isAuthenticated: false, hasCachedSnapshot: false),
            .signedOut
        )
    }

    func testStoredSignedOutStateOverridesCachedSnapshot() {
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(
                storedState: .signedOut,
                isAuthenticated: false,
                hasCachedSnapshot: true
            ),
            .signedOut
        )
    }

    func testStoredReauthenticationRequiredStateOverridesCachedSnapshot() {
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(
                storedState: .reauthenticationRequired,
                isAuthenticated: false,
                hasCachedSnapshot: true
            ),
            .reauthenticationRequired
        )
    }

    func testStoredTransientStateRequiresCachedSnapshot() {
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(
                storedState: .transientlyUnavailable,
                isAuthenticated: false,
                hasCachedSnapshot: true
            ),
            .transientlyUnavailable
        )
        XCTAssertEqual(
            WidgetDisplayAuthorization.displayState(
                storedState: .transientlyUnavailable,
                isAuthenticated: false,
                hasCachedSnapshot: false
            ),
            .signedOut
        )
    }
}
