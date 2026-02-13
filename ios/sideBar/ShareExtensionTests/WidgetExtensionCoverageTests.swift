import Foundation
import WidgetKit
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

    func testSavedSitesWidgetUsesSevenItemsForLargeFamily() {
        XCTAssertEqual(SavedSitesWidgetView.maxSites(for: .systemSmall), 3)
        XCTAssertEqual(SavedSitesWidgetView.maxSites(for: .systemMedium), 3)
        XCTAssertEqual(SavedSitesWidgetView.maxSites(for: .systemLarge), 7)
    }

    func testWidgetWebsiteResolvedFaviconURLPrefersMetadataValue() {
        let site = WidgetWebsite(
            id: "site-1",
            title: "OpenAI",
            url: "https://openai.com/research",
            domain: "openai.com",
            faviconUrl: "https://cdn.openai.com/favicon.ico"
        )

        XCTAssertEqual(site.resolvedFaviconURL?.absoluteString, "https://cdn.openai.com/favicon.ico")
    }

    func testWidgetWebsiteResolvedFaviconURLFallsBackToWebsiteDomain() {
        let site = WidgetWebsite(
            id: "site-2",
            title: "Example",
            url: "https://sub.example.com/path/page",
            domain: "sub.example.com",
            faviconUrl: nil
        )

        XCTAssertEqual(site.resolvedFaviconURL?.absoluteString, "https://sub.example.com/favicon.ico")
    }

    func testWidgetWebsiteResolvedFaviconURLReturnsNilForInvalidURLs() {
        let site = WidgetWebsite(
            id: "site-3",
            title: "Broken",
            url: "not-a-url",
            domain: "example.com",
            faviconUrl: "ftp://example.com/favicon.ico"
        )

        XCTAssertNil(site.resolvedFaviconURL)
    }

    func testWidgetWebsiteResolvedFaviconURLResolvesRelativeMetadataValue() {
        let site = WidgetWebsite(
            id: "site-4",
            title: "Relative",
            url: "https://example.com/articles/1",
            domain: "example.com",
            faviconUrl: "/assets/favicon.png"
        )

        XCTAssertEqual(site.resolvedFaviconURL?.absoluteString, "https://example.com/assets/favicon.png")
    }

    func testWidgetWebsiteDisplayDomainMatchesSidebarFormatting() {
        let prefixed = WidgetWebsite(
            id: "site-5",
            title: "Guardian",
            url: "https://www.theguardian.com",
            domain: "www.theguardian.com"
        )
        let plain = WidgetWebsite(
            id: "site-6",
            title: "HBR",
            url: "https://hbr.org",
            domain: "hbr.org"
        )

        XCTAssertEqual(prefixed.displayDomain, "theguardian.com")
        XCTAssertEqual(plain.displayDomain, "hbr.org")
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
