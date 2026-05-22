import Foundation

final class NotesRefreshAdapter: SectionRefreshAdapter {
    private let viewModel: NotesViewModel

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
        super.init(
            section: .notes,
            hasVisibleDetail: { viewModel.selectedNoteId != nil },
            hasPinnedMetadata: { !viewModel.store.pinnedNoteOrder().isEmpty },
            prepareForPresentation: Self.protectedListPreparation(
                hydrateFromCache: {
                    viewModel.hydrateTreeFromCache()
                },
                loadWhenServerReadUnavailable: {
                    await viewModel.loadTree()
                }
            ),
            refreshList: {
                await viewModel.refreshTree(force: true)
            },
            refreshVisibleDetail: {
                guard let noteId = viewModel.selectedNoteId else { return }
                await viewModel.loadNote(id: noteId, force: true)
            },
            applyMetadataPatch: { change in
                guard change.kind == .metadataPatch,
                      let noteId = change.entityId,
                      !viewModel.isSelectedNoteRealtimeIdentifier(noteId) else {
                    return false
                }
                let didPatch = viewModel.store.applyRealtimeMetadataPatch(
                    noteId: noteId,
                    updatedAt: change.updatedAt
                )
                if didPatch {
                    viewModel.setMirroredTree(viewModel.store.tree)
                    viewModel.setMirroredArchivedTree(viewModel.store.archivedTree)
                }
                return didPatch
            },
            clearTransientState: { change in
                guard change.kind == .listRefresh,
                      let noteId = change.entityId else {
                    return
                }
                viewModel.clearSelectedNoteForRealtimeDeletion(noteId: noteId)
            }
        )
    }

    override func refresh(plan: RefreshPlan) async {
        guard plan.containsRefreshWork(for: section) else {
            return
        }

        if plan.containsListOrPinnedMetadata(for: section) {
            await viewModel.refreshTree(force: true)
        }

        guard plan.containsVisibleDetail(for: section) else {
            return
        }
        if plan.trigger == .realtimeInvalidation {
            await viewModel.refreshSelectedNoteForRealtime()
            return
        }
        guard let noteId = viewModel.selectedNoteId else { return }
        await viewModel.loadNote(id: noteId, force: true)
    }

    func classifyNoteRealtime(noteId: String, updatedAt: Date?, isDeleted: Bool) -> DomainSyncChange {
        let isSelected = viewModel.isSelectedNoteRealtimeIdentifier(noteId)
        return DomainSyncChange(
            section: .notes,
            entityId: noteId,
            kind: isDeleted ? .listRefresh : (isSelected ? .detailRefresh : .metadataPatch),
            updatedAt: updatedAt,
            requiresListRefresh: true,
            requiresDetailRefresh: isSelected,
            canPatchMetadata: !isDeleted && !isSelected
        )
    }
}
