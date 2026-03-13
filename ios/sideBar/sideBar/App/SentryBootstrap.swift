import Foundation
import Sentry
import sideBarShared

protocol SentryBundleInfo {
    var bundleIdentifier: String? { get }
    func string(forInfoDictionaryKey key: String) -> String?
}

protocol SentryBootstrapClient {
    func start(options: SentryBootstrap.Configuration)
    func crashForTesting()
}

extension Bundle: SentryBundleInfo {
    func string(forInfoDictionaryKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

enum SentryBootstrap {
    struct Configuration: Equatable {
        let dsn: String
        let environment: String
        let releaseName: String
        let tracesSampleRate: Double
        let sendDefaultPii: Bool
    }

    private static let stateLock = NSLock()
    private static var hasStarted = false

    @discardableResult
    static func startIfConfigured(
        config: EnvironmentConfig,
        isDebugBuild: Bool = defaultIsDebugBuild,
        isRunningTestsOrPreviews: Bool = EnvironmentConfig.isRunningTestsOrPreviews(),
        bundle: SentryBundleInfo = Bundle.main,
        client: SentryBootstrapClient = DefaultSentryBootstrapClient.shared
    ) -> Bool {
        guard let options = makeOptions(
            config: config,
            isDebugBuild: isDebugBuild,
            isRunningTestsOrPreviews: isRunningTestsOrPreviews,
            bundle: bundle
        ) else {
            return false
        }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard hasStarted == false else {
            return false
        }

        client.start(options: options)
        hasStarted = true
        return true
    }

    static func makeOptions(
        config: EnvironmentConfig,
        isDebugBuild: Bool,
        isRunningTestsOrPreviews: Bool,
        bundle: SentryBundleInfo
    ) -> Configuration? {
        guard let dsn = config.sentryDsn, dsn.isEmpty == false else {
            return nil
        }
        guard isRunningTestsOrPreviews == false else {
            return nil
        }

        return Configuration(
            dsn: dsn,
            environment: isDebugBuild ? "debug" : "production",
            releaseName: releaseName(bundle: bundle),
            tracesSampleRate: 0.1,
            sendDefaultPii: false
        )
    }

    private static func releaseName(bundle: SentryBundleInfo) -> String {
        let bundleIdentifier = bundle.bundleIdentifier ?? "sideBar"
        let shortVersion = bundle.string(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0"
        let buildNumber = bundle.string(forInfoDictionaryKey: "CFBundleVersion") ?? "0"
        return "\(bundleIdentifier)@\(shortVersion)+\(buildNumber)"
    }

    private static var defaultIsDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func resetForTesting() {
        stateLock.lock()
        hasStarted = false
        stateLock.unlock()
    }

    @discardableResult
    static func triggerTestCrash(
        isRunningTestsOrPreviews: Bool = EnvironmentConfig.isRunningTestsOrPreviews(),
        client: SentryBootstrapClient = DefaultSentryBootstrapClient.shared
    ) -> Bool {
        guard isRunningTestsOrPreviews == false else {
            return false
        }

        client.crashForTesting()
        return true
    }
}

private final class DefaultSentryBootstrapClient: SentryBootstrapClient {
    static let shared = DefaultSentryBootstrapClient()

    func start(options: SentryBootstrap.Configuration) {
        SentrySDK.start { sdkOptions in
            sdkOptions.dsn = options.dsn
            sdkOptions.environment = options.environment
            sdkOptions.releaseName = options.releaseName
            sdkOptions.tracesSampleRate = NSNumber(value: options.tracesSampleRate)
            sdkOptions.sendDefaultPii = options.sendDefaultPii
        }
    }

    func crashForTesting() {
        SentrySDK.crash()
    }
}
