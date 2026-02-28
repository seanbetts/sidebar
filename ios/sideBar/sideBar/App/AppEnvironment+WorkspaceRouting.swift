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
}
