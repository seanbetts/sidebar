import Foundation

@MainActor
extension AppEnvironment {
    func routeWorkspaceSelection(
        to section: AppSection,
        source: String
    ) {
        workspaceStore.dispatch(
            .selectSection(section),
            source: source,
            expectLegacyFollowup: true
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
            source: source,
            expectLegacyFollowup: true
        )
    }

    func closeWorkspacePane(
        _ pane: WorkspacePane,
        source: String
    ) {
        workspaceStore.dispatch(
            .closePane(pane),
            source: source,
            expectLegacyFollowup: true
        )
    }

    func setAgentSurfacePinned(
        surfaceId: String,
        isPinned: Bool,
        source: String
    ) {
        workspaceStore.dispatch(
            .setAgentSurfacePinned(surfaceId: surfaceId, isPinned: isPinned),
            source: source,
            expectLegacyFollowup: true
        )
    }
}
