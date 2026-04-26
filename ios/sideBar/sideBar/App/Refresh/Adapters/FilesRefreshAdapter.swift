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
            StartupDebugTrace.log(
                "files.refresh.list.start",
                details: [
                    "item_count": "\(viewModel.items.count)",
                    "selected": viewModel.selectedFileId ?? "<none>"
                ]
            )
            await viewModel.load(force: true)
            StartupDebugTrace.log(
                "files.refresh.list.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "item_count": "\(viewModel.items.count)",
                    "selected": viewModel.selectedFileId ?? "<none>"
                ]
            )
        }

        if plan.targets.contains(.visibleDetail(.files)),
           let fileId = viewModel.selectedFileId {
            StartupDebugTrace.log(
                "files.refresh.detail.start",
                details: ["file_id": fileId]
            )
            _ = await viewModel.loadMeta(fileId: fileId, force: true)
            StartupDebugTrace.log(
                "files.refresh.detail.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "file_id": fileId
                ]
            )
        }
    }
}
