import Foundation
import sideBarShared

extension TasksUtils {
    public static func buildUpcomingSections(tasks: [TaskItem]) -> [TaskSection] {
        let today = startOfDay(Date())
        let dailyCutoff = calculateDailyCutoff(from: today)
        var overdue: [TaskItem] = []
        var daily: [String: TaskSection] = [:]
        var weekly: [Int: TaskSection] = [:]
        var monthly: [String: (date: Date, section: TaskSection)] = [:]

        // Filter out undated tasks - we don't show them in Upcoming.
        let datedTasks = tasks.filter { $0.deadline != nil }
        let sorted = datedTasks.sorted { compareByDueThenTitle($0, $1) }

        for task in sorted {
            let bucket = upcomingBucket(for: task, today: today, dailyCutoff: dailyCutoff)
            addUpcomingTask(
                task,
                bucket: bucket,
                overdue: &overdue,
                daily: &daily,
                weekly: &weekly,
                monthly: &monthly
            )
        }

        var sections: [TaskSection] = []
        if !overdue.isEmpty {
            sections.append(TaskSection(id: "overdue", title: "Overdue", tasks: overdue))
        }

        if dailyCutoff >= 1 {
            for offset in 1...dailyCutoff {
                let date = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
                let key = formatDateKey(date)
                let label = formatDayLabel(date: date, dayDiff: offset)
                let section = daily[key] ?? TaskSection(id: key, title: label, tasks: [])
                sections.append(section)
            }
        }

        for weekIndex in 1...3 {
            if let section = weekly[weekIndex] {
                sections.append(section)
            }
        }

        let monthSections = monthly.values.sorted { $0.date < $1.date }
        sections.append(contentsOf: monthSections.map { $0.section })

        return sections
    }

    public static func buildCompletedSections(tasks: [TaskItem]) -> [TaskSection] {
        let today = startOfDay(Date())
        var daily: [String: TaskSection] = [:]

        let datedTasks = tasks.filter { $0.deadline != nil }
        let undated = tasks.filter { $0.deadline == nil }
        let sorted = datedTasks.sorted { compareByDueThenTitle($0, $1) }

        for task in sorted {
            guard let date = parseTaskDate(task) else { continue }
            let diff = dayDiff(from: today, to: date)
            let key = formatDateKey(date)
            let label = formatDayLabel(date: date, dayDiff: diff)
            var section = daily[key] ?? TaskSection(id: key, title: label, tasks: [])
            section.tasks.append(task)
            daily[key] = section
        }

        var sections: [TaskSection] = []
        let sortedKeys = daily.keys.sorted { lhs, rhs in
            guard let left = tasksDateFormatter.date(from: lhs),
                  let right = tasksDateFormatter.date(from: rhs) else {
                return lhs < rhs
            }
            return left > right
        }
        for key in sortedKeys {
            if let section = daily[key], !section.tasks.isEmpty {
                sections.append(section)
            }
        }
        if !undated.isEmpty {
            sections.append(TaskSection(id: "undated", title: "No due date", tasks: undated))
        }

        return sections
    }

    private enum UpcomingBucket {
        case undated
        case overdue
        case daily(key: String, label: String)
        case weekly(index: Int, label: String)
        case monthly(key: String, date: Date, label: String)
    }

    private static func upcomingBucket(for task: TaskItem, today: Date, dailyCutoff: Int) -> UpcomingBucket {
        guard let date = parseTaskDate(task) else {
            return .undated
        }
        let diff = dayDiff(from: today, to: date)
        if diff < 0 {
            return .overdue
        }
        if diff <= dailyCutoff {
            let key = formatDateKey(date)
            let label = formatDayLabel(date: date, dayDiff: diff)
            return .daily(key: key, label: label)
        }
        if diff <= dailyCutoff + 21 {
            let todayMonday = mondayOfWeek(for: today)
            let dateMonday = mondayOfWeek(for: date)
            let weekIndex = dayDiff(from: todayMonday, to: dateMonday) / 7
            let label = formatWeekLabel(date: dateMonday)
            return .weekly(index: weekIndex, label: label)
        }
        let monthKey = "\(Calendar.current.component(.year, from: date))-\(Calendar.current.component(.month, from: date))"
        let label = formatMonthLabel(date: date)
        return .monthly(key: monthKey, date: date, label: label)
    }

    /// Returns the Monday of the week containing the given date.
    private static func mondayOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Calculates the daily section cutoff: shows individual days through Sunday of the current week.
    private static func calculateDailyCutoff(from today: Date) -> Int {
        let sunday = sundayOfWeek(for: today)
        return dayDiff(from: today, to: sunday)
    }

    /// Returns the Sunday of the week containing the given date (Monday-based weeks).
    private static func sundayOfWeek(for date: Date) -> Date {
        let monday = mondayOfWeek(for: date)
        return Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? date
    }

    private static func addUpcomingTask(
        _ task: TaskItem,
        bucket: UpcomingBucket,
        overdue: inout [TaskItem],
        daily: inout [String: TaskSection],
        weekly: inout [Int: TaskSection],
        monthly: inout [String: (date: Date, section: TaskSection)]
    ) {
        switch bucket {
        case .undated:
            return
        case .overdue:
            overdue.append(task)
        case let .daily(key, label):
            var section = daily[key] ?? TaskSection(id: key, title: label, tasks: [])
            section.tasks.append(task)
            daily[key] = section
        case let .weekly(index, label):
            var section = weekly[index] ?? TaskSection(id: "week-\(index)", title: label, tasks: [])
            section.tasks.append(task)
            weekly[index] = section
        case let .monthly(key, date, label):
            if var entry = monthly[key] {
                entry.section.tasks.append(task)
                monthly[key] = entry
            } else {
                monthly[key] = (date, TaskSection(id: "month-\(key)", title: label, tasks: [task]))
            }
        }
    }
}
