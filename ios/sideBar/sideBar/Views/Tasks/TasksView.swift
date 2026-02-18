import SwiftUI

public struct TasksView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

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
            #if os(iOS)
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await environment.tasksViewModel.load(selection: environment.tasksViewModel.selection, force: true)
                    await environment.tasksViewModel.loadCounts(force: true)
                }
            }
            #endif
            #if !os(macOS)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
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
