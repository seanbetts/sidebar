import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentBiometricAuthRefreshTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var isolatedDefaults: TestIsolation.IsolatedUserDefaults!

    override func setUp() {
        super.setUp()
        isolatedDefaults = TestIsolation.makeUserDefaults(
            prefix: "AppEnvironmentBiometricAuthRefreshTests"
        )
        retainedEnvironments.removeAll()
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        isolatedDefaults?.tearDown()
        isolatedDefaults = nil
        super.tearDown()
    }

    func testRefreshAuthStateKeepsBiometricUnlockForActiveSessionRefresh() {
        let defaults = isolatedDefaults.defaults
        defaults.set(true, forKey: AppStorageKeys.biometricUnlockEnabled)

        let authSession = PlaceholderAuthSession(
            accessToken: "token-123",
            userId: "user-123",
            authState: .active
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            storage: AppEnvironmentStorage(userDefaults: defaults)
        )
        retainedEnvironments.append(environment)
        environment.isBiometricUnlocked = true

        environment.refreshAuthState()

        XCTAssertTrue(environment.isBiometricUnlocked)
        XCTAssertTrue(environment.isProtectedContentReady)
        XCTAssertFalse(environment.isBiometricUnlockRequired)
    }
}
