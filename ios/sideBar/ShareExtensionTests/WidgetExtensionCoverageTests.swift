import Foundation
import XCTest
@testable import sideBarWidgetsExtension

final class WidgetExtensionCoverageTests: XCTestCase {
    func testWidgetContentTypeKeysAndKindsAreStable() {
        XCTAssertEqual(WidgetContentType.tasks.dataKey, "widget_tasks_data")
        XCTAssertEqual(WidgetContentType.tasks.pendingKey, "widget_tasks_pending")
        XCTAssertTrue(WidgetContentType.tasks.widgetKinds.contains("TodayTasksWidget"))

        XCTAssertEqual(WidgetContentType.notes.dataKey, "widget_notes_data")
        XCTAssertTrue(WidgetContentType.notes.widgetKinds.contains("PinnedNotesWidget"))

        XCTAssertEqual(WidgetContentType.websites.dataKey, "widget_websites_data")
        XCTAssertTrue(WidgetContentType.websites.widgetKinds.contains("SavedSitesWidget"))

        XCTAssertEqual(WidgetContentType.files.dataKey, "widget_files_data")
        XCTAssertTrue(WidgetContentType.files.widgetKinds.contains("PinnedFilesWidget"))
    }

    func testVisibleTasksExcludesExpiredCompletions() {
        let now = Date(timeIntervalSince1970: 2_000)
        let completedAt = now.addingTimeInterval(-10)

        let expired = WidgetTask(id: "1", title: "Expired", isCompleted: true, completedAt: completedAt)
        let active = WidgetTask(id: "2", title: "Active")

        let visible = WidgetTasksUtils.visibleTasks([expired, active], now: now)

        XCTAssertEqual(visible.map(\.id), ["2"])
        XCTAssertTrue(WidgetTasksUtils.hasCompletionDisplayExpired(expired, now: now))
        XCTAssertNotNil(WidgetTasksUtils.completionRemovalDate(for: expired))
    }

    func testSortByDueDatePrioritizesOverdueThenUpcomingThenNoDeadline() {
        let overdue = WidgetTask(id: "1", title: "Overdue", deadline: "2000-01-01")
        let upcomingA = WidgetTask(id: "2", title: "Alpha", deadline: "2099-01-02")
        let upcomingB = WidgetTask(id: "3", title: "Beta", deadline: "2099-01-02")
        let unscheduled = WidgetTask(id: "4", title: "No Due Date")

        let sorted = WidgetTasksUtils.sortByDueDate([unscheduled, upcomingB, overdue, upcomingA])

        XCTAssertEqual(sorted.map(\.id), ["1", "2", "3", "4"])
        XCTAssertTrue(WidgetTasksUtils.isOverdue(overdue))
        XCTAssertFalse(WidgetTasksUtils.isOverdue(upcomingA))
    }

    func testQuickSaveRoundTripAndConsumeClearsStoredValue() {
        let manager = WidgetDataManager.shared
        let url = URL(string: "https://example.com/docs")!

        manager.recordPendingQuickSave(url: url)
        XCTAssertEqual(manager.consumePendingQuickSave(), url)
        XCTAssertNil(manager.consumePendingQuickSave())
    }

    func testWidgetIntentsExecuteWithoutThrowing() async throws {
        _ = try await OpenScratchpadIntent().perform()
        _ = try await StartChatIntent().perform()
        _ = try await OpenChatIntent(chatId: "chat_1").perform()

        _ = try await OpenTodayIntent().perform()
        _ = try await AddTaskIntent().perform()
        _ = try await OpenTaskIntent(taskId: "task_1").perform()
        _ = try await CompleteTaskIntent(taskId: "task_1").perform()

        _ = try await OpenNotesIntent().perform()
        _ = try await CreateNoteIntent().perform()
        _ = try await OpenNoteIntent(notePath: "/notes/a.md").perform()

        _ = try await OpenFilesIntent().perform()
        _ = try await OpenFileIntent(fileId: "file_1").perform()

        _ = try await OpenWebsitesIntent().perform()
        _ = try await OpenWebsiteIntent(websiteId: "site_1").perform()
        _ = try await QuickSaveIntent(url: URL(string: "https://example.com")!).perform()
    }
}
