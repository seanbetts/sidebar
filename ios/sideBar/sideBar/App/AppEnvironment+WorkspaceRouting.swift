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
}
