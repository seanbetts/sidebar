import Foundation

@MainActor
final class FilesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .files
    var hasVisibleDetail: Bool { viewModel.selectedFileId != nil }
    var hasPinnedMetadata: Bool { !viewModel.store.pinnedFileOrder().isEmpty }

    private let viewModel: IngestionViewModel

    init(viewModel: IngestionViewModel) {
        self.viewModel = viewModel
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        viewModel.errorMessage = nil
        if canAttemptServerRead {
            viewModel.store.hydrateListFromCache()
        } else {
            await viewModel.load()
        }
    }

    func refresh(plan: RefreshPlan) async {
        if plan.containsListOrPinnedMetadata(for: section) {
            await viewModel.load(force: true)
        }

        if plan.containsVisibleDetail(for: section),
           let fileId = viewModel.selectedFileId {
            _ = await viewModel.loadMeta(fileId: fileId, force: true)
        }
    }
}
