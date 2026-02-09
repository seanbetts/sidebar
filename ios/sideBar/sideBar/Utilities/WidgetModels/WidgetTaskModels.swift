import Foundation

// MARK: - Widget Task Models

/// Lightweight task model for widgets (subset of TaskItem)
public struct WidgetTask: WidgetStorable {
  public let id: String
  public let title: String
  public let isCompleted: Bool
  public let completedAt: Date?
  public let projectName: String?
  public let groupName: String?
  public let hasNotes: Bool
  public let deadline: String?

  public init(
    id: String,
    title: String,
    isCompleted: Bool = false,
    completedAt: Date? = nil,
    projectName: String? = nil,
    groupName: String? = nil,
    hasNotes: Bool = false,
    deadline: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.completedAt = completedAt
    self.projectName = projectName
    self.groupName = groupName
    self.hasNotes = hasNotes
    self.deadline = deadline
  }
}

/// Data snapshot for widgets
public struct WidgetTaskData: WidgetDataContainer {
  public typealias Item = WidgetTask

  public let tasks: [WidgetTask]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetTask] { tasks }

  public init(tasks: [WidgetTask], totalCount: Int, lastUpdated: Date = Date()) {
    self.tasks = tasks
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetTaskData(tasks: [], totalCount: 0)

  public static let placeholder = WidgetTaskData(
    tasks: [
      WidgetTask(id: "1", title: "Review project proposal", projectName: "Work", deadline: "2026-01-25"),
      WidgetTask(id: "2", title: "Call dentist", hasNotes: true, deadline: "2026-01-26"),
      WidgetTask(id: "3", title: "Buy groceries", groupName: "Home"),
      WidgetTask(id: "4", title: "Prepare presentation", projectName: "Work", deadline: "2026-01-27")
    ],
    totalCount: 6
  )
}

// MARK: - TaskItem to WidgetTask Conversion

extension WidgetTask {
  /// Creates a WidgetTask from a TaskItem with optional name lookups
  public init(from task: TaskItem, projectName: String? = nil, groupName: String? = nil) {
    self.id = task.id
    self.title = task.title
    self.isCompleted = task.status == "completed"
    self.completedAt = nil
    self.projectName = projectName
    self.groupName = groupName
    self.hasNotes = !(task.notes?.isEmpty ?? true)
    self.deadline = task.deadline
  }
}
