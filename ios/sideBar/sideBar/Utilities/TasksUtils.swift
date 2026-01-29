import Foundation
import sideBarShared

private let tasksDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
}()

private let displayMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "LLLL yyyy"
    return formatter
}()

private let displayWeekFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "d MMM"
    return formatter
}()

public enum TasksUtils {
    private static let msPerDay: Double = 24 * 60 * 60

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

    public static func buildTodaySections(
        tasks: [TaskItem],
        groups: [TaskGroup],
        projects: [TaskProject],
        groupTitleById: [String: String],
        projectTitleById: [String: String]
    ) -> [TaskSection] {
        var buckets = buildGroupBuckets(groups)
        for task in tasks {
            appendTaskToTodayBuckets(
                task,
                buckets: &buckets,
                projects: projects,
                groupTitleById: groupTitleById,
                projectTitleById: projectTitleById
            )
        }

        for key in buckets.keys {
            if var section = buckets[key] {
                section.tasks = sortByDueDate(section.tasks)
                buckets[key] = section
            }
        }

        return orderedTodaySections(from: buckets, groups: groups)
    }

    public static func buildSearchSections(tasks: [TaskItem], groups: [TaskGroup]) -> [TaskSection] {
        var sections: [TaskSection] = []
        var tasksByGroup: [String: [TaskItem]] = [:]
        var unassigned: [TaskItem] = []

        for group in groups {
            tasksByGroup[group.id] = []
        }

        for task in tasks {
            if let groupId = task.groupId, tasksByGroup[groupId] != nil {
                tasksByGroup[groupId]?.append(task)
            } else {
                unassigned.append(task)
            }
        }

        for group in groups {
            let bucket = tasksByGroup[group.id] ?? []
            if !bucket.isEmpty {
                sections.append(TaskSection(id: group.id, title: group.title, tasks: sortByDueDate(bucket)))
            }
        }

        if !unassigned.isEmpty {
            sections.append(TaskSection(id: "other", title: "Other", tasks: sortByDueDate(unassigned)))
        }

        return sections
    }

    public static func buildGroupSections(
        tasks: [TaskItem],
        groupId: String,
        groupTitle: String,
        projects: [TaskProject]
    ) -> [TaskSection] {
        let projectsInGroup = projects.filter { $0.groupId == groupId }
        let projectById = Dictionary(uniqueKeysWithValues: projectsInGroup.map { ($0.id, $0) })
        var projectSections: [String: [TaskItem]] = [:]
        var groupTasks: [TaskItem] = []

        for task in tasks {
            if let projectId = task.projectId, projectById[projectId] != nil {
                projectSections[projectId, default: []].append(task)
                continue
            }
            if task.groupId == groupId || task.projectId == nil {
                groupTasks.append(task)
            }
        }

        var sections: [TaskSection] = []
        if !groupTasks.isEmpty {
            sections.append(TaskSection(id: "group", title: groupTitle, tasks: groupTasks))
        }

        for project in projectsInGroup.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if let bucket = projectSections[project.id], !bucket.isEmpty {
                sections.append(TaskSection(id: project.id, title: project.title, tasks: bucket))
            }
        }

        return sections
    }

    public static func buildUpcomingSections(tasks: [TaskItem]) -> [TaskSection] {
        let today = startOfDay(Date())
        let dailyCutoff = calculateDailyCutoff(from: today)
        var overdue: [TaskItem] = []
        var daily: [String: TaskSection] = [:]
        var weekly: [Int: TaskSection] = [:]
        var monthly: [String: (date: Date, section: TaskSection)] = [:]

        // Filter out undated tasks - we don't show them in Upcoming
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

        // Show individual days from tomorrow through Sunday of the current week
        // Weekly sections start from the following Monday
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

    private static func buildGroupBuckets(_ groups: [TaskGroup]) -> [String: TaskSection] {
        var buckets: [String: TaskSection] = [:]
        for group in groups {
            buckets["group:\(group.id)"] = TaskSection(id: group.id, title: group.title, tasks: [])
        }
        return buckets
    }

    private static func appendTaskToTodayBuckets(
        _ task: TaskItem,
        buckets: inout [String: TaskSection],
        projects: [TaskProject],
        groupTitleById: [String: String],
        projectTitleById: [String: String]
    ) {
        if let groupId = resolvedGroupId(for: task, projects: projects) {
            let key = "group:\(groupId)"
            let title = groupTitleById[groupId] ?? "Group"
            appendTask(task, buckets: &buckets, key: key, title: title)
            return
        }
        if let projectId = task.projectId {
            let key = "project:\(projectId)"
            let title = projectTitleById[projectId] ?? "Project"
            appendTask(task, buckets: &buckets, key: key, title: title)
            return
        }
        appendTask(task, buckets: &buckets, key: "other", title: "Other")
    }

    private static func resolvedGroupId(for task: TaskItem, projects: [TaskProject]) -> String? {
        if let groupId = task.groupId {
            return groupId
        }
        guard let projectId = task.projectId else {
            return nil
        }
        return projects.first(where: { $0.id == projectId })?.groupId
    }

    private static func appendTask(
        _ task: TaskItem,
        buckets: inout [String: TaskSection],
        key: String,
        title: String
    ) {
        var section = buckets[key] ?? TaskSection(id: key, title: title, tasks: [])
        section.tasks.append(task)
        buckets[key] = section
    }

    private static func orderedTodaySections(
        from buckets: [String: TaskSection],
        groups: [TaskGroup]
    ) -> [TaskSection] {
        var sections: [TaskSection] = []
        for group in groups {
            if let section = buckets["group:\(group.id)"], !section.tasks.isEmpty {
                sections.append(TaskSection(id: group.id, title: section.title, tasks: section.tasks))
            }
        }
        for (key, section) in buckets where key.hasPrefix("project:") && !section.tasks.isEmpty {
            sections.append(TaskSection(id: key, title: section.title, tasks: section.tasks))
        }
        if let other = buckets["other"], !other.tasks.isEmpty {
            sections.append(other)
        }
        return sections
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
            // Use Monday-based calendar weeks
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
        calendar.firstWeekday = 2 // Monday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Calculates the daily section cutoff: shows individual days through Sunday of the current week.
    /// Weekly sections start from next Monday.
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
            return // Undated tasks are filtered out before this is called
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

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func dayDiff(from start: Date, to end: Date) -> Int {
        Int(floor((startOfDay(end).timeIntervalSince(startOfDay(start))) / msPerDay))
    }

    private static func formatDayLabel(date: Date, dayDiff: Int) -> String {
        if dayDiff == 0 { return "Today" }
        if dayDiff == 1 { return "Tomorrow" }
        if dayDiff == -1 { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private static func formatWeekLabel(date: Date) -> String {
        let label = displayWeekFormatter.string(from: date)
        return "Week of \(label)"
    }

    private static func formatMonthLabel(date: Date) -> String {
        displayMonthFormatter.string(from: date)
    }

    private static func compareByDueThenTitle(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
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
}
