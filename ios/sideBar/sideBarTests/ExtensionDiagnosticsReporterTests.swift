import OSLog
import XCTest
import sideBarShared

final class ExtensionDiagnosticsReporterTests: XCTestCase {
    func testBreadcrumbLogsAndMirrorsToDiagnosticsStore() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store
        )

        reporter.recordBreadcrumb(
            surface: "widget_provider",
            stage: "timeline",
            message: "Built notes widget entry.",
            metadata: [
                "provider": "PinnedNotesProvider",
                "item_count": "3"
            ]
        )

        XCTAssertEqual(logger.records.count, 1)
        XCTAssertEqual(logger.records.first?.level, .info)
        XCTAssertEqual(logger.records.first?.surface, "widget_provider")
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.surface, "widget_provider")
    }

    func testFailureLogsAndMirrorsToDiagnosticsStore() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store
        )

        reporter.captureFailure(
            surface: "share_extension",
            stage: "environment_init_failed",
            message: "Share extension environment unavailable.",
            metadata: ["reason": "missing_app_group"]
        )

        XCTAssertEqual(logger.records.count, 1)
        XCTAssertEqual(logger.records.first?.level, .error)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.surface, "share_extension")
        XCTAssertEqual(store.records.first?.metadata["reason"], "missing_app_group")
    }

    func testBreadcrumbStillLogsWhenDiagnosticsStoreIsUnavailable() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        store.shouldAcceptRecords = false
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store
        )

        reporter.recordBreadcrumb(
            surface: "widget_bridge_extension",
            stage: "load",
            message: "Loaded widget data snapshot.",
            metadata: ["decode_success": "true"]
        )

        XCTAssertEqual(logger.records.count, 1)
        XCTAssertEqual(store.records.count, 0)
    }

    func testFailureSanitizesUnsafeMetadataAndNormalizesKeys() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store
        )

        reporter.captureFailure(
            surface: "widget_provider",
            stage: "refresh_failed",
            message: "Refresh failed.",
            metadata: [
                "url": "https://example.com/private/path",
                "file_path": "/tmp/private.mov",
                "backend_body": "{\"detail\":\"raw\"}",
                "requestKind": "foregroundRead",
                "statusCode": "503",
                "category": "offline"
            ]
        )

        let metadata = try! XCTUnwrap(store.records.first?.metadata)
        XCTAssertEqual(metadata["category"], "offline")
        XCTAssertEqual(metadata["request_kind"], "foregroundRead")
        XCTAssertEqual(metadata["status_code"], "503")
        XCTAssertNil(metadata["url"])
        XCTAssertNil(metadata["file_path"])
        XCTAssertNil(metadata["backend_body"])
        XCTAssertNil(metadata["requestKind"])
        XCTAssertNil(metadata["statusCode"])
    }
}

private final class RecordingExtensionDiagnosticsLogger: ExtensionDiagnosticsLogging {
    struct Record: Equatable {
        let level: OSLogType
        let surface: String
        let stage: String
        let message: String
        let metadata: [String: String]
    }

    private(set) var records: [Record] = []

    func log(
        level: OSLogType,
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String]
    ) {
        records.append(
            Record(
                level: level,
                surface: surface,
                stage: stage,
                message: message,
                metadata: metadata
            )
        )
    }
}

private final class RecordingExternalSurfaceDiagnosticsStore: ExternalSurfaceDiagnosticsRecording {
    private(set) var records: [ExternalSurfaceDiagnosticEntry] = []
    var shouldAcceptRecords = true

    func record(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String]
    ) -> Bool {
        guard shouldAcceptRecords else { return false }
        records.append(
            ExternalSurfaceDiagnosticEntry(
                surface: surface,
                stage: stage,
                message: message,
                metadata: metadata
            )
        )
        return true
    }
}
