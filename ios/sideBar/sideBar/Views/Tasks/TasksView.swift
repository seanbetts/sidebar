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
            .onChange(of: environment.pendingSidebarDeepLink) { _, _ in
                consumePendingNewTaskDeepLinkIfNeeded()
            }
            #if !os(macOS)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private func consumePendingNewTaskDeepLinkIfNeeded() {
        guard environment.consumePendingSidebarDeepLink(host: "tasks", path: "/new") != nil else { return }
        Task {
            await environment.tasksViewModel.load(selection: .today)
            environment.tasksViewModel.startNewTask()
        }
    }
}
