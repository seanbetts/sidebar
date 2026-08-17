import Foundation
import sideBarShared
@testable import sideBar

@MainActor
final class TasksWriteQueueStoreSpy: TasksWriteQueueApplying {
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

final class TasksSyncAPIStub: TasksProviding {
    var syncCallCount: Int = 0
    var accountBoundAuthorizationTokens: [String] = []
    private var queuedSyncResponses: [TaskSyncResponse]
    private let accountBoundSyncBarrier: TasksAccountBoundSyncBarrier?

    init(
        syncResponses: [TaskSyncResponse] = [],
        accountBoundSyncBarrier: TasksAccountBoundSyncBarrier? = nil
    ) {
        self.queuedSyncResponses = syncResponses
        self.accountBoundSyncBarrier = accountBoundSyncBarrier
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

    func sync(
        _ payload: TaskSyncRequest,
        authorizationToken: String
    ) async throws -> TaskSyncResponse {
        accountBoundAuthorizationTokens.append(authorizationToken)
        await accountBoundSyncBarrier?.suspend()
        return try await sync(payload)
    }
}

actor TasksAccountBoundSyncBarrier {
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isSuspended = false
    private var isReleased = false

    func suspend() async {
        isSuspended = true
        suspendedContinuation?.resume()
        suspendedContinuation = nil
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

enum TasksWriteQueueExecutorStubError: Error {
    case unused
}

struct IdentityRemap: Equatable {
    let localID: String
    let serverID: String
}
