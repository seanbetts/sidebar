import Foundation

@MainActor
extension AppEnvironment {
    func routeWorkspaceSelection(
        to section: AppSection,
        source: String
    ) {
        workspaceStore.dispatch(
            .selectSection(section),
            source: source
        )
        commandSelection = section
        AppSentry.recordNavigation(to: section, source: source)
    }

    func dispatchChatWorkspaceAction(_ action: WorkspaceAction) {
        switch action {
        case .openEntity(let request):
            openWorkspaceEntity(request, source: "chat_workspace_patch")

        default:
            workspaceStore.dispatch(
                action,
                source: "chat_workspace_patch"
            )
        }
    }

    func openWorkspaceEntity(
        _ request: WorkspaceEntityOpenRequest,
        source: String
    ) {
        if let section = request.section {
            routeWorkspaceSelection(to: section, source: source)
        }

        if openStandardEntity(request) || openSpecialEntity(request) {
            return
        }

        if let routeURL = request.routeURL {
            handleDeepLink(routeURL)
        }
    }

    func presentAgentSurface(
        _ surface: AgentWorkspaceSurfaceDescriptor,
        in pane: WorkspacePane = .primary,
        source: String
    ) {
        workspaceStore.dispatch(
            .presentAgentSurface(surface, pane: pane),
            source: source
        )
    }

    func closeWorkspacePane(
        _ pane: WorkspacePane,
        source: String
    ) {
        workspaceStore.dispatch(
            .closePane(pane),
            source: source
        )
    }

    func setAgentSurfacePinned(
        surfaceId: String,
        isPinned: Bool,
        source: String
    ) {
        workspaceStore.dispatch(
            .setAgentSurfacePinned(surfaceId: surfaceId, isPinned: isPinned),
            source: source
        )
    }

    private func openTaskScope(id: String, kind: String = "today") {
        let selection: TaskSelection
        switch kind {
        case "project":
            selection = .project(id: id)
        case "group":
            selection = .group(id: id)
        default:
            selection = .today
        }

        Task {
            await tasksViewModel.load(selection: selection, force: true)
        }
        #if !os(macOS)
        tasksPhoneDetailRouteId = selection.cacheKey
        #endif
    }

    private func openStandardEntity(_ request: WorkspaceEntityOpenRequest) -> Bool {
        switch request.entity.type {
        case "note":
            Task {
                await notesViewModel.loadNote(id: request.entity.id)
            }
        case "website":
            Task {
                await websitesViewModel.selectWebsite(id: request.entity.id)
            }
        case "file":
            Task {
                await ingestionViewModel.selectFile(fileId: request.entity.id)
            }
        case "conversation":
            Task {
                await chatViewModel.selectConversation(id: request.entity.id)
            }
        default:
            return false
        }
        return true
    }

    private func openSpecialEntity(_ request: WorkspaceEntityOpenRequest) -> Bool {
        switch request.entity.type {
        case "scratchpad":
            pendingScratchpadDeepLink = true
        case "task_scope":
            openTaskScope(id: request.entity.id)
        case "task":
            openTaskScope(id: "today")
        case "task_project":
            openTaskScope(id: request.entity.id, kind: "project")
        case "task_group":
            openTaskScope(id: request.entity.id, kind: "group")
        default:
            return false
        }
        return true
    }
}
