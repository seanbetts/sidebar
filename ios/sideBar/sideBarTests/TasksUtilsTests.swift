import XCTest
@testable import sideBar

final class TasksUtilsTests: XCTestCase {

    // MARK: - Date parsing & formatting

    func testParseTaskDateExtractsYYYYMMDD() async {
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: "2025-03-15")
        let date = TasksUtils.parseTaskDate(task)
        XCTAssertNotNil(date)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    func testParseTaskDateReturnsNilForMissingDeadline() async {
        let noDeadline = TaskItem(id: "1", title: "T", status: "open")
        XCTAssertNil(TasksUtils.parseTaskDate(noDeadline))

        let shortString = TaskItem(id: "2", title: "T", status: "open", deadline: "2025")
        XCTAssertNil(TasksUtils.parseTaskDate(shortString))
    }

    func testFormatDateKeyRoundTrips() async {
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: "2025-06-01")
        let date = TasksUtils.parseTaskDate(task)!
        let formatted = TasksUtils.formatDateKey(date)
        XCTAssertEqual(formatted, "2025-06-01")
    }

    // MARK: - Due labels

    func testDueLabelToday() async {
        let today = TasksUtils.formatDateKey(Date())
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: today)
        XCTAssertEqual(TasksUtils.dueLabel(for: task), "Today")
    }

    func testDueLabelTomorrow() async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(tomorrow))
        XCTAssertEqual(TasksUtils.dueLabel(for: task), "Tomorrow")
    }

    func testDueLabelYesterday() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(yesterday))
        XCTAssertEqual(TasksUtils.dueLabel(for: task), "Yesterday")
    }

    func testDueLabelWithinWeek() async {
        let threeDaysOut = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(threeDaysOut))
        let label = TasksUtils.dueLabel(for: task)
        XCTAssertNotNil(label)
        // Should be an abbreviated weekday like "Mon", "Tue", etc.
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let hasWeekdayPrefix = weekdays.contains(where: { label!.contains($0) })
        XCTAssertTrue(hasWeekdayPrefix, "Expected abbreviated weekday, got \(label!)")
    }

    func testDueLabelBeyondWeek() async {
        let tenDaysOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(tenDaysOut))
        let label = TasksUtils.dueLabel(for: task)
        XCTAssertNotNil(label)
        // Should contain month abbreviation and day number (e.g. "Jan 15")
        XCTAssertNotEqual(label, "Today")
        XCTAssertNotEqual(label, "Tomorrow")
        XCTAssertNotEqual(label, "Yesterday")
    }

    func testDueLabelNilDeadline() async {
        let task = TaskItem(id: "1", title: "T", status: "open")
        XCTAssertNil(TasksUtils.dueLabel(for: task))
    }

    // MARK: - Recurrence labels

    func testRecurrenceLabelDaily() async {
        let task = TaskItem(
            id: "1", title: "T", status: "open",
            recurrenceRule: RecurrenceRule(type: "daily", interval: 1, weekday: nil, dayOfMonth: nil)
        )
        XCTAssertEqual(TasksUtils.recurrenceLabel(for: task), "Daily")
    }

    func testRecurrenceLabelWeeklyWithDay() async {
        let task = TaskItem(
            id: "1", title: "T", status: "open",
            recurrenceRule: RecurrenceRule(type: "weekly", interval: 1, weekday: 1, dayOfMonth: nil)
        )
        XCTAssertEqual(TasksUtils.recurrenceLabel(for: task), "Weekly on Mon")
    }

    func testRecurrenceLabelMonthlyWithDay() async {
        let task = TaskItem(
            id: "1", title: "T", status: "open",
            recurrenceRule: RecurrenceRule(type: "monthly", interval: 1, weekday: nil, dayOfMonth: 15)
        )
        XCTAssertEqual(TasksUtils.recurrenceLabel(for: task), "Monthly on day 15")
    }

    func testRecurrenceLabelWithInterval() async {
        let task = TaskItem(
            id: "1", title: "T", status: "open",
            recurrenceRule: RecurrenceRule(type: "weekly", interval: 2, weekday: 2, dayOfMonth: nil)
        )
        XCTAssertEqual(TasksUtils.recurrenceLabel(for: task), "Every 2 weeks on Tue")
    }

    func testRecurrenceLabelNilRule() async {
        let task = TaskItem(id: "1", title: "T", status: "open")
        XCTAssertNil(TasksUtils.recurrenceLabel(for: task))
    }

    // MARK: - Overdue

    func testIsOverdueForPastDate() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(yesterday))
        XCTAssertTrue(TasksUtils.isOverdue(task))
    }

    func testIsOverdueForFutureDate() async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let task = TaskItem(id: "1", title: "T", status: "open", deadline: TasksUtils.formatDateKey(tomorrow))
        XCTAssertFalse(TasksUtils.isOverdue(task))
    }

    // MARK: - Expand repeating

    func testExpandRepeatingTasksCreatesPreview() async {
        let task = TaskItem(
            id: "1", title: "Repeat", status: "open",
            deadline: "2025-03-15",
            repeating: true,
            nextInstanceDate: "2025-03-22"
        )
        let result = TasksUtils.expandRepeatingTasks([task])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "1")
        XCTAssertFalse(result[0].isPreview)
        XCTAssertEqual(result[1].id, "1-next")
        XCTAssertTrue(result[1].isPreview)
        XCTAssertEqual(result[1].deadline, "2025-03-22")
    }

    func testExpandSkipsNonRepeating() async {
        let task = TaskItem(id: "1", title: "Once", status: "open", deadline: "2025-03-15")
        let result = TasksUtils.expandRepeatingTasks([task])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "1")
    }

    // MARK: - Sorting

    func testSortByDueDateOrdersChronologically() async {
        let early = TaskItem(id: "1", title: "A", status: "open", deadline: "2025-03-01")
        let late = TaskItem(id: "2", title: "B", status: "open", deadline: "2025-03-10")
        let result = TasksUtils.sortByDueDate([late, early])
        XCTAssertEqual(result.map(\.id), ["1", "2"])
    }

    func testSortByDueDatePutsNilLast() async {
        let dated = TaskItem(id: "1", title: "A", status: "open", deadline: "2025-03-01")
        let undated = TaskItem(id: "2", title: "B", status: "open")
        let result = TasksUtils.sortByDueDate([undated, dated])
        XCTAssertEqual(result.map(\.id), ["1", "2"])
    }

    func testSortByDueDatePutsPreviewsAfterOriginals() async {
        let original = TaskItem(id: "1", title: "A", status: "open", deadline: "2025-03-01")
        let preview = TaskItem(id: "1-next", title: "A", status: "open", deadline: "2025-03-01", isPreview: true)
        let result = TasksUtils.sortByDueDate([preview, original])
        XCTAssertEqual(result.map(\.id), ["1", "1-next"])
    }

    // MARK: - Section builders

    func testBuildTodaySectionsBucketsTasksByGroup() async {
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let task = TaskItem(id: "t1", title: "Do thing", status: "open", groupId: "g1")
        let sections = TasksUtils.buildTodaySections(
            tasks: [task],
            groups: [group],
            projects: [],
            groupTitleById: ["g1": "Work"],
            projectTitleById: [:]
        )
        XCTAssertTrue(sections.contains(where: { $0.id == "g1" }))
        let workSection = sections.first(where: { $0.id == "g1" })
        XCTAssertEqual(workSection?.tasks.map(\.id), ["t1"])
    }

    func testBuildTodaySectionsResolvesGroupFromProject() async {
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let project = TaskProject(id: "p1", title: "Project A", groupId: "g1", status: "active", updatedAt: nil)
        let task = TaskItem(id: "t1", title: "Do thing", status: "open", projectId: "p1")
        let sections = TasksUtils.buildTodaySections(
            tasks: [task],
            groups: [group],
            projects: [project],
            groupTitleById: ["g1": "Work"],
            projectTitleById: ["p1": "Project A"]
        )
        // Task should land in the group bucket since project resolves to group g1
        let workSection = sections.first(where: { $0.id == "g1" })
        XCTAssertNotNil(workSection)
        XCTAssertEqual(workSection?.tasks.map(\.id), ["t1"])
    }

    func testBuildSearchSectionsGroupsAndUnassigned() async {
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let grouped = TaskItem(id: "t1", title: "Grouped", status: "open", groupId: "g1")
        let ungrouped = TaskItem(id: "t2", title: "Ungrouped", status: "open")
        let sections = TasksUtils.buildSearchSections(tasks: [grouped, ungrouped], groups: [group])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].id, "g1")
        XCTAssertEqual(sections[0].tasks.map(\.id), ["t1"])
        XCTAssertEqual(sections[1].id, "other")
        XCTAssertEqual(sections[1].tasks.map(\.id), ["t2"])
    }

    func testBuildGroupSectionsSplitsByProject() async {
        let project = TaskProject(id: "p1", title: "Alpha", groupId: "g1", status: "active", updatedAt: nil)
        let projectTask = TaskItem(id: "t1", title: "In project", status: "open", projectId: "p1", groupId: "g1")
        let groupTask = TaskItem(id: "t2", title: "In group", status: "open", groupId: "g1")
        let sections = TasksUtils.buildGroupSections(
            tasks: [projectTask, groupTask],
            groupId: "g1",
            groupTitle: "Work",
            projects: [project]
        )
        // Should have a group section and a project section
        XCTAssertTrue(sections.contains(where: { $0.id == "group" }))
        XCTAssertTrue(sections.contains(where: { $0.id == "p1" }))
        let groupSection = sections.first(where: { $0.id == "group" })
        XCTAssertEqual(groupSection?.tasks.map(\.id), ["t2"])
        let projectSection = sections.first(where: { $0.id == "p1" })
        XCTAssertEqual(projectSection?.tasks.map(\.id), ["t1"])
    }

    func testBuildCompletedSectionsOrdersByDateDescending() async {
        let older = TaskItem(id: "t1", title: "Old", status: "completed", deadline: "2025-01-01")
        let newer = TaskItem(id: "t2", title: "New", status: "completed", deadline: "2025-03-01")
        let undated = TaskItem(id: "t3", title: "None", status: "completed")
        let sections = TasksUtils.buildCompletedSections(tasks: [older, newer, undated])
        // Newest date first
        XCTAssertGreaterThanOrEqual(sections.count, 2)
        XCTAssertEqual(sections[0].id, "2025-03-01")
        XCTAssertEqual(sections[1].id, "2025-01-01")
        // Undated at end
        XCTAssertEqual(sections.last?.id, "undated")
        XCTAssertEqual(sections.last?.tasks.map(\.id), ["t3"])
    }

    // MARK: - Subtitle

    func testSubtitleShowsProjectTitleForTodaySelection() async {
        let task = TaskItem(id: "t1", title: "T", status: "open", projectId: "p1")
        let subtitle = TasksUtils.taskSubtitle(
            task: task,
            selection: .today,
            selectionLabel: "Today",
            projectTitleById: ["p1": "My Project"],
            groupTitleById: [:]
        )
        XCTAssertEqual(subtitle, "My Project")
    }

    func testSubtitleShowsDueDateForInbox() async {
        let task = TaskItem(id: "t1", title: "T", status: "open", deadline: "2025-06-15")
        let subtitle = TasksUtils.taskSubtitle(
            task: task,
            selection: .inbox,
            selectionLabel: "Inbox",
            projectTitleById: [:],
            groupTitleById: [:]
        )
        XCTAssertEqual(subtitle, "Due 2025-06-15")
    }
}
