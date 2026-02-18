import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksWriteQueueExecutorTests: XCTestCase {
    func testExecuteDebouncesRefreshAcrossBackToBackWrites() async throws {
        let api = TasksSyncAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            refreshDebounceNanoseconds: 40_000_000
        )

        try await executor.execute(write: makeWrite(operationId: "op-1", taskId: "task-1"))
        try await executor.execute(write: makeWrite(operationId: "op-2", taskId: "task-2"))
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(api.syncCallCount, 2)
        XCTAssertEqual(store.refreshAfterSyncCallCount, 1)
        XCTAssertEqual(store.removedPlaceholders, ["op-1", "op-2"])
        XCTAssertEqual(store.lastToken, "token-2")
    }

    private func makeWrite(operationId: String, taskId: String) throws -> PendingWriteRecord {
        let payload = TaskOperationPayload(
            operationId: operationId,
            op: "notes",
            id: taskId,
            notes: "Updated",
            clientUpdatedAt: nil
        )
        let encoded = try JSONEncoder().encode(payload)
        return PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.update.rawValue,
            entityType: WriteEntityType.task.rawValue,
            entityId: taskId,
            payload: encoded,
            serverSnapshot: nil,
            attempts: 0
        )
    }
}

@MainActor
private final class TasksWriteQueueStoreSpy: TasksWriteQueueApplying {
    var removedPlaceholders: [String] = []
    var lastToken: String?
    var refreshAfterSyncCallCount: Int = 0

    func removePendingTaskPlaceholder(operationId: String) {
        removedPlaceholders.append(operationId)
    }

    func lastSyncToken() -> String? {
        lastToken
    }

    func updateLastSyncToken(_ token: String?) {
        lastToken = token
    }

    func refreshAfterSync() async {
        refreshAfterSyncCallCount += 1
    }
}

private final class TasksSyncAPIStub: TasksProviding {
    var syncCallCount: Int = 0

    func list(scope: String) async throws -> TaskListResponse {
        _ = scope
        throw TasksWriteQueueExecutorStubError.unused
    }

    func projectTasks(projectId: String) async throws -> TaskListResponse {
        _ = projectId
        throw TasksWriteQueueExecutorStubError.unused
    }

    func groupTasks(groupId: String) async throws -> TaskListResponse {
        _ = groupId
        throw TasksWriteQueueExecutorStubError.unused
    }

    func search(query: String) async throws -> TaskListResponse {
        _ = query
        throw TasksWriteQueueExecutorStubError.unused
    }

    func counts() async throws -> TaskCountsResponse {
        throw TasksWriteQueueExecutorStubError.unused
    }

    func createGroup(title: String) async throws -> TaskGroup {
        _ = title
        throw TasksWriteQueueExecutorStubError.unused
    }

    func renameGroup(groupId: String, title: String) async throws -> TaskGroup {
        _ = groupId
        _ = title
        throw TasksWriteQueueExecutorStubError.unused
    }

    func deleteGroup(groupId: String) async throws {
        _ = groupId
        throw TasksWriteQueueExecutorStubError.unused
    }

    func createProject(title: String, groupId: String?) async throws -> TaskProject {
        _ = title
        _ = groupId
        throw TasksWriteQueueExecutorStubError.unused
    }

    func renameProject(projectId: String, title: String) async throws -> TaskProject {
        _ = projectId
        _ = title
        throw TasksWriteQueueExecutorStubError.unused
    }

    func deleteProject(projectId: String) async throws {
        _ = projectId
        throw TasksWriteQueueExecutorStubError.unused
    }

    func apply(_ payload: TaskOperationBatch) async throws -> TaskSyncResponse {
        _ = payload
        throw TasksWriteQueueExecutorStubError.unused
    }

    func sync(_ payload: TaskSyncRequest) async throws -> TaskSyncResponse {
        syncCallCount += 1
        let operationId = payload.operations.first?.operationId ?? ""
        return TaskSyncResponse(
            applied: [operationId],
            tasks: [],
            nextTasks: [],
            conflicts: [],
            updates: nil,
            serverUpdatedSince: "token-\(syncCallCount)"
        )
    }
}

private enum TasksWriteQueueExecutorStubError: Error {
    case unused
}
