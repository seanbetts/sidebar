import Foundation
import XCTest
import sideBarShared
@testable import sideBar

final class WidgetBridgeContractTests: XCTestCase {
    func testWidgetContentTypeKeysRemainStable() {
        XCTAssertEqual(WidgetContentType.tasks.dataKey, "widget_tasks_data")
        XCTAssertEqual(WidgetContentType.tasks.pendingKey, "widget_tasks_pending")
        XCTAssertEqual(WidgetContentType.notes.dataKey, "widget_notes_data")
        XCTAssertEqual(WidgetContentType.notes.pendingKey, "widget_notes_pending")
        XCTAssertEqual(WidgetContentType.websites.dataKey, "widget_websites_data")
        XCTAssertEqual(WidgetContentType.websites.pendingKey, "widget_websites_pending")
        XCTAssertEqual(WidgetContentType.files.dataKey, "widget_files_data")
        XCTAssertEqual(WidgetContentType.files.pendingKey, "widget_files_pending")
    }

    func testWidgetContentTypeIncludesExpectedPrimaryKinds() {
        XCTAssertTrue(WidgetContentType.tasks.widgetKinds.contains("TodayTasksWidget"))
        XCTAssertTrue(WidgetContentType.notes.widgetKinds.contains("PinnedNotesWidget"))
        XCTAssertTrue(WidgetContentType.websites.widgetKinds.contains("SavedSitesWidget"))
        XCTAssertTrue(WidgetContentType.files.widgetKinds.contains("PinnedFilesWidget"))
    }

    func testWidgetContentTypeKindsAreUniquePerContentType() {
        for contentType in WidgetContentType.allCases {
            let kinds = contentType.widgetKinds
            XCTAssertEqual(kinds.count, Set(kinds).count)
        }
    }

    func testWidgetPendingOperationRoundTripsViaCodable() throws {
        let operation = WidgetPendingOperation(itemId: "task-123", action: TaskWidgetAction.complete)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoded = try encoder.encode(operation)
        let decoded = try decoder.decode(WidgetPendingOperation<TaskWidgetAction>.self, from: encoded)

        XCTAssertEqual(decoded.id, operation.id)
        XCTAssertEqual(decoded.itemId, operation.itemId)
        XCTAssertEqual(decoded.action, operation.action)
        XCTAssertLessThan(abs(decoded.timestamp.timeIntervalSince(operation.timestamp)), 1.0)
    }

    func testAppGroupConfigurationNormalizesKnownExtensionBundleSuffixes() {
        XCTAssertEqual(
            AppGroupConfiguration.normalizedSharedBundleIdentifier("ai.sidebar.sidebar.sideBarWidgets"),
            "ai.sidebar.sidebar"
        )
        XCTAssertEqual(
            AppGroupConfiguration.normalizedSharedBundleIdentifier("ai.sidebar.sidebar.ShareExtension"),
            "ai.sidebar.sidebar"
        )
        XCTAssertEqual(
            AppGroupConfiguration.normalizedSharedBundleIdentifier(
                "ai.sidebar.sidebar.sideBar-Safari-Extension--macOS-.Extension"
            ),
            "ai.sidebar.sidebar"
        )
    }
}
