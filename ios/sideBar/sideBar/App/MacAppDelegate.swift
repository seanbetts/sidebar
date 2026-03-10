#if os(macOS)
import AppKit
import os
import sideBarShared

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "sideBar", category: "Push")
    private let deepLinkLogger = Logger(subsystem: "sideBar", category: "DeepLink")
    private static var queuedDeepLinks: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if let config = try? EnvironmentConfig.load() {
            SentryBootstrap.startIfConfigured(config: config)
        }
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard !tokenString.isEmpty else { return }
        AppEnvironment.shared?.updateDeviceToken(tokenString)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Remote notifications registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        AppEnvironment.shared?.handleRemoteNotification(userInfo)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = application
        for url in urls where url.scheme == "sidebar" {
            deepLinkLogger.info("MacAppDelegate handling deep link: \(url.absoluteString, privacy: .public)")
            handleOrQueueDeepLink(url)
        }
    }

    static func flushQueuedDeepLinks(using environment: AppEnvironment) {
        guard !queuedDeepLinks.isEmpty else { return }
        let queued = queuedDeepLinks
        queuedDeepLinks.removeAll()
        for url in queued {
            environment.handleDeepLink(url)
        }
    }

    private func handleOrQueueDeepLink(_ url: URL) {
        guard let environment = AppEnvironment.shared else {
            Self.queuedDeepLinks.append(url)
            deepLinkLogger.info("MacAppDelegate queued deep link until environment is ready")
            return
        }
        Self.flushQueuedDeepLinks(using: environment)
        environment.handleDeepLink(url)
    }
}
#endif
