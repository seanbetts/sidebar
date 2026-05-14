import Foundation
import sideBarShared

/// Stores UI state derived from tasks data and selection.
public struct TasksViewState: Equatable {
    public let selectionLabel: String
    public let titleIcon: AppIcon
    public let sections: [TaskSection]
    public let totalCount: Int
    public let selection: TaskSelection
    public let projectTitleById: [String: String]
    public let groupTitleById: [String: String]
}
