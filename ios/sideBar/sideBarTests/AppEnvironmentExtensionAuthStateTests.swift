import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentExtensionAuthStateTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []

    func testBeginSignOutClearsSharedExtensionAuthState() async throws {
        let extensionStore = ExtensionAuthStateStoreFactory.makeSharedStore()
        try extensionStore.clear()
        try extensionStore.removeSessionData(forKey: "supabase.auth.token")
        try extensionStore.removeSessionData(forKey: "supabase.session")

        try extensionStore.saveAccessToken("extension-token")
        try extensionStore.saveUserId("extension-user")
        try extensionStore.saveSessionData(Data("session".utf8), forKey: "supabase.auth.token")
        try extensionStore.saveSessionData(Data("legacy".utf8), forKey: "supabase.session")

        let authSession = PlaceholderAuthSession(
            accessToken: "app-token",
            userId: "user-123",
            authState: .active
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        retainedEnvironments.append(environment)
        environment.refreshAuthState()

        await environment.beginSignOut()

        XCTAssertNil(try extensionStore.loadAccessToken())
        XCTAssertNil(try extensionStore.loadUserId())
        XCTAssertNil(try extensionStore.loadSessionData(forKey: "supabase.auth.token"))
        XCTAssertNil(try extensionStore.loadSessionData(forKey: "supabase.session"))
    }
}
