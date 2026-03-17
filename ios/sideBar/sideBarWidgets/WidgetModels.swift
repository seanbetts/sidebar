import Foundation
import sideBarShared

// MARK: - Widget Task Ordering

private let widgetTasksDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone.current
  return formatter
}()

public enum WidgetTasksUtils {
  private static let msPerDay: Double = 24 * 60 * 60
  private static let completionDisplayDurationSeconds: TimeInterval = 1.25

  public static func visibleTasks(_ tasks: [WidgetTask], now: Date) -> [WidgetTask] {
    tasks.filter { task in
      !hasCompletionDisplayExpired(task, now: now)
    }
  }

  public static func completionRemovalDate(for task: WidgetTask) -> Date? {
    guard task.isCompleted, let completedAt = task.completedAt else { return nil }
    return completedAt.addingTimeInterval(completionDisplayDurationSeconds)
  }

  public static func hasCompletionDisplayExpired(_ task: WidgetTask, now: Date) -> Bool {
    guard let removalDate = completionRemovalDate(for: task) else { return false }
    return now >= removalDate
  }

  public static func isOverdue(_ task: WidgetTask) -> Bool {
    guard let date = parseTaskDate(task) else { return false }
    let today = startOfDay(Date())
    return dayDiff(from: today, to: date) < 0
  }

  public static func sortByDueDate(_ tasks: [WidgetTask]) -> [WidgetTask] {
    tasks.sorted { lhs, rhs in
      compareByDueThenTitle(lhs, rhs)
    }
  }

  private static func parseTaskDate(_ task: WidgetTask) -> Date? {
    guard let deadline = task.deadline, deadline.count >= 10 else { return nil }
    let dateKey = String(deadline.prefix(10))
    return widgetTasksDateFormatter.date(from: dateKey)
  }

  private static func compareByDueThenTitle(_ lhs: WidgetTask, _ rhs: WidgetTask) -> Bool {
    let lhsOverdue = isOverdue(lhs)
    let rhsOverdue = isOverdue(rhs)
    if lhsOverdue != rhsOverdue {
      return lhsOverdue
    }
    let dateA = parseTaskDate(lhs)
    let dateB = parseTaskDate(rhs)
    if dateA == nil && dateB == nil {
      return lhs.title.lowercased() < rhs.title.lowercased()
    }
    if dateA == nil {
      return false
    }
    if dateB == nil {
      return true
    }
    if let dateA, let dateB, dateA != dateB {
      return dateA < dateB
    }
    return lhs.title.lowercased() < rhs.title.lowercased()
  }

  private static func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
  }

  private static func dayDiff(from start: Date, to end: Date) -> Int {
    Int(floor((startOfDay(end).timeIntervalSince(startOfDay(start))) / msPerDay))
  }
}
