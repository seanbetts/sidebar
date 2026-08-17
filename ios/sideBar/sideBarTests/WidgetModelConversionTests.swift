import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class WidgetModelConversionTests: XCTestCase {
    func testWidgetTaskInitFromTaskItemMapsCompletionAndNotes() {
        let task = TaskItem(
            id: "task-1",
            title: "Ship release",
            status: "completed",
            deadline: "2026-02-10",
            notes: "release notes"
        )

        let widgetTask = WidgetTask(from: task, projectName: "App", groupName: "Team")

        XCTAssertEqual(widgetTask.id, "task-1")
        XCTAssertEqual(widgetTask.title, "Ship release")
        XCTAssertTrue(widgetTask.isCompleted)
        XCTAssertEqual(widgetTask.projectName, "App")
        XCTAssertEqual(widgetTask.groupName, "Team")
        XCTAssertTrue(widgetTask.hasNotes)
        XCTAssertEqual(widgetTask.deadline, "2026-02-10")
    }

    func testTaskCompletionOverlayAccountsForKnownDueTodayOffscreenTaskOnlyOnce() {
        let taskId = UUID().uuidString
        let snapshot = WidgetTaskData(
            tasks: (0..<10).map { WidgetTask(id: "visible-\($0)", title: "Visible \($0)") },
            totalCount: 11,
            progressCompletedCount: 0,
            progressTotalCount: 11,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        let operation = WidgetPendingOperation(
            itemId: taskId,
            action: TaskWidgetAction.complete
        )

        let once = WidgetTaskPendingCompletionOverlay.apply(
            to: snapshot,
            pendingOperations: [operation],
            knownDueTodayTaskIds: [taskId]
        )
        let twice = WidgetTaskPendingCompletionOverlay.apply(
            to: once,
            pendingOperations: [operation],
            knownDueTodayTaskIds: [taskId]
        )

        XCTAssertEqual(once.tasks.count, 10)
        XCTAssertEqual(once.totalCount, 10)
        XCTAssertEqual(once.progressCompletedCount, 1)
        XCTAssertEqual(once.progressTotalCount, 11)
        XCTAssertEqual(once.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(once.pendingOptimisticCompletionTaskIds, [taskId])
        XCTAssertEqual(twice, once)
    }

    func testNotificationCompletionRolloverCreatesEmptyCurrentDayBaseline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 172_800)
        let previousDay = now.addingTimeInterval(-86_400)
        let staleTaskId = UUID().uuidString
        let priorSnapshot = WidgetTaskData(
            tasks: [],
            totalCount: 0,
            progressCompletedCount: 5,
            progressTotalCount: 5,
            optimisticallyCompletedTaskIds: [staleTaskId],
            pendingOptimisticCompletionTaskIds: [staleTaskId],
            lastUpdated: previousDay
        )

        let prepared = WidgetTaskPendingCompletionOverlay.prepareForNotificationCompletion(
            priorSnapshot,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(prepared.tasks.isEmpty)
        XCTAssertEqual(prepared.totalCount, 0)
        XCTAssertEqual(prepared.progressCompletedCount, 0)
        XCTAssertEqual(prepared.progressTotalCount, 0)
        XCTAssertTrue(prepared.optimisticallyCompletedTaskIds.isEmpty)
        XCTAssertTrue(prepared.pendingOptimisticCompletionTaskIds.isEmpty)
        XCTAssertEqual(prepared.lastUpdated, now)
    }

    func testNotificationCompletionRolloverDoesNotRelabelPriorRowsForOffscreenTask() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 172_800)
        let previousDay = now.addingTimeInterval(-86_400)
        let taskId = UUID().uuidString
        let priorSnapshot = WidgetTaskData(
            tasks: (0..<10).map { WidgetTask(id: "stale-\($0)", title: "Stale \($0)") },
            totalCount: 11,
            progressCompletedCount: 3,
            progressTotalCount: 14,
            lastUpdated: previousDay
        )
        let prepared = WidgetTaskPendingCompletionOverlay.prepareForNotificationCompletion(
            priorSnapshot,
            now: now,
            calendar: calendar
        )

        let updated = WidgetTaskPendingCompletionOverlay.apply(
            to: prepared,
            pendingOperations: [
                WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
            ],
            knownDueTodayTaskIds: [taskId]
        )

        XCTAssertTrue(updated.tasks.isEmpty)
        XCTAssertEqual(updated.totalCount, 0)
        XCTAssertEqual(updated.progressCompletedCount, 0)
        XCTAssertEqual(updated.progressTotalCount, 0)
        XCTAssertEqual(updated.optimisticallyCompletedTaskIds, [taskId])
        XCTAssertEqual(updated.pendingOptimisticCompletionTaskIds, [taskId])
        XCTAssertEqual(updated.lastUpdated, now)
    }

    func testTaskSnapshotRefreshClearsHandledIdWhenTaskIsExplicitlyReopened() {
        let taskId = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_000)
        let completedSnapshot = WidgetTaskData(
            tasks: [],
            totalCount: 0,
            progressCompletedCount: 1,
            progressTotalCount: 1,
            optimisticallyCompletedTaskIds: [taskId],
            pendingOptimisticCompletionTaskIds: [],
            lastUpdated: now
        )

        let refreshed = WidgetTaskSnapshotRefresh.reconcile(
            tasks: [WidgetTask(id: taskId, title: "Reopened")],
            previousSnapshot: completedSnapshot,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(refreshed.tasks.map(\.id), [taskId])
        XCTAssertEqual(refreshed.totalCount, 1)
        XCTAssertEqual(refreshed.progressCompletedCount, 0)
        XCTAssertEqual(refreshed.progressTotalCount, 1)
        XCTAssertTrue(refreshed.optimisticallyCompletedTaskIds.isEmpty)
        XCTAssertTrue(refreshed.pendingOptimisticCompletionTaskIds.isEmpty)
    }

    func testTaskCompletionOverlayDoesNotDecrementForUnknownOffscreenTask() {
        let snapshot = WidgetTaskData(
            tasks: [WidgetTask(id: "visible", title: "Visible")],
            totalCount: 2,
            progressCompletedCount: 0,
            progressTotalCount: 2
        )
        let operation = WidgetPendingOperation(
            itemId: UUID().uuidString,
            action: TaskWidgetAction.complete
        )

        let updated = WidgetTaskPendingCompletionOverlay.apply(
            to: snapshot,
            pendingOperations: [operation]
        )

        XCTAssertEqual(updated, snapshot)
    }

    func testWidgetNoteInitFromFileNodeNormalizesNameAndMapsMetadata() {
        let timestamp: Double = 1_700_000_000
        let node = FileNode(
            name: "meeting.md",
            path: "/notes/meeting.md",
            type: .file,
            size: 120,
            modified: timestamp,
            created: nil,
            children: nil,
            expanded: nil,
            pinned: nil,
            pinnedOrder: 3,
            archived: nil,
            folderMarker: nil
        )

        let widgetNote = WidgetNote(from: node)

        XCTAssertEqual(widgetNote.id, "/notes/meeting.md")
        XCTAssertEqual(widgetNote.name, "meeting.md")
        XCTAssertEqual(widgetNote.path, "/notes/meeting.md")
        XCTAssertNil(widgetNote.scopePath)
        XCTAssertEqual(widgetNote.modifiedAt, Date(timeIntervalSince1970: timestamp))
        XCTAssertFalse(widgetNote.pinned)
        XCTAssertEqual(widgetNote.pinnedOrder, 3)
    }

    func testWidgetWebsiteInitFromWebsiteItemCopiesWidgetFields() {
        let faviconUrl = "https://openai.com/favicon.ico"
        let faviconR2Key = "openai.com.png"
        let website = WebsiteItem(
            id: "site-1",
            title: "OpenAI",
            url: "https://openai.com",
            domain: "openai.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: true,
            pinnedOrder: 1,
            archived: false,
            faviconUrl: faviconUrl,
            faviconR2Key: faviconR2Key,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )

        let widgetWebsite = WidgetWebsite(from: website)

        XCTAssertEqual(widgetWebsite.id, "site-1")
        XCTAssertEqual(widgetWebsite.title, "OpenAI")
        XCTAssertEqual(widgetWebsite.url, "https://openai.com")
        XCTAssertEqual(widgetWebsite.domain, "openai.com")
        XCTAssertEqual(widgetWebsite.faviconUrl, faviconUrl)
        XCTAssertEqual(widgetWebsite.faviconR2Key, faviconR2Key)
        XCTAssertTrue(widgetWebsite.pinned)
        XCTAssertEqual(widgetWebsite.pinnedOrder, 1)
        XCTAssertFalse(widgetWebsite.archived)
    }

    func testWidgetFileInitFromIngestionListItemMapsFileMetadata() {
        let meta = IngestedFileMeta(
            id: "file-1",
            filenameOriginal: "report.pdf",
            path: "/files/report.pdf",
            mimeOriginal: "application/pdf",
            sizeBytes: 2048,
            sha256: nil,
            pinned: nil,
            pinnedOrder: nil,
            category: "documents",
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2026-02-09T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
        let job = IngestionJob(
            status: "complete",
            stage: nil,
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: 1.0,
            attempts: 1,
            updatedAt: "2026-02-09T00:00:00Z"
        )
        let listItem = IngestionListItem(file: meta, job: job, recommendedViewer: "pdf")

        let widgetFile = WidgetFile(from: listItem)

        XCTAssertEqual(widgetFile.id, "file-1")
        XCTAssertEqual(widgetFile.filename, "report.pdf")
        XCTAssertEqual(widgetFile.path, "/files/report.pdf")
        XCTAssertEqual(widgetFile.sizeBytes, 2048)
        XCTAssertFalse(widgetFile.pinned)
        XCTAssertEqual(widgetFile.category, "documents")
        XCTAssertEqual(widgetFile.mimeType, "application/pdf")
        XCTAssertEqual(widgetFile.recommendedViewer, "pdf")
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
        XCTAssertTrue(decoded.optimisticallyCompletedTaskIds.isEmpty)
        XCTAssertTrue(decoded.pendingOptimisticCompletionTaskIds.isEmpty)
    }
}
