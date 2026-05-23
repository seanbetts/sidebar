import Foundation

final class FilesRefreshAdapter: SectionRefreshAdapter {
    static func jobTerminalChange(
        entityId: String?,
        requiresDetailRefresh: Bool
    ) -> DomainSyncChange {
        DomainSyncChange(
            section: .files,
            entityId: entityId,
            kind: .jobProgress,
            updatedAt: nil,
            requiresListRefresh: true,
            requiresDetailRefresh: requiresDetailRefresh,
            canPatchMetadata: false
        )
    }

    init(viewModel: IngestionViewModel) {
        super.init(
            section: .files,
            hasVisibleDetail: { viewModel.selectedFileId != nil },
            hasPinnedMetadata: { !viewModel.store.pinnedFileOrder().isEmpty },
            prepareForPresentation: Self.protectedListPreparation(
                clearError: {
                    viewModel.errorMessage = nil
                },
                hydrateFromCache: {
                    viewModel.store.hydrateListFromCache()
                },
                loadWhenServerReadUnavailable: {
                    await viewModel.load()
                }
            ),
            refreshList: {
                await viewModel.load(force: true)
            },
            refreshVisibleDetail: {
                guard let fileId = viewModel.selectedFileId else { return }
                _ = await viewModel.loadMeta(fileId: fileId, force: true)
            }
        )
    }
}
