import SwiftUI
import sideBarShared

extension ContentView {
    var saveSuppressionPolicy: RestorationSaveSuppressionPolicy {
        get {
            RestorationSaveSuppressionPolicy(
                isApplying: isApplyingWorkspaceRestoration,
                queuedSaveSuppressions: pendingWorkspaceRestorationSaveSuppressions
            )
        }
        nonmutating set {
            isApplyingWorkspaceRestoration = newValue.isApplying
            pendingWorkspaceRestorationSaveSuppressions = newValue.queuedSaveSuppressions
        }
    }

    var currentRestorationUserId: String? {
        environment.container.authSession.userId
    }

    var hasMeaningfulChatDraftForRestoration: Bool {
        !environment.chatViewModel.draftText.trimmed.isEmpty
            || !environment.chatViewModel.attachments.isEmpty
    }

    func saveCurrentWorkspaceRestorationSnapshot() {
        var policy = saveSuppressionPolicy
        guard !policy.shouldSuppressSave() else {
            saveSuppressionPolicy = policy
            return
        }
        saveSuppressionPolicy = policy
        guard environment.isAuthenticated else { return }

        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        let snapshot = WorkspaceRestorationPlanner.makeDeviceSnapshot(
            family: family,
            userId: currentRestorationUserId,
            phoneRoute: family == .phone ? currentPhoneWorkspaceRoute() : nil,
            splitWorkspace: family == .workspace ? currentSplitWorkspaceSnapshot() : nil,
            updatedAt: Date()
        )
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
        WorkspaceRestorationPlanner.makeSplitSnapshot(
            sidebarSelection: sidebarSelection,
            primaryDescriptor: primaryWorkspaceDescriptor,
            secondaryDescriptor: secondaryWorkspaceDescriptor,
            focusedPane: environment.focusedWorkspacePane,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded
        )
    }

    var shouldSkipWorkspaceRestoration: Bool {
        WorkspaceRestorationPlanner.shouldSkipRestorationForExternalIntent(
            commandSelection: environment.commandSelection,
            hasQueuedProtectedDeepLinks: !environment.queuedProtectedDeepLinks.isEmpty,
            hasPendingSidebarDeepLink: environment.pendingSidebarDeepLink != nil
        )
    }

    func initialSelectionReadinessPlan() -> InitialSelectionReadinessPlan {
        InitialSelectionReadinessPlan.resolve(
            authState: environment.authState,
            isProtectedContentReady: environment.isProtectedContentReady,
            didSetInitialSelection: didSetInitialSelection
        )
    }

    func applyWithWorkspaceRestorationSaveSuppression<T>(_ operation: () async -> T) async -> T {
        var policy = saveSuppressionPolicy
        policy.beginLaunchApplication()
        saveSuppressionPolicy = policy

        let result = await operation()
        await Task.yield()

        policy = saveSuppressionPolicy
        policy.finishLaunchApplication()
        saveSuppressionPolicy = policy
        return result
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
        let previousCounts = environment.tasksViewModel.counts
        await environment.tasksViewModel.loadCounts(force: true)
        let todayTaskCount = WorkspaceRestorationPlanner.freshTodayTaskCountForLaunch(
            previousCounts: previousCounts,
            currentCounts: environment.tasksViewModel.counts,
            errorMessage: environment.tasksViewModel.errorMessage
        )
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
            return await applyWithWorkspaceRestorationSaveSuppression {
                await applyDueTodayTasksLaunchOverride(localDateKey: todayDateKey)
            }
        case .restoredSnapshot:
            guard let snapshot else { return false }
            return await applyWithWorkspaceRestorationSaveSuppression {
                await applyRestoredWorkspace(snapshot)
            }
        }
    }

    func applyRestoredWorkspace(_ snapshot: DeviceWorkspaceSnapshot) async -> Bool {
        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        switch family {
        case .phone:
            guard let route = snapshot.phoneRoute else { return false }
            await applyPhoneRestoration(route)
            return true
        case .workspace:
            guard let splitWorkspace = snapshot.splitWorkspace else { return false }
            applySplitWorkspaceRestoration(splitWorkspace)
            return true
        }
    }

    func applyDueTodayTasksLaunchOverride(localDateKey: String) async -> Bool {
        guard await environment.tasksViewModel.loadTodayForLaunch() else {
            return false
        }
        environment.workspaceRestorationStore.recordDueTodayAutoOpen(
            userId: currentRestorationUserId,
            localDateKey: localDateKey
        )
        let plan = WorkspaceRestorationPlanner.makeDueTodayLaunchOverridePlan(
            isPhone: isPhoneIdiom
        )
        #if os(iOS)
        if isPhoneIdiom {
            phoneSelection = plan.phoneSelection ?? plan.sidebarSelection
            sidebarSelection = plan.sidebarSelection
            environment.tasksPhoneDetailRouteId = plan.phoneTaskRouteId
            environment.workspaceStore.dispatch(.setLayout(plan.layout), source: "due_today_launch_override")
            environment.workspaceStore.dispatch(.selectSection(plan.sidebarSelection), source: "due_today_launch_override")
            return true
        }
        #endif
        sidebarSelection = plan.sidebarSelection
        isLeftPanelExpanded = plan.isLeftPanelExpanded ?? isLeftPanelExpanded
        isWorkspaceExpanded = plan.isWorkspaceExpanded ?? isWorkspaceExpanded
        environment.focusedWorkspacePane = plan.focusedPane ?? environment.focusedWorkspacePane
        environment.workspaceStore.dispatch(.setLayout(plan.layout), source: "due_today_launch_override")
        if let primaryDescriptor = plan.primaryDescriptor {
            environment.workspaceStore.dispatch(
                .setPrimaryContent(primaryDescriptor),
                source: "due_today_launch_override"
            )
        }
        if let secondaryDescriptor = plan.secondaryDescriptor {
            environment.workspaceStore.dispatch(
                .setSecondaryContent(secondaryDescriptor),
                source: "due_today_launch_override"
            )
        }
        environment.workspaceStore.dispatch(
            .selectSection(plan.sidebarSelection),
            source: "due_today_launch_override"
        )
        return true
    }

    func applyPhoneRestoration(_ route: PhoneWorkspaceRoute) async {
        let plan = WorkspaceRestorationPlanner.makePhonePlan(
            route: route,
            hasMeaningfulChatDraft: hasMeaningfulChatDraftForRestoration
        )
        phoneSelection = plan.section
        sidebarSelection = plan.section
        environment.workspaceStore.dispatch(.setLayout(.compact), source: "workspace_restoration")
        environment.workspaceStore.dispatch(.selectSection(plan.section), source: "workspace_restoration")
        await applyPhoneRestorationDetail(plan.detail)
    }

    func applyPhoneRestorationDetail(_ detail: PhoneWorkspaceDetail?) async {
        switch detail {
        case .conversation(let id):
            await environment.chatViewModel.selectConversation(id: id)
            await clearFailedConversationRestorationIfNeeded()
        case .chatDraft:
            await environment.chatViewModel.openDraftConversation()
        case .note(let id):
            environment.notesPhoneDetailRouteId = id
            await environment.notesViewModel.loadNote(id: id)
            clearFailedNoteRestorationIfNeeded()
        case .taskRoute(let id):
            environment.tasksPhoneDetailRouteId = id
        case .website(let id):
            await environment.websitesViewModel.selectWebsite(id: id)
            clearFailedWebsiteRestorationIfNeeded()
        case .file(let id):
            let didOpen = await environment.ingestionViewModel.selectFile(fileId: id)
            clearFailedFileRestorationIfNeeded(didOpen: didOpen)
        case nil:
            break
        }
    }

    func clearFailedConversationRestorationIfNeeded() async {
        if environment.chatViewModel.errorMessage != nil {
            await environment.chatViewModel.selectConversation(id: nil)
        }
    }

    func clearFailedNoteRestorationIfNeeded() {
        if environment.notesViewModel.errorMessage != nil {
            environment.notesPhoneDetailRouteId = nil
            environment.notesRuntime.viewModel.clearSelection()
        }
    }

    func clearFailedWebsiteRestorationIfNeeded() {
        if environment.websitesViewModel.errorMessage != nil {
            environment.websitesViewModel.clearSelection()
        }
    }

    func clearFailedFileRestorationIfNeeded(didOpen: Bool) {
        if !didOpen {
            environment.ingestionViewModel.clearSelection()
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
