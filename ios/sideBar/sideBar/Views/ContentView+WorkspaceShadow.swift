import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
    var workspaceState: WorkspaceState {
        environment.workspaceStore.state
    }

    var primaryWorkspaceDescriptor: WorkspaceContentDescriptor {
        workspaceState.primaryPane.descriptor
    }

    var secondaryWorkspaceDescriptor: WorkspaceContentDescriptor {
        guard workspaceState.layout != .compact else {
            return .empty
        }
        return workspaceState.secondaryPane?.descriptor ?? .empty
    }

    var compactWorkspaceSection: AppSection {
        WorkspaceLegacySectionAdapter.section(from: primaryWorkspaceDescriptor)
            ?? phoneSelection
    }

    var resolvedActiveSectionForWorkspace: AppSection {
        if isSettingsPresented {
            return .settings
        }
        if isCompactWorkspaceLayout {
            return compactWorkspaceSection
        }
        let primarySection = WorkspaceLegacySectionAdapter.section(from: primaryWorkspaceDescriptor)
        let secondarySection = WorkspaceLegacySectionAdapter.section(from: secondaryWorkspaceDescriptor)
        return primarySection
            ?? sidebarSelection
            ?? secondarySection
            ?? workspaceState.activeSection
            ?? .chat
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

    func compactDetailDescriptor(for section: AppSection) -> WorkspaceContentDescriptor {
        if section == compactWorkspaceSection {
            return primaryWorkspaceDescriptor
        }
        return .builtIn(section)
    }

    func isSectionVisibleInWorkspace(_ section: AppSection) -> Bool {
        if isCompactWorkspaceLayout {
            return compactWorkspaceSection == section
        }
        let primarySection = WorkspaceLegacySectionAdapter.section(from: primaryWorkspaceDescriptor)
        let secondarySection = WorkspaceLegacySectionAdapter.section(from: secondaryWorkspaceDescriptor)
        return primarySection == section || secondarySection == section
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
        guard !isCompact else { return nil }
        return WorkspaceLegacySectionAdapter.section(from: primaryWorkspaceDescriptor)
            ?? sidebarSelection
    }
    #endif
}
