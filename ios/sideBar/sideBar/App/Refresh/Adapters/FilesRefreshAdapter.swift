import Foundation

final class FilesRefreshAdapter: SectionRefreshAdapter {
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
