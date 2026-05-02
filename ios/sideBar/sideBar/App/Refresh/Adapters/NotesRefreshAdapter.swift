import Foundation

final class NotesRefreshAdapter: SectionRefreshAdapter {
    init(viewModel: NotesViewModel) {
        super.init(
            section: .notes,
            hasVisibleDetail: { viewModel.selectedNoteId != nil },
            hasPinnedMetadata: { !viewModel.store.pinnedNoteOrder().isEmpty },
            prepareForPresentation: { canAttemptServerRead in
                if canAttemptServerRead {
                    viewModel.hydrateTreeFromCache()
                } else {
                    await viewModel.loadTree()
                }
            },
            refreshList: {
                await viewModel.refreshTree(force: true)
            },
            refreshVisibleDetail: {
                guard let noteId = viewModel.selectedNoteId else { return }
                await viewModel.loadNote(id: noteId, force: true)
            }
        )
    }
}
