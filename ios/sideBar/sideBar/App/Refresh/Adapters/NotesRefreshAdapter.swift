import Foundation

@MainActor
final class NotesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .notes
    var hasVisibleDetail: Bool { viewModel.selectedNoteId != nil }
    var hasPinnedMetadata: Bool { !viewModel.store.pinnedNoteOrder().isEmpty }

    private let viewModel: NotesViewModel

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        if canAttemptServerRead {
            viewModel.hydrateTreeFromCache()
        } else {
            await viewModel.loadTree()
        }
    }

    func refresh(plan: RefreshPlan) async {
        if plan.containsListOrPinnedMetadata(for: section) {
            await viewModel.refreshTree(force: true)
        }

        if plan.containsVisibleDetail(for: section),
           let noteId = viewModel.selectedNoteId {
            await viewModel.loadNote(id: noteId, force: true)
        }
    }
}
