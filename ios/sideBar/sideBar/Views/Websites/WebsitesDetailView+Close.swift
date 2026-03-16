import SwiftUI

extension WebsitesDetailView {
    func closeWebsite() {
        let closePlan = WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: currentWorkspaceExpandedByRotation
        )
        isWorkspaceExpanded = closePlan.isWorkspaceExpanded
        #if os(iOS)
        isWorkspaceExpandedByRotation = closePlan.isWorkspaceExpandedByRotation
        #endif
        viewModel.clearSelection()
    }

    private var currentWorkspaceExpandedByRotation: Bool {
        #if os(iOS)
        isWorkspaceExpandedByRotation
        #else
        false
        #endif
    }
}
