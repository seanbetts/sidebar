import XCTest
@testable import sideBar

@MainActor
final class CompactPhoneSearchDockTests: XCTestCase {
    func testCompactPhoneDockButtonsUseFortyFourPointTapTargets() {
        XCTAssertEqual(PhoneFloatingActionMetrics.buttonSize, 44)
    }

    func testCompactPhoneDockMetricsUseDesignTokens() throws {
        XCTAssertEqual(PhoneFloatingActionMetrics.buttonSize, DesignTokens.Size.touchTarget)
        XCTAssertEqual(PhoneFloatingActionMetrics.contentSpacing, DesignTokens.Spacing.xxsPlus)

        let normalized = try phoneFloatingActionDockSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("staticletbuttonSize:CGFloat=DesignTokens.Size.touchTarget"))
        XCTAssertTrue(normalized.contains("staticletcontentSpacing:CGFloat=DesignTokens.Spacing.xxsPlus"))
        XCTAssertTrue(normalized.contains(".frame(width:1,height:DesignTokens.Spacing.sm)"))
        XCTAssertFalse(normalized.contains("staticletbuttonSize:CGFloat=44"))
        XCTAssertFalse(normalized.contains("staticletcontentSpacing:CGFloat=6"))
        XCTAssertFalse(normalized.contains(".frame(width:1,height:12)"))
    }

    func testCompactPhoneDockIconsUseAppIconVocabulary() throws {
        let dockSource = try normalizedSource("sideBar/Design/Components/PhoneFloatingActionDock.swift")
        let searchDockSource = try normalizedSource("sideBar/Views/ContentView+CompactPhoneSearchDock.swift")
        let layoutSource = try normalizedSource("sideBar/Views/ContentView+Layout.swift")
        let taskDockSource = try normalizedSource("sideBar/Views/Tasks/TasksDetailView+FloatingDock.swift")

        XCTAssertTrue(dockSource.contains("leticon:AppIcon"))
        XCTAssertTrue(dockSource.contains("Image(appIcon:icon)"))
        XCTAssertFalse(dockSource.contains("letsystemName:String"))
        XCTAssertFalse(dockSource.contains("Image(systemName:systemName)"))

        XCTAssertTrue(searchDockSource.contains("Image(appIcon:AppIcon.Action.search)"))
        XCTAssertTrue(searchDockSource.contains("PhoneFloatingActionButton(icon:AppIcon.Action.add"))
        XCTAssertTrue(searchDockSource.contains("PhoneFloatingActionButton(icon:AppIcon.Content.folder"))
        XCTAssertTrue(searchDockSource.contains("PhoneFloatingActionButton(icon:AppIcon.Media.video"))
        XCTAssertTrue(searchDockSource.contains("Label(\"Addfolder\",systemImage:AppIcon.Content.folder.rawValue)"))
        XCTAssertTrue(searchDockSource.contains("Label(\"Newtask\",systemImage:AppIcon.State.successCircle.rawValue)"))
        XCTAssertTrue(searchDockSource.contains("Label(\"Newproject\",systemImage:AppIcon.Content.taskList.rawValue)"))
        XCTAssertFalse(searchDockSource.contains("Image(systemName:\"magnifyingglass\")"))
        XCTAssertFalse(searchDockSource.contains("Image(systemName:\"plus\")"))
        XCTAssertFalse(searchDockSource.contains("systemName:\"plus\""))
        XCTAssertFalse(searchDockSource.contains("systemName:\"folder\""))
        XCTAssertFalse(searchDockSource.contains("systemName:\"play.rectangle\""))
        XCTAssertFalse(searchDockSource.contains("systemImage:\"plus\""))
        XCTAssertFalse(searchDockSource.contains("systemImage:\"folder\""))
        XCTAssertFalse(searchDockSource.contains("systemImage:\"checkmark.circle\""))
        XCTAssertFalse(searchDockSource.contains("systemImage:\"list.bullet.rectangle\""))
        XCTAssertFalse(searchDockSource.contains("systemImage:\"play.rectangle\""))

        XCTAssertTrue(layoutSource.contains("PhoneFloatingActionButton(icon:AppIcon.Action.add"))
        XCTAssertTrue(layoutSource.contains("PhoneFloatingActionButton(icon:AppIcon.Content.folder"))
        XCTAssertTrue(layoutSource.contains("PhoneFloatingActionButton(icon:AppIcon.Media.video"))
        XCTAssertTrue(layoutSource.contains("Label(\"Newtask\",systemImage:AppIcon.State.successCircle.rawValue)"))
        XCTAssertTrue(layoutSource.contains("Label(\"Newgroup\",systemImage:AppIcon.Content.folder.rawValue)"))
        XCTAssertTrue(layoutSource.contains("Label(\"Newproject\",systemImage:AppIcon.Content.taskList.rawValue)"))
        XCTAssertFalse(layoutSource.contains("PhoneFloatingActionButton(systemName:"))
        XCTAssertFalse(layoutSource.contains("systemImage:\"checkmark.circle\""))
        XCTAssertFalse(layoutSource.contains("systemImage:\"folder\""))
        XCTAssertFalse(layoutSource.contains("systemImage:\"list.bullet.rectangle\""))
        XCTAssertFalse(layoutSource.contains("Image(systemName:\"plus\")"))

        XCTAssertTrue(taskDockSource.contains("PhoneFloatingActionButton(icon:AppIcon.Action.add"))
        XCTAssertFalse(taskDockSource.contains("systemName:AppIcon.Action.add.rawValue"))
    }

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
            isSoftwareKeyboardVisible: false,
            bottomSafeAreaInset: 0
        )

        XCTAssertEqual(padding, 72)
    }

    func testCompactPhoneSearchDockBottomPaddingAddsOnlyExtraTabBarClearanceWhenBottomSafeAreaExists() {
        let padding = ContentView.compactPhoneSearchDockBottomPadding(
            isSoftwareKeyboardVisible: false,
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 76)
    }

    func testCompactPhoneSearchDockBottomPaddingAttachesToKeyboardWhenVisible() {
        let padding = ContentView.compactPhoneSearchDockBottomPadding(
            isSoftwareKeyboardVisible: true,
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, DesignTokens.Spacing.sm)
    }

    func testShouldAttachCompactPhoneSearchDockToKeyboardIgnoresStaleKeyboardVisibilityWhenCollapsed() {
        let shouldAttach = ContentView.shouldAttachCompactPhoneSearchDockToKeyboard(
            isSoftwareKeyboardVisible: true,
            searchText: "",
            isSearchExplicitlyExpanded: false
        )

        XCTAssertFalse(shouldAttach)
    }

    func testShouldAttachCompactPhoneSearchDockToKeyboardWhenSearchIsExpanded() {
        let shouldAttach = ContentView.shouldAttachCompactPhoneSearchDockToKeyboard(
            isSoftwareKeyboardVisible: true,
            searchText: "",
            isSearchExplicitlyExpanded: true
        )

        XCTAssertTrue(shouldAttach)
    }

    func testShouldAttachCompactPhoneSearchDockToKeyboardWhenSearchQueryRemainsActive() {
        let shouldAttach = ContentView.shouldAttachCompactPhoneSearchDockToKeyboard(
            isSoftwareKeyboardVisible: true,
            searchText: "notes",
            isSearchExplicitlyExpanded: false
        )

        XCTAssertTrue(shouldAttach)
    }

    func testCompactPhoneSearchDockBottomPaddingFallsBackToTabClearanceForStaleKeyboardVisibility() {
        let padding = ContentView.compactPhoneSearchDockBottomPadding(
            isSoftwareKeyboardVisible: ContentView.shouldAttachCompactPhoneSearchDockToKeyboard(
                isSoftwareKeyboardVisible: true,
                searchText: "",
                isSearchExplicitlyExpanded: false
            ),
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 76)
    }

    func testShouldHandleCompactPhoneSearchDockBackgroundTapWhenExpandedOutsideMoreRoot() {
        let shouldHandle = ContentView.shouldHandleCompactPhoneSearchDockBackgroundTap(
            isSearchExplicitlyExpanded: true,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertTrue(shouldHandle)
    }

    func testShouldHandleCompactPhoneSearchDockBackgroundTapIgnoresMoreRoot() {
        let shouldHandle = ContentView.shouldHandleCompactPhoneSearchDockBackgroundTap(
            isSearchExplicitlyExpanded: true,
            isCompactPhoneMoreRootVisible: true
        )

        XCTAssertFalse(shouldHandle)
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

private func phoneFloatingActionDockSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("PhoneFloatingActionDock.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read PhoneFloatingActionDock.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func normalizedSource(
    _ path: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let sourceURL = sideBarRoot.appendingPathComponent(path)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    } catch {
        XCTFail("Failed to read \(path): \(error)", file: file, line: line)
        throw error
    }
}

private var sideBarRoot: URL {
    let fileURL = URL(fileURLWithPath: #filePath)
    return fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
