import CoreData
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueHeaderStatusTests: XCTestCase {
    func testRetryFailedWriteTransitionsQueueOutOfErrorState() async throws {
        let failedID1 = UUID()
        let failedID2 = UUID()
        let queue = try await makeQueue(
            writes: [
                makeWrite(id: failedID1, status: .failed, createdAt: Date(timeIntervalSince1970: 1)),
                makeWrite(id: failedID2, status: .failed, createdAt: Date(timeIntervalSince1970: 2)),
                makeWrite(id: UUID(), status: .pending, createdAt: Date(timeIntervalSince1970: 3))
            ]
        )

        try await queue.retryWrite(id: failedID1)

        XCTAssertEqual(queue.failedHeaderRows.map(\.id), [failedID2])
        XCTAssertEqual(queue.headerStatusSnapshotLabel, "Sync error")
    }

    func testQueueHeaderSnapshotPrefersErrorOverSyncingAndPending() async throws {
        let queue = try await makeQueue(
            writes: [
                makeWrite(id: UUID(), status: .failed, createdAt: Date(timeIntervalSince1970: 1)),
                makeWrite(id: UUID(), status: .pending, createdAt: Date(timeIntervalSince1970: 2))
            ]
        )

        XCTAssertEqual(queue.headerStatusSnapshotLabel, "Sync error")
    }

    func testCancelFailedWriteOnlyRemovesTargetedRow() async throws {
        let failedID1 = UUID()
        let failedID2 = UUID()
        let queue = try await makeQueue(
            writes: [
                makeWrite(id: failedID1, status: .failed, createdAt: Date(timeIntervalSince1970: 1)),
                makeWrite(id: failedID2, status: .failed, createdAt: Date(timeIntervalSince1970: 2))
            ]
        )

        try await queue.cancelWrite(id: failedID1)

        XCTAssertEqual(queue.failedHeaderRows.map(\.id), [failedID2])
        XCTAssertEqual(queue.headerStatusSnapshotLabel, "Sync error")
    }

    func testCancelFailedWriteRecomputesToNoSyncPillWhenQueueBecomesEmpty() async throws {
        let failedID1 = UUID()
        let queue = try await makeQueue(
            writes: [makeWrite(id: failedID1, status: .failed, createdAt: Date(timeIntervalSince1970: 1))]
        )

        try await queue.cancelWrite(id: failedID1)

        XCTAssertNil(queue.headerStatusSnapshot)
    }

    func testQueueHeaderSnapshotTracksPendingAndSyncingStates() async throws {
        let queue = try await makeQueue(
            writes: [makeWrite(id: UUID(), status: .pending, createdAt: Date(timeIntervalSince1970: 1))]
        )

        XCTAssertEqual(queue.headerStatusSnapshotLabel, "Pending")

        let processingTask = Task {
            await queue.processQueue()
        }

        await waitUntilWriteQueueHeaderState { queue.isProcessing }
        XCTAssertEqual(queue.headerStatusSnapshotLabel, "Syncing")

        processingTask.cancel()
    }

    func testQueueHeaderSnapshotMapsStoredAPIClientErrorsToUserFacingDetail() async throws {
        let queue = try await makeQueue(
            writes: [
                makeWrite(
                    id: UUID(),
                    status: .failed,
                    lastError: "decodingFailed",
                    createdAt: Date(timeIntervalSince1970: 1)
                )
            ]
        )

        guard case let .error(rows)? = queue.headerStatusSnapshot else {
            return XCTFail("Expected sync error snapshot")
        }

        XCTAssertEqual(rows.first?.detail, "Unexpected response from server.")
    }

    private func makeQueue(
        writes: [PendingWriteFixture]
    ) async throws -> WriteQueue {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        for write in writes {
            let pendingWrite = PendingWrite.insertNew(in: context)
            pendingWrite.id = write.id
            pendingWrite.operationType = write.operation.rawValue
            pendingWrite.entityType = write.entityType.rawValue
            pendingWrite.entityId = write.entityID
            pendingWrite.payload = Data("{}".utf8)
            pendingWrite.createdAt = write.createdAt
            pendingWrite.attempts = write.attempts
            pendingWrite.status = write.status.rawValue
            pendingWrite.lastError = write.lastError
        }

        try context.save()

        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: TestWriteExecutor(),
            autoProcessEnabled: false
        )

        await waitUntilWriteQueueHeaderState {
            queue.pendingCount == writes.count && queue.failedCount == writes.filter { $0.status == .failed }.count
        }
        return queue
    }

    private func makeWrite(
        id: UUID,
        status: WriteQueueStatus,
        operation: WriteOperation = .delete,
        entityType: WriteEntityType = .website,
        entityID: String? = "website-1",
        attempts: Int16 = 1,
        lastError: String? = "requestFailed(500)",
        createdAt: Date
    ) -> PendingWriteFixture {
        PendingWriteFixture(
            id: id,
            operation: operation,
            entityType: entityType,
            entityID: entityID,
            status: status,
            attempts: attempts,
            lastError: lastError,
            createdAt: createdAt
        )
    }
}

private struct PendingWriteFixture {
    let id: UUID
    let operation: WriteOperation
    let entityType: WriteEntityType
    let entityID: String?
    let status: WriteQueueStatus
    let attempts: Int16
    let lastError: String?
    let createdAt: Date
}

private extension WriteQueue {
    var headerStatusSnapshotLabel: String? {
        switch headerStatusSnapshot {
        case .syncing:
            return "Syncing"
        case .pending:
            return "Pending"
        case .error:
            return "Sync error"
        case nil:
            return nil
        }
    }
}

private final class TestWriteExecutor: WriteQueueExecutor {
    func execute(write: PendingWriteRecord) async throws {
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled {
            throw CancellationError()
        }
    }
}

@MainActor
private func waitUntilWriteQueueHeaderState(
    timeoutNanoseconds: UInt64 = 300_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if condition() {
            return
        }
        await Task.yield()
    }

    if !condition() {
        XCTFail("Condition was not met before timeout")
    }
}
