import Foundation
import sideBarShared

public enum TasksUtils {
    static let msPerDay: Double = 24 * 60 * 60

    static let tasksDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static let displayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    static let displayWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    public static func parseTaskDate(_ task: TaskItem) -> Date? {
        guard let deadline = task.deadline, deadline.count >= 10 else { return nil }
        let dateKey = String(deadline.prefix(10))
        return tasksDateFormatter.date(from: dateKey)
    }

    public static func formatDateKey(_ date: Date) -> String {
        tasksDateFormatter.string(from: date)
    }

    public static func dueLabel(for task: TaskItem) -> String? {
        guard let date = parseTaskDate(task) else { return nil }
        let today = startOfDay(Date())
        let diff = dayDiff(from: today, to: date)
        if diff == 0 {
            return "Today"
        }
        if diff == 1 {
            return "Tomorrow"
        }
        if diff == -1 {
            return "Yesterday"
        }
        if diff > 1 && diff <= 6 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    public static func recurrenceLabel(for task: TaskItem) -> String? {
        guard let rule = task.recurrenceRule else { return nil }
        let interval = rule.interval ?? 1
        switch rule.type {
        case "daily":
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case "weekly":
            let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayLabel = rule.weekday.flatMap { weekdays.indices.contains($0) ? weekdays[$0] : nil }
            if interval == 1, let dayLabel {
                return "Weekly on \(dayLabel)"
            }
            if let dayLabel {
                return "Every \(interval) weeks on \(dayLabel)"
            }
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case "monthly":
            if let day = rule.dayOfMonth {
                return interval == 1 ? "Monthly on day \(day)" : "Every \(interval) months on day \(day)"
            }
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        default:
            return nil
        }
    }

    public static func isOverdue(_ task: TaskItem) -> Bool {
        guard let date = parseTaskDate(task) else { return false }
        let today = startOfDay(Date())
        return dayDiff(from: today, to: date) < 0
    }

    public static func expandRepeatingTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        var expanded: [TaskItem] = []
        for task in tasks {
            expanded.append(task)
            if task.repeating == true, let nextDate = task.nextInstanceDate {
                let preview = TaskItem(
                    id: "\(task.id)-next",
                    title: task.title,
                    status: task.status,
                    deadline: nextDate,
                    notes: task.notes,
                    projectId: task.projectId,
                    groupId: task.groupId,
                    repeating: task.repeating,
                    repeatTemplate: true,
                    recurrenceRule: task.recurrenceRule,
                    nextInstanceDate: task.nextInstanceDate,
                    updatedAt: task.updatedAt,
                    deletedAt: task.deletedAt,
                    isPreview: true
                )
                expanded.append(preview)
            }
        }
        return expanded
    }

    public static func sortByDueDate(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            compareByDueThenTitle(lhs, rhs)
        }
    }

    public static func taskSubtitle(
        task: TaskItem,
        selection: TaskSelection,
        selectionLabel: String,
        projectTitleById: [String: String],
        groupTitleById: [String: String]
    ) -> String {
        let projectTitle = task.projectId.flatMap { projectTitleById[$0] } ?? ""
        let groupTitle = task.groupId.flatMap { groupTitleById[$0] } ?? ""

        switch selection {
        case .none:
            return projectTitle.isEmpty ? selectionLabel : projectTitle
        case .project:
            return projectTitle.isEmpty ? selectionLabel : projectTitle
        case .group:
            return !projectTitle.isEmpty ? projectTitle : groupTitle
        case .today, .upcoming, .search, .completed:
            return !projectTitle.isEmpty ? projectTitle : groupTitle
        case .inbox:
            if let deadline = task.deadline {
                return "Due \(String(deadline.prefix(10)))"
            }
            return !projectTitle.isEmpty ? projectTitle : groupTitle
        }
    }

    static func compareByDueThenTitle(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isPreview != rhs.isPreview {
            return lhs.isPreview == false
        }
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

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func dayDiff(from start: Date, to end: Date) -> Int {
        Int(floor((startOfDay(end).timeIntervalSince(startOfDay(start))) / msPerDay))
    }

    static func formatDayLabel(date: Date, dayDiff: Int) -> String {
        if dayDiff == 0 { return "Today" }
        if dayDiff == 1 { return "Tomorrow" }
        if dayDiff == -1 { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func formatWeekLabel(date: Date) -> String {
        let label = displayWeekFormatter.string(from: date)
        return "Week of \(label)"
    }

    static func formatMonthLabel(date: Date) -> String {
        displayMonthFormatter.string(from: date)
    }
}
