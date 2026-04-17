import SwiftUI

public struct TasksView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        TasksDetailView(viewModel: environment.tasksViewModel)
            .onAppear {
                environment.isTasksFocused = true
                consumePendingNewTaskDeepLinkIfNeeded()
            }
            .onDisappear {
                environment.isTasksFocused = false
            }
            .onChange(of: environment.pendingNewTaskDeepLink) { _, isPending in
                guard isPending else { return }
                consumePendingNewTaskDeepLinkIfNeeded()
            }
            #if !os(macOS)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private func consumePendingNewTaskDeepLinkIfNeeded() {
        guard environment.pendingNewTaskDeepLink else { return }
        environment.pendingNewTaskDeepLink = false
        Task {
            await environment.tasksViewModel.load(selection: .today)
            environment.tasksViewModel.startNewTask()
        }
    }
}
