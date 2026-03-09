import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class NavigationStateTests: XCTestCase {
    private var isolatedDefaults: TestIsolation.IsolatedUserDefaults!

    override func setUp() {
        super.setUp()
        isolatedDefaults = TestIsolation.makeUserDefaults(prefix: "NavigationStateTests")
    }

    override func tearDown() {
        isolatedDefaults?.tearDown()
        isolatedDefaults = nil
        super.tearDown()
    }

    func testLastSectionReadsFromStorage() async {
        isolatedDefaults.defaults.set(AppSection.notes.rawValue, forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState(userDefaults: isolatedDefaults.defaults)

        XCTAssertEqual(state.lastSection, .notes)
    }

    func testLastSectionFallsBackToChat() async {
        isolatedDefaults.defaults.set("invalid", forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState(userDefaults: isolatedDefaults.defaults)

        XCTAssertEqual(state.lastSection, .chat)
    }

    func testSidebarWidthPersists() async {
        isolatedDefaults.defaults.set(420.0, forKey: AppStorageKeys.sidebarWidth)

        let state = NavigationState(userDefaults: isolatedDefaults.defaults)

        XCTAssertEqual(state.sidebarWidth, 420.0)
    }
}
