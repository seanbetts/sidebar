import Foundation

/// Stores UI state derived from tasks data and selection.
public struct TasksViewState: Equatable {
    public let selectionLabel: String
    public let titleIcon: String
    public let sections: [TaskSection]
    public let totalCount: Int
    public let selection: TaskSelection
    public let projectTitleById: [String: String]
    public let groupTitleById: [String: String]
}
