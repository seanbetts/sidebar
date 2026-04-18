extension TasksDetailView {
    func handleCompletionAction(for task: TaskItem, selection: TaskSelection) {
        Task {
            switch taskRowCompletionAction(selection: selection, taskStatus: task.status) {
            case .complete:
                await viewModel.completeTask(task: task)
            case .reopen:
                await viewModel.reopenTask(task: task)
            }
        }
    }
}
