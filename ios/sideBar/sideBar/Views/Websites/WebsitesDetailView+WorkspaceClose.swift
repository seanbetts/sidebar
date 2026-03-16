import SwiftUI

extension WebsitesDetailView {
    func makeWorkspaceItemClosePlan() -> WorkspaceItemClosePlan {
        WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: currentWorkspaceExpandedByRotation
        )
    }

    func applyWorkspaceItemClosePlan(_ closePlan: WorkspaceItemClosePlan) {
        isWorkspaceExpanded = closePlan.isWorkspaceExpanded
        #if os(iOS)
        isWorkspaceExpandedByRotation = closePlan.isWorkspaceExpandedByRotation
        #endif
    }

    private var currentWorkspaceExpandedByRotation: Bool {
        #if os(iOS)
        isWorkspaceExpandedByRotation
        #else
        false
        #endif
    }
}
