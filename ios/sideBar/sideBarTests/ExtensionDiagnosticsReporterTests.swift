import OSLog
import XCTest
import sideBarShared

final class ExtensionDiagnosticsReporterTests: XCTestCase {
    func testBreadcrumbLogsAndMirrorsToDiagnosticsStore() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let failureRecorder = RecordingExtensionFailureRecorder()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store,
            failureRecorder: failureRecorder
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
        XCTAssertTrue(failureRecorder.messages.isEmpty)
    }

    func testFailureCapturesToFailureRecorderAndDiagnosticsStore() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let failureRecorder = RecordingExtensionFailureRecorder()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store,
            failureRecorder: failureRecorder
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
        XCTAssertEqual(failureRecorder.messages.count, 1)
        XCTAssertEqual(failureRecorder.messages.first?.message, "Share extension environment unavailable.")
        XCTAssertEqual(failureRecorder.messages.first?.context["reason"], "missing_app_group")
    }

    func testFailureDoesNotCaptureToSentryRecorderWhenDisabled() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        let failureRecorder = RecordingExtensionFailureRecorder()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store,
            failureRecorder: failureRecorder,
            isFailureCaptureEnabled: false
        )

        reporter.captureFailure(
            surface: "safari_extension",
            stage: "queue_write_failed",
            message: "Failed to queue website from Safari extension.",
            metadata: ["code": "queue_failed"]
        )

        XCTAssertEqual(logger.records.count, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertTrue(failureRecorder.messages.isEmpty)
    }

    func testBreadcrumbStillLogsWhenDiagnosticsStoreIsUnavailable() {
        let logger = RecordingExtensionDiagnosticsLogger()
        let store = RecordingExternalSurfaceDiagnosticsStore()
        store.shouldAcceptRecords = false
        let failureRecorder = RecordingExtensionFailureRecorder()
        let reporter = ExtensionDiagnosticsReporter(
            logger: logger,
            store: store,
            failureRecorder: failureRecorder
        )

        reporter.recordBreadcrumb(
            surface: "widget_bridge_extension",
            stage: "load",
            message: "Loaded widget data snapshot.",
            metadata: ["decode_success": "true"]
        )

        XCTAssertEqual(logger.records.count, 1)
        XCTAssertEqual(store.records.count, 0)
        XCTAssertTrue(failureRecorder.messages.isEmpty)
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

private final class RecordingExtensionFailureRecorder: ExtensionFailureRecording {
    struct Message: Equatable {
        let message: String
        let context: [String: String]
    }

    private(set) var messages: [Message] = []

    func capture(message: String, context: [String: String]) {
        messages.append(Message(message: message, context: context))
    }
}
