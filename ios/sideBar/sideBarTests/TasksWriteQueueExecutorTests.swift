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
