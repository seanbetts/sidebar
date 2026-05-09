import SwiftUI
import sideBarShared

private enum WorkspaceRestorationApplicationGate {
    @MainActor static var isApplyingWorkspaceRestoration = false
}

extension ContentView {
    static var isApplyingWorkspaceRestoration: Bool {
        get { WorkspaceRestorationApplicationGate.isApplyingWorkspaceRestoration }
        set { WorkspaceRestorationApplicationGate.isApplyingWorkspaceRestoration = newValue }
    }

    var currentRestorationUserId: String? {
        environment.container.authSession.userId
    }

    var hasMeaningfulChatDraftForRestoration: Bool {
        !environment.chatViewModel.draftText.trimmed.isEmpty
            || !environment.chatViewModel.attachments.isEmpty
    }

    func saveCurrentWorkspaceRestorationSnapshot() {
        guard !Self.isApplyingWorkspaceRestoration else { return }
        guard environment.isAuthenticated else { return }

        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        let snapshot: DeviceWorkspaceSnapshot
        switch family {
        case .phone:
            snapshot = DeviceWorkspaceSnapshot(
                schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
                userId: currentRestorationUserId,
                family: .phone,
                updatedAt: Date(),
                phoneRoute: currentPhoneWorkspaceRoute(),
                splitWorkspace: nil
            )
        case .workspace:
            snapshot = DeviceWorkspaceSnapshot(
                schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
                userId: currentRestorationUserId,
                family: .workspace,
                updatedAt: Date(),
                phoneRoute: nil,
                splitWorkspace: currentSplitWorkspaceSnapshot()
            )
        }
        environment.workspaceRestorationStore.save(snapshot)
    }

    func currentPhoneWorkspaceRoute() -> PhoneWorkspaceRoute {
        WorkspaceRestorationPlanner.makePhoneRoute(
            section: compactWorkspaceSection,
            selectedConversationId: environment.chatViewModel.selectedConversationId,
            isDraftConversationActive: environment.chatViewModel.isDraftConversationActive,
            hasMeaningfulChatDraft: hasMeaningfulChatDraftForRestoration,
            selectedNoteId: environment.notesRuntime.viewModel.selectedNoteId,
            selectedTaskRouteId: environment.tasksPhoneDetailRouteId,
            selectedWebsiteId: environment.websitesViewModel.selectedWebsiteId,
            selectedFileId: environment.ingestionViewModel.selectedFileId
        )
    }

    func currentSplitWorkspaceSnapshot() -> SplitWorkspaceSnapshot {
        SplitWorkspaceSnapshot(
            sidebarSelection: sidebarSelection,
            primaryDescriptor: WorkspaceDescriptorSnapshot(
                descriptor: primaryWorkspaceDescriptor
            ),
            secondaryDescriptor: WorkspaceDescriptorSnapshot(
                descriptor: secondaryWorkspaceDescriptor
            ),
            focusedPane: environment.focusedWorkspacePane ?? .primary,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded
        )
    }

    var shouldSkipWorkspaceRestoration: Bool {
        WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: environment.commandSelection,
            hasQueuedProtectedDeepLinks: !environment.queuedProtectedDeepLinks.isEmpty,
            hasPendingNewTaskDeepLink: environment.pendingNewTaskDeepLink,
            hasPendingNewNoteDeepLink: environment.pendingNewNoteDeepLink,
            hasPendingScratchpadDeepLink: environment.pendingScratchpadDeepLink,
            hasPendingMorningDigestDeepLink: environment.pendingMorningDigestDeepLink
        )
    }

    func applyInitialLaunchDestinationIfAvailable() async -> Bool {
        guard environment.authState == .active else { return false }
        guard environment.isProtectedContentReady else { return false }
        guard !shouldSkipWorkspaceRestoration else { return false }

        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        let snapshot = environment.workspaceRestorationStore.load(
            family: family,
            expectedUserId: currentRestorationUserId
        )
        let todayDateKey = TasksUtils.formatDateKey(Date())
        await environment.tasksViewModel.loadCounts(force: false)
        let todayTaskCount = environment.tasksViewModel.counts?.counts.today ?? 0
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: todayTaskCount,
            hasOpenedDueToday: environment.workspaceRestorationStore.hasDueTodayAutoOpened(
                userId: currentRestorationUserId,
                localDateKey: todayDateKey
            ),
            hasRestorationSnapshot: snapshot != nil
        )

        switch destination {
        case .externalIntent, .fallbackChat:
            return false
        case .dueTodayTasks:
            Self.isApplyingWorkspaceRestoration = true
            defer { Self.isApplyingWorkspaceRestoration = false }
            await applyDueTodayTasksLaunchOverride(localDateKey: todayDateKey)
            return true
        case .restoredSnapshot:
            guard let snapshot else { return false }
            Self.isApplyingWorkspaceRestoration = true
            defer { Self.isApplyingWorkspaceRestoration = false }
            return applyRestoredWorkspace(snapshot)
        }
    }

    func applyRestoredWorkspace(_ snapshot: DeviceWorkspaceSnapshot) -> Bool {
        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        switch family {
        case .phone:
            guard let route = snapshot.phoneRoute else { return false }
            applyPhoneRestoration(route)
            return true
        case .workspace:
            guard let splitWorkspace = snapshot.splitWorkspace else { return false }
            applySplitWorkspaceRestoration(splitWorkspace)
            return true
        }
    }

    func applyDueTodayTasksLaunchOverride(localDateKey: String) async {
        environment.workspaceRestorationStore.recordDueTodayAutoOpen(
            userId: currentRestorationUserId,
            localDateKey: localDateKey
        )
        await environment.tasksViewModel.load(selection: .today, force: true)
        #if os(iOS)
        if isPhoneIdiom {
            phoneSelection = .tasks
            sidebarSelection = .tasks
            environment.tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
            environment.workspaceStore.dispatch(.setLayout(.compact), source: "due_today_launch_override")
            environment.workspaceStore.dispatch(.selectSection(.tasks), source: "due_today_launch_override")
            return
        }
        #endif
        sidebarSelection = .tasks
        isLeftPanelExpanded = true
        isWorkspaceExpanded = false
        environment.focusedWorkspacePane = .primary
        environment.workspaceStore.dispatch(.setLayout(.split), source: "due_today_launch_override")
        environment.workspaceStore.dispatch(.setPrimaryContent(.builtIn(.tasks)), source: "due_today_launch_override")
        environment.workspaceStore.dispatch(.setSecondaryContent(.builtIn(.chat)), source: "due_today_launch_override")
        environment.workspaceStore.dispatch(.selectSection(.tasks), source: "due_today_launch_override")
    }

    func applyPhoneRestoration(_ route: PhoneWorkspaceRoute) {
        let plan = WorkspaceRestorationPlanner.makePhonePlan(
            route: route,
            hasMeaningfulChatDraft: hasMeaningfulChatDraftForRestoration
        )
        phoneSelection = plan.section
        sidebarSelection = plan.section
        environment.workspaceStore.dispatch(.setLayout(.compact), source: "workspace_restoration")
        environment.workspaceStore.dispatch(.selectSection(plan.section), source: "workspace_restoration")
        applyPhoneRestorationDetail(plan.detail)
    }

    func applyPhoneRestorationDetail(_ detail: PhoneWorkspaceDetail?) {
        switch detail {
        case .conversation(let id):
            Task { await environment.chatViewModel.selectConversation(id: id) }
        case .chatDraft:
            Task { await environment.chatViewModel.openDraftConversation() }
        case .note(let id):
            environment.notesPhoneDetailRouteId = id
            Task { await environment.notesViewModel.loadNote(id: id) }
        case .taskRoute(let id):
            environment.tasksPhoneDetailRouteId = id
        case .website(let id):
            Task { await environment.websitesViewModel.selectWebsite(id: id) }
        case .file(let id):
            Task { _ = await environment.ingestionViewModel.selectFile(fileId: id) }
        case nil:
            break
        }
    }

    func applySplitWorkspaceRestoration(_ snapshot: SplitWorkspaceSnapshot) {
        let plan = WorkspaceRestorationPlanner.makeWorkspacePlan(snapshot: snapshot)
        sidebarSelection = plan.sidebarSelection
        isLeftPanelExpanded = plan.isLeftPanelExpanded
        isWorkspaceExpanded = plan.isWorkspaceExpanded
        environment.focusedWorkspacePane = plan.focusedPane
        environment.workspaceStore.dispatch(.setLayout(.split), source: "workspace_restoration")
        environment.workspaceStore.dispatch(
            .setPrimaryContent(plan.primaryDescriptor),
            source: "workspace_restoration"
        )
        environment.workspaceStore.dispatch(
            .setSecondaryContent(plan.secondaryDescriptor),
            source: "workspace_restoration"
        )
        environment.workspaceStore.dispatch(
            .selectSection(plan.sidebarSelection),
            source: "workspace_restoration"
        )
    }
}
