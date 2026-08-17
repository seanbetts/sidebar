import Foundation
import sideBarShared
@testable import sideBar

@MainActor
final class StaleRecoveryTasksAPI: TasksProviding {
    private let task: TaskItem
    private(set) var fixedAuthorizationSyncCallCount = 0
    private(set) var currentSessionSyncCallCount = 0
    private(set) var authorizationTokens: [String] = []
    private var isCompleted = false

    init(task: TaskItem) {
        self.task = task
    }

    func list(scope: String) async throws -> TaskListResponse {
        TaskListResponse(
            scope: scope,
            generatedAt: nil,
            tasks: isCompleted ? [] : [task],
            projects: [],
            groups: []
        )
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        _ = projectId
        throw StaleRecoveryTasksAPIError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        _ = groupId
        throw StaleRecoveryTasksAPIError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        throw StaleRecoveryTasksAPIError.unused
    }

    func counts() async throws -> TaskCountsResponse {
        TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: isCompleted ? 0 : 1, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
    }

    func createGroup(title: String) async throws -> TaskGroup {
        _ = title
        throw StaleRecoveryTasksAPIError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw StaleRecoveryTasksAPIError.unused
    }

    func deleteGroup(groupId: String) async throws {
        _ = groupId
        throw StaleRecoveryTasksAPIError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw StaleRecoveryTasksAPIError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw StaleRecoveryTasksAPIError.unused
    }

    func deleteProject(projectId: String) async throws {
        _ = projectId
        throw StaleRecoveryTasksAPIError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        _ = payload
        throw StaleRecoveryTasksAPIError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        currentSessionSyncCallCount += 1
        return syncResponse(for: payload)
    }

    func sync(
        _ payload: TaskSyncRequest,
        authorizationToken: String
    ) async throws -> TaskSyncResponse {
        fixedAuthorizationSyncCallCount += 1
        authorizationTokens.append(authorizationToken)
        return syncResponse(for: payload)
    }

    private func syncResponse(for payload: TaskSyncRequest) -> TaskSyncResponse {
        let operationIds = payload.operations.map(\.operationId)
        if payload.operations.contains(where: { $0.op == "complete" && $0.id == task.id }) {
            isCompleted = true
        }
        return TaskSyncResponse(
            applied: operationIds,
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: "recovered-token"
        )
    }
}

private enum StaleRecoveryTasksAPIError: Error {
    case unused
}
