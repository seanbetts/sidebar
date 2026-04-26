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
}
