import Foundation

/// Lightweight task model for widgets (subset of TaskItem)
public struct WidgetTask: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let projectName: String?
    public let hasNotes: Bool

    public init(
        id: String,
        title: String,
        isCompleted: Bool = false,
        projectName: String? = nil,
        hasNotes: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.projectName = projectName
        self.hasNotes = hasNotes
    }
}

/// Data snapshot for widgets
public struct WidgetTaskData: Codable, Equatable {
    public let tasks: [WidgetTask]
    public let totalCount: Int
    public let lastUpdated: Date

    public init(tasks: [WidgetTask], totalCount: Int, lastUpdated: Date = Date()) {
        self.tasks = tasks
        self.totalCount = totalCount
        self.lastUpdated = lastUpdated
    }

    public static let empty = WidgetTaskData(tasks: [], totalCount: 0)

    public static let placeholder = WidgetTaskData(
        tasks: [
            WidgetTask(id: "1", title: "Review project proposal", projectName: "Work"),
            WidgetTask(id: "2", title: "Call dentist", hasNotes: true),
            WidgetTask(id: "3", title: "Buy groceries"),
            WidgetTask(id: "4", title: "Prepare presentation", projectName: "Work"),
        ],
        totalCount: 6
    )
}
