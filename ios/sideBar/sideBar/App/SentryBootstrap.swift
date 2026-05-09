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

    private struct PendingStartupBreadcrumb {
        let name: String
        let data: [String: String]
    }

    private static let stateLock = NSLock()
    private static var hasStarted = false
    private static var pendingStartupBreadcrumbs: [PendingStartupBreadcrumb] = []

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
        client: SentryBootstrapClient = DefaultSentryBootstrapClient.shared,
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared
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
        guard hasStarted == false else {
            stateLock.unlock()
            return false
        }

        client.start(options: options)
        hasStarted = true
        let pending = pendingStartupBreadcrumbs
        pendingStartupBreadcrumbs.removeAll()
        stateLock.unlock()
        flushStartupBreadcrumbs(pending, recorder: recorder)
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
        pendingStartupBreadcrumbs.removeAll()
        stateLock.unlock()
    }

    static func filteredBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        let message = breadcrumb.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = breadcrumb.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeaningfulCategory = !category.isEmpty && category != "default"
        let hasData = !(breadcrumb.data?.isEmpty ?? true)

        guard (message?.isEmpty == false) || hasMeaningfulCategory || hasData else {
            return nil
        }

        breadcrumb.message = message?.isEmpty == false ? message : nil
        breadcrumb.category = category
        return breadcrumb
    }

    static func recordStartupBreadcrumb(
        name: String,
        data: [String: String] = [:],
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared
    ) {
        stateLock.lock()
        if hasStarted == false {
            pendingStartupBreadcrumbs.append(
                PendingStartupBreadcrumb(
                    name: name,
                    data: data
                )
            )
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        AppSentry.recordAction(
            category: "startup",
            name: name,
            data: data,
            recorder: recorder,
            isEnabled: true
        )
    }

    private static func tracePropagationTargets(config: EnvironmentConfig) -> [String] {
        var targets: [String] = []
        for host in [config.apiBaseUrl.host, config.supabaseUrl.host] {
            guard let host, targets.contains(host) == false else { continue }
            targets.append(host)
        }
        return targets
    }

    private static func flushStartupBreadcrumbs(
        _ breadcrumbs: [PendingStartupBreadcrumb],
        recorder: AppSentryRecording
    ) {
        guard !breadcrumbs.isEmpty else { return }
        for breadcrumb in breadcrumbs {
            AppSentry.recordAction(
                category: "startup",
                name: breadcrumb.name,
                data: breadcrumb.data,
                recorder: recorder,
                isEnabled: true
            )
        }
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
                SentryBootstrap.filteredBreadcrumb(breadcrumb)
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

    static func recordRequestLifecycleFailure(
        _ signal: RequestLifecycleSignal,
        recorder: AppSentryRecording = DefaultAppSentryRecorder.shared,
        isEnabled: Bool = SentryBootstrap.isStarted
    ) {
        guard signal.stage == .failed else { return }
        var context = signal.metadata
        context["operation"] = signal.operation
        context["requestKind"] = signal.requestKind.rawValue
        if let errorCategory = signal.errorCategory {
            context["category"] = errorCategory.rawValue
        }
        capture(
            message: "Request lifecycle failed",
            level: "error",
            context: context,
            recorder: recorder,
            isEnabled: isEnabled
        )
    }

    private static func sanitizedData(_ data: [String: String]) -> [String: String] {
        DiagnosticsMetadataSanitizer.sanitize(data)
    }
}

private final class DefaultAppSentryRecorder: AppSentryRecording {
    static let shared = DefaultAppSentryRecorder()
    private let requestLifecycleContextKey = "request_lifecycle"

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
        SentrySDK.capture(error: error) { scope in
            scope.setContext(value: context, key: self.requestLifecycleContextKey)
        }
    }

    func capture(message: String, level: String, context: [String: String]) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(self.sentryLevel(named: level))
            guard context.isEmpty == false else { return }
            scope.setContext(value: context, key: self.requestLifecycleContextKey)
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
