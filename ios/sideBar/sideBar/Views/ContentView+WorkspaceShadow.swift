import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
    var workspaceState: WorkspaceState {
        environment.workspaceStore.state
    }

    var workspaceLegacySectionProjection: WorkspaceLegacySectionProjection {
        WorkspaceLegacySectionAdapter.makeProjection(
            workspaceState: workspaceState,
            fallbackCompactSelection: phoneSelection
        )
    }

    var resolvedActiveSectionForWorkspace: AppSection {
        WorkspaceLegacySectionAdapter.resolvedActiveSection(
            projection: workspaceLegacySectionProjection,
            isCompactLayout: isCompactWorkspaceLayout,
            isSettingsPresented: isSettingsPresented,
            fallbackSidebarSelection: sidebarSelection
        )
    }

    private var isCompactWorkspaceLayout: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    func syncLocalSectionSelectionFromWorkspaceState(_ state: WorkspaceState) {
        #if !os(macOS)
        if isCompactWorkspaceLayout {
            let compactSelection = WorkspaceLegacySectionAdapter.section(
                from: state.primaryPane.descriptor
            ) ?? phoneSelection
            if phoneSelection != compactSelection {
                phoneSelection = compactSelection
            }
        }
        #endif

        if let selection = state.sidebarSelection, sidebarSelection != selection {
            sidebarSelection = selection
        }
    }

    func handleWorkspaceExpandedChange(isExpanded: Bool) {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceExpandedChangePlan(
            isExpanded: isExpanded,
            isLeftPanelExpanded: isLeftPanelExpanded,
            previousLeftPanelExpanded: workspaceExpandedPreviousLeftPanelExpanded
        )
        isLeftPanelExpanded = plan.isLeftPanelExpanded
        workspaceExpandedPreviousLeftPanelExpanded = plan.previousLeftPanelExpanded
        #if os(iOS)
        if plan.clearExpandedByRotation {
            isWorkspaceExpandedByRotation = false
        }
        #endif
    }

    #if os(iOS)
    func handleRootSizeChange(_ size: CGSize) {
        let rotationPlan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: UIDevice.current.userInterfaceIdiom == .pad,
            previousIsPortrait: lastWorkspaceIsPortrait,
            size: size,
            primaryWorkspaceSection: primaryWorkspaceSectionForRotation,
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: isWorkspaceExpandedByRotation
        )
        guard let rotationPlan else { return }
        lastWorkspaceIsPortrait = rotationPlan.lastWorkspaceIsPortrait
        if let nextExpanded = rotationPlan.isWorkspaceExpanded {
            isWorkspaceExpanded = nextExpanded
        }
        if let nextExpandedByRotation = rotationPlan.isWorkspaceExpandedByRotation {
            isWorkspaceExpandedByRotation = nextExpandedByRotation
        }
    }

    var primaryWorkspaceSectionForRotation: AppSection? {
        WorkspaceLegacySectionAdapter.primaryWorkspaceSectionForRotation(
            projection: workspaceLegacySectionProjection,
            isCompactLayout: isCompact,
            fallbackSidebarSelection: sidebarSelection
        )
    }
    #endif
}
