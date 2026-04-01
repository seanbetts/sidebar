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
        let response: TasksWidgetTodayResponse = try await apiClient.request("tasks/lists/today")
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

        return buildSnapshot(
            tasks: Array(widgetTasks.prefix(10)),
            remainingCount: activeTasks.count,
            previousSnapshot: previousSnapshot,
            now: now
        )
    }

    private func buildSnapshot(
        tasks: [WidgetTask],
        remainingCount: Int,
        previousSnapshot: WidgetTaskData,
        now: Date
    ) -> WidgetTaskData {
        let calendar = Calendar.current
        let progressCompletedCount: Int
        let progressTotalCount: Int

        if calendar.isDate(previousSnapshot.lastUpdated, inSameDayAs: now) {
            let persistedCompleted = max(0, previousSnapshot.progressCompletedCount)
            let persistedTotal = max(0, previousSnapshot.progressTotalCount)
            let nextTotal = max(persistedTotal, remainingCount + persistedCompleted)
            let inferredCompleted = max(persistedCompleted, nextTotal - remainingCount)
            progressTotalCount = nextTotal
            progressCompletedCount = min(inferredCompleted, nextTotal)
        } else {
            progressTotalCount = max(0, remainingCount)
            progressCompletedCount = 0
        }

        return WidgetTaskData(
            tasks: tasks,
            totalCount: remainingCount,
            progressCompletedCount: progressCompletedCount,
            progressTotalCount: progressTotalCount,
            lastUpdated: now
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
