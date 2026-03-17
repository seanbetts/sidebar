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
    }
}
