import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class NavigationStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NavigationStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLastSectionReadsFromStorage() async {
        defaults.set(AppSection.notes.rawValue, forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState(userDefaults: defaults)

        XCTAssertEqual(state.lastSection, .notes)
    }

    func testLastSectionFallsBackToChat() async {
        defaults.set("invalid", forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState(userDefaults: defaults)

        XCTAssertEqual(state.lastSection, .chat)
    }

    func testSidebarWidthPersists() async {
        defaults.set(420.0, forKey: AppStorageKeys.sidebarWidth)

        let state = NavigationState(userDefaults: defaults)

        XCTAssertEqual(state.sidebarWidth, 420.0)
    }
}
