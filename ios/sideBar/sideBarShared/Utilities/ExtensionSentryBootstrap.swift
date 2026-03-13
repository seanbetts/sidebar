import Foundation

public protocol ExtensionSentryBundleInfo {
    var bundleIdentifier: String? { get }
    func infoString(forInfoDictionaryKey key: String) -> String?
}

public protocol ExtensionSentryBootstrapClient {
    func start(options: ExtensionSentryBootstrap.Configuration)
}

extension Bundle: ExtensionSentryBundleInfo {
    public func infoString(forInfoDictionaryKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

public enum ExtensionSentryBootstrap {
    public struct Configuration: Equatable {
        public let dsn: String
        public let environment: String
        public let releaseName: String
        public let tracesSampleRate: Double
        public let sendDefaultPii: Bool
        public let enableAppHangTracking: Bool
        public let enableAutoSessionTracking: Bool
        public let enableNetworkTracking: Bool
        public let tracePropagationTargets: [String]

        public init(
            dsn: String,
            environment: String,
            releaseName: String,
            tracesSampleRate: Double,
            sendDefaultPii: Bool,
            enableAppHangTracking: Bool,
            enableAutoSessionTracking: Bool,
            enableNetworkTracking: Bool,
            tracePropagationTargets: [String]
        ) {
            self.dsn = dsn
            self.environment = environment
            self.releaseName = releaseName
            self.tracesSampleRate = tracesSampleRate
            self.sendDefaultPii = sendDefaultPii
            self.enableAppHangTracking = enableAppHangTracking
            self.enableAutoSessionTracking = enableAutoSessionTracking
            self.enableNetworkTracking = enableNetworkTracking
            self.tracePropagationTargets = tracePropagationTargets
        }
    }

    private static let stateLock = NSLock()
    private static var hasStarted = false

    public static var isStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return hasStarted
    }

    @discardableResult
    public static func startIfConfigured(
        config: EnvironmentConfig,
        client: any ExtensionSentryBootstrapClient,
        isDebugBuild: Bool = defaultIsDebugBuild,
        isRunningTestsOrPreviews: Bool = EnvironmentConfig.isRunningTestsOrPreviews(),
        bundle: any ExtensionSentryBundleInfo = Bundle.main
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

    public static func makeOptions(
        config: EnvironmentConfig,
        isDebugBuild: Bool,
        isRunningTestsOrPreviews: Bool,
        bundle: any ExtensionSentryBundleInfo
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
            sendDefaultPii: false,
            enableAppHangTracking: true,
            enableAutoSessionTracking: true,
            enableNetworkTracking: true,
            tracePropagationTargets: tracePropagationTargets(config: config)
        )
    }

    public static func resetForTesting() {
        stateLock.lock()
        hasStarted = false
        stateLock.unlock()
    }

    private static func releaseName(bundle: any ExtensionSentryBundleInfo) -> String {
        let bundleIdentifier = bundle.bundleIdentifier ?? "sideBar"
        let shortVersion = bundle.infoString(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0"
        let buildNumber = bundle.infoString(forInfoDictionaryKey: "CFBundleVersion") ?? "0"
        return "\(bundleIdentifier)@\(shortVersion)+\(buildNumber)"
    }

    public static var defaultIsDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static func tracePropagationTargets(config: EnvironmentConfig) -> [String] {
        var targets: [String] = []
        for host in [config.apiBaseUrl.host, config.supabaseUrl.host] {
            guard let host, targets.contains(host) == false else { continue }
            targets.append(host)
        }
        return targets
    }
}
