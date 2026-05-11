import Foundation
import sideBarShared

extension AppEnvironment {
    func currentRefreshContext() -> RefreshContext {
        let baseContext = Self.makeRefreshContext(
            workspaceState: workspaceStore.state,
            refreshCoordinator: refreshCoordinator,
            canAttemptServerRead: canAttemptProtectedServerRead
        )
        guard baseContext.visibleSection == nil else {
            return baseContext
        }
        return RefreshContext(
            visibleSection: [focusedSection, activeSection]
                .compactMap { $0 }
                .first(where: AppSection.primaryNavigationSections.contains),
            hasVisibleDetail: baseContext.hasVisibleDetail,
            pinnedSections: baseContext.pinnedSections,
            lastOpenedSection: baseContext.lastOpenedSection,
            staleTargets: baseContext.staleTargets,
            canAttemptServerRead: baseContext.canAttemptServerRead
        )
    }

    func refreshContext(for section: AppSection?) -> RefreshContext {
        let baseContext = currentRefreshContext()
        guard let section else { return baseContext }
        return RefreshContext(
            visibleSection: section,
            hasVisibleDetail: refreshCoordinator.hasVisibleDetail(for: section),
            pinnedSections: baseContext.pinnedSections,
            lastOpenedSection: baseContext.lastOpenedSection,
            staleTargets: baseContext.staleTargets,
            canAttemptServerRead: baseContext.canAttemptServerRead
        )
    }

    func refreshVisibleSectionChange(to section: AppSection?) async {
        guard authState == .active else { return }
        await prepareVisibleSectionForPresentation(section)
        await refreshCoordinator.visibleSectionDidChange(
            to: section,
            context: refreshContext(for: section)
        )
    }

    func refreshSectionManually(_ section: AppSection) async {
        guard authState == .active else { return }
        await refreshCoordinator.refresh(
            trigger: .manualRefresh,
            context: refreshContext(for: section)
        )
    }

    func prepareVisibleSectionForPresentation(_ section: AppSection?) async {
        await refreshCoordinator.prepareVisibleSectionForPresentation(
            section,
            canAttemptServerRead: canAttemptProtectedServerRead
        )
    }

    static func makeRefreshCoordinator(
        chatViewModel: ChatViewModel,
        notesViewModel: NotesViewModel,
        tasksViewModel: TasksViewModel,
        websitesViewModel: WebsitesViewModel,
        ingestionViewModel: IngestionViewModel
    ) -> RefreshCoordinator {
        let metadataStore = RefreshMetadataStore()
        let policy = RefreshPolicy(metadataStore: metadataStore)
        let registry = RefreshRegistry(
            adapters: [
                ChatRefreshAdapter(viewModel: chatViewModel),
                NotesRefreshAdapter(viewModel: notesViewModel),
                TasksRefreshAdapter(viewModel: tasksViewModel),
                WebsitesRefreshAdapter(viewModel: websitesViewModel),
                FilesRefreshAdapter(viewModel: ingestionViewModel)
            ]
        )
        return RefreshCoordinator(policy: policy, registry: registry)
    }

    static func makeRefreshContext(
        workspaceState: WorkspaceState,
        refreshCoordinator: RefreshCoordinatorType,
        canAttemptServerRead: Bool
    ) -> RefreshContext {
        let visibleSection = refreshableVisibleSection(from: workspaceState)
        return RefreshContext(
            visibleSection: visibleSection,
            hasVisibleDetail: refreshCoordinator.hasVisibleDetail(for: visibleSection),
            pinnedSections: refreshCoordinator.pinnedSections(),
            lastOpenedSection: workspaceState.lastNonChatSection,
            staleTargets: [],
            canAttemptServerRead: canAttemptServerRead
        )
    }

    private static func refreshableVisibleSection(from workspaceState: WorkspaceState) -> AppSection? {
        let candidates = [
            workspaceState.focusedSection,
            workspaceState.activeSection,
            workspaceState.sidebarSelection,
            workspaceState.lastNonChatSection
        ]
        return candidates
            .compactMap { $0 }
            .first(where: AppSection.primaryNavigationSections.contains)
    }

    static func scheduleBackgroundWriteQueueFlush() {
        guard !EnvironmentConfig.isRunningTestsOrPreviews() else { return }
        #if os(iOS)
        AppLaunchDelegate.scheduleWriteQueueFlush()
        #endif
    }

    private var canAttemptProtectedServerRead: Bool {
        connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead
            && protectedContentReadiness.canAttemptServerRead
    }

}
