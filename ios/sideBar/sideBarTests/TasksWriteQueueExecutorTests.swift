import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksWriteQueueExecutorTests: XCTestCase {
    func testExecuteAppliesSyncResponsesAcrossBackToBackWrites() async throws {
        let api = TasksSyncAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            refreshDebounceNanoseconds: 10_000_000
        )

        try await executor.execute(write: makeWrite(operationId: "op-1", taskId: "task-1"))
        try await executor.execute(write: makeWrite(operationId: "op-2", taskId: "task-2"))

        XCTAssertEqual(api.syncCallCount, 2)
        XCTAssertEqual(store.appliedOperationIds, ["op-1", "op-2"])
        XCTAssertEqual(store.lastToken, "token-2")
    }

    func testExecuteCreateRemapsPendingPlaceholderToServerIdentity() async throws {
        let createdTask = TaskItem(
            id: "task-42",
            title: "Buy milk",
            status: "open",
            updatedAt: "u1"
        )
        let api = TasksSyncAPIStub(
            syncResponses: [
                TaskSyncResponse(
                    applied: ["create-op"],
                    tasks: [createdTask],
                    nextTasks: [],
                    conflicts: [],
                    updates: nil,
                    serverUpdatedSince: "token-1"
                )
            ]
        )
        let store = TasksWriteQueueStoreSpy()
        store.pendingPlaceholderIDs["create-op"] = "local-task-1"
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            refreshDebounceNanoseconds: 10_000_000
        )

        try await executor.execute(
            write: makeCreateWrite(operationId: "create-op", title: "Buy milk")
        )

        XCTAssertEqual(
            store.remappedIdentityPairs,
            [IdentityRemap(localID: "local-task-1", serverID: "task-42")]
        )
        XCTAssertEqual(store.appliedOperationIds, ["create-op"])
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

    private func makeCreateWrite(operationId: String, title: String) throws -> PendingWriteRecord {
        let payload = TaskOperationPayload(
            operationId: operationId,
            op: "add",
            id: nil,
            title: title
        )
        let encoded = try JSONEncoder().encode(payload)
        return PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.create.rawValue,
            entityType: WriteEntityType.task.rawValue,
            entityId: nil,
            payload: encoded,
            serverSnapshot: nil,
            attempts: 0
        )
    }
}

@MainActor
private final class TasksWriteQueueStoreSpy: TasksWriteQueueApplying {
    var appliedOperationIds: [String] = []
    var lastToken: String?
    var pendingPlaceholderIDs: [String: String] = [:]
    var remappedIdentityPairs: [IdentityRemap] = []

    func applySyncResponse(_ response: TaskSyncResponse, operationId: String) {
        _ = response
        appliedOperationIds.append(operationId)
    }

    func removePendingTaskPlaceholder(operationId: String) {
        _ = operationId
    }

    func pendingPlaceholderId(operationId: String) -> String? {
        pendingPlaceholderIDs[operationId]
    }

    func remapPendingTaskReferences(localID: String, serverID: String) async {
        remappedIdentityPairs.append(IdentityRemap(localID: localID, serverID: serverID))
    }

    func lastSyncToken() -> String? {
        lastToken
    }

    func updateLastSyncToken(_ token: String?) {
        lastToken = token
    }

    func refreshAfterSync() async {}
}

private final class TasksSyncAPIStub: TasksProviding {
    var syncCallCount: Int = 0
    private var queuedSyncResponses: [TaskSyncResponse]

    init(syncResponses: [TaskSyncResponse] = []) {
        self.queuedSyncResponses = syncResponses
    }

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
        if !queuedSyncResponses.isEmpty {
            return queuedSyncResponses.removeFirst()
        }
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

private struct IdentityRemap: Equatable {
    let localID: String
    let serverID: String
}
