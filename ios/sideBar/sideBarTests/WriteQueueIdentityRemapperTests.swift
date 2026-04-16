import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueIdentityRemapperTests: XCTestCase {
    func testApplyServerIdentityMapRetargetsPendingTaskMutations() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )

        let localID = "local-task-1"
        let serverID = "task-42"
        let context = persistence.container.viewContext

        let rename = PendingWrite.insertNew(in: context)
        rename.id = UUID()
        rename.operationType = WriteOperation.update.rawValue
        rename.entityType = WriteEntityType.task.rawValue
        rename.entityId = localID
        rename.payload = try JSONEncoder().encode(
            TaskOperationPayload(
                operationId: "rename-op",
                op: "rename",
                id: localID,
                title: "Renamed"
            )
        )
        rename.createdAt = Date()
        rename.attempts = 0
        rename.status = WriteQueueStatus.pending.rawValue

        let unrelated = PendingWrite.insertNew(in: context)
        unrelated.id = UUID()
        unrelated.operationType = WriteOperation.update.rawValue
        unrelated.entityType = WriteEntityType.task.rawValue
        unrelated.entityId = "task-99"
        unrelated.payload = try JSONEncoder().encode(
            TaskOperationPayload(
                operationId: "other-op",
                op: "rename",
                id: "task-99",
                title: "Unrelated"
            )
        )
        unrelated.createdAt = Date()
        unrelated.attempts = 0
        unrelated.status = WriteQueueStatus.pending.rawValue
        try context.save()

        try await queue.applyServerIdentityMap(
            entityType: .task,
            localID: localID,
            serverID: serverID
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        let updatedRename = try XCTUnwrap(writes.first(where: { $0.id == rename.id }))
        let renamePayload = try JSONDecoder().decode(TaskOperationPayload.self, from: updatedRename.payload)
        XCTAssertEqual(updatedRename.entityId, serverID)
        XCTAssertEqual(renamePayload.id, serverID)

        let updatedUnrelated = try XCTUnwrap(writes.first(where: { $0.id == unrelated.id }))
        let unrelatedPayload = try JSONDecoder().decode(TaskOperationPayload.self, from: updatedUnrelated.payload)
        XCTAssertEqual(updatedUnrelated.entityId, "task-99")
        XCTAssertEqual(unrelatedPayload.id, "task-99")
    }
}
