import Foundation
import sideBarShared
@testable import sideBar

@MainActor
final class TasksTestNetworkStatus: NetworkStatusProviding {
    var isNetworkAvailable: Bool
    var isServerReachable: Bool
    var isOffline: Bool { !isNetworkAvailable }

    init(isNetworkAvailable: Bool, isServerReachable: Bool = true) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isServerReachable = isServerReachable
    }
}

@MainActor
final class TasksViewModelAPIStub: TasksProviding {
    var listCallCount = 0
    var searchCallCount = 0
    var countsCallCount = 0
    var applyCallCount = 0
    var groupTasksCallCount = 0
    var projectTasksCallCount = 0
    var createGroupCallCount = 0
    var deleteGroupCallCount = 0
    var deleteProjectCallCount = 0
    var lastApplyPayload: TaskOperationBatch?
    var applyResult: Result<TaskSyncResponse, Error> = .success(
        TaskSyncResponse(
            applied: [],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: nil
        )
    )
    var searchResponse = TaskListResponse(scope: "search", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    var groupTasksResponse: TaskListResponse?
    var projectTasksResponse: TaskListResponse?
    var createGroupResult: Result<TaskGroup, Error> = .failure(TasksTestStubError.unused)
    var deleteGroupResult: Result<Void, Error> = .failure(TasksTestStubError.unused)
    var deleteProjectResult: Result<Void, Error> = .failure(TasksTestStubError.unused)
    private var queuedListResponsesByScope: [String: [TaskListResponse]] = [:]

    func enqueueListResponse(scope: String, tasks: [TaskItem], groups: [TaskGroup]? = nil, projects: [TaskProject]? = nil) {
        let response = TaskListResponse(
            scope: scope,
            generatedAt: nil,
            tasks: tasks,
            projects: projects,
            groups: groups
        )
        queuedListResponsesByScope[scope, default: []].append(response)
    }

    func list(scope: String) async throws -> TaskListResponse {
        listCallCount += 1
        if var responses = queuedListResponsesByScope[scope], !responses.isEmpty {
            let first = responses.removeFirst()
            queuedListResponsesByScope[scope] = responses
            return first
        }
        return TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        projectTasksCallCount += 1
        if let response = projectTasksResponse {
            return response
        }
        return TaskListResponse(scope: "project", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        groupTasksCallCount += 1
        if let response = groupTasksResponse {
            return response
        }
        return TaskListResponse(scope: "group", generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        searchCallCount += 1
        return searchResponse
    }

    func counts() async throws -> TaskCountsResponse {
        countsCallCount += 1
        return TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(inbox: 1, today: 1, upcoming: 1, completed: 1),
            projects: [],
            groups: []
        )
    }

    func createGroup(title: String) async throws -> TaskGroup {
        createGroupCallCount += 1
        return try createGroupResult.get()
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw TasksTestStubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        deleteGroupCallCount += 1
        try deleteGroupResult.get()
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw TasksTestStubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw TasksTestStubError.unused
    }

    func deleteProject(projectId: String) async throws {
        deleteProjectCallCount += 1
        try deleteProjectResult.get()
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        lastApplyPayload = payload
        applyCallCount += 1
        return try applyResult.get()
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        _ = payload
        throw TasksTestStubError.unused
    }
}

enum TasksTestStubError: Error {
    case unused
}
