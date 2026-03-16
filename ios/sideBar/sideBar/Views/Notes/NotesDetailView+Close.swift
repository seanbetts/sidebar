import SwiftUI

extension NotesDetailView {
    func requestCloseNote() {
        let closePlan = makeWorkspaceItemClosePlan()

        Task {
            await editorViewModel.saveIfNeeded()
            applyWorkspaceItemClosePlan(closePlan)
            viewModel.clearSelection()
        }
    }
}
