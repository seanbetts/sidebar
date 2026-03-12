import Foundation
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

    @discardableResult
    static func startIfConfigured(
        config: EnvironmentConfig,
        isDebugBuild: Bool = defaultIsDebugBuild,
        isRunningTestsOrPreviews: Bool = EnvironmentConfig.isRunningTestsOrPreviews(),
        bundle: SentryBundleInfo = Bundle.main,
        client: SentryBootstrapClient = DefaultSentryBootstrapClient.shared
    ) -> Bool {
        _ = config
        _ = isDebugBuild
        _ = isRunningTestsOrPreviews
        _ = bundle
        _ = client
        return false
    }

    private static var defaultIsDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func resetForTesting() {
        // Intentionally empty: the release bootstrap is currently inert.
    }
}

private final class DefaultSentryBootstrapClient: SentryBootstrapClient {
    static let shared = DefaultSentryBootstrapClient()

    func start(options: SentryBootstrap.Configuration) {
        _ = options
    }
}
