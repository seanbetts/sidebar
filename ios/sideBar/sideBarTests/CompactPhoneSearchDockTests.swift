import XCTest
@testable import sideBar

@MainActor
final class CompactPhoneSearchDockTests: XCTestCase {
    func testCompactPhoneBottomSearchSectionsIncludeFilesAndSkillsStore() {
        let sections = ContentView.compactPhoneBottomSearchSections
        XCTAssertEqual(
            sections,
            [.chat, .notes, .tasks, .websites, .files, .skillsStore]
        )
    }

    func testCompactPhoneSearchDockDescriptorsExistForSearchableSections() {
        let placeholders = ContentView.compactPhoneBottomSearchSections.compactMap {
            ContentView.compactPhoneSearchDockDescriptor(for: $0)?.placeholder
        }
        XCTAssertEqual(
            placeholders,
            ["Search chats", "Search notes", "Search tasks", "Search websites", "Search files", "Search skills"]
        )
    }

    func testCompactPhoneSearchDockDescriptorSupportsFilesFromMore() {
        let descriptor = ContentView.compactPhoneSearchDockDescriptor(for: .files)
        XCTAssertEqual(descriptor?.placeholder, "Search files")
    }

    func testCompactPhoneSearchDockDescriptorExcludesSettings() {
        let descriptor = ContentView.compactPhoneSearchDockDescriptor(for: .settings)
        XCTAssertNil(descriptor)
    }

    func testShouldShowCompactPhoneInlineSearchHidesOnCompactIPhone() {
        let shouldShow = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: true,
            isPhoneIdiom: true
        )
        XCTAssertFalse(shouldShow)
    }

    func testShouldShowCompactPhoneInlineSearchKeepsInlineSearchOffPhone() {
        let shouldShow = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: true,
            isPhoneIdiom: false
        )
        XCTAssertTrue(shouldShow)
    }

    func testShouldShowCompactPhoneInlineSearchKeepsInlineSearchInRegularLayout() {
        let shouldShow = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: false,
            isPhoneIdiom: true
        )
        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayCompactPhoneSearchDockForSearchableMoreDestinationRoot() {
        let shouldShow = ContentView.shouldDisplayCompactPhoneSearchDock(
            isCompact: true,
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .files,
            isCompactPhoneMoreRootVisible: false
        )
        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayCompactPhoneSearchDockHidesInDetailWorkspace() {
        let shouldShow = ContentView.shouldDisplayCompactPhoneSearchDock(
            isCompact: true,
            isPhoneIdiom: true,
            isPhonePanelListVisible: false,
            phoneSelection: .tasks,
            isCompactPhoneMoreRootVisible: false
        )
        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayCompactPhoneSearchDockHidesOnCompactPhoneMoreRoot() {
        let shouldShow = ContentView.shouldDisplayCompactPhoneSearchDock(
            isCompact: true,
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .chat,
            isCompactPhoneMoreRootVisible: true
        )
        XCTAssertFalse(shouldShow)
    }

    func testShouldResetCompactPhoneSearchDockWhenSwitchingSections() {
        let shouldReset = ContentView.shouldResetCompactPhoneSearchDock(
            previousSection: .chat,
            nextSection: .notes
        )

        XCTAssertTrue(shouldReset)
    }

    func testShouldResetCompactPhoneSearchDockWhenSectionIsUnchanged() {
        let shouldReset = ContentView.shouldResetCompactPhoneSearchDock(
            previousSection: .files,
            nextSection: .files
        )

        XCTAssertFalse(shouldReset)
    }

    func testCompactPhoneSearchDockBottomPaddingKeepsTabBarClearanceWhenKeyboardIsHidden() {
        let padding = ContentView.compactPhoneSearchDockBottomPadding(
            isSoftwareKeyboardVisible: false
        )

        XCTAssertEqual(padding, 72)
    }

    func testCompactPhoneSearchDockBottomPaddingAttachesToKeyboardWhenVisible() {
        let padding = ContentView.compactPhoneSearchDockBottomPadding(
            isSoftwareKeyboardVisible: true
        )

        XCTAssertEqual(padding, DesignTokens.Spacing.sm)
    }

    func testCompactPhoneSearchDockExpandedStateTracksFocusOrQuery() {
        let collapsed = ContentView.isCompactPhoneSearchDockExpanded(
            searchText: "",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: false
        )
        let expandedFromFocus = ContentView.isCompactPhoneSearchDockExpanded(
            searchText: "",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: true
        )
        let expandedFromQuery = ContentView.isCompactPhoneSearchDockExpanded(
            searchText: "notes",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: false
        )
        XCTAssertFalse(collapsed)
        XCTAssertTrue(expandedFromFocus)
        XCTAssertTrue(expandedFromQuery)
    }

    func testCompactPhoneSearchDockExpandedStateTracksExplicitExpansion() {
        let expanded = ContentView.isCompactPhoneSearchDockExpanded(
            searchText: "",
            isSearchExplicitlyExpanded: true,
            isSearchFocused: false
        )
        XCTAssertTrue(expanded)
    }

    func testCompactPhoneSearchDockCollapsesMultiActionSectionsOnlyWhenExpanded() {
        let collapsedState = ContentView.shouldCollapseCompactPhoneSearchDockActions(
            actionCount: 2,
            isSearchExpanded: false
        )
        let expandedMultiActionState = ContentView.shouldCollapseCompactPhoneSearchDockActions(
            actionCount: 2,
            isSearchExpanded: true
        )
        let expandedSingleActionState = ContentView.shouldCollapseCompactPhoneSearchDockActions(
            actionCount: 1,
            isSearchExpanded: true
        )
        XCTAssertFalse(collapsedState)
        XCTAssertTrue(expandedMultiActionState)
        XCTAssertFalse(expandedSingleActionState)
    }

    func testMakeCompactPhoneSearchDockDisplayModelShowsCollapsedMagnifyingGlassState() {
        let model = ContentView.makeCompactPhoneSearchDockDisplayModel(
            searchText: "",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: false,
            actionCount: 2
        )
        XCTAssertEqual(model.searchPresentation, .collapsedIcon)
        XCTAssertEqual(model.actionPresentation, .buttons)
    }

    func testMakeCompactPhoneSearchDockDisplayModelShowsExpandedSearchState() {
        let model = ContentView.makeCompactPhoneSearchDockDisplayModel(
            searchText: "",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: true,
            actionCount: 1
        )
        XCTAssertEqual(model.searchPresentation, .expandedField)
        XCTAssertEqual(model.actionPresentation, .buttons)
    }

    func testMakeCompactPhoneSearchDockDisplayModelCollapsesMultiActionSectionsWhileExpanded() {
        let model = ContentView.makeCompactPhoneSearchDockDisplayModel(
            searchText: "note",
            isSearchExplicitlyExpanded: false,
            isSearchFocused: false,
            actionCount: 2
        )
        XCTAssertEqual(model.searchPresentation, .expandedField)
        XCTAssertEqual(model.actionPresentation, .collapsedMenu)
    }

    func testMakeCompactPhoneSearchDockDisplayModelExpandsFieldFromExplicitExpansion() {
        let model = ContentView.makeCompactPhoneSearchDockDisplayModel(
            searchText: "",
            isSearchExplicitlyExpanded: true,
            isSearchFocused: false,
            actionCount: 2
        )
        XCTAssertEqual(model.searchPresentation, .expandedField)
        XCTAssertEqual(model.actionPresentation, .collapsedMenu)
    }
}
