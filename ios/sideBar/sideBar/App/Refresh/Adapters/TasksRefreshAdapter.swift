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
                "targets": plan.targets.map { String(describing: $0) }.joined(separator: ",")
            ]
        )

        if plan.targets.contains(.sectionList(.tasks)) || plan.targets.contains(.visibleDetail(.tasks)) {
            await viewModel.load(selection: viewModel.preferredLoadSelection, force: true)
        }

        if plan.targets.contains(.taskCounts) {
            await viewModel.loadCounts(force: true)
            await viewModel.refreshWidgetData()
        }
    }
}
