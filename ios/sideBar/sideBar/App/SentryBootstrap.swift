import Foundation
import Sentry
import sideBarShared

protocol SentryBundleInfo {
    var bundleIdentifier: String? { get }
    func string(forInfoDictionaryKey key: String) -> String?
}

protocol SentryBootstrapClient {
    func start(options: SentryBootstrap.Configuration)
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
        guard isDebugBuild == false else {
            return nil
        }
        guard isRunningTestsOrPreviews == false else {
            return nil
        }

        return Configuration(
            dsn: dsn,
            environment: "production",
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
}

private final class DefaultSentryBootstrapClient: SentryBootstrapClient {
    static let shared = DefaultSentryBootstrapClient()
    private static let startSelector = NSSelectorFromString("startWithOptions:")

    func start(options: SentryBootstrap.Configuration) {
        guard let sdkOptions = Self.makeSdkOptions(from: options) else {
            assertionFailure("Failed to create SentryOptions")
            return
        }
        guard SentrySDK.responds(to: Self.startSelector) else {
            assertionFailure("SentrySDK.startWithOptions: is unavailable")
            return
        }
        _ = SentrySDK.perform(Self.startSelector, with: sdkOptions)
    }

    private static func makeSdkOptions(from options: SentryBootstrap.Configuration) -> NSObject? {
        guard let sdkOptionsType = NSClassFromString("SentryOptions") as? NSObject.Type else {
            return nil
        }
        let sdkOptions = sdkOptionsType.init()
        sdkOptions.setValue(options.dsn, forKey: "dsn")
        sdkOptions.setValue(options.environment, forKey: "environment")
        sdkOptions.setValue(options.releaseName, forKey: "releaseName")
        sdkOptions.setValue(NSNumber(value: options.tracesSampleRate), forKey: "tracesSampleRate")
        sdkOptions.setValue(options.sendDefaultPii, forKey: "sendDefaultPii")
        return sdkOptions
    }
}
