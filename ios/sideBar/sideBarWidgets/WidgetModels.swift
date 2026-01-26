import Foundation

/// Lightweight task model for widgets (subset of TaskItem)
public struct WidgetTask: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let projectName: String?
    public let hasNotes: Bool
    public let deadline: String?

    public init(
        id: String,
        title: String,
        isCompleted: Bool = false,
        projectName: String? = nil,
        hasNotes: Bool = false,
        deadline: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.projectName = projectName
        self.hasNotes = hasNotes
        self.deadline = deadline
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
            WidgetTask(id: "1", title: "Review project proposal", projectName: "Work", deadline: "2026-01-25"),
            WidgetTask(id: "2", title: "Call dentist", hasNotes: true, deadline: "2026-01-26"),
            WidgetTask(id: "3", title: "Buy groceries"),
            WidgetTask(id: "4", title: "Prepare presentation", projectName: "Work", deadline: "2026-01-27"),
        ],
        totalCount: 6
    )
}

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
