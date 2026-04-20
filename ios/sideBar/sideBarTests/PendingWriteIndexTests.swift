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

    func testPendingWriteIndexMapsSettingsPatchToSettingsSectionAndDirtyFields() throws {
        let payload = SettingsMutationPayload(
            communicationStyle: "Concise",
            notificationPreferences: NotificationPreferencesUpdate(
                taskRemindersEnabled: true,
                assistantReplyNotificationsEnabled: false
            ),
            assistantIdentity: AssistantIdentitySettings(
                name: "Ada",
                tone: "Warm",
                values: "Precision",
                boundaries: "No fluff"
            ),
            aiPrimaryProvider: "openai"
        )
        let index = try PendingWriteIndex(
            writes: [
                makeWrite(
                    operation: .update,
                    entityType: .settings,
                    entityId: payload.entityId,
                    payload: try JSONEncoder().encode(payload)
                )
            ]
        )

        XCTAssertTrue(index.overlaps(section: AppSection.settings))
        let dirtyFields = index.dirtyFields(for: WriteEntityType.settings, entityId: payload.entityId)
        XCTAssertTrue(
            Set([
                "aiPrimaryProvider",
                "assistantIdentity",
                "communicationStyle",
                "notificationPreferences"
            ]).isSubset(of: dirtyFields)
        )
        XCTAssertFalse(index.overlaps(section: AppSection.notes))
    }

    private func makeWrite(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String,
        payload: [String: Any]
    ) throws -> PendingWriteRecord {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try makeWrite(
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            payload: data
        )
    }

    private func makeWrite(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String,
        payload: Data
    ) throws -> PendingWriteRecord {
        return PendingWriteRecord(
            id: UUID(),
            operationType: operation.rawValue,
            entityType: entityType.rawValue,
            entityId: entityId,
            payload: payload,
            serverSnapshot: nil,
            attempts: 0
        )
    }
}
