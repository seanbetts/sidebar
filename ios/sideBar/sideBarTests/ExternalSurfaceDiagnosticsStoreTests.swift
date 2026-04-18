import XCTest
import sideBarShared

final class ExternalSurfaceDiagnosticsStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalSurfaceDiagnosticsStore.shared.clear()
    }

    override func tearDown() {
        ExternalSurfaceDiagnosticsStore.shared.clear()
        super.tearDown()
    }

    func testRecordAddsSanitizedBuildAndProcessMetadata() throws {
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "test_surface",
            stage: "test_stage",
            message: "Recorded test diagnostic."
        )

        let entry = try XCTUnwrap(ExternalSurfaceDiagnosticsStore.shared.recentEntries(limit: 1).first)
        XCTAssertFalse((entry.metadata["process_name"] ?? "").isEmpty)
        XCTAssertFalse((entry.metadata["bundle_id"] ?? "").isEmpty)
        XCTAssertFalse((entry.metadata["app_version"] ?? "").isEmpty)
        XCTAssertFalse((entry.metadata["build_number"] ?? "").isEmpty)
        XCTAssertNil(entry.metadata["bundle_path"])
        XCTAssertNil(entry.metadata["process_id"])
    }

    func testCanQueueURLItemsRecordsStorageAvailabilityDetails() {
        let suiteName = "ExternalSurfaceDiagnosticsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer {
            defaults?.removePersistentDomain(forName: suiteName)
        }

        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let store = PendingShareStore(
            baseDirectory: baseDirectory,
            userDefaults: defaults,
            allowAppGroupFallback: false
        )

        XCTAssertTrue(store.canQueueURLItems())

        let export = ExternalSurfaceDiagnosticsStore.shared.exportText(limit: 10)
        XCTAssertTrue(export.contains("[pending_share_store] storage_available:"))
        XCTAssertTrue(export.contains("context=canQueueURLItems"))
        XCTAssertTrue(export.contains("has_defaults=true"))
        XCTAssertTrue(export.contains("has_root_directory=true"))
    }

    func testCanQueueFileItemsRecordsMissingAppGroupContextWhenFileContainerUnavailable() {
        let suiteName = "ExternalSurfaceDiagnosticsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer {
            defaults?.removePersistentDomain(forName: suiteName)
        }

        let store = PendingShareStore(
            baseDirectory: nil,
            userDefaults: defaults,
            allowAppGroupFallback: false
        )

        XCTAssertFalse(store.canQueueFileItems())

        let entries = ExternalSurfaceDiagnosticsStore.shared.recentEntries(limit: 10)
        XCTAssertTrue(entries.contains { entry in
            entry.surface == "pending_share_store"
                && entry.stage == "missing_app_group"
                && entry.metadata["context"] == "canQueueFileItems"
        })
    }
}
