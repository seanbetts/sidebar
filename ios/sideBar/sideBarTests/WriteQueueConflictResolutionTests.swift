import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueConflictResolutionTests: XCTestCase {
    func testResolveConflictKeepLocalRebasesIngestionClientUpdatedAt() async throws {
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

        let writeId = UUID()
        let originalPayload = IngestionOperationPayload(
            operationId: "op-file-1",
            op: "rename",
            id: "file-1",
            filename: "updated.pdf",
            clientUpdatedAt: "2026-01-01T00:00:00Z"
        )
        let conflict = IngestionSyncConflict(
            operationId: "op-file-1",
            op: "rename",
            id: "file-1",
            clientUpdatedAt: "2026-01-01T00:00:00Z",
            serverUpdatedAt: "2026-01-02T00:00:00Z",
            serverFile: nil,
            reason: "File changed on another device."
        )

        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.rename.rawValue
        write.entityType = WriteEntityType.file.rawValue
        write.entityId = "file-1"
        write.payload = try JSONEncoder().encode(originalPayload)
        write.createdAt = Date()
        write.attempts = 1
        write.status = WriteQueueStatus.failed.rawValue
        write.conflictReason = "File changed on another device."
        write.serverSnapshot = try JSONEncoder().encode(conflict)
        try context.save()

        await queue.resolveConflict(id: writeId, resolution: .keepLocal)

        let request = PendingWrite.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let refreshed = try persistence.container.viewContext.fetch(request)
        let updated = try XCTUnwrap(refreshed.first)
        let rebased = try JSONDecoder().decode(IngestionOperationPayload.self, from: updated.payload)
        XCTAssertEqual(rebased.clientUpdatedAt, "2026-01-02T00:00:00Z")
        XCTAssertEqual(updated.status, WriteQueueStatus.pending.rawValue)
        XCTAssertNil(updated.conflictReason)
        XCTAssertNil(updated.serverSnapshot)
    }

    func testResolveConflictKeepLocalRebasesWebsiteClientUpdatedAt() async throws {
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

        let writeId = UUID()
        let originalPayload = WebsiteOperationPayload(
            operationId: "op-web-1",
            op: "rename",
            id: "website-1",
            title: "Local Title",
            clientUpdatedAt: "2026-01-01T00:00:00Z"
        )
        let conflict = WebsiteSyncConflict(
            operationId: "op-web-1",
            op: "rename",
            id: "website-1",
            clientUpdatedAt: "2026-01-01T00:00:00Z",
            serverUpdatedAt: "2026-01-02T00:00:00Z",
            serverWebsite: nil,
            reason: "Website changed on another device."
        )

        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.rename.rawValue
        write.entityType = WriteEntityType.website.rawValue
        write.entityId = "website-1"
        write.payload = try JSONEncoder().encode(originalPayload)
        write.createdAt = Date()
        write.attempts = 1
        write.status = WriteQueueStatus.failed.rawValue
        write.conflictReason = "Website changed on another device."
        write.serverSnapshot = try JSONEncoder().encode(conflict)
        try context.save()

        await queue.resolveConflict(id: writeId, resolution: .keepLocal)

        let request = PendingWrite.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let refreshed = try persistence.container.viewContext.fetch(request)
        let updated = try XCTUnwrap(refreshed.first)
        let rebased = try JSONDecoder().decode(WebsiteOperationPayload.self, from: updated.payload)
        XCTAssertEqual(rebased.clientUpdatedAt, "2026-01-02T00:00:00Z")
        XCTAssertEqual(updated.status, WriteQueueStatus.pending.rawValue)
        XCTAssertNil(updated.conflictReason)
        XCTAssertNil(updated.serverSnapshot)
    }

    func testInitRestoresPausedStateWhenConflictExists() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = UUID()
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 1
        write.status = WriteQueueStatus.failed.rawValue
        write.conflictReason = "Note changed"
        try context.save()

        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(queue.isPausedForConflict)
    }
}
