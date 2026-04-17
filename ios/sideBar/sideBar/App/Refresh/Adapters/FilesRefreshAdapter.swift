import Foundation

@MainActor
final class FilesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .files

    private let viewModel: IngestionViewModel

    init(viewModel: IngestionViewModel) {
        self.viewModel = viewModel
    }

    func refresh(plan: RefreshPlan) async {
        if plan.targets.contains(.sectionList(.files)) || plan.targets.contains(.pinnedMetadata(.files)) {
            await viewModel.store.refreshList()
        }

        if plan.targets.contains(.visibleDetail(.files)),
           let fileId = viewModel.selectedFileId {
            await viewModel.store.refreshMeta(fileId: fileId)
        }
    }
}
