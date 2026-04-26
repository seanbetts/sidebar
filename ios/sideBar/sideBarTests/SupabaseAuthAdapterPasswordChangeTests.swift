import XCTest
import sideBarShared
import Supabase
@testable import sideBar

@MainActor
final class SupabaseAuthAdapterPasswordChangeTests: XCTestCase {
    func testChangePasswordTrimsAndUpdatesViaClient() async throws {
        let authClient = FakeSupabaseAuthClient()
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterPasswordChangeTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: authClient,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        try await adapter.changePassword(newPassword: "  StrongPass123!  ")

        XCTAssertEqual(authClient.updatedPasswords, ["StrongPass123!"])
    }

    func testChangePasswordRejectsWeakPassword() async {
        let authClient = FakeSupabaseAuthClient()
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthAdapterPasswordChangeTests")
        defer { isolated.tearDown() }
        let adapter = SupabaseAuthAdapter(
            authClient: authClient,
            stateStore: InMemoryAuthStateStore(),
            startAuthStateTask: false,
            userDefaults: isolated.defaults
        )

        do {
            try await adapter.changePassword(newPassword: "short")
            XCTFail("Expected weak password error")
        } catch let error as AuthAdapterError {
            XCTAssertEqual(error, .weakPassword)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSupabaseAuthClientMapsTypedInitialSessionEvent() {
        XCTAssertEqual(SupabaseAuthClient.mapEvent(.initialSession), .initialSession)
    }

    func testSupabaseAuthClientMapsTypedSignedOutEvent() {
        XCTAssertEqual(SupabaseAuthClient.mapEvent(.signedOut), .signedOut)
    }

    func testSupabaseAuthClientPreservesSupabaseRawValueForOtherTypedEvents() {
        XCTAssertEqual(SupabaseAuthClient.mapEvent(.signedIn), .other("SIGNED_IN"))
        XCTAssertEqual(SupabaseAuthClient.mapEvent(.tokenRefreshed), .other("TOKEN_REFRESHED"))
        XCTAssertEqual(SupabaseAuthClient.mapEvent(.userUpdated), .other("USER_UPDATED"))
    }
}
