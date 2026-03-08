import XCTest
@testable import sideBar

@MainActor
final class ContentViewLifecycleTests: XCTestCase {
    func testCompactPhoneBottomTabSectionsUseMoreAsFinalTab() {
        let sections = ContentView.compactPhoneBottomTabSections

        XCTAssertEqual(sections, [.chat, .notes, .tasks, .websites])
    }

    func testCompactPhoneOverflowSectionsIncludeFilesAndSkillsStore() {
        let sections = ContentView.compactPhoneOverflowSections

        XCTAssertEqual(sections, [.files, .skillsStore])
    }

    func testCompactPhoneMoreTabUsesPlainEllipsisIcon() {
        let iconName = ContentView.compactPhoneTabIconName(
            for: .more,
            phoneIconName: { _ in "unused" }
        )

        XCTAssertEqual(iconName, "ellipsis")
    }

    func testCompactPhoneMoreHeaderShowsSettingsAvatarInCompactLayout() {
        let shouldShow = ContentView.shouldShowCompactPhoneMoreSettingsAvatar(
            isCompact: true
        )

        XCTAssertTrue(shouldShow)
    }

    func testCompactPhoneMoreHeaderHidesSettingsAvatarOutsideCompactLayout() {
        let shouldShow = ContentView.shouldShowCompactPhoneMoreSettingsAvatar(
            isCompact: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldShowGlobalTopSafeAreaOverlayDisablesForCompactIPhone() {
        let shouldShow = ContentView.shouldShowGlobalTopSafeAreaOverlay(
            isCompact: true,
            isPhoneIdiom: true
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldShowGlobalTopSafeAreaOverlayKeepsOverlayForRegularIPadLayout() {
        let shouldShow = ContentView.shouldShowGlobalTopSafeAreaOverlay(
            isCompact: false,
            isPhoneIdiom: false
        )

        XCTAssertTrue(shouldShow)
    }

    func testCompactPhoneRootTopSafeAreaStyleUsesPanelChromeForChat() {
        let style = ContentView.compactPhoneRootTopSafeAreaStyle(for: .chat)

        XCTAssertEqual(style, .panelChrome)
    }

    func testCompactPhoneRootTopSafeAreaStyleUsesSettingsChromeForSettings() {
        let style = ContentView.compactPhoneRootTopSafeAreaStyle(for: .settings)

        XCTAssertEqual(style, .settingsChrome)
    }

    func testCompactPhoneRootTopSafeAreaStyleUsesPanelChromeForSkillsStore() {
        let style = ContentView.compactPhoneRootTopSafeAreaStyle(for: .skillsStore)

        XCTAssertEqual(style, .panelChrome)
    }

    func testCompactPhonePanelBackgroundStyleUsesSidebarForChat() {
        let style = ContentView.compactPhonePanelBackgroundStyle(for: .chat)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhonePanelBackgroundStyleUsesSidebarForSkillsStore() {
        let style = ContentView.compactPhonePanelBackgroundStyle(for: .skillsStore)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhonePanelBackgroundStyleUsesSettingsBackgroundForSettings() {
        let style = ContentView.compactPhonePanelBackgroundStyle(for: .settings)

        XCTAssertEqual(style, .settings)
    }

    func testCompactPhoneMoreRootUsesSidebarBackgroundStyle() {
        let style = ContentView.compactPhoneMoreRootBackgroundStyle()

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhoneMoreRootUsesPanelChromeTopSafeAreaStyle() {
        let style = ContentView.compactPhoneMoreRootTopSafeAreaStyle()

        XCTAssertEqual(style, .panelChrome)
    }

    func testCompactPhoneMoreDestinationBackgroundStyleUsesSidebarForFiles() {
        let style = ContentView.compactPhoneMoreDestinationBackgroundStyle(for: .files)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhoneMoreDestinationBackgroundStyleUsesSidebarForSkillsStore() {
        let style = ContentView.compactPhoneMoreDestinationBackgroundStyle(for: .skillsStore)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhoneMoreDestinationTopSafeAreaStyleUsesSidebarForFiles() {
        let style = ContentView.compactPhoneMoreDestinationTopSafeAreaStyle(for: .files)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhoneMoreDestinationTopSafeAreaStyleUsesSidebarForSkillsStore() {
        let style = ContentView.compactPhoneMoreDestinationTopSafeAreaStyle(for: .skillsStore)

        XCTAssertEqual(style, .sidebar)
    }

    func testCompactPhoneMoreDestinationNavigationBarAppearanceUsesOpaqueSidebarForFiles() {
        let style = ContentView.compactPhoneMoreDestinationNavigationBarAppearanceStyle(for: .files)

        XCTAssertEqual(style.backgroundStyle, .sidebar)
        XCTAssertTrue(style.isOpaque)
    }

    func testCompactPhoneMoreDestinationNavigationBarAppearanceUsesOpaqueSidebarForSkillsStore() {
        let style = ContentView.compactPhoneMoreDestinationNavigationBarAppearanceStyle(for: .skillsStore)

        XCTAssertEqual(style.backgroundStyle, .sidebar)
        XCTAssertTrue(style.isOpaque)
    }

    func testCompactPhoneMoreDestinationUsesDedicatedScaffoldForFiles() {
        let usesDedicatedScaffold = ContentView.compactPhoneMoreDestinationUsesDedicatedScaffold(for: .files)

        XCTAssertTrue(usesDedicatedScaffold)
    }

    func testCompactPhoneMoreDestinationUsesDedicatedScaffoldForSkillsStore() {
        let usesDedicatedScaffold = ContentView.compactPhoneMoreDestinationUsesDedicatedScaffold(for: .skillsStore)

        XCTAssertTrue(usesDedicatedScaffold)
    }

    func testCompactPhoneMoreDestinationDoesNotUseDedicatedScaffoldForWebsites() {
        let usesDedicatedScaffold = ContentView.compactPhoneMoreDestinationUsesDedicatedScaffold(for: .websites)

        XCTAssertFalse(usesDedicatedScaffold)
    }

    func testMakeMacInitialSelectionPlanDefaultsToChatWithoutPendingSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: nil)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertNil(plan.focusedSection)
        XCTAssertFalse(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanUsesPendingNonChatSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .websites)

        XCTAssertEqual(plan.primarySection, .websites)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.lastNonChatSection, .websites)
        XCTAssertEqual(plan.sidebarSelection, .websites)
        XCTAssertEqual(plan.focusedSection, .websites)
        XCTAssertTrue(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanHandlesPendingChatSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .chat)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertEqual(plan.focusedSection, .chat)
        XCTAssertTrue(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanIgnoresPendingSettingsSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .settings)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertNil(plan.focusedSection)
        XCTAssertFalse(plan.shouldConsumeCommandSelection)
    }

    func testMakeInitialPhoneChatActionOpensDraftWhenConversationIsNotSelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: nil
        )

        XCTAssertEqual(action, .openDraftConversation)
    }

    func testMakeInitialPhoneChatActionDoesNothingWhenConversationIsSelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: "conversation-1"
        )

        XCTAssertEqual(action, .none)
    }

    func testMakeRegularLayoutPlanFromCompactSelectionForChat() {
        let plan = ContentView.makeRegularLayoutPlanFromCompactSelection(phoneSelection: .chat)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
    }

    func testMakeRegularLayoutPlanFromCompactSelectionForNonChatSection() {
        let plan = ContentView.makeRegularLayoutPlanFromCompactSelection(phoneSelection: .tasks)

        XCTAssertEqual(plan.primarySection, .tasks)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.lastNonChatSection, .tasks)
        XCTAssertEqual(plan.sidebarSelection, .tasks)
    }

    func testMakeDesktopSidebarSelectionPlanRoutesSkillsStoreToPrimaryWorkspace() {
        let plan = ContentView.makeDesktopSidebarSelectionPlan(
            currentPrimarySection: nil,
            currentSecondarySection: .chat,
            currentLastNonChatSection: nil,
            selectedSection: .skillsStore
        )

        XCTAssertEqual(plan.primarySection, .skillsStore)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.lastNonChatSection, .skillsStore)
    }

    func testMakeDesktopSidebarSelectionPlanResetsToChatWithoutDroppingLastNonChatSection() {
        let plan = ContentView.makeDesktopSidebarSelectionPlan(
            currentPrimarySection: .skillsStore,
            currentSecondarySection: .chat,
            currentLastNonChatSection: .skillsStore,
            selectedSection: .chat
        )

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.lastNonChatSection, .skillsStore)
    }

    func testMakeDesktopSidebarSelectionPlanUsesSecondaryWhenPrimaryIsChat() {
        let plan = ContentView.makeDesktopSidebarSelectionPlan(
            currentPrimarySection: .chat,
            currentSecondarySection: .tasks,
            currentLastNonChatSection: .tasks,
            selectedSection: .websites
        )

        XCTAssertEqual(plan.primarySection, .chat)
        XCTAssertEqual(plan.secondarySection, .websites)
        XCTAssertEqual(plan.lastNonChatSection, .websites)
    }

    func testShouldDisplayPhoneFloatingActionDockForPrimaryPhoneSectionPanelList() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .chat,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesInPhoneDetailWorkspace() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: false,
            phoneSelection: .notes,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockShowsInTasksDetailWorkspace() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: false,
            phoneSelection: .tasks,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesForNonPhone() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: false,
            isPhonePanelListVisible: true,
            phoneSelection: .tasks,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesOutsidePrimaryPhoneSections() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .settings,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesForSkillsStore() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .skillsStore,
            isCompactPhoneMoreRootVisible: false
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesOnCompactPhoneMoreRoot() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .chat,
            isCompactPhoneMoreRootVisible: true
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldAutoExpandChatSidebarWhenDesktopLayoutAndChatSelected() {
        let shouldExpand = ContentView.shouldAutoExpandChatSidebar(
            section: .chat,
            isDesktopLikeLayout: true
        )

        XCTAssertTrue(shouldExpand)
    }

    func testShouldAutoExpandChatSidebarWhenDesktopLayoutAndNonChatSelected() {
        let shouldExpand = ContentView.shouldAutoExpandChatSidebar(
            section: .tasks,
            isDesktopLikeLayout: true
        )

        XCTAssertFalse(shouldExpand)
    }

    func testShouldAutoExpandChatSidebarWhenNotDesktopLayout() {
        let shouldExpand = ContentView.shouldAutoExpandChatSidebar(
            section: .chat,
            isDesktopLikeLayout: false
        )

        XCTAssertFalse(shouldExpand)
    }

}
