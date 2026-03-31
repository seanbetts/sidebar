import Foundation
import sideBarShared
import XCTest

final class WidgetDataBridgeTests: XCTestCase {
    private func makeBridge(
        userDefaults: UserDefaults,
        diagnostics: @escaping (String, String, [String: String]) -> Void = { _, _, _ in },
        reloader: @escaping (WidgetContentType) -> Void = { _ in }
    ) -> WidgetDataBridge {
        WidgetDataBridge(
            userDefaultsProvider: { userDefaults },
            appGroupResolutionProvider: {
                WidgetBridgeAppGroupResolution(id: "group.test.widget", source: "test")
            },
            diagnosticsRecorder: diagnostics,
            timelineReloader: reloader
        )
    }

    func testStoreAndLoadRoundTripPreservesWidgetPayload() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let payload = WidgetNoteData(
            notes: [WidgetNote(id: "/note.md", name: "Note", path: "/note.md", pinned: true, pinnedOrder: 0)],
            totalCount: 1
        )

        bridge.store(payload, for: .notes)
        let loaded: WidgetNoteData = bridge.load(for: .notes)

        XCTAssertEqual(loaded.totalCount, 1)
        XCTAssertEqual(loaded.notes.map(\.path), ["/note.md"])
    }

    func testPendingOperationsRoundTripAndDeduplicate() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let operation = WidgetPendingOperation(itemId: "task-1", action: TaskWidgetAction.complete)

        bridge.recordPendingOperation(operation, for: .tasks)
        bridge.recordPendingOperation(operation, for: .tasks)
        let pending = bridge.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.itemId, "task-1")
        XCTAssertEqual(pending.first?.action, .complete)
        XCTAssertTrue(
            bridge.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self).isEmpty
        )
    }

    func testHasStoredSnapshotReturnsTrueAfterStoringEmptyPayload() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)

        XCTAssertFalse(bridge.hasStoredSnapshot(for: .notes))

        bridge.store(WidgetNoteData.empty, for: .notes)

        XCTAssertTrue(bridge.hasStoredSnapshot(for: .notes))
    }
}
