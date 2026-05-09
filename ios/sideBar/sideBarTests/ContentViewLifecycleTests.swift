// swiftlint:disable file_length

import XCTest
@testable import sideBar

@MainActor
// swiftlint:disable:next type_body_length
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

    func testMakeInitialPhoneChatActionDoesNotOpenDraftWithoutRestoredDraft() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: nil
        )
        XCTAssertEqual(action, .none)
    }

    func testMakeInitialPhoneChatActionDoesNothingWhenConversationIsSelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: "conversation-1"
        )
        XCTAssertEqual(action, .none)
    }

    func testMakeMacInitialSelectionPlanStillDefaultsToChatWithoutSnapshot() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: nil)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.sidebarSelection, .chat)
    }

    func testWorkspaceRestorationPlannerSkipsRestorationForPendingDeepLink() {
        XCTAssertTrue(WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: nil,
            hasQueuedProtectedDeepLinks: true,
            hasPendingNewTaskDeepLink: false,
            hasPendingNewNoteDeepLink: false,
            hasPendingScratchpadDeepLink: false,
            hasPendingMorningDigestDeepLink: false
        ))
    }

    func testInitialLaunchDestinationUsesDueTodayBeforeRestoration() {
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: 1,
            hasOpenedDueToday: false,
            hasRestorationSnapshot: true
        )

        XCTAssertEqual(destination, .dueTodayTasks)
    }

    func testWorkspaceRestorationSaveSuppressionSkipsActiveAndQueuedLaunchSaves() {
        var policy = RestorationSaveSuppressionPolicy(
            isApplying: false,
            queuedSaveSuppressions: 0
        )

        policy.beginLaunchApplication()

        XCTAssertTrue(policy.shouldSuppressSave())
        policy.finishLaunchApplication()
        XCTAssertTrue(policy.shouldSuppressSave())
        XCTAssertTrue(policy.shouldSuppressSave())

        policy.clearQueuedSuppressions()

        XCTAssertFalse(policy.shouldSuppressSave())
    }

    func testFreshLaunchTaskCountTreatsUnchangedCachedCountsAsUnknown() {
        let previous = TaskCountsResponse(
            generatedAt: "2026-05-09T10:00:00Z",
            counts: TaskCounts(today: 3, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        let current = TaskCountsResponse(
            generatedAt: "2026-05-09T10:00:00Z",
            counts: TaskCounts(today: 3, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )

        XCTAssertEqual(
            WorkspaceRestorationPlanner.freshTodayTaskCountForLaunch(
                previousCounts: previous,
                currentCounts: current,
                errorMessage: nil
            ),
            0
        )
    }

    func testFreshLaunchTaskCountUsesFreshCounts() {
        let previous = TaskCountsResponse(
            generatedAt: "2026-05-09T10:00:00Z",
            counts: TaskCounts(today: 0, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        let current = TaskCountsResponse(
            generatedAt: "2026-05-09T10:00:01Z",
            counts: TaskCounts(today: 2, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )

        XCTAssertEqual(
            WorkspaceRestorationPlanner.freshTodayTaskCountForLaunch(
                previousCounts: previous,
                currentCounts: current,
                errorMessage: nil
            ),
            2
        )
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

    func testUpdateActiveSectionNotifiesRefreshCoordinator() throws {
        let normalized = try contentViewLifecycleSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Task{awaitenvironment.refreshVisibleSectionChange(to:section)}"))
    }

    func testTasksViewDoesNotOwnScenePhaseRefresh() throws {
        let normalized = try tasksViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let forcedSelectionLoad =
            "awaitenvironment.tasksViewModel.load(selection:environment.tasksViewModel.preferredLoadSelection,force:true)"

        XCTAssertFalse(normalized.contains("@Environment(\\.scenePhase)privatevarscenePhase"))
        XCTAssertFalse(normalized.contains(".onChange(of:scenePhase)"))
        XCTAssertFalse(normalized.contains(forcedSelectionLoad))
        XCTAssertFalse(normalized.contains("awaitenvironment.tasksViewModel.loadCounts(force:true)"))
    }

    func testWebsitesViewDoesNotOwnLaunchOrForegroundRefresh() throws {
        let normalized = try websitesViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("@Environment(\\.scenePhase)privatevarscenePhase"))
        XCTAssertFalse(normalized.contains(".task{awaitenvironment.websitesViewModel.load(force:true)}"))
        XCTAssertFalse(normalized.contains(".onChange(of:scenePhase)"))
        XCTAssertFalse(normalized.contains("awaitenvironment.websitesViewModel.load(force:true)"))
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

    func testSignedInBackgroundContinuationPlanSchedulesWebsiteQueueAndWidgetRefreshWhenAuthenticated() {
        let plan = ContentView.signedInBackgroundContinuationPlan(
            isAuthenticated: true,
            pendingWriteCount: 0
        )

        XCTAssertTrue(plan.shouldScheduleWidgetRefresh)
        XCTAssertFalse(plan.shouldScheduleWriteQueueFlush)
        XCTAssertTrue(plan.shouldNotifyWebsiteQueueCoordinator)
    }

    func testSignedInBackgroundContinuationPlanSchedulesWriteQueueFlushWhenPendingWritesExist() {
        let plan = ContentView.signedInBackgroundContinuationPlan(
            isAuthenticated: true,
            pendingWriteCount: 2
        )

        XCTAssertTrue(plan.shouldScheduleWidgetRefresh)
        XCTAssertTrue(plan.shouldScheduleWriteQueueFlush)
        XCTAssertTrue(plan.shouldNotifyWebsiteQueueCoordinator)
    }

    func testSignedInBackgroundContinuationPlanDoesNothingWhenSignedOut() {
        let plan = ContentView.signedInBackgroundContinuationPlan(
            isAuthenticated: false,
            pendingWriteCount: 3
        )

        XCTAssertFalse(plan.shouldScheduleWidgetRefresh)
        XCTAssertFalse(plan.shouldScheduleWriteQueueFlush)
        XCTAssertFalse(plan.shouldNotifyWebsiteQueueCoordinator)
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

    func testInitialSelectionAttemptsLaunchDestinationBeforeDefaultSelection() throws {
        let normalized = try contentViewLifecycleSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("letreadiness=initialSelectionReadinessPlan()"))
        XCTAssertTrue(normalized.contains("didSetInitialSelection=readiness.didSetInitialSelection"))
        XCTAssertTrue(normalized.contains("ifawaitapplyInitialLaunchDestinationIfAvailable()"))
        XCTAssertTrue(normalized.contains("applyDefaultInitialSelection()"))
    }

    func testInitialSelectionReadinessDoesNotConsumeAttemptBeforeProtectedContentIsReady() {
        var didSetInitialSelection = false
        let blocked = InitialSelectionReadinessPlan.resolve(
            authState: .active,
            isProtectedContentReady: false,
            didSetInitialSelection: didSetInitialSelection
        )
        XCTAssertFalse(blocked.shouldProceed)
        XCTAssertFalse(blocked.didSetInitialSelection)

        didSetInitialSelection = blocked.didSetInitialSelection
        let ready = InitialSelectionReadinessPlan.resolve(
            authState: .active,
            isProtectedContentReady: true,
            didSetInitialSelection: didSetInitialSelection
        )
        XCTAssertTrue(ready.shouldProceed)
        XCTAssertTrue(ready.didSetInitialSelection)
    }

    func testDefaultInitialSelectionDoesNotEnsureInitialPhoneChatInterface() throws {
        let source = try contentViewLifecycleSource()
        let helperBody = try XCTUnwrap(
            source.range(of: "func applyDefaultInitialSelection()")
                .flatMap { startRange in
                    source.range(of: "func updateActiveSection()", range: startRange.upperBound..<source.endIndex)
                        .map { endRange in String(source[startRange.lowerBound..<endRange.lowerBound]) }
                }
        )

        XCTAssertFalse(helperBody.contains("ensureInitialPhoneChatInterfaceIfNeeded"))
    }

    func testWorkspaceRestorationApplicationIsGatedFromSnapshotSaves() throws {
        let normalized = try contentViewWorkspaceRestorationSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("staticvarisApplyingWorkspaceRestoration"))
        XCTAssertTrue(normalized.contains("policy.shouldSuppressSave()"))
        XCTAssertTrue(normalized.contains("isApplying=true"))
        XCTAssertTrue(normalized.contains("pendingWorkspaceRestorationSaveSuppressions"))
    }

    private func contentViewLifecycleSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("ContentView+Lifecycle.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ContentView+Lifecycle.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func tasksViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Tasks")
            .appendingPathComponent("TasksView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read TasksView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func websitesViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Websites")
            .appendingPathComponent("WebsitesView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read WebsitesView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func contentViewWorkspaceRestorationSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("ContentView+WorkspaceRestoration.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail(
                "Failed to read ContentView+WorkspaceRestoration.swift: \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }

}
