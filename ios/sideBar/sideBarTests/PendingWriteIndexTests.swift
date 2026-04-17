import XCTest
@testable import sideBar

@MainActor
final class PendingWriteIndexTests: XCTestCase {
    func testPendingWriteIndexMapsWebsitePinWriteToWebsitesSectionAndPinnedField() throws {
        let index = try PendingWriteIndex(
            writes: [
                makeWrite(
                    operation: .pin,
                    entityType: .website,
                    entityId: "website-1",
                    payload: ["pinned": true]
                )
            ]
        )

        XCTAssertTrue(index.overlaps(section: .websites))
        XCTAssertEqual(index.dirtyFields(for: .website, entityId: "website-1"), ["pinned"])
        XCTAssertFalse(index.overlaps(section: .notes))
    }

    func testPendingWriteIndexMapsTaskUpdatePayloadFieldsToDirtyFieldSet() throws {
        let index = try PendingWriteIndex(
            writes: [
                makeWrite(
                    operation: .update,
                    entityType: .task,
                    entityId: "task-1",
                    payload: ["title": "Edited title", "status": "done"]
                )
            ]
        )

        XCTAssertTrue(index.overlaps(section: .tasks))
        XCTAssertEqual(index.dirtyFields(for: .task, entityId: "task-1"), ["status", "title"])
        XCTAssertFalse(index.overlaps(section: .chat))
    }

    private func makeWrite(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String,
        payload: [String: Any]
    ) throws -> PendingWriteRecord {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return PendingWriteRecord(
            id: UUID(),
            operationType: operation.rawValue,
            entityType: entityType.rawValue,
            entityId: entityId,
            payload: data,
            serverSnapshot: nil,
            attempts: 0
        )
    }
}
