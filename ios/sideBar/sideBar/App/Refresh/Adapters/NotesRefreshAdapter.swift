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
        if plan.targets.contains(.sectionList(.notes)) || plan.targets.contains(.pinnedMetadata(.notes)) {
            await viewModel.refreshTree(force: true)
        }

        if plan.targets.contains(.visibleDetail(.notes)),
           let noteId = viewModel.selectedNoteId {
            await viewModel.loadNote(id: noteId, force: true)
        }
    }
}
