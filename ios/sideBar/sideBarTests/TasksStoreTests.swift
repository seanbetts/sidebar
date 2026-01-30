import Foundation
import XCTest
@testable import sideBar

@MainActor
final class TasksStoreTests: XCTestCase {
    func testLoadUsesOfflineSnapshotWhenOffline() async {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let networkStatus = TestNetworkStatus(isNetworkAvailable: false)
        let store = TasksStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: networkStatus
        )

        let selection: TaskSelection = .today
        let task = TaskItem(id: "task-1", title: "Offline", status: "open")
        let list = TaskListResponse(
            scope: "today",
            generatedAt: nil,
            tasks: [task],
            projects: nil,
            groups: nil
        )
        offlineStore.set(
            key: CacheKeys.tasksList(selectionKey: selection.cacheKey),
            entityType: "taskList",
            value: list,
            lastSyncAt: nil
        )

        await store.load(selection: selection)

        XCTAssertEqual(store.tasks, [task])
        XCTAssertEqual(api.listCallCount, 0)
    }

    func testApplyLocalAddCreatesPreviewTask() {
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let cache = TestCacheClient()
        let api = StubTasksAPI()
        let store = TasksStore(api: api, cache: cache, offlineStore: offlineStore, networkStatus: nil)

        let operationId = UUID().uuidString
        let operation = TaskOperationPayload(
            operationId: operationId,
            op: "add",
            id: nil,
            title: "Queued Task",
            notes: "Offline",
            listId: nil,
            dueDate: nil,
            startDate: nil,
            recurrenceRule: nil,
            clientUpdatedAt: nil
        )

        store.applyLocalOperation(operation)

        XCTAssertEqual(store.tasks.first?.title, "Queued Task")
        XCTAssertEqual(store.tasks.first?.notes, "Offline")
        XCTAssertEqual(store.tasks.first?.isPreview, true)
        let pendingKey = "tasks.pending.\(operationId)"
        let placeholderId = offlineStore.get(key: pendingKey, as: String.self)
        XCTAssertEqual(store.tasks.first?.id, placeholderId)
    }
}

@MainActor
private final class TestNetworkStatus: NetworkStatusProviding {
    var isNetworkAvailable: Bool
    var isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

private final class StubTasksAPI: TasksProviding {
    var listCallCount: Int = 0

    func list(scope: String) async throws -> TaskListResponse {
        listCallCount += 1
        return TaskListResponse(scope: scope, generatedAt: nil, tasks: [], projects: nil, groups: nil)
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        throw StubError.unused
    }

    func counts() async throws -> TaskCountsResponse {
        throw StubError.unused
    }

    func createGroup(title: String) async throws -> TaskGroup {
        throw StubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        throw StubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        throw StubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        throw StubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        throw StubError.unused
    }

    func deleteProject(projectId: String) async throws {
        throw StubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        throw StubError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        throw StubError.unused
    }
}

private enum StubError: Error {
    case unused
}
