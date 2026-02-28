import SwiftUI

extension ContentView {
    var workspaceLegacySectionProjection: WorkspaceLegacySectionProjection {
        WorkspaceLegacySectionAdapter.makeProjection(
            workspaceState: environment.workspaceStore.state,
            fallbackPrimarySection: primarySection,
            fallbackSecondarySection: secondarySection,
            fallbackCompactSelection: phoneSelection
        )
    }

    var resolvedActiveSectionForWorkspace: AppSection {
        #if os(macOS)
        return isSettingsPresented
            ? .settings
            : (primarySection ?? sidebarSelection ?? secondarySection ?? .chat)
        #else
        if isSettingsPresented {
            return .settings
        }
        if horizontalSizeClass == .compact {
            return workspaceLegacySectionProjection.compactSelection
        }
        return primarySection ?? sidebarSelection ?? secondarySection ?? .chat
        #endif
    }

    var workspaceLegacySnapshot: WorkspaceLegacySnapshot {
        WorkspaceLegacySnapshot(
            isCompactLayout: isCompactWorkspaceLayout,
            sidebarSelection: sidebarSelection,
            primarySection: primarySection,
            secondarySection: secondarySection,
            phoneSelection: isCompactWorkspaceLayout ? phoneSelection : nil,
            activeSection: resolvedActiveSectionForWorkspace,
            focusedSection: environment.focusedSection,
            lastNonChatSection: lastNonChatSection,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: workspaceExpandedByRotationFlag,
            isSettingsPresented: isSettingsPresented
        )
    }

    func syncWorkspaceShadowState(source: String = "content_state_change") {
        environment.workspaceStore.syncLegacySnapshot(
            workspaceLegacySnapshot,
            source: source
        )
    }

    private var isCompactWorkspaceLayout: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var workspaceExpandedByRotationFlag: Bool {
        #if os(iOS)
        return isWorkspaceExpandedByRotation
        #else
        return false
        #endif
    }
}
