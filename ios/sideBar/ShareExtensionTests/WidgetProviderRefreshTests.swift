import Foundation
import XCTest
import WidgetKit
import sideBarShared
@testable import sideBarWidgetsExtension

final class WidgetProviderRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearWidgetStorage()
    }

    override func tearDown() {
        WidgetRefreshURLProtocolMock.requestHandler = nil
        clearWidgetStorage()
        super.tearDown()
    }

    func testTasksRefreshMapsServerDataIntoWidgetTaskData() async throws {
        let client = makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/lists/today")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "scope": "today",
                      "generatedAt": "2026-03-31T10:00:00Z",
                      "tasks": [
                        {
                          "id": "task-a",
                          "title": "Review launch plan",
                          "status": "open",
                          "deadline": "2026-03-31",
                          "notes": "Bring metrics",
                          "projectId": "project-1",
                          "groupId": "group-1"
                        },
                        {
                          "id": "task-b",
                          "title": "Inbox zero",
                          "status": "open",
                          "deadline": null,
                          "notes": "",
                          "projectId": null,
                          "groupId": null
                        },
                        {
                          "id": "task-c",
                          "title": "Already done",
                          "status": "completed",
                          "deadline": "2026-03-30",
                          "notes": null,
                          "projectId": null,
                          "groupId": null
                        }
                      ],
                      "projects": [
                        { "id": "project-1", "title": "Launch", "groupId": "group-1", "status": "active", "updatedAt": null }
                      ],
                      "groups": [
                        { "id": "group-1", "title": "Work", "updatedAt": null }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let refreshed = try await TasksWidgetRefreshClient(apiClient: client).refreshTodayTasks(
            previousSnapshot: WidgetTaskData.empty,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(refreshed.tasks.map(\.id), ["task-a", "task-b"])
        XCTAssertEqual(refreshed.totalCount, 2)
        XCTAssertEqual(refreshed.tasks.first?.projectName, "Launch")
        XCTAssertEqual(refreshed.tasks.first?.groupName, "Work")
        XCTAssertEqual(refreshed.tasks.first?.hasNotes, true)
        XCTAssertEqual(refreshed.progressCompletedCount, 0)
        XCTAssertEqual(refreshed.progressTotalCount, 2)
    }

    func testNotesRefreshMapsPinnedNotesIntoWidgetNoteData() async throws {
        let client = makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/notes/tree")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "children": [
                        {
                          "name": "Projects",
                          "path": "/Projects",
                          "type": "directory",
                          "children": [
                            {
                              "name": "Pinned.md",
                              "path": "/Projects/Pinned.md",
                              "type": "file",
                              "modified": 1710000000,
                              "pinned": true,
                              "pinnedOrder": 1,
                              "archived": false
                            },
                            {
                              "name": "Archived.md",
                              "path": "/Projects/Archived.md",
                              "type": "file",
                              "modified": 1710000001,
                              "pinned": true,
                              "pinnedOrder": 0,
                              "archived": true
                            }
                          ]
                        },
                        {
                          "name": "Top.md",
                          "path": "/Top.md",
                          "type": "file",
                          "modified": 1710000002,
                          "pinned": true,
                          "pinnedOrder": 0,
                          "archived": false
                        },
                        {
                          "name": "Loose.md",
                          "path": "/Loose.md",
                          "type": "file",
                          "modified": 1710000003,
                          "pinned": false,
                          "archived": false
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let refreshed = try await NotesWidgetRefreshClient(apiClient: client).refreshPinnedNotes(
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(refreshed.notes.map(\.path), ["/Top.md", "/Projects/Pinned.md"])
        XCTAssertEqual(refreshed.totalCount, 2)
        XCTAssertEqual(refreshed.notes.first?.pinnedOrder, 0)
    }

    func testWebsitesRefreshMapsSavedWebsitesIntoWidgetWebsiteData() async throws {
        let client = makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/websites")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "items": [
                        {
                          "id": "site-a",
                          "title": "Pinned",
                          "url": "https://example.com/a",
                          "domain": "example.com",
                          "savedAt": "2026-03-31T09:00:00Z",
                          "publishedAt": null,
                          "pinned": true,
                          "pinnedOrder": 0,
                          "archived": false,
                          "faviconUrl": "https://example.com/favicon.ico",
                          "faviconR2Key": null,
                          "youtubeTranscripts": null,
                          "readingTime": null,
                          "updatedAt": null,
                          "lastOpenedAt": null,
                          "deletedAt": null
                        },
                        {
                          "id": "site-b",
                          "title": "Recent",
                          "url": "https://example.com/b",
                          "domain": "example.com",
                          "savedAt": "2026-03-31T08:00:00Z",
                          "publishedAt": null,
                          "pinned": false,
                          "pinnedOrder": null,
                          "archived": false,
                          "faviconUrl": null,
                          "faviconR2Key": null,
                          "youtubeTranscripts": null,
                          "readingTime": null,
                          "updatedAt": null,
                          "lastOpenedAt": null,
                          "deletedAt": null
                        },
                        {
                          "id": "site-c",
                          "title": "Archived",
                          "url": "https://example.com/c",
                          "domain": "example.com",
                          "savedAt": "2026-03-31T07:00:00Z",
                          "publishedAt": null,
                          "pinned": false,
                          "pinnedOrder": null,
                          "archived": true,
                          "faviconUrl": null,
                          "faviconR2Key": null,
                          "youtubeTranscripts": null,
                          "readingTime": null,
                          "updatedAt": null,
                          "lastOpenedAt": null,
                          "deletedAt": null
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let refreshed = try await WebsitesWidgetRefreshClient(apiClient: client).refreshSavedWebsites(
            now: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(refreshed.websites.map(\.id), ["site-a", "site-b"])
        XCTAssertEqual(refreshed.totalCount, 2)
        XCTAssertEqual(refreshed.websites.first?.faviconUrl, "https://example.com/favicon.ico")
    }

    func testFilesRefreshMapsPinnedFilesIntoWidgetFileData() async throws {
        let client = makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/files")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "items": [
                        {
                          "file": {
                            "id": "file-a",
                            "filenameOriginal": "Plan.pdf",
                            "path": "/docs/Plan.pdf",
                            "mimeOriginal": "application/pdf",
                            "sizeBytes": 1024,
                            "sha256": null,
                            "pinned": true,
                            "pinnedOrder": 0,
                            "category": "Docs",
                            "sourceUrl": null,
                            "sourceMetadata": null,
                            "createdAt": "2026-03-31T09:00:00Z",
                            "updatedAt": null,
                            "deletedAt": null
                          },
                          "job": {
                            "status": "ready",
                            "stage": "complete",
                            "errorCode": null,
                            "errorMessage": null,
                            "userMessage": null,
                            "progress": 1.0,
                            "attempts": 1,
                            "updatedAt": "2026-03-31T09:00:00Z"
                          },
                          "recommendedViewer": "pdf"
                        },
                        {
                          "file": {
                            "id": "file-b",
                            "filenameOriginal": "Loose.txt",
                            "path": "/docs/Loose.txt",
                            "mimeOriginal": "text/plain",
                            "sizeBytes": 128,
                            "sha256": null,
                            "pinned": false,
                            "pinnedOrder": null,
                            "category": "Text",
                            "sourceUrl": null,
                            "sourceMetadata": null,
                            "createdAt": "2026-03-31T09:00:00Z",
                            "updatedAt": null,
                            "deletedAt": null
                          },
                          "job": {
                            "status": "ready",
                            "stage": "complete",
                            "errorCode": null,
                            "errorMessage": null,
                            "userMessage": null,
                            "progress": 1.0,
                            "attempts": 1,
                            "updatedAt": "2026-03-31T09:00:00Z"
                          },
                          "recommendedViewer": "text"
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let refreshed = try await FilesWidgetRefreshClient(apiClient: client).refreshPinnedFiles(
            now: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(refreshed.files.map(\.id), ["file-a"])
        XCTAssertEqual(refreshed.totalCount, 1)
        XCTAssertEqual(refreshed.files.first?.recommendedViewer, "pdf")
    }

    func testTaskOverlayHidesTasksWithPendingLocalCompletionOperations() {
        let snapshot = WidgetTaskData(
            tasks: [
                WidgetTask(id: "task-a", title: "One"),
                WidgetTask(id: "task-b", title: "Two")
            ],
            totalCount: 2,
            progressCompletedCount: 0,
            progressTotalCount: 2,
            lastUpdated: Date(timeIntervalSince1970: 5_000)
        )
        let pending = [
            WidgetPendingOperation(itemId: "task-a", action: TaskWidgetAction.complete)
        ]

        let overlaid = WidgetTaskPendingCompletionOverlay.apply(
            to: snapshot,
            pendingOperations: pending
        )

        XCTAssertEqual(overlaid.tasks.map(\.id), ["task-b"])
        XCTAssertEqual(overlaid.totalCount, 1)
        XCTAssertEqual(overlaid.progressCompletedCount, 1)
        XCTAssertEqual(overlaid.progressTotalCount, 2)
    }

    func testTodayTasksProviderReturnsCachedDataWhenSnapshotIsFresh() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let cached = WidgetTaskData(
            tasks: [WidgetTask(id: "cached-task", title: "Cached")],
            totalCount: 1,
            lastUpdated: now
        )
        WidgetDataManager.shared.store(cached, for: .tasks)
        setWidgetAuthenticated(true)

        var refreshCallCount = 0
        let provider = TodayTasksProvider(
            now: { now },
            refreshData: { _, _ in
                refreshCallCount += 1
                return WidgetTaskData(tasks: [WidgetTask(id: "refreshed-task", title: "Refreshed")], totalCount: 1)
            }
        )

        let timeline = await provider.timeline(for: now)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(timeline.entries.first?.data.tasks.map(\.id), ["cached-task"])
    }

    func testPinnedNotesProviderRefreshesStaleSnapshotWhenAuthIsAvailable() async {
        let now = Date(timeIntervalSince1970: 20_000)
        WidgetDataManager.shared.store(
            WidgetNoteData(
                notes: [WidgetNote(id: "/cached.md", name: "Cached", path: "/cached.md")],
                totalCount: 1,
                lastUpdated: now.addingTimeInterval(-3600)
            ),
            for: .notes
        )
        setWidgetAuthenticated(true)

        let refreshed = WidgetNoteData(
            notes: [WidgetNote(id: "/refreshed.md", name: "Refreshed", path: "/refreshed.md")],
            totalCount: 1,
            lastUpdated: now
        )
        let provider = PinnedNotesProvider(
            now: { now },
            refreshData: { _ in refreshed }
        )

        let timeline = await provider.timeline(for: now)
        let stored: WidgetNoteData = WidgetDataManager.shared.load(for: .notes)

        XCTAssertEqual(timeline.entries.first?.data.notes.map(\.path), ["/refreshed.md"])
        XCTAssertEqual(stored.notes.map(\.path), ["/refreshed.md"])
    }

    func testSavedSitesProviderPreservesCachedDataWhenRefreshFails() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let cached = WidgetWebsiteData(
            websites: [WidgetWebsite(id: "cached-site", title: "Cached", url: "https://cached.example", domain: "cached.example")],
            totalCount: 1,
            lastUpdated: now.addingTimeInterval(-3600)
        )
        WidgetDataManager.shared.store(cached, for: .websites)
        setWidgetAuthenticated(true)

        let provider = SavedSitesProvider(
            now: { now },
            refreshData: { _ in
                struct RefreshFailure: Error {}
                throw RefreshFailure()
            },
            faviconFetcher: { _ in [:] }
        )

        let timeline = await provider.timeline(for: now)

        XCTAssertEqual(timeline.entries.first?.data.websites.map(\.id), ["cached-site"])
    }

    func testPinnedFilesProviderRendersCachedDataWhenAuthIsUnavailableButSnapshotExists() async {
        let now = Date(timeIntervalSince1970: 40_000)
        let cached = WidgetFileData(
            files: [WidgetFile(id: "cached-file", filename: "Cached.pdf", sizeBytes: 12)],
            totalCount: 1,
            lastUpdated: now.addingTimeInterval(-3600)
        )
        WidgetDataManager.shared.store(cached, for: .files)
        setWidgetAuthenticated(false)

        var refreshCallCount = 0
        let provider = PinnedFilesProvider(
            now: { now },
            refreshData: { _ in
                refreshCallCount += 1
                return WidgetFileData(files: [], totalCount: 0)
            }
        )

        let timeline = await provider.timeline(for: now)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(timeline.entries.first?.data.files.map(\.id), ["cached-file"])
    }

    private func makeAPIClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> APIClient {
        WidgetRefreshURLProtocolMock.requestHandler = handler
        let config = APIClientConfig(
            baseUrl: URL(string: "https://api.example.com/api/v1")!,
            accessTokenProvider: { "token-123" }
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [WidgetRefreshURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfiguration)
        return APIClient(config: config, session: session)
    }

    private func setWidgetAuthenticated(_ isAuthenticated: Bool) {
        let defaults = UserDefaults(suiteName: appGroupIdForWidgetTests())
        defaults?.set(isAuthenticated, forKey: "widgetIsAuthenticated")
        defaults?.synchronize()
    }

    private func clearWidgetStorage() {
        let defaults = UserDefaults(suiteName: appGroupIdForWidgetTests())
        for contentType in [WidgetContentType.tasks, .notes, .websites, .files] {
            defaults?.removeObject(forKey: contentType.dataKey)
            defaults?.removeObject(forKey: contentType.pendingKey)
        }
        defaults?.removeObject(forKey: "widgetIsAuthenticated")
        defaults?.removeObject(forKey: "widgetTodayTasks")
        defaults?.removeObject(forKey: "widgetPendingCompletions")
        defaults?.removeObject(forKey: "widgetPendingAddTask")
        defaults?.synchronize()
    }
}

private final class WidgetRefreshURLProtocolMock: URLProtocol {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "WidgetRefreshURLProtocolMock", code: 0))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func appGroupIdForWidgetTests() -> String {
    AppGroupConfiguration.appGroupId ?? "group.ai.sidebar.sidebar"
}
