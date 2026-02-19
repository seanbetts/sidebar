import XCTest
@testable import sideBar

final class ContentViewLifecycleTests: XCTestCase {
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

    func testMakeInitialPhoneChatActionCreatesConversationWhenConversationIsNotSelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: nil
        )

        XCTAssertEqual(action, .createConversation)
    }

    func testMakeInitialPhoneChatActionCreatesConversationWhenConversationIsSelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: "conversation-1"
        )

        XCTAssertEqual(action, .createConversation)
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

    func testShouldDisplayPhoneFloatingActionDockForPrimaryPhoneSectionPanelList() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .chat
        )

        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesInPhoneDetailWorkspace() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: false,
            phoneSelection: .notes
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockShowsInTasksDetailWorkspace() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: false,
            phoneSelection: .tasks
        )

        XCTAssertTrue(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesForNonPhone() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: false,
            isPhonePanelListVisible: true,
            phoneSelection: .tasks
        )

        XCTAssertFalse(shouldShow)
    }

    func testShouldDisplayPhoneFloatingActionDockHidesOutsidePrimaryPhoneSections() {
        let shouldShow = ContentView.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: true,
            isPhonePanelListVisible: true,
            phoneSelection: .settings
        )

        XCTAssertFalse(shouldShow)
    }

    func testWorkspaceSidebarSwipePolicyCollapsesExpandedPanelOnLeftSwipe() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -120, height: 12),
            startX: 180,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .collapseLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyExpandsCollapsedPanelOnRightSwipe() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: 96, height: 10),
            startX: 24,
            regionWidth: 800,
            isLeftPanelExpanded: false,
            isIPad: true
        )

        XCTAssertEqual(action, .expandLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyExpandsRightSwipeWhenNotFromEdge() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: 96, height: 6),
            startX: 280,
            regionWidth: 800,
            isLeftPanelExpanded: false,
            isIPad: true
        )

        XCTAssertEqual(action, .expandLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyIgnoresMostlyVerticalSwipes() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -140, height: 140),
            startX: 200,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyDisablesSwipesWhenNotIPad() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -180, height: 10),
            startX: 180,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: false
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyIgnoresGesturesOutsideMainRegion() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -140, height: 8),
            startX: 920,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyCollapsesWhenSwipeStartsInSecondaryWorkspacePane() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -120, height: 8),
            startX: 920,
            regionWidth: 1100,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .collapseLeftPanel)
    }
}
