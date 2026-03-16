import SwiftUI

extension NotesDetailView {
    func requestCloseNote() {
        let closePlan = WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: currentWorkspaceExpandedByRotation
        )

        Task {
            await editorViewModel.saveIfNeeded()
            isWorkspaceExpanded = closePlan.isWorkspaceExpanded
            #if os(iOS)
            isWorkspaceExpandedByRotation = closePlan.isWorkspaceExpandedByRotation
            #endif
            viewModel.clearSelection()
        }
    }

    private var currentWorkspaceExpandedByRotation: Bool {
        #if os(iOS)
        isWorkspaceExpandedByRotation
        #else
        false
        #endif
    }
}
