import XCTest
@testable import sideBar

@MainActor
final class NavigationStateTests: XCTestCase {
    private var previousSection: String?
    private var previousWidth: Double?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        previousSection = defaults.string(forKey: AppStorageKeys.lastSelectedSection)
        previousWidth = defaults.object(forKey: AppStorageKeys.sidebarWidth) as? Double
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let previousSection {
            defaults.set(previousSection, forKey: AppStorageKeys.lastSelectedSection)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.lastSelectedSection)
        }
        if let previousWidth {
            defaults.set(previousWidth, forKey: AppStorageKeys.sidebarWidth)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.sidebarWidth)
        }
        super.tearDown()
    }

    func testLastSectionReadsFromStorage() {
        UserDefaults.standard.set(AppSection.notes.rawValue, forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState()

        XCTAssertEqual(state.lastSection, .notes)
    }

    func testLastSectionFallsBackToChat() {
        UserDefaults.standard.set("invalid", forKey: AppStorageKeys.lastSelectedSection)

        let state = NavigationState()

        XCTAssertEqual(state.lastSection, .chat)
    }

    func testSidebarWidthPersists() {
        UserDefaults.standard.set(420.0, forKey: AppStorageKeys.sidebarWidth)

        let state = NavigationState()

        XCTAssertEqual(state.sidebarWidth, 420.0)
    }
}
