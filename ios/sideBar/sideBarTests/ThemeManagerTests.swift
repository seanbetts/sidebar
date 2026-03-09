import XCTest
import sideBarShared
@testable import sideBar

final class ThemeManagerTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []
    private static var retainedManagers: [ThemeManager] = []

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testDefaultsToSystemWhenUnset() {
        let (manager, _) = makeThemeManager()
        XCTAssertEqual(manager.mode, .system)
    }

    func testPersistsModeChange() {
        let (manager, defaults) = makeThemeManager()
        manager.mode = .dark

        let stored = defaults.string(forKey: AppStorageKeys.themeMode)
        XCTAssertEqual(stored, ThemeMode.dark.rawValue)
    }

    func testFreshTestManagerStartsWithCleanDefaults() {
        let (firstManager, _) = makeThemeManager()
        firstManager.mode = .dark

        let (secondManager, _) = makeThemeManager()

        XCTAssertEqual(secondManager.mode, .system)
    }

    private func makeThemeManager() -> (ThemeManager, UserDefaults) {
        let isolated = TestIsolation.makeUserDefaults(prefix: "ThemeManagerTests")
        isolatedDefaults.append(isolated)
        let manager = ThemeManager(userDefaults: isolated.defaults)
        // Keep managers alive past the test method scope. On current macOS/XCTest
        // toolchains their deallocation can crash while the memory checker unwinds.
        Self.retainedManagers.append(manager)
        return (manager, isolated.defaults)
    }
}
