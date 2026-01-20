import Foundation

// TODO: Revisit to prefer native-first data sources where applicable.

public protocol TaskProvider {
    func listTasks(scope: String) async throws -> [TaskItem]
    func searchTasks(query: String) async throws -> [TaskItem]
    func createTask(_ draft: TaskDraft) async throws -> TaskItem
    func updateTask(_ task: TaskItem) async throws -> TaskItem
    func deleteTask(id: String) async throws
    func deferTask(id: String, days: Int) async throws
    func moveTask(id: String, toProjectId: String?) async throws
    func setDueDate(id: String, date: Date?) async throws
}

/// Represents a task returned by a task provider.
public struct TaskItem: Identifiable, Codable {
    public let id: String
    public let title: String
    public let status: String
    public let deadline: String?
    public let notes: String?
    public let projectId: String?
    public let areaId: String?
    public let updatedAt: String?
}

/// Defines the fields needed to create or update a task.
public struct TaskDraft: Codable {
    public let title: String
    public let notes: String?
    public let projectId: String?
    public let areaId: String?
    public let dueDate: String?
}
