import Foundation

extension AppEnvironment {
    func currentRefreshContext() -> RefreshContext {
        let baseContext = Self.makeRefreshContext(
            workspaceState: workspaceStore.state,
            chatViewModel: chatViewModel,
            notesViewModel: notesViewModel,
            websitesViewModel: websitesViewModel,
            ingestionViewModel: ingestionViewModel,
            notesStore: notesStore,
            websitesStore: websitesStore,
            ingestionStore: ingestionStore,
            canAttemptServerRead: connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead
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
            hasVisibleDetail: Self.hasVisibleDetail(
                for: section,
                chatViewModel: chatViewModel,
                notesViewModel: notesViewModel,
                websitesViewModel: websitesViewModel,
                ingestionViewModel: ingestionViewModel
            ),
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
        guard let section else { return }
        let canAttemptServerRead = connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead

        switch section {
        case .chat:
            await prepareChatForPresentation(canAttemptServerRead: canAttemptServerRead)
        case .notes:
            await prepareNotesForPresentation(canAttemptServerRead: canAttemptServerRead)
        case .tasks:
            await prepareTasksForPresentation(canAttemptServerRead: canAttemptServerRead)
        case .websites:
            await prepareWebsitesForPresentation(canAttemptServerRead: canAttemptServerRead)
        case .files:
            await prepareFilesForPresentation(canAttemptServerRead: canAttemptServerRead)
        case .skillsStore, .settings:
            break
        }
    }

    private func prepareChatForPresentation(canAttemptServerRead: Bool) async {
        chatViewModel.errorMessage = nil
        if canAttemptServerRead {
            await chatStore.hydrateConversationsFromCache()
        } else {
            await chatViewModel.loadConversations()
        }
    }

    private func prepareNotesForPresentation(canAttemptServerRead: Bool) async {
        if canAttemptServerRead {
            notesViewModel.hydrateTreeFromCache()
        } else {
            await notesViewModel.loadTree()
        }
    }

    private func prepareTasksForPresentation(canAttemptServerRead: Bool) async {
        let selection = tasksViewModel.preferredLoadSelection
        tasksViewModel.localErrorMessage = nil
        if canAttemptServerRead {
            tasksStore.hydrateListFromCache(selection: selection)
            tasksStore.hydrateCountsFromCache()
            if case .upcoming = selection {
                tasksViewModel.filteredUpcomingCount = tasksViewModel.viewState.totalCount
            }
        } else {
            await tasksViewModel.load(selection: selection)
            await tasksViewModel.loadCounts()
        }
    }

    private func prepareWebsitesForPresentation(canAttemptServerRead: Bool) async {
        websitesViewModel.errorMessage = nil
        if canAttemptServerRead {
            websitesStore.hydrateListFromCache()
        } else {
            await websitesViewModel.load()
        }
    }

    private func prepareFilesForPresentation(canAttemptServerRead: Bool) async {
        ingestionViewModel.errorMessage = nil
        if canAttemptServerRead {
            ingestionStore.hydrateListFromCache()
        } else {
            await ingestionViewModel.load()
        }
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
        chatViewModel: ChatViewModel,
        notesViewModel: NotesViewModel,
        websitesViewModel: WebsitesViewModel,
        ingestionViewModel: IngestionViewModel,
        notesStore: NotesStore,
        websitesStore: WebsitesStore,
        ingestionStore: IngestionStore,
        canAttemptServerRead: Bool
    ) -> RefreshContext {
        let visibleSection = refreshableVisibleSection(from: workspaceState)
        return RefreshContext(
            visibleSection: visibleSection,
            hasVisibleDetail: hasVisibleDetail(
                for: visibleSection,
                chatViewModel: chatViewModel,
                notesViewModel: notesViewModel,
                websitesViewModel: websitesViewModel,
                ingestionViewModel: ingestionViewModel
            ),
            pinnedSections: pinnedRefreshSections(
                notesStore: notesStore,
                websitesStore: websitesStore,
                ingestionStore: ingestionStore
            ),
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

    private static func hasVisibleDetail(
        for section: AppSection?,
        chatViewModel: ChatViewModel,
        notesViewModel: NotesViewModel,
        websitesViewModel: WebsitesViewModel,
        ingestionViewModel: IngestionViewModel
    ) -> Bool {
        switch section {
        case .chat:
            return chatViewModel.selectedConversationId != nil
        case .notes:
            return notesViewModel.selectedNoteId != nil
        case .websites:
            return websitesViewModel.selectedWebsiteId != nil
        case .files:
            return ingestionViewModel.selectedFileId != nil
        default:
            return false
        }
    }

    private static func pinnedRefreshSections(
        notesStore: NotesStore,
        websitesStore: WebsitesStore,
        ingestionStore: IngestionStore
    ) -> [AppSection] {
        var sections: [AppSection] = []
        if !notesStore.pinnedNoteOrder().isEmpty {
            sections.append(.notes)
        }
        if !websitesStore.pinnedWebsiteOrder().isEmpty {
            sections.append(.websites)
        }
        if !ingestionStore.pinnedFileOrder().isEmpty {
            sections.append(.files)
        }
        return sections
    }
}
