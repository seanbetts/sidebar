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
            await viewModel.refreshTree(force: true)
        }

        if plan.targets.contains(.visibleDetail(.notes)),
           let noteId = viewModel.selectedNoteId {
            await viewModel.store.refreshNote(id: noteId)
        }
    }
}
