import Foundation

@MainActor
final class NotesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .notes

    private let viewModel: NotesViewModel

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    func refresh(plan: RefreshPlan) async {
        if plan.targets.contains(.sectionList(.notes)) || plan.targets.contains(.pinnedMetadata(.notes)) {
            StartupDebugTrace.log(
                "notes.refresh.tree.start",
                details: [
                    "has_tree": viewModel.tree == nil ? "false" : "true",
                    "selected": viewModel.selectedNoteId ?? "<none>"
                ]
            )
            await viewModel.refreshTree(force: true)
            StartupDebugTrace.log(
                "notes.refresh.tree.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "has_tree": viewModel.tree == nil ? "false" : "true",
                    "selected": viewModel.selectedNoteId ?? "<none>"
                ]
            )
        }

        if plan.targets.contains(.visibleDetail(.notes)),
           let noteId = viewModel.selectedNoteId {
            StartupDebugTrace.log(
                "notes.refresh.detail.start",
                details: ["note_id": noteId]
            )
            await viewModel.loadNote(id: noteId, force: true)
            StartupDebugTrace.log(
                "notes.refresh.detail.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "note_id": noteId
                ]
            )
        }
    }
}
