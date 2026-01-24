import Foundation

public protocol TasksProviding {
    func list(scope: String) async throws -> TaskListResponse
    func projectTasks(projectId: String) async throws -> TaskListResponse
    func groupTasks(groupId: String) async throws -> TaskListResponse
    func search(query: String) async throws -> TaskListResponse
    func counts() async throws -> TaskCountsResponse
    func createGroup(title: String) async throws -> TaskGroup
    func createProject(title: String, groupId: String?) async throws -> TaskProject
    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse
    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse
}

public struct TaskOperationBatch: Encodable {
    public let operations: [TaskOperationPayload]

    public init(operations: [TaskOperationPayload]) {
        self.operations = operations
    }
}

public struct TaskOperationPayload: Encodable {
    public let operationId: String
    public let op: String
    public let id: String?
    public let title: String?
    public let notes: String?
    public let listId: String?
    public let dueDate: String?
    public let startDate: String?
    public let recurrenceRule: RecurrenceRule?
    public let clientUpdatedAt: String?

    public init(
        operationId: String,
        op: String,
        id: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        listId: String? = nil,
        dueDate: String? = nil,
        startDate: String? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        clientUpdatedAt: String? = nil
    ) {
        self.operationId = operationId
        self.op = op
        self.id = id
        self.title = title
        self.notes = notes
        self.listId = listId
        self.dueDate = dueDate
        self.startDate = startDate
        self.recurrenceRule = recurrenceRule
        self.clientUpdatedAt = clientUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case op
        case id
        case title
        case notes
        case listId = "list_id"
        case dueDate = "due_date"
        case startDate = "start_date"
        case recurrenceRule = "recurrence_rule"
        case clientUpdatedAt = "client_updated_at"
    }
}

public struct TaskSyncRequest: Encodable {
    public let lastSync: String?
    public let operations: [TaskOperationPayload]

    public init(lastSync: String?, operations: [TaskOperationPayload]) {
        self.lastSync = lastSync
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case lastSync = "last_sync"
        case operations
    }
}

private struct TaskCreateGroupRequest: Encodable {
    let title: String
}

private struct TaskCreateProjectRequest: Encodable {
    let title: String
    let groupId: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case groupId
    }
}

public struct TasksAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list(scope: String) async throws -> TaskListResponse {
        try await client.request("tasks/lists/\(scope)")
    }

    public func projectTasks(projectId: String) async throws -> TaskListResponse {
        try await client.request("tasks/projects/\(projectId)/tasks")
    }

    public func groupTasks(groupId: String) async throws -> TaskListResponse {
        try await client.request("tasks/groups/\(groupId)/tasks")
    }

    public func search(query: String) async throws -> TaskListResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await client.request("tasks/search?query=\(encoded)")
    }

    public func counts() async throws -> TaskCountsResponse {
        try await client.request("tasks/counts")
    }

    public func createGroup(title: String) async throws -> TaskGroup {
        try await client.request("tasks/groups", method: "POST", body: TaskCreateGroupRequest(title: title))
    }

    public func createProject(title: String, groupId: String?) async throws -> TaskProject {
        try await client.request(
            "tasks/projects",
            method: "POST",
            body: TaskCreateProjectRequest(title: title, groupId: groupId)
        )
    }

    public func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        try await client.request("tasks/apply", method: "POST", body: payload)
    }

    public func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        try await client.request("tasks/sync", method: "POST", body: payload)
    }
}

extension TasksAPI: TasksProviding {}

public enum TaskOperationId {
    public static func make() -> String {
        UUID().uuidString
    }
}
