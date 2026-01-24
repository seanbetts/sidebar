import Foundation

private extension TaskSelection {
    var isSearch: Bool {
        if case .search = self {
            return true
        }
        return false
    }
}

public struct TasksViewState: Equatable {
    public let selectionLabel: String
    public let titleIcon: String
    public let sections: [TaskSection]
    public let totalCount: Int
    public let selection: TaskSelection
    public let projectTitleById: [String: String]
    public let groupTitleById: [String: String]
}
