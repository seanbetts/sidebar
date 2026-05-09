import XCTest
@testable import sideBar

final class WorkspaceRestorationPlannerTests: XCTestCase {
    func testPhonePlanRestoresListRoute() {
        let route = PhoneWorkspaceRoute(section: .notes, detail: nil)

        let plan = WorkspaceRestorationPlanner.makePhonePlan(route: route)

        XCTAssertEqual(plan.section, .notes)
        XCTAssertNil(plan.detail)
        XCTAssertFalse(plan.shouldOpenEmptyChatDraft)
    }

    func testPhonePlanDoesNotRestoreEmptyChatDraft() {
        let route = PhoneWorkspaceRoute(section: .chat, detail: .chatDraft)

        let plan = WorkspaceRestorationPlanner.makePhonePlan(
            route: route,
            hasMeaningfulChatDraft: false
        )

        XCTAssertEqual(plan.section, .chat)
        XCTAssertNil(plan.detail)
        XCTAssertFalse(plan.shouldOpenEmptyChatDraft)
    }

    func testPhonePlanRestoresMeaningfulChatDraft() {
        let route = PhoneWorkspaceRoute(section: .chat, detail: .chatDraft)

        let plan = WorkspaceRestorationPlanner.makePhonePlan(
            route: route,
            hasMeaningfulChatDraft: true
        )

        XCTAssertEqual(plan.section, .chat)
        XCTAssertEqual(plan.detail, .chatDraft)
    }

    func testWorkspacePlanRestoresSplitSnapshot() {
        let snapshot = SplitWorkspaceSnapshot(
            sidebarSelection: .notes,
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .builtIn(.chat),
            focusedPane: .primary,
            isLeftPanelExpanded: true,
            isWorkspaceExpanded: false
        )

        let plan = WorkspaceRestorationPlanner.makeWorkspacePlan(snapshot: snapshot)

        XCTAssertEqual(plan.sidebarSelection, .notes)
        XCTAssertEqual(plan.primaryDescriptor, .builtIn(.notes))
        XCTAssertEqual(plan.secondaryDescriptor, .builtIn(.chat))
        XCTAssertEqual(plan.focusedPane, .primary)
    }

    func testWorkspacePlanFallsBackToChatWhenBothPanesAreEmpty() {
        let snapshot = SplitWorkspaceSnapshot(
            sidebarSelection: nil,
            primaryDescriptor: .empty,
            secondaryDescriptor: nil,
            focusedPane: .primary,
            isLeftPanelExpanded: false,
            isWorkspaceExpanded: true
        )

        let plan = WorkspaceRestorationPlanner.makeWorkspacePlan(snapshot: snapshot)

        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertEqual(plan.primaryDescriptor, .empty)
        XCTAssertEqual(plan.secondaryDescriptor, .builtIn(.chat))
        XCTAssertEqual(plan.focusedPane, .secondary)
    }

    func testShouldSkipRestorationForExternalIntent() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: .tasks,
            hasQueuedProtectedDeepLinks: false,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testInitialLaunchDestinationUsesExternalIntentFirst() {
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: true,
            todayTaskCount: 3,
            hasOpenedDueToday: false,
            hasRestorationSnapshot: true
        )

        XCTAssertEqual(destination, .externalIntent)
    }

    func testInitialLaunchDestinationUsesDueTodayBeforeRestoration() {
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: 2,
            hasOpenedDueToday: false,
            hasRestorationSnapshot: true
        )

        XCTAssertEqual(destination, .dueTodayTasks)
    }

    func testInitialLaunchDestinationUsesRestorationAfterDueTodayOpened() {
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: 2,
            hasOpenedDueToday: true,
            hasRestorationSnapshot: true
        )

        XCTAssertEqual(destination, .restoredSnapshot)
    }

    func testInitialLaunchDestinationFallsBackToChat() {
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: 0,
            hasOpenedDueToday: false,
            hasRestorationSnapshot: false
        )

        XCTAssertEqual(destination, .fallbackChat)
    }
}
