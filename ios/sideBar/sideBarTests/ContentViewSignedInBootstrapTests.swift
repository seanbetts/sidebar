import XCTest
@testable import sideBar

@MainActor
final class ContentViewSignedInBootstrapTests: XCTestCase {
    func testSignedInBootstrapWaitsForActiveAuth() {
        XCTAssertFalse(
            ContentView.shouldStartSignedInBootstrap(
                authState: .staleRecoverable,
                isProtectedContentReady: true,
                didLoadSettings: false
            )
        )
        XCTAssertTrue(
            ContentView.shouldStartSignedInBootstrap(
                authState: .active,
                isProtectedContentReady: true,
                didLoadSettings: false
            )
        )
        XCTAssertFalse(
            ContentView.shouldStartSignedInBootstrap(
                authState: .active,
                isProtectedContentReady: true,
                didLoadSettings: true
            )
        )
    }

    func testSignedInBootstrapStateResetsWhenAuthLeavesAuthenticatedContent() {
        XCTAssertTrue(ContentView.shouldResetSignedInBootstrapState(authState: .reauthenticationRequired))
        XCTAssertTrue(ContentView.shouldResetSignedInBootstrapState(authState: .signedOut))
        XCTAssertFalse(ContentView.shouldResetSignedInBootstrapState(authState: .active))
        XCTAssertFalse(ContentView.shouldResetSignedInBootstrapState(authState: .staleRecoverable))
    }

    func testSignedInBootstrapActionCentralizesStartResetAndNoopDecisions() {
        XCTAssertEqual(
            ContentView.signedInBootstrapAction(
                authState: .active,
                isProtectedContentReady: true,
                didLoadSettings: false
            ),
            .start
        )
        XCTAssertEqual(
            ContentView.signedInBootstrapAction(
                authState: .active,
                isProtectedContentReady: false,
                didLoadSettings: false
            ),
            .none
        )
        XCTAssertEqual(
            ContentView.signedInBootstrapAction(
                authState: .staleRecoverable,
                isProtectedContentReady: true,
                didLoadSettings: false
            ),
            .none
        )
        XCTAssertEqual(
            ContentView.signedInBootstrapAction(
                authState: .reauthenticationRequired,
                isProtectedContentReady: false,
                didLoadSettings: true
            ),
            .reset
        )
        XCTAssertEqual(
            ContentView.signedInBootstrapAction(
                authState: .signedOut,
                isProtectedContentReady: false,
                didLoadSettings: true
            ),
            .reset
        )
    }
}
