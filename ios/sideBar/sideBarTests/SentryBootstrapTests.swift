import XCTest
import Sentry
import sideBarShared
@testable import sideBar

final class SentryBootstrapTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SentryBootstrap.resetForTesting()
    }

    func testStartIfConfiguredDoesNotStartWithoutDsn() {
        let client = RecordingSentryBootstrapClient()

        let didStart = SentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: nil),
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: TestSentryBundleInfo(),
            client: client
        )

        XCTAssertFalse(didStart)
        XCTAssertEqual(client.startCallCount, 0)
    }

    func testStartIfConfiguredDoesNotStartWhileRunningTests() {
        let client = RecordingSentryBootstrapClient()

        let didStart = SentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            isDebugBuild: false,
            isRunningTestsOrPreviews: true,
            bundle: TestSentryBundleInfo(),
            client: client
        )

        XCTAssertFalse(didStart)
        XCTAssertEqual(client.startCallCount, 0)
    }

    func testStartIfConfiguredStartsInDebugBuildsWhenDsnIsPresent() {
        let client = RecordingSentryBootstrapClient()

        let didStart = SentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            isDebugBuild: true,
            isRunningTestsOrPreviews: false,
            bundle: TestSentryBundleInfo(),
            client: client
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(client.startCallCount, 1)
        XCTAssertEqual(
            client.lastOptions,
            SentryBootstrap.Configuration(
                dsn: "https://example@sentry.io/123",
                environment: "debug",
                releaseName: "ai.sidebar.sidebar@0.1+1",
                tracesSampleRate: 0.1,
                sendDefaultPii: false,
                enableAppHangTracking: true,
                enableAutoSessionTracking: true,
                enableNetworkTracking: true,
                tracePropagationTargets: ["api.example.com", "project.supabase.co"]
            )
        )
    }

    func testStartIfConfiguredStartsForConfiguredReleaseBuild() {
        let client = RecordingSentryBootstrapClient()

        let didStart = SentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: TestSentryBundleInfo(
                bundleIdentifier: "ai.sidebar.sidebar",
                shortVersion: "1.2.3",
                buildNumber: "456"
            ),
            client: client
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(client.startCallCount, 1)
        XCTAssertEqual(
            client.lastOptions,
            SentryBootstrap.Configuration(
                dsn: "https://example@sentry.io/123",
                environment: "production",
                releaseName: "ai.sidebar.sidebar@1.2.3+456",
                tracesSampleRate: 0.1,
                sendDefaultPii: false,
                enableAppHangTracking: true,
                enableAutoSessionTracking: true,
                enableNetworkTracking: true,
                tracePropagationTargets: ["api.example.com", "project.supabase.co"]
            )
        )
    }

    func testMakeOptionsDedupeTracePropagationTargets() {
        let config = EnvironmentConfig(
            apiBaseUrl: URL(string: "https://shared.example.com/api/v1")!,
            supabaseUrl: URL(string: "https://shared.example.com")!,
            supabaseAnonKey: "anon-key",
            sentryDsn: "https://example@sentry.io/123"
        )

        let options = SentryBootstrap.makeOptions(
            config: config,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: TestSentryBundleInfo()
        )

        XCTAssertEqual(options?.tracePropagationTargets, ["shared.example.com"])
    }

    func testRecordNavigationAddsBreadcrumbWhenEnabled() {
        let recorder = RecordingAppSentryRecorder()

        AppSentry.recordNavigation(
            to: .notes,
            source: "deeplink_notes",
            recorder: recorder,
            isEnabled: true
        )

        XCTAssertEqual(
            recorder.breadcrumbs,
            [
                BreadcrumbRecord(
                    level: "info",
                    category: "navigation",
                    message: "Opened Notes",
                    data: ["section": "notes", "source": "deeplink_notes"]
                )
            ]
        )
    }

    func testRecordActionAddsBreadcrumbWhenEnabled() {
        let recorder = RecordingAppSentryRecorder()

        AppSentry.recordAction(
            category: "widget",
            name: "Quick Save",
            data: ["source": "widget_quick_save"],
            recorder: recorder,
            isEnabled: true
        )

        XCTAssertEqual(
            recorder.breadcrumbs,
            [
                BreadcrumbRecord(
                    level: "info",
                    category: "widget",
                    message: "Quick Save",
                    data: ["source": "widget_quick_save"]
                )
            ]
        )
    }

    func testRecordNavigationDoesNothingWhenDisabled() {
        let recorder = RecordingAppSentryRecorder()

        AppSentry.recordNavigation(
            to: .tasks,
            source: "shortcut_navigate",
            recorder: recorder,
            isEnabled: false
        )

        XCTAssertTrue(recorder.breadcrumbs.isEmpty)
    }

    func testCaptureSanitizesContextBeforeSendingToRecorder() throws {
        let recorder = RecordingAppSentryRecorder()

        AppSentry.capture(
            message: "Widget refresh failed",
            context: [
                "operation": "widget.files.refresh",
                "requestKind": "foregroundRead",
                "url": "https://example.com/private/path",
                "backend_body": "{\"detail\":\"raw\"}",
                "file_path": "/tmp/private.mov",
                "category": "offline"
            ],
            recorder: recorder,
            isEnabled: true
        )

        let record = try XCTUnwrap(recorder.messages.first)
        XCTAssertEqual(record.message, "Widget refresh failed")
        XCTAssertEqual(record.context["operation"], "widget.files.refresh")
        XCTAssertEqual(record.context["request_kind"], "foregroundRead")
        XCTAssertEqual(record.context["category"], "offline")
        XCTAssertNil(record.context["url"])
        XCTAssertNil(record.context["backend_body"])
        XCTAssertNil(record.context["file_path"])
        XCTAssertNil(record.context["requestKind"])
    }

    func testRecordRequestLifecycleFailureCapturesSanitizedContext() throws {
        let recorder = RecordingAppSentryRecorder()
        let signal = RequestLifecycleSignal(
            operation: "files.upload",
            requestKind: .multipartUpload,
            stage: .failed,
            errorCategory: .payloadTooLarge,
            metadata: [
                "backend_body": "{\"detail\":\"raw backend detail\"}",
                "retryability": "notRetryable",
                "statusCode": "413",
                "url": "https://api.example.com/private/files"
            ]
        )

        AppSentry.recordRequestLifecycleFailure(
            signal,
            recorder: recorder,
            isEnabled: true
        )

        let record = try XCTUnwrap(recorder.messages.first)
        XCTAssertEqual(record.message, "Request lifecycle failed")
        XCTAssertEqual(record.level, "error")
        XCTAssertEqual(record.context["operation"], "files.upload")
        XCTAssertEqual(record.context["request_kind"], "multipartUpload")
        XCTAssertEqual(record.context["category"], "payloadTooLarge")
        XCTAssertEqual(record.context["retryability"], "notRetryable")
        XCTAssertEqual(record.context["status_code"], "413")
        XCTAssertNil(record.context["backend_body"])
        XCTAssertNil(record.context["url"])
    }

    func testStartIfConfiguredStartsOnlyOnce() {
        let client = RecordingSentryBootstrapClient()
        let bundle = TestSentryBundleInfo()
        let config = makeConfig(sentryDsn: "https://example@sentry.io/123")

        let firstStart = SentryBootstrap.startIfConfigured(
            config: config,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: bundle,
            client: client
        )
        let secondStart = SentryBootstrap.startIfConfigured(
            config: config,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: bundle,
            client: client
        )

        XCTAssertTrue(firstStart)
        XCTAssertFalse(secondStart)
        XCTAssertEqual(client.startCallCount, 1)
    }

    func testFilteredBreadcrumbKeepsAutomaticHTTPBreadcrumbWithoutMessage() {
        let breadcrumb = Breadcrumb()
        breadcrumb.category = "http"
        breadcrumb.data = [
            "method": "GET",
            "url": "https://api.example.com/health"
        ]

        let filtered = SentryBootstrap.filteredBreadcrumb(breadcrumb)

        XCTAssertNotNil(filtered)
        XCTAssertEqual(filtered?.category, "http")
    }

    func testFilteredBreadcrumbDropsBreadcrumbWithoutMessageCategoryOrData() {
        let breadcrumb = Breadcrumb()

        let filtered = SentryBootstrap.filteredBreadcrumb(breadcrumb)

        XCTAssertNil(filtered)
    }

    func testStartIfConfiguredFlushesBufferedStartupBreadcrumbs() {
        let client = RecordingSentryBootstrapClient()
        let recorder = RecordingAppSentryRecorder()

        SentryBootstrap.recordStartupBreadcrumb(
            name: "Config load",
            data: ["duration_ms": "18"],
            recorder: recorder
        )

        XCTAssertTrue(recorder.breadcrumbs.isEmpty)

        let didStart = SentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: TestSentryBundleInfo(),
            client: client,
            recorder: recorder
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(
            recorder.breadcrumbs,
            [
                BreadcrumbRecord(
                    level: "info",
                    category: "startup",
                    message: "Config load",
                    data: ["duration_ms": "18"]
                )
            ]
        )
    }

    private func makeConfig(sentryDsn: String?) -> EnvironmentConfig {
        EnvironmentConfig(
            apiBaseUrl: URL(string: "https://api.example.com/api/v1")!,
            supabaseUrl: URL(string: "https://project.supabase.co")!,
            supabaseAnonKey: "anon-key",
            sentryDsn: sentryDsn
        )
    }
}

private struct BreadcrumbRecord: Equatable {
    let level: String
    let category: String
    let message: String
    let data: [String: String]
}

private struct ErrorCaptureRecord {
    let context: [String: String]
}

private struct MessageCaptureRecord {
    let message: String
    let level: String
    let context: [String: String]
}

private final class RecordingSentryBootstrapClient: SentryBootstrapClient {
    private(set) var startCallCount = 0
    private(set) var lastOptions: SentryBootstrap.Configuration?

    func start(options: SentryBootstrap.Configuration) {
        startCallCount += 1
        lastOptions = options
    }
}

private final class RecordingAppSentryRecorder: AppSentryRecording {
    private(set) var breadcrumbs: [BreadcrumbRecord] = []
    private(set) var errors: [ErrorCaptureRecord] = []
    private(set) var messages: [MessageCaptureRecord] = []

    func addBreadcrumb(level: String, category: String, message: String, data: [String: String]) {
        breadcrumbs.append(
            BreadcrumbRecord(
                level: level,
                category: category,
                message: message,
                data: data
            )
        )
    }

    func capture(error: any Error, context: [String: String]) {
        errors.append(ErrorCaptureRecord(context: context))
    }

    func capture(message: String, level: String, context: [String: String]) {
        messages.append(
            MessageCaptureRecord(
                message: message,
                level: level,
                context: context
            )
        )
    }
}

private struct TestSentryBundleInfo: SentryBundleInfo {
    let bundleIdentifier: String?
    let shortVersion: String
    let buildNumber: String

    init(
        bundleIdentifier: String? = "ai.sidebar.sidebar",
        shortVersion: String = "0.1",
        buildNumber: String = "1"
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
    }

    func string(forInfoDictionaryKey key: String) -> String? {
        switch key {
        case "CFBundleShortVersionString":
            return shortVersion
        case "CFBundleVersion":
            return buildNumber
        default:
            return nil
        }
    }
}
