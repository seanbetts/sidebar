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
        XCTAssertTrue(plan.isLeftPanelExpanded)
        XCTAssertFalse(plan.isWorkspaceExpanded)
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
        XCTAssertEqual(plan.isLeftPanelExpanded, snapshot.isLeftPanelExpanded)
        XCTAssertFalse(plan.isWorkspaceExpanded)
    }

    func testPhoneValidationFailurePlanFallsBackToSectionList() {
        let route = PhoneWorkspaceRoute(section: .notes, detail: .note(id: "missing"))

        let plan = WorkspaceRestorationPlanner.makePhoneValidationFailurePlan(
            route: route
        )

        XCTAssertEqual(plan, PhoneWorkspaceRestorationPlan(section: .notes, detail: nil))
    }

    func testWorkspaceValidationFailurePlanReplacesInvalidPrimaryFromSidebarSelection() {
        let snapshot = SplitWorkspaceSnapshot(
            sidebarSelection: .tasks,
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .builtIn(.chat),
            focusedPane: .primary,
            isLeftPanelExpanded: true,
            isWorkspaceExpanded: false
        )

        let plan = WorkspaceRestorationPlanner.makeWorkspaceValidationFailurePlan(
            snapshot: snapshot,
            invalidPane: .primary
        )

        XCTAssertEqual(plan.sidebarSelection, .tasks)
        XCTAssertEqual(plan.primaryDescriptor, .builtIn(.tasks))
        XCTAssertEqual(plan.secondaryDescriptor, .builtIn(.chat))
        XCTAssertEqual(plan.focusedPane, .primary)
        XCTAssertTrue(plan.isLeftPanelExpanded)
        XCTAssertFalse(plan.isWorkspaceExpanded)
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

    func testShouldSkipRestorationForQueuedProtectedDeepLinks() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: true,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testShouldSkipRestorationForPendingNewTaskDeepLink() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: false,
            hasPendingNewTaskDeepLink: true,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testShouldSkipRestorationForPendingNewNoteDeepLink() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: false,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: true,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testShouldSkipRestorationForPendingScratchpadDeepLink() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: false,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: true,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testShouldSkipRestorationForPendingMorningDigestDeepLink() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: false,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: true
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

    func testPhoneRouteOmitsEmptyChatDraft() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .chat,
            selectedConversationId: nil,
            isDraftConversationActive: true,
            hasMeaningfulChatDraft: false,
            selectedNoteId: nil,
            selectedTaskRouteId: nil,
            selectedWebsiteId: nil,
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .chat, detail: nil))
    }

    func testPhoneRouteIncludesMeaningfulChatDraft() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .chat,
            selectedConversationId: nil,
            isDraftConversationActive: true,
            hasMeaningfulChatDraft: true,
            selectedNoteId: nil,
            selectedTaskRouteId: nil,
            selectedWebsiteId: nil,
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .chat, detail: .chatDraft))
    }

    func testPhoneRouteIncludesSelectedConversation() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .chat,
            selectedConversationId: "conversation-1",
            isDraftConversationActive: true,
            hasMeaningfulChatDraft: true,
            selectedNoteId: nil,
            selectedTaskRouteId: nil,
            selectedWebsiteId: nil,
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .chat, detail: .conversation(id: "conversation-1")))
    }

    func testPhoneRouteIncludesSelectedNote() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .notes,
            selectedConversationId: nil,
            isDraftConversationActive: false,
            hasMeaningfulChatDraft: false,
            selectedNoteId: "note-1",
            selectedTaskRouteId: nil,
            selectedWebsiteId: nil,
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .notes, detail: .note(id: "note-1")))
    }

    func testPhoneRouteIncludesSelectedTaskRoute() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .tasks,
            selectedConversationId: nil,
            isDraftConversationActive: false,
            hasMeaningfulChatDraft: false,
            selectedNoteId: nil,
            selectedTaskRouteId: "today",
            selectedWebsiteId: nil,
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .tasks, detail: .taskRoute(id: "today")))
    }

    func testPhoneRouteIncludesSelectedWebsite() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .websites,
            selectedConversationId: nil,
            isDraftConversationActive: false,
            hasMeaningfulChatDraft: false,
            selectedNoteId: nil,
            selectedTaskRouteId: nil,
            selectedWebsiteId: "site-1",
            selectedFileId: nil
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .websites, detail: .website(id: "site-1")))
    }

    func testPhoneRouteIncludesSelectedFile() {
        let route = WorkspaceRestorationPlanner.makePhoneRoute(
            section: .files,
            selectedConversationId: nil,
            isDraftConversationActive: false,
            hasMeaningfulChatDraft: false,
            selectedNoteId: nil,
            selectedTaskRouteId: nil,
            selectedWebsiteId: nil,
            selectedFileId: "file-1"
        )

        XCTAssertEqual(route, PhoneWorkspaceRoute(section: .files, detail: .file(id: "file-1")))
    }

    func testWorkspaceRestorationSaveOnlyObserversSuppressInitialEmission() throws {
        let normalized = try contentViewSignedInSource().normalizedForSourceAssertions()
        let saveOnlyPublishers = [
            "environment.notesRuntime.viewModel.$selectedNoteId",
            "environment.ingestionViewModel.$selectedFileId",
            "environment.websitesViewModel.$selectedWebsiteId",
            "environment.chatViewModel.$selectedConversationId",
            "environment.chatViewModel.$isDraftConversationActive",
            "environment.chatViewModel.$draftText",
            "environment.chatViewModel.$attachments",
            "environment.navigation.$tasksPhoneDetailRouteId"
        ]

        for publisher in saveOnlyPublishers {
            XCTAssertTrue(normalized.contains("\(publisher).dropFirst().removeDuplicates().map{_in()}.eraseToAnyPublisher()"))
        }
        XCTAssertTrue(normalized.contains(".onReceive(workspaceRestorationSaveTriggers){_insaveCurrentWorkspaceRestorationSnapshot()}"))
    }

    func testWorkspaceRestorationSavesFocusedPaneChanges() throws {
        let normalized = try contentViewSignedInSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains(
            "environment.navigation.$focusedWorkspacePane.dropFirst().removeDuplicates().map{_in()}.eraseToAnyPublisher()"
        ))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func contentViewSignedInSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let sourceURL = sideBarRoot
        .appendingPathComponent("Views")
        .appendingPathComponent("ContentView+SignedIn.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ContentView+SignedIn.swift: \(error)", file: file, line: line)
        throw error
    }
}
