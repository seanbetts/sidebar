import Foundation

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
    formatter.dateFormat = "MMM d"
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
                    areaId: task.areaId,
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
        areaTitleById: [String: String]
    ) -> String {
        let projectTitle = task.projectId.flatMap { projectTitleById[$0] } ?? ""
        let areaTitle = task.areaId.flatMap { areaTitleById[$0] } ?? ""

        switch selection {
        case .project:
            return projectTitle.isEmpty ? selectionLabel : projectTitle
        case .area:
            return !projectTitle.isEmpty ? projectTitle : areaTitle
        case .today, .upcoming, .search:
            return !projectTitle.isEmpty ? projectTitle : areaTitle
        case .inbox:
            if let deadline = task.deadline {
                return "Due \(deadline.prefix(10))"
            }
            return !projectTitle.isEmpty ? projectTitle : areaTitle
        }
    }

    public static func buildTodaySections(
        tasks: [TaskItem],
        areas: [TaskArea],
        projects: [TaskProject],
        areaTitleById: [String: String],
        projectTitleById: [String: String]
    ) -> [TaskSection] {
        var buckets: [String: TaskSection] = [:]
        for area in areas {
            buckets["area:\(area.id)"] = TaskSection(id: area.id, title: area.title, tasks: [])
        }

        for task in tasks {
            let project = task.projectId.flatMap { id in projects.first(where: { $0.id == id }) }
            let areaId = task.areaId ?? project?.areaId

            if let areaId {
                let key = "area:\(areaId)"
                if buckets[key] == nil {
                    let title = areaTitleById[areaId] ?? "Group"
                    buckets[key] = TaskSection(id: key, title: title, tasks: [])
                }
                if var section = buckets[key] {
                    section.tasks.append(task)
                    buckets[key] = section
                }
                continue
            }
            if let projectId = task.projectId {
                let key = "project:\(projectId)"
                if buckets[key] == nil {
                    let title = projectTitleById[projectId] ?? "Project"
                    buckets[key] = TaskSection(id: key, title: title, tasks: [])
                }
                if var section = buckets[key] {
                    section.tasks.append(task)
                    buckets[key] = section
                }
                continue
            }
            if buckets["other"] == nil {
                buckets["other"] = TaskSection(id: "other", title: "Other", tasks: [])
            }
            if var section = buckets["other"] {
                section.tasks.append(task)
                buckets["other"] = section
            }
        }

        var sections: [TaskSection] = []
        for area in areas {
            if let section = buckets["area:\(area.id)"], !section.tasks.isEmpty {
                sections.append(TaskSection(id: area.id, title: section.title, tasks: section.tasks))
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

    public static func buildSearchSections(tasks: [TaskItem], areas: [TaskArea]) -> [TaskSection] {
        var sections: [TaskSection] = []
        var tasksByArea: [String: [TaskItem]] = [:]
        var unassigned: [TaskItem] = []

        for area in areas {
            tasksByArea[area.id] = []
        }

        for task in tasks {
            if let areaId = task.areaId, tasksByArea[areaId] != nil {
                tasksByArea[areaId]?.append(task)
            } else {
                unassigned.append(task)
            }
        }

        for area in areas {
            let bucket = tasksByArea[area.id] ?? []
            if !bucket.isEmpty {
                sections.append(TaskSection(id: area.id, title: area.title, tasks: sortByDueDate(bucket)))
            }
        }

        if !unassigned.isEmpty {
            sections.append(TaskSection(id: "other", title: "Other", tasks: sortByDueDate(unassigned)))
        }

        return sections
    }

    public static func buildAreaSections(
        tasks: [TaskItem],
        areaId: String,
        areaTitle: String,
        projects: [TaskProject]
    ) -> [TaskSection] {
        let projectsInArea = projects.filter { $0.areaId == areaId }
        let projectById = Dictionary(uniqueKeysWithValues: projectsInArea.map { ($0.id, $0) })
        var projectSections: [String: [TaskItem]] = [:]
        var areaTasks: [TaskItem] = []

        for task in tasks {
            if let projectId = task.projectId, projectById[projectId] != nil {
                projectSections[projectId, default: []].append(task)
                continue
            }
            if task.areaId == areaId || task.projectId == nil {
                areaTasks.append(task)
            }
        }

        var sections: [TaskSection] = []
        if !areaTasks.isEmpty {
            sections.append(TaskSection(id: "area", title: areaTitle, tasks: areaTasks))
        }

        for project in projectsInArea.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if let bucket = projectSections[project.id], !bucket.isEmpty {
                sections.append(TaskSection(id: project.id, title: project.title, tasks: bucket))
            }
        }

        return sections
    }

    public static func buildUpcomingSections(tasks: [TaskItem]) -> [TaskSection] {
        let today = startOfDay(Date())
        var overdue: [TaskItem] = []
        var undated: [TaskItem] = []
        var daily: [String: TaskSection] = [:]
        var weekly: [Int: TaskSection] = [:]
        var monthly: [String: (date: Date, section: TaskSection)] = [:]

        let sorted = tasks.sorted { compareByDueThenTitle($0, $1) }

        for task in sorted {
            guard let date = parseTaskDate(task) else {
                undated.append(task)
                continue
            }
            let diff = dayDiff(from: today, to: date)
            if diff < 0 {
                overdue.append(task)
                continue
            }
            if diff <= 6 {
                let key = formatDateKey(date)
                let label = formatDayLabel(date: date, dayDiff: diff)
                var section = daily[key] ?? TaskSection(id: key, title: label, tasks: [])
                section.tasks.append(task)
                daily[key] = section
                continue
            }
            if diff <= 27 {
                let weekIndex = Int(floor(Double(diff) / 7.0))
                let weekStart = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: today) ?? today
                let label = formatWeekLabel(date: weekStart)
                var section = weekly[weekIndex] ?? TaskSection(id: "week-\(weekIndex)", title: label, tasks: [])
                section.tasks.append(task)
                weekly[weekIndex] = section
                continue
            }
            let monthKey = "\(Calendar.current.component(.year, from: date))-\(Calendar.current.component(.month, from: date))"
            if var entry = monthly[monthKey] {
                entry.section.tasks.append(task)
                monthly[monthKey] = entry
            } else {
                monthly[monthKey] = (date, TaskSection(id: "month-\(monthKey)", title: formatMonthLabel(date: date), tasks: [task]))
            }
        }

        var sections: [TaskSection] = []
        if !overdue.isEmpty {
            sections.append(TaskSection(id: "overdue", title: "Overdue", tasks: overdue))
        }

        for offset in 0...6 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
            let key = formatDateKey(date)
            if let section = daily[key] {
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

        if !undated.isEmpty {
            sections.append(TaskSection(id: "undated", title: "No date", tasks: undated))
        }

        return sections
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
