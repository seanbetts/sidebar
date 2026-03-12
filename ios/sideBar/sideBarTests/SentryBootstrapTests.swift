import XCTest
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
                sendDefaultPii: false
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
                sendDefaultPii: false
            )
        )
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

    private func makeConfig(sentryDsn: String?) -> EnvironmentConfig {
        EnvironmentConfig(
            apiBaseUrl: URL(string: "https://api.example.com/api/v1")!,
            supabaseUrl: URL(string: "https://project.supabase.co")!,
            supabaseAnonKey: "anon-key",
            sentryDsn: sentryDsn
        )
    }
}

private final class RecordingSentryBootstrapClient: SentryBootstrapClient {
    private(set) var startCallCount = 0
    private(set) var lastOptions: SentryBootstrap.Configuration?

    func start(options: SentryBootstrap.Configuration) {
        startCallCount += 1
        lastOptions = options
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
