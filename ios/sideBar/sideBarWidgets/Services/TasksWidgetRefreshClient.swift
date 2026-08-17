import Foundation
import sideBarShared

struct TasksWidgetRefreshClient {
    private let apiClient: APIClient

    init(environment: WidgetAPIEnvironment) {
        self.apiClient = environment.apiClient
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refreshTodayTasks(
        previousSnapshot: WidgetTaskData,
        now: Date = Date()
    ) async throws -> WidgetTaskData {
        try await refreshTasks(previousSnapshot: previousSnapshot, selection: .today, now: now)
    }

    func refreshTasks(
        previousSnapshot: WidgetTaskData,
        selection: TaskWidgetSelection,
        now: Date = Date()
    ) async throws -> WidgetTaskData {
        let response: TasksWidgetTodayResponse
        switch selection {
        case .today:
            response = try await apiClient.request("tasks/lists/today")
        case .project(let id, _):
            response = try await apiClient.request("tasks/projects/\(id)/tasks")
        case .group(let id, _):
            response = try await apiClient.request("tasks/groups/\(id)/tasks")
        }
        let projectTitleById = Dictionary(
            uniqueKeysWithValues: (response.projects ?? []).map { ($0.id, $0.title) }
        )
        let groupTitleById = Dictionary(
            uniqueKeysWithValues: (response.groups ?? []).map { ($0.id, $0.title) }
        )
        let activeTasks = response.tasks.filter { $0.status != "completed" && $0.status != "project" }
        let widgetTasks = WidgetTasksUtils
            .sortByDueDate(
                activeTasks.map { task in
                    WidgetTask(
                        id: task.id,
                        title: task.title,
                        projectName: task.projectId.flatMap { projectTitleById[$0] },
                        groupName: task.groupId.flatMap { groupTitleById[$0] },
                        hasNotes: !(task.notes?.isEmpty ?? true),
                        deadline: task.deadline
                    )
                }
            )

        return WidgetTaskSnapshotRefresh.reconcile(
            tasks: widgetTasks,
            previousSnapshot: previousSnapshot,
            now: now
        )
    }
}

private struct TasksWidgetTodayResponse: Decodable {
    let tasks: [TasksWidgetTaskPayload]
    let projects: [TasksWidgetProjectPayload]?
    let groups: [TasksWidgetGroupPayload]?
}

private struct TasksWidgetTaskPayload: Decodable {
    let id: String
    let title: String
    let status: String
    let deadline: String?
    let notes: String?
    let projectId: String?
    let groupId: String?
}

private struct TasksWidgetProjectPayload: Decodable {
    let id: String
    let title: String
}

private struct TasksWidgetGroupPayload: Decodable {
    let id: String
    let title: String
}
