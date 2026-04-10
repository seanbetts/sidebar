import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreSpotlightTests: XCTestCase {
    func testLoadIndexesTasksInSpotlightWhenPersistingServerSnapshot() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)
        let spotlightIndexer = SpotlightIndexerSpy()
        store.spotlightIndexer = spotlightIndexer

        let task = TaskItem(
            id: "task-spotlight-1",
            title: "Review launch checklist",
            status: "open",
            deadline: "2026-04-12",
            notes: "Confirm App Store copy"
        )
        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [task],
            projects: nil,
            groups: nil
        )

        await store.load(selection: TaskSelection.today, force: true)
        await Task.yield()

        XCTAssertEqual(spotlightIndexer.indexedTasks.count, 1)
        XCTAssertEqual(spotlightIndexer.indexedTasks.first?.id, task.id)
        XCTAssertEqual(spotlightIndexer.indexedTasks.first?.title, task.title)
        XCTAssertEqual(spotlightIndexer.indexedTasks.first?.deadline, task.deadline)
    }

    func testLoadSkipsDeletedAndPreviewTasksWhenIndexingSpotlight() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)
        let spotlightIndexer = SpotlightIndexerSpy()
        store.spotlightIndexer = spotlightIndexer

        let activeTask = TaskItem(id: "task-active", title: "Visible", status: "open")
        let deletedTask = TaskItem(
            id: "task-deleted",
            title: "Deleted",
            status: "open",
            deletedAt: "2026-04-10T12:00:00Z"
        )
        let previewTask = TaskItem(
            id: "task-preview",
            title: "Preview",
            status: "open",
            isPreview: true
        )
        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [activeTask, deletedTask, previewTask],
            projects: nil,
            groups: nil
        )

        await store.load(selection: TaskSelection.today, force: true)
        await Task.yield()

        XCTAssertEqual(spotlightIndexer.indexedTasks.map(\.id), [activeTask.id])
    }
}

private final class SpotlightIndexerSpy: SpotlightIndexing {
    private(set) var indexedTasks: [SpotlightTask] = []

    func indexTask(_ task: SpotlightTask) async {
        indexedTasks = [task]
    }

    func indexTasks(_ tasks: [SpotlightTask]) async {
        indexedTasks = tasks
    }

    func indexNote(_ note: SpotlightNote) async { _ = note }
    func indexNotes(_ notes: [SpotlightNote]) async { _ = notes }
    func indexFile(_ file: SpotlightFile) async { _ = file }
    func indexFiles(_ files: [SpotlightFile]) async { _ = files }
    func indexWebsite(_ website: SpotlightWebsite) async { _ = website }
    func indexWebsites(_ websites: [SpotlightWebsite]) async { _ = websites }
    func removeTask(id: String) async { _ = id }
    func removeNote(path: String) async { _ = path }
    func removeFile(id: String) async { _ = id }
    func removeWebsite(id: String) async { _ = id }
    func clearTasksIndex() async {}
    func clearNotesIndex() async {}
    func clearFilesIndex() async {}
    func clearWebsitesIndex() async {}
    func clearAllIndexes() async {}
}
