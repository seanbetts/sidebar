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
            ingestionStore: ingestionStore
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
            staleTargets: baseContext.staleTargets
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
        chatViewModel: ChatViewModel,
        notesViewModel: NotesViewModel,
        websitesViewModel: WebsitesViewModel,
        ingestionViewModel: IngestionViewModel,
        notesStore: NotesStore,
        websitesStore: WebsitesStore,
        ingestionStore: IngestionStore
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
            staleTargets: []
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
