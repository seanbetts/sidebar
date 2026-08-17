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

    func testExecuteDiscardsAccountBoundWriteAfterAccountGenerationChanges() async throws {
        let api = TasksSyncAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let scopeCoordinator = TaskNotificationAccountScopeCoordinator()
        let receivingAccountId = UUID()
        let receivingScope = try XCTUnwrap(
            scopeCoordinator.activate(accountId: receivingAccountId.uuidString)
        )
        scopeCoordinator.invalidate()
        _ = scopeCoordinator.activate(accountId: UUID().uuidString)
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            accountScopeCoordinator: scopeCoordinator,
            refreshDebounceNanoseconds: 10_000_000
        )

        do {
            try await executor.execute(
                write: makeAccountBoundWrite(
                    operationId: "notification-op",
                    taskId: UUID().uuidString,
                    scope: receivingScope
                )
            )
            XCTFail("A stale account-bound write must be discarded")
        } catch WriteQueueError.accountScopeChanged {
            // Expected: the write is rejected before the API or local store boundary.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.syncCallCount, 0)
        XCTAssertTrue(store.appliedOperationIds.isEmpty)
        XCTAssertNil(store.lastToken)
    }

    func testExecuteRejectsAccountBoundWriteWithoutAuthorizationTokenProvider() async throws {
        let api = TasksSyncAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let scopeCoordinator = TaskNotificationAccountScopeCoordinator()
        let receivingScope = try XCTUnwrap(
            scopeCoordinator.activate(accountId: UUID().uuidString)
        )
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            accountScopeCoordinator: scopeCoordinator,
            refreshDebounceNanoseconds: 10_000_000
        )

        do {
            try await executor.execute(
                write: makeAccountBoundWrite(
                    operationId: "notification-op",
                    taskId: UUID().uuidString,
                    scope: receivingScope
                )
            )
            XCTFail("Account-bound writes must fail closed without captured authorization")
        } catch WriteQueueError.accountScopeChanged {
            // Expected: never fall back to the executor's current API session.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.syncCallCount, 0)
        XCTAssertTrue(api.accountBoundAuthorizationTokens.isEmpty)
        XCTAssertTrue(store.appliedOperationIds.isEmpty)
        XCTAssertNil(store.lastToken)
    }

    func testTasksProvidingDefaultFixedAuthorizationSyncFailsClosed() async throws {
        let api = TasksViewModelAPIStub()
        let request = TaskSyncRequest(lastSync: nil, operations: [])

        do {
            _ = try await api.sync(request, authorizationToken: "captured-token")
            XCTFail("A provider without fixed-authorization support must fail closed")
        } catch TasksProvidingError.fixedAuthorizationUnsupported {
            // Expected: do not fall back to sync using the provider's current session.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExecuteTreatsUnsupportedFixedAuthorizationAsTerminal() async throws {
        let api = TasksViewModelAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let scopeCoordinator = TaskNotificationAccountScopeCoordinator()
        let accountId = UUID()
        let accountScope = try XCTUnwrap(
            scopeCoordinator.activate(accountId: accountId.uuidString)
        )
        let authorizationToken = try makeUnsignedJWT(subject: accountId.uuidString)
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            accountScopeCoordinator: scopeCoordinator,
            authorizationTokenProvider: { authorizationToken }
        )

        do {
            try await executor.execute(
                write: makeAccountBoundWrite(
                    operationId: "notification-op",
                    taskId: UUID().uuidString,
                    scope: accountScope
                )
            )
            XCTFail("Unsupported fixed authorization must be terminal")
        } catch WriteQueueError.accountScopeChanged {
            // Expected: WriteQueue will discard this operation instead of retrying it.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(store.appliedOperationIds.isEmpty)
        XCTAssertNil(store.lastToken)
    }

    func testAccountBoundWriteWaitsForSameAccountAuthorizationRecovery() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let api = TasksSyncAPIStub()
        let store = TasksWriteQueueStoreSpy()
        let scopeCoordinator = TaskNotificationAccountScopeCoordinator()
        let accountId = UUID()
        let accountScope = try XCTUnwrap(
            scopeCoordinator.activate(accountId: accountId.uuidString)
        )
        var authorizationToken: String?
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            accountScopeCoordinator: scopeCoordinator,
            authorizationTokenProvider: { authorizationToken }
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false,
            retrySleep: { _ in }
        )
        let operationId = "stale-recoverable-notification-op"
        let taskId = UUID().uuidString
        let payload = TaskAccountBoundOperationPayload(
            operation: TaskOperationPayload(
                operationId: operationId,
                op: "complete",
                id: taskId
            ),
            accountScope: accountScope
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: taskId,
            payload: payload
        )

        await queue.processQueue()

        let pendingRequest = PendingWrite.fetchRequest()
        let pendingWrites = try persistence.container.viewContext.fetch(pendingRequest)
        let deferredWrite = try XCTUnwrap(pendingWrites.first)
        XCTAssertEqual(pendingWrites.count, 1)
        XCTAssertEqual(deferredWrite.status, WriteQueueStatus.pending.rawValue)
        XCTAssertEqual(deferredWrite.attempts, 0)
        XCTAssertNil(deferredWrite.lastError)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(api.syncCallCount, 0)
        XCTAssertTrue(api.accountBoundAuthorizationTokens.isEmpty)
        XCTAssertTrue(store.appliedOperationIds.isEmpty)
        XCTAssertNil(store.lastToken)

        let recoveredToken = try makeUnsignedJWT(subject: accountId.uuidString)
        authorizationToken = recoveredToken
        await queue.processQueue()
        await queue.processQueue()

        let remainingWrites = try persistence.container.viewContext.fetch(pendingRequest)
        XCTAssertTrue(remainingWrites.isEmpty)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(api.syncCallCount, 1)
        XCTAssertEqual(api.accountBoundAuthorizationTokens, [recoveredToken])
        XCTAssertEqual(store.appliedOperationIds, [operationId])
        XCTAssertEqual(store.lastToken, "token-1")
    }

    func testExecuteKeepsAccountBoundWriteOnCapturedAuthorizationToken() async throws {
        let barrier = TasksAccountBoundSyncBarrier()
        let api = TasksSyncAPIStub(accountBoundSyncBarrier: barrier)
        let store = TasksWriteQueueStoreSpy()
        let scopeCoordinator = TaskNotificationAccountScopeCoordinator()
        let receivingAccountId = UUID()
        let receivingScope = try XCTUnwrap(
            scopeCoordinator.activate(accountId: receivingAccountId.uuidString)
        )
        let receivingToken = try makeUnsignedJWT(subject: receivingAccountId.uuidString)
        let nextAccountId = UUID()
        let nextToken = try makeUnsignedJWT(subject: nextAccountId.uuidString)
        var currentToken = receivingToken
        let executor = TasksWriteQueueExecutor(
            api: api,
            store: store,
            accountScopeCoordinator: scopeCoordinator,
            authorizationTokenProvider: { currentToken },
            refreshDebounceNanoseconds: 10_000_000
        )

        let execution = Task { @MainActor in
            try await executor.execute(
                write: makeAccountBoundWrite(
                    operationId: "notification-op",
                    taskId: UUID().uuidString,
                    scope: receivingScope
                )
            )
        }
        await barrier.waitUntilSuspended()

        scopeCoordinator.invalidate()
        _ = scopeCoordinator.activate(accountId: nextAccountId.uuidString)
        currentToken = nextToken
        await barrier.release()

        do {
            try await execution.value
            XCTFail("The completed A response must not update B state")
        } catch WriteQueueError.accountScopeChanged {
            // Expected after the fixed-token A request returns in B's generation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.accountBoundAuthorizationTokens, [receivingToken])
        XCTAssertTrue(store.appliedOperationIds.isEmpty)
        XCTAssertNil(store.lastToken)
    }

    private func makeUnsignedJWT(subject: String) throws -> String {
        let headerData = try JSONSerialization.data(
            withJSONObject: ["alg": "none", "typ": "JWT"]
        )
        let payloadData = try JSONSerialization.data(
            withJSONObject: ["sub": subject]
        )
        func encode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(headerData)).\(encode(payloadData))."
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

    private func makeAccountBoundWrite(
        operationId: String,
        taskId: String,
        scope: TaskNotificationAccountScope
    ) throws -> PendingWriteRecord {
        let payload = TaskAccountBoundOperationPayload(
            operation: TaskOperationPayload(
                operationId: operationId,
                op: "complete",
                id: taskId
            ),
            accountScope: scope
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

private actor TasksAccountBoundSyncBarrier {
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

private enum TasksWriteQueueExecutorStubError: Error {
    case unused
}

private struct IdentityRemap: Equatable {
    let localID: String
    let serverID: String
}
