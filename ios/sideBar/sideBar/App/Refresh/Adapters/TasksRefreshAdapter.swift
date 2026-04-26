import Foundation

@MainActor
final class TasksRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .tasks

    private let viewModel: TasksViewModel

    init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    func refresh(plan: RefreshPlan) async {
        StartupDebugTrace.log(
            "tasks.refresh.plan",
            details: [
                "targets": plan.traceTargets
            ]
        )

        if plan.targets.contains(.sectionList(.tasks)) || plan.targets.contains(.visibleDetail(.tasks)) {
            StartupDebugTrace.log(
                "tasks.refresh.list.start",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "selection": viewModel.preferredLoadSelection.cacheKey,
                    "task_count": "\(viewModel.tasks.count)"
                ]
            )
            await viewModel.load(selection: viewModel.preferredLoadSelection, force: true)
            StartupDebugTrace.log(
                "tasks.refresh.list.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "selection": viewModel.selection.cacheKey,
                    "task_count": "\(viewModel.tasks.count)"
                ]
            )
        }

        if plan.targets.contains(.taskCounts) {
            StartupDebugTrace.log(
                "tasks.refresh.counts.start",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "has_counts": viewModel.counts == nil ? "false" : "true"
                ]
            )
            await viewModel.loadCounts(force: true)
            await viewModel.refreshWidgetData()
            StartupDebugTrace.log(
                "tasks.refresh.counts.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "has_counts": viewModel.counts == nil ? "false" : "true"
                ]
            )
        }
    }
}
