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
        let enableAppHangTracking: Bool
        let enableAutoSessionTracking: Bool
        let enableNetworkTracking: Bool
        let tracePropagationTargets: [String]
    }

    private static let stateLock = NSLock()
    private static var hasStarted = false

    static var isStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return hasStarted
    }

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
            sendDefaultPii: false,
            enableAppHangTracking: true,
            enableAutoSessionTracking: true,
            enableNetworkTracking: true,
            tracePropagationTargets: tracePropagationTargets(config: config)
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

    private static func tracePropagationTargets(config: EnvironmentConfig) -> [String] {
        var targets: [String] = []
        for host in [config.apiBaseUrl.host, config.supabaseUrl.host] {
            guard let host, targets.contains(host) == false else { continue }
            targets.append(host)
        }
        return targets
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
            sdkOptions.enableAppHangTracking = options.enableAppHangTracking
            sdkOptions.enableAutoSessionTracking = options.enableAutoSessionTracking
            sdkOptions.enableNetworkTracking = options.enableNetworkTracking
            sdkOptions.tracePropagationTargets = options.tracePropagationTargets
            sdkOptions.beforeBreadcrumb = { breadcrumb in
                guard let message = breadcrumb.message?.trimmingCharacters(in: .whitespacesAndNewlines),
                      message.isEmpty == false else {
                    return nil
                }
                return breadcrumb
            }
        }
    }
}

protocol AppSentryRecording {
    func addBreadcrumb(level: String, category: String, message: String, data: [String: String])
    func capture(error: any Error, context: [String: String])
    func capture(message: String, level: String, context: [String: String])
}

enum AppSentry {
    static func recordNavigation(
        to section: AppSection,
        source: String,
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared,
        isEnabled: Bool = SentryBootstrap.isStarted
    ) {
        guard isEnabled else { return }
        recorder.addBreadcrumb(
            level: "info",
            category: "navigation",
            message: "Opened \(section.title)",
            data: [
                "section": section.rawValue,
                "source": source
            ]
        )
    }

    static func recordAction(
        category: String,
        name: String,
        data: [String: String] = [:],
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared,
        isEnabled: Bool = SentryBootstrap.isStarted
    ) {
        guard isEnabled else { return }
        recorder.addBreadcrumb(
            level: "info",
            category: category,
            message: name,
            data: sanitizedData(data)
        )
    }

    static func capture(
        error: any Error,
        context: [String: String] = [:],
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared,
        isEnabled: Bool = SentryBootstrap.isStarted
    ) {
        guard isEnabled else { return }
        recorder.capture(error: error, context: sanitizedData(context))
    }

    static func capture(
        message: String,
        level: String = "error",
        context: [String: String] = [:],
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared,
        isEnabled: Bool = SentryBootstrap.isStarted
    ) {
        guard isEnabled else { return }
        recorder.capture(message: message, level: level, context: sanitizedData(context))
    }

    private static func sanitizedData(_ data: [String: String]) -> [String: String] {
        let blockedKeys = Set(["url", "path", "note_id", "chat_id", "file_id"])
        return data.reduce(into: [:]) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false, value.isEmpty == false, blockedKeys.contains(key) == false else {
                return
            }
            result[key] = value
        }
    }
}

private final class DefaultAppSentryRecorder: AppSentryRecording {
    static let shared = DefaultAppSentryRecorder()

    func addBreadcrumb(level: String, category: String, message: String, data: [String: String]) {
        let breadcrumb = Breadcrumb(level: sentryLevel(named: level), category: category)
        breadcrumb.timestamp = Date()
        breadcrumb.message = message
        breadcrumb.data = data
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    func capture(error: any Error, context: [String: String]) {
        if context.isEmpty {
            SentrySDK.capture(error: error)
            return
        }
        SentrySDK.capture(error: error) { _ in
        }
    }

    func capture(message: String, level: String, context: [String: String]) {
        if context.isEmpty {
            SentrySDK.capture(message: message)
            return
        }
        SentrySDK.capture(message: message) { _ in
        }
    }

    private func sentryLevel(named level: String) -> SentryLevel {
        switch level {
        case "debug":
            return .debug
        case "warning":
            return .warning
        case "error":
            return .error
        default:
            return .info
        }
    }
}
