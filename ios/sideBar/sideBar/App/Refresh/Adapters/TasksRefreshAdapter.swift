import Foundation

@MainActor
final class TasksRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .tasks

    private let viewModel: TasksViewModel

    init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        let selection = viewModel.preferredLoadSelection
        viewModel.localErrorMessage = nil
        if canAttemptServerRead {
            viewModel.store.hydrateListFromCache(selection: selection)
            viewModel.store.hydrateCountsFromCache()
            if case .upcoming = selection {
                viewModel.filteredUpcomingCount = viewModel.viewState.totalCount
            }
        } else {
            await viewModel.load(selection: selection)
            await viewModel.loadCounts()
        }
    }

    func refresh(plan: RefreshPlan) async {
        if plan.containsListOrVisibleDetail(for: section) {
            await viewModel.load(selection: viewModel.preferredLoadSelection, force: true)
        }

        if plan.contains(.taskCounts) {
            await viewModel.loadCounts(force: true)
            await viewModel.refreshWidgetData()
        }
    }

    static func classifyTaskRealtime(entityId: String?, updatedAt: Date?, isDeleted: Bool) -> DomainSyncChange {
        DomainSyncChange(
            section: .tasks,
            entityId: entityId,
            kind: isDeleted ? .listRefresh : .metadataPatch,
            updatedAt: updatedAt,
            requiresListRefresh: true,
            requiresDetailRefresh: false,
            canPatchMetadata: false
        )
    }
}
