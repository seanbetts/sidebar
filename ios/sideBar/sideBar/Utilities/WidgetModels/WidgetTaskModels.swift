import Foundation
import sideBarShared

// MARK: - TaskItem to WidgetTask Conversion

extension WidgetTask {
  /// Creates a WidgetTask from a TaskItem with optional name lookups
  public init(from task: TaskItem, projectName: String? = nil, groupName: String? = nil) {
    self.init(
      id: task.id,
      title: task.title,
      isCompleted: task.status == "completed",
      completedAt: nil,
      projectName: projectName,
      groupName: groupName,
      hasNotes: !(task.notes?.isEmpty ?? true),
      deadline: task.deadline
    )
  }
}
