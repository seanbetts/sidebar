import Foundation
import Sentry
import sideBarShared

enum ShareExtensionDiagnostics {
    static let reporter = ExtensionDiagnosticsReporter(
        logger: SystemExtensionDiagnosticsLogger(category: "ShareExtension"),
        store: ExternalSurfaceDiagnosticsStore.shared,
        failureRecorder: ShareExtensionFailureRecorder()
    )

    static func ensureSentryStarted() {
        guard let config = try? EnvironmentConfig.load() else { return }
        _ = ExtensionSentryBootstrap.startIfConfigured(
            config: config,
            client: ShareExtSentryClient.shared
        )
    }
}

private final class ShareExtSentryClient: ExtensionSentryBootstrapClient {
    static let shared = ShareExtSentryClient()

    func start(options: ExtensionSentryBootstrap.Configuration) {
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

private final class ShareExtensionFailureRecorder: ExtensionFailureRecording {
    func capture(message: String, context: [String: String]) {
        guard ExtensionSentryBootstrap.isStarted else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setContext(value: context, key: "extension_diagnostics")
        }
    }
}
