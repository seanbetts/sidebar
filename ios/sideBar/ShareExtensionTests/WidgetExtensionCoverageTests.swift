import Foundation
import AppIntents
import WidgetKit
import XCTest
import sideBarShared
@testable import sideBarWidgetsExtension

final class WidgetExtensionCoverageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalSurfaceDiagnosticsStore.shared.clear()
    }

    override func tearDown() {
        ExternalSurfaceDiagnosticsStore.shared.clear()
        super.tearDown()
    }

    func testWidgetTestsResolveExpectedAppGroupIdentifier() {
        XCTAssertEqual(appGroupIdForWidgetTests(), "group.ai.sidebar.sidebar")
    }

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

    func testWidgetTaskDataDecodingDefaultsProgressFieldsForLegacyPayload() throws {
        let legacyPayload = """
        {
          "tasks": [
            {
              "id": "task-1",
              "title": "Legacy",
              "isCompleted": false,
              "completedAt": null,
              "projectName": null,
              "groupName": null,
              "hasNotes": false,
              "deadline": null
            }
          ],
          "totalCount": 3,
          "lastUpdated": "2026-02-17T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetTaskData.self, from: Data(legacyPayload.utf8))

        XCTAssertEqual(decoded.totalCount, 3)
        XCTAssertEqual(decoded.progressCompletedCount, 0)
        XCTAssertEqual(decoded.progressTotalCount, 3)
    }

    func testCompleteTaskIntentOptimisticallyUpdatesProgressCounts() async throws {
        clearTaskWidgetStorage()
        defer { clearTaskWidgetStorage() }

        let taskOneId = "11111111-1111-1111-1111-111111111111"
        let taskTwoId = "22222222-2222-2222-2222-222222222222"
        let taskThreeId = "33333333-3333-3333-3333-333333333333"
        let seededTasks = [
            WidgetTask(id: taskOneId, title: "Task 1"),
            WidgetTask(id: taskTwoId, title: "Task 2"),
            WidgetTask(id: taskThreeId, title: "Task 3")
        ]
        WidgetDataManager.shared.updateTodayTasks(
            seededTasks,
            totalCount: 3,
            progressCompletedCount: 1,
            progressTotalCount: 4
        )

        _ = try await CompleteTaskIntent(taskId: taskTwoId).perform()
        let updated = WidgetDataManager.shared.loadTodayTasks()

        XCTAssertEqual(updated.totalCount, 2)
        XCTAssertEqual(updated.progressCompletedCount, 2)
        XCTAssertEqual(updated.progressTotalCount, 4)
        XCTAssertEqual(updated.tasks.first(where: { $0.id == taskTwoId })?.isCompleted, true)
    }

    func testCompleteTaskIntentIsIdempotentForAlreadyCompletedTask() async throws {
        clearTaskWidgetStorage()
        defer { clearTaskWidgetStorage() }

        let taskOneId = "11111111-1111-1111-1111-111111111111"
        let taskTwoId = "22222222-2222-2222-2222-222222222222"
        let taskThreeId = "33333333-3333-3333-3333-333333333333"
        let seededTasks = [
            WidgetTask(id: taskOneId, title: "Task 1"),
            WidgetTask(id: taskTwoId, title: "Task 2", isCompleted: true, completedAt: Date()),
            WidgetTask(id: taskThreeId, title: "Task 3")
        ]
        WidgetDataManager.shared.updateTodayTasks(
            seededTasks,
            totalCount: 2,
            progressCompletedCount: 1,
            progressTotalCount: 3
        )

        _ = try await CompleteTaskIntent(taskId: taskTwoId).perform()
        let updated = WidgetDataManager.shared.loadTodayTasks()

        XCTAssertEqual(updated.totalCount, 2)
        XCTAssertEqual(updated.progressCompletedCount, 1)
        XCTAssertEqual(updated.progressTotalCount, 3)
    }

    func testQuickSaveRoundTripAndConsumeClearsStoredValue() {
        let manager = WidgetDataManager.shared
        let url = URL(string: "https://example.com/docs")!

        manager.recordPendingQuickSave(url: url)
        XCTAssertEqual(manager.consumePendingQuickSave(), url)
        XCTAssertNil(manager.consumePendingQuickSave())
    }

    func testWidgetDiagnosticsUseSharedExternalSurfaceStoreMetadata() {
        let groupId = appGroupIdForWidgetTests()
        let defaults = UserDefaults(suiteName: groupId)
        defaults?.set(true, forKey: "widgetIsAuthenticated")
        defaults?.synchronize()
        defer {
            defaults?.removeObject(forKey: "widgetIsAuthenticated")
            defaults?.synchronize()
        }

        XCTAssertTrue(WidgetDataManager.shared.isAuthenticated())

        let export = ExternalSurfaceDiagnosticsStore.shared.exportText(limit: 5)
        XCTAssertTrue(export.contains("[widget_bridge_extension] read_auth_state:"))
        XCTAssertTrue(export.contains("build_number="))
        XCTAssertTrue(export.contains("process_name="))
        XCTAssertTrue(export.contains("bundle_path="))
        XCTAssertTrue(export.contains("app_group_source="))
        XCTAssertTrue(export.contains("auth_key_present=true"))
    }

    func testWidgetLoadDiagnosticsIncludeSnapshotMetadata() throws {
        let groupId = appGroupIdForWidgetTests()
        let defaults = UserDefaults(suiteName: groupId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = WidgetNoteData(
            notes: [
                WidgetNote(id: "/note.md", name: "Note", path: "/note.md", pinned: true, pinnedOrder: 0)
            ],
            totalCount: 1
        )
        defaults?.set(try encoder.encode(payload), forKey: WidgetContentType.notes.dataKey)
        defaults?.synchronize()
        defer {
            defaults?.removeObject(forKey: WidgetContentType.notes.dataKey)
            defaults?.synchronize()
        }

        let loaded: WidgetNoteData = WidgetDataManager.shared.load(for: .notes)

        XCTAssertEqual(loaded.totalCount, 1)
        let export = ExternalSurfaceDiagnosticsStore.shared.exportText(limit: 10)
        XCTAssertTrue(export.contains("[widget_bridge_extension] load:"))
        XCTAssertTrue(export.contains("content_type=notes"))
        XCTAssertTrue(export.contains("has_data_key=true"))
        XCTAssertTrue(export.contains("decode_success=true"))
        XCTAssertTrue(export.contains("item_count=1"))
        XCTAssertTrue(export.contains("total_count=1"))
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

    func testWidgetWebsiteResolvedFaviconURLUsesSharedPublicBaseWhenR2KeyPresent() {
        let groupId = appGroupIdForWidgetTests()
        let defaults = UserDefaults(suiteName: groupId)
        defaults?.set("https://cdn.example.com/favicons", forKey: "widget_favicon_r2_public_base_url")
        defaults?.removeObject(forKey: "widget_favicon_r2_endpoint")
        defaults?.removeObject(forKey: "widget_favicon_r2_bucket")
        defaults?.synchronize()
        defer {
            defaults?.removeObject(forKey: "widget_favicon_r2_public_base_url")
            defaults?.removeObject(forKey: "widget_favicon_r2_endpoint")
            defaults?.removeObject(forKey: "widget_favicon_r2_bucket")
            defaults?.synchronize()
        }

        let site = WidgetWebsite(
            id: "site-r2",
            title: "R2",
            url: "https://example.com",
            domain: "example.com",
            faviconUrl: nil,
            faviconR2Key: "news/icon.png"
        )

        XCTAssertEqual(site.resolvedFaviconURL?.absoluteString, "https://cdn.example.com/favicons/news/icon.png")
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

    func testWidgetWebsiteDisplayDomainFallsBackToURLWhenDomainMissing() {
        let site = WidgetWebsite(
            id: "site-7",
            title: "Guardian",
            url: "https://www.theguardian.com/world/2026/feb/13/story",
            domain: ""
        )

        XCTAssertEqual(site.displayDomain, "theguardian.com")
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

    func testWidgetOpenAndMutationIntentsReturnOpenResults() async throws {
        assertOpensIntent(try await OpenTodayIntent().perform())
        assertOpensIntent(try await AddTaskIntent().perform())
        assertOpensIntent(try await OpenNotesIntent().perform())
        assertOpensIntent(try await CreateNoteIntent().perform())
        assertOpensIntent(try await OpenWebsitesIntent().perform())
        assertOpensIntent(try await QuickSaveIntent(url: URL(string: "https://example.com")!).perform())
        assertOpensIntent(try await OpenFilesIntent().perform())
        assertOpensIntent(try await OpenScratchpadIntent().perform())
        assertOpensIntent(try await StartChatIntent().perform())
    }
}

private func assertOpensIntent<Result: OpensIntent>(_: Result) {}

private func appGroupIdForWidgetTests() -> String {
    AppGroupConfiguration.appGroupId ?? "group.ai.sidebar.sidebar"
}

private func clearTaskWidgetStorage() {
    let groupId = appGroupIdForWidgetTests()
    let defaults = UserDefaults(suiteName: groupId)
    defaults?.removeObject(forKey: WidgetContentType.tasks.dataKey)
    defaults?.removeObject(forKey: WidgetContentType.tasks.pendingKey)
    defaults?.removeObject(forKey: "widgetTodayTasks")
    defaults?.removeObject(forKey: "widgetPendingCompletions")
    defaults?.removeObject(forKey: "widgetPendingAddTask")
    defaults?.synchronize()
}
