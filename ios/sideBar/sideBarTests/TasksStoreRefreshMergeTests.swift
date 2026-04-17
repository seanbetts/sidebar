import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreRefreshMergeTests: XCTestCase {
    func testBackgroundRefreshPreservesPendingPreviewTask() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: OfflineStore(container: persistence.container))
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false
            ),
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)

        let cachedTask = TaskItem(id: "server-1", title: "Server task", status: "open")
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: TaskListResponse(
                scope: "today",
                generatedAt: nil,
                tasks: [cachedTask],
                projects: nil,
                groups: nil
            ),
            ttlSeconds: CachePolicy.tasksList
        )
        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [cachedTask],
            projects: nil,
            groups: nil
        )

        await store.load(selection: .today)

        let addOperation = TaskOperationPayload(
            operationId: UUID().uuidString,
            op: "add",
            id: nil,
            title: "Queued task",
            dueDate: TasksUtils.formatDateKey(Date())
        )
        try await store.enqueueOperation(addOperation)
        store.applyLocalOperation(addOperation)

        XCTAssertEqual(store.tasks.map(\.title), ["Queued task", "Server task"])
        XCTAssertEqual(store.tasks.first?.isPreview, true)

        await store.load(selection: .today)
        try await waitUntilTasksCondition(timeoutSeconds: 0.2) {
            api.listCallCount >= 2
        }

        XCTAssertEqual(store.tasks.map(\.title), ["Queued task", "Server task"])
        XCTAssertEqual(store.tasks.first?.isPreview, true)
    }

    func testBackgroundRefreshPreservesPendingTaskEdits() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = TestCacheClient()
        let api = TasksStoreStubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: OfflineStore(container: persistence.container))
        let writeQueue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false
            ),
            autoProcessEnabled: false
        )
        store.attachWriteQueue(writeQueue)

        let cachedTask = TaskItem(id: "task-1", title: "Server title", status: "open")
        let cachedList = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [cachedTask],
            projects: nil,
            groups: nil
        )
        cache.set(
            key: CacheKeys.tasksList(selectionKey: TaskSelection.today.cacheKey),
            value: cachedList,
            ttlSeconds: CachePolicy.tasksList
        )
        api.listResponsesByScope["today"] = cachedList

        await store.load(selection: .today)

        let renameOperation = TaskOperationPayload(
            operationId: UUID().uuidString,
            op: "rename",
            id: "task-1",
            title: "Local title"
        )
        try await store.enqueueOperation(renameOperation)
        store.applyLocalOperation(renameOperation)

        XCTAssertEqual(store.tasks.first?.title, "Local title")

        api.listResponsesByScope["today"] = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [cachedTask],
            projects: nil,
            groups: nil
        )

        await store.load(selection: .today)
        try await waitUntilTasksCondition(timeoutSeconds: 0.2) {
            api.listCallCount >= 2
        }

        XCTAssertEqual(store.tasks.first?.title, "Local title")
    }
}
