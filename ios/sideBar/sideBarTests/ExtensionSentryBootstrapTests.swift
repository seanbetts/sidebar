import XCTest
import sideBarShared

final class ExtensionSentryBootstrapTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExtensionSentryBootstrap.resetForTesting()
    }

    func testStartIfConfiguredDoesNotStartWithoutDsn() {
        let client = RecordingExtensionSentryBootstrapClient()

        let didStart = ExtensionSentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: nil),
            client: client,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: TestExtensionSentryBundleInfo()
        )

        XCTAssertFalse(didStart)
        XCTAssertEqual(client.startCallCount, 0)
    }

    func testStartIfConfiguredDoesNotStartWhileRunningTests() {
        let client = RecordingExtensionSentryBootstrapClient()

        let didStart = ExtensionSentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            client: client,
            isDebugBuild: false,
            isRunningTestsOrPreviews: true,
            bundle: TestExtensionSentryBundleInfo()
        )

        XCTAssertFalse(didStart)
        XCTAssertEqual(client.startCallCount, 0)
    }

    func testStartIfConfiguredStartsInDebugBuildsWhenDsnIsPresent() {
        let client = RecordingExtensionSentryBootstrapClient()

        let didStart = ExtensionSentryBootstrap.startIfConfigured(
            config: makeConfig(sentryDsn: "https://example@sentry.io/123"),
            client: client,
            isDebugBuild: true,
            isRunningTestsOrPreviews: false,
            bundle: TestExtensionSentryBundleInfo()
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(client.startCallCount, 1)
        XCTAssertEqual(
            client.lastOptions,
            ExtensionSentryBootstrap.Configuration(
                dsn: "https://example@sentry.io/123",
                environment: "debug",
                releaseName: "ai.sidebar.sidebar.widget@0.1+1",
                tracesSampleRate: 0.1,
                sendDefaultPii: false,
                enableAppHangTracking: true,
                enableAutoSessionTracking: true,
                enableNetworkTracking: true,
                tracePropagationTargets: ["api.example.com", "project.supabase.co"]
            )
        )
    }

    func testStartIfConfiguredStartsOnlyOnce() {
        let client = RecordingExtensionSentryBootstrapClient()
        let config = makeConfig(sentryDsn: "https://example@sentry.io/123")
        let bundle = TestExtensionSentryBundleInfo()

        let firstStart = ExtensionSentryBootstrap.startIfConfigured(
            config: config,
            client: client,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: bundle
        )
        let secondStart = ExtensionSentryBootstrap.startIfConfigured(
            config: config,
            client: client,
            isDebugBuild: false,
            isRunningTestsOrPreviews: false,
            bundle: bundle
        )

        XCTAssertTrue(firstStart)
        XCTAssertFalse(secondStart)
        XCTAssertEqual(client.startCallCount, 1)
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

private final class RecordingExtensionSentryBootstrapClient: ExtensionSentryBootstrapClient {
    private(set) var startCallCount = 0
    private(set) var lastOptions: ExtensionSentryBootstrap.Configuration?

    func start(options: ExtensionSentryBootstrap.Configuration) {
        startCallCount += 1
        lastOptions = options
    }
}

private struct TestExtensionSentryBundleInfo: ExtensionSentryBundleInfo {
    let bundleIdentifier: String?
    let shortVersion: String
    let buildNumber: String

    init(
        bundleIdentifier: String? = "ai.sidebar.sidebar.widget",
        shortVersion: String = "0.1",
        buildNumber: String = "1"
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
    }

    func infoString(forInfoDictionaryKey key: String) -> String? {
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
