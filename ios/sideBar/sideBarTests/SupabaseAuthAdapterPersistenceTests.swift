import XCTest
import sideBarShared
import Supabase
@testable import sideBar

@MainActor
extension SupabaseAuthAdapterTests {
    func testRefreshSessionReturnsBeforeStateStorePersistenceCompletes() async throws {
        let exp: TimeInterval = Date().addingTimeInterval(60 * 60).timeIntervalSince1970
        let token = makeJwt(exp: exp)
        let refreshedSession = SupabaseSessionInfo(accessToken: token, userId: "user-1", expiresAt: exp)
        let client = FakeSupabaseAuthClient()
        client.currentSession = refreshedSession
        client.refreshResult = .success(refreshedSession)

        let store = BlockingAuthStateStore()
        store.blockWrites()
        defer { store.releaseWrites() }

        let adapter = SupabaseAuthAdapter(
            authClient: client,
            stateStore: store,
            startAuthStateTask: false,
            userDefaults: makeUserDefaults()
        )

        let refreshReturned = expectation(description: "refresh returned")
        Task { @MainActor in
            await adapter.refreshSession()
            refreshReturned.fulfill()
        }

        await fulfillment(of: [refreshReturned], timeout: 0.2)
        XCTAssertEqual(adapter.accessToken, token)
        XCTAssertEqual(adapter.userId, "user-1")

        store.releaseWrites()
        try await waitUntil(timeoutSeconds: 1.0) {
            store.persistedAccessToken == token && store.persistedUserId == "user-1"
        }
    }
}
