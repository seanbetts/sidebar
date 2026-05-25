import XCTest
@testable import sideBar

final class WriteQueueCoalescingPolicyTests: XCTestCase {
    func testRecognizesTaskNotesUpdatesOnly() throws {
        let notesPayload = try JSONEncoder().encode(TaskOperationPayload(
            operationId: "op-1",
            op: "notes",
            id: "task-1",
            notes: "Draft"
        ))
        let renamePayload = try JSONEncoder().encode(TaskOperationPayload(
            operationId: "op-2",
            op: "rename",
            id: "task-1",
            title: "Renamed"
        ))

        XCTAssertTrue(WriteQueueCoalescingPolicy.isTaskNotesUpdate(notesPayload))
        XCTAssertFalse(WriteQueueCoalescingPolicy.isTaskNotesUpdate(renamePayload))
    }

    func testMergesSettingsPatchPayloads() throws {
        let existing = SettingsMutationPayload(
            communicationStyle: "Concise",
            name: "Ada",
            includeDateOfBirth: true
        )
        let incoming = SettingsMutationPayload(
            workingRelationship: "Operator",
            jobTitle: "Rear Admiral",
            includeDateOfBirth: false
        )

        let merged = try XCTUnwrap(
            WriteQueueCoalescingPolicy.mergedSettingsPatch(
                existing: try JSONEncoder().encode(existing),
                incoming: try JSONEncoder().encode(incoming)
            )
        )
        let decoded = try JSONDecoder().decode(SettingsMutationPayload.self, from: merged)

        XCTAssertEqual(decoded.communicationStyle, "Concise")
        XCTAssertEqual(decoded.workingRelationship, "Operator")
        XCTAssertEqual(decoded.name, "Ada")
        XCTAssertEqual(decoded.jobTitle, "Rear Admiral")
        XCTAssertTrue(decoded.includeDateOfBirth)
    }

    func testRejectsNonSettingsPatchPayloadsForSettingsMerge() throws {
        let existing = SettingsMutationPayload.providerKey(
            provider: "openai",
            rawSecretReference: "secret"
        )
        let incoming = SettingsMutationPayload(name: "Ada")

        let merged = WriteQueueCoalescingPolicy.mergedSettingsPatch(
            existing: try JSONEncoder().encode(existing),
            incoming: try JSONEncoder().encode(incoming)
        )

        XCTAssertNil(merged)
    }
}
