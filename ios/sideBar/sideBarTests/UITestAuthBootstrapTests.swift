import XCTest
@testable import sideBar

@MainActor
final class UITestAuthBootstrapTests: XCTestCase {
    private static var retainedSessions: [PlaceholderAuthSession] = []

    func testMakeSeededSessionReturnsNilWithoutCompleteCredentials() {
        XCTAssertNil(UITestAuthBootstrap.makeSeededSession(from: [:]))
        XCTAssertNil(UITestAuthBootstrap.makeSeededSession(from: [
            UITestAuthBootstrap.accessTokenKey: "token-only"
        ]))
        XCTAssertNil(UITestAuthBootstrap.makeSeededSession(from: [
            UITestAuthBootstrap.userIdKey: "user-only"
        ]))
    }

    func testMakeSeededSessionReturnsActiveSessionForTrimmedEnvironmentValues() throws {
        let session = try XCTUnwrap(UITestAuthBootstrap.makeSeededSession(from: [
            UITestAuthBootstrap.accessTokenKey: " token-123 ",
            UITestAuthBootstrap.userIdKey: "\nuser-456\t"
        ]))
        Self.retainedSessions.append(session)

        XCTAssertEqual(session.accessToken, "token-123")
        XCTAssertEqual(session.userId, "user-456")
        XCTAssertEqual(session.authState, .active)
        XCTAssertEqual(session.authorizationToken, "token-123")
    }

    func testMakeSeededSessionReturnsStaleSessionWhenForcedByEnvironment() throws {
        let session = try XCTUnwrap(UITestAuthBootstrap.makeSeededSession(from: [
            UITestAuthBootstrap.forceStaleAuthKey: "1"
        ]))
        Self.retainedSessions.append(session)

        XCTAssertEqual(session.accessToken, "debug-stale-auth-token")
        XCTAssertEqual(session.userId, "debug-stale-auth-user")
        XCTAssertEqual(session.authState, .stale)
        XCTAssertNil(session.authorizationToken)
    }

    func testForcedStaleSessionPreservesExplicitSeededCredentials() throws {
        let session = try XCTUnwrap(UITestAuthBootstrap.makeSeededSession(from: [
            UITestAuthBootstrap.forceStaleAuthKey: "1",
            UITestAuthBootstrap.accessTokenKey: " token-123 ",
            UITestAuthBootstrap.userIdKey: "\nuser-456\t"
        ]))
        Self.retainedSessions.append(session)

        XCTAssertEqual(session.accessToken, "token-123")
        XCTAssertEqual(session.userId, "user-456")
        XCTAssertEqual(session.authState, .stale)
        XCTAssertNil(session.authorizationToken)
    }

    func testShouldForcePasswordResetReadsLaunchEnvironment() {
        XCTAssertTrue(UITestAuthBootstrap.shouldForcePasswordReset(from: [
            UITestAuthBootstrap.forcePasswordResetKey: "1"
        ]))
        XCTAssertFalse(UITestAuthBootstrap.shouldForcePasswordReset(from: [:]))
    }

    func testSeededSessionSignOutClearsAuthorization() async {
        let session = PlaceholderAuthSession(
            accessToken: "token-123",
            userId: "user-456",
            authState: .active
        )
        Self.retainedSessions.append(session)

        await session.signOut()

        XCTAssertEqual(session.authState, .signedOut)
        XCTAssertNil(session.accessToken)
        XCTAssertNil(session.userId)
        XCTAssertNil(session.authorizationToken)
    }

    func testSeededStaleSessionRefreshPromotesAuthorization() async {
        let session = PlaceholderAuthSession(
            accessToken: "token-123",
            userId: "user-456",
            authState: .stale
        )
        Self.retainedSessions.append(session)

        await session.refreshSession()

        XCTAssertEqual(session.authState, .active)
        XCTAssertEqual(session.authorizationToken, "token-123")
    }
}
