struct WorkspaceParityProjection: Equatable {
    let layout: WorkspaceLayoutMode
    let primaryDescriptor: WorkspaceContentDescriptor
    let secondaryDescriptor: WorkspaceContentDescriptor?
    let sidebarSelection: AppSection?
    let activeSection: AppSection?
    let focusedSection: AppSection?
    let lastNonChatSection: AppSection?
    let isLeftPanelExpanded: Bool
    let isWorkspaceExpanded: Bool
    let isWorkspaceExpandedByRotation: Bool
    let isSettingsPresented: Bool
}

extension WorkspaceState {
    static func fromLegacySnapshot(_ snapshot: WorkspaceLegacySnapshot) -> WorkspaceState {
        let layout: WorkspaceLayoutMode = snapshot.isCompactLayout ? .compact : .split
        let compactSection = snapshot.phoneSelection ?? snapshot.sidebarSelection ?? snapshot.activeSection ?? .chat
        let primaryDescriptor: WorkspaceContentDescriptor = snapshot.isCompactLayout
            ? .builtIn(compactSection)
            : .fromOptionalBuiltInSection(snapshot.primarySection)
        let secondaryPane: WorkspacePaneState? = snapshot.isCompactLayout
            ? nil
            : WorkspacePaneState(
                pane: .secondary,
                descriptor: .fromOptionalBuiltInSection(snapshot.secondarySection)
            )

        return WorkspaceState(
            mode: snapshot.mode,
            layout: layout,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: primaryDescriptor
            ),
            secondaryPane: secondaryPane,
            sidebarSelection: snapshot.sidebarSelection,
            activeSection: snapshot.activeSection,
            focusedSection: snapshot.focusedSection,
            lastNonChatSection: snapshot.lastNonChatSection,
            isLeftPanelExpanded: snapshot.isLeftPanelExpanded,
            isWorkspaceExpanded: snapshot.isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: snapshot.isWorkspaceExpandedByRotation,
            isSettingsPresented: snapshot.isSettingsPresented
        )
    }

    var parityProjection: WorkspaceParityProjection {
        WorkspaceParityProjection(
            layout: layout,
            primaryDescriptor: primaryPane.descriptor,
            secondaryDescriptor: secondaryPane?.descriptor,
            sidebarSelection: sidebarSelection,
            activeSection: activeSection,
            focusedSection: focusedSection,
            lastNonChatSection: lastNonChatSection,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: isWorkspaceExpandedByRotation,
            isSettingsPresented: isSettingsPresented
        )
    }

    static func expectedParityProjection(
        from snapshot: WorkspaceLegacySnapshot
    ) -> WorkspaceParityProjection {
        fromLegacySnapshot(snapshot).parityProjection
    }
}
