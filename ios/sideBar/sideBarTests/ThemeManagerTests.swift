import XCTest
import sideBarShared
@testable import sideBar

final class ThemeManagerTests: XCTestCase {
    private let suiteName = "ThemeManagerTests"
    private static var retained: [ThemeManager] = []

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToSystemWhenUnset() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = ThemeManager(userDefaults: defaults)
        Self.retained.append(manager)
        XCTAssertEqual(manager.mode, .system)
    }

    func testPersistsModeChange() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = ThemeManager(userDefaults: defaults)
        Self.retained.append(manager)
        manager.mode = .dark

        let stored = defaults.string(forKey: AppStorageKeys.themeMode)
        XCTAssertEqual(stored, ThemeMode.dark.rawValue)
    }
}
