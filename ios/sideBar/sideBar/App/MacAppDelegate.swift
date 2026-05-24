#if os(macOS)
import AppKit
import os
import sideBarShared
import UserNotifications

extension Notification.Name {
    static let macAppTerminationRequested = Notification.Name("sideBar.macAppTerminationRequested")
}

final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "sideBar", category: "Push")
    private let deepLinkLogger = Logger(subsystem: "sideBar", category: "DeepLink")
    private static var queuedDeepLinks: [URL] = []
    private static var shouldBootstrapWebsiteQueueWhenEnvironmentReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSWindow.allowsAutomaticWindowTabbing = false
        if let config = try? EnvironmentConfig.load() {
            SentryBootstrap.startIfConfigured(config: config)
        }
        purgeGeneratedSwiftUIWindowFrames()
        restoreMainWindowFrameIfNeeded()
        scheduleRemoteNotificationRegistration()
        Self.requestWebsiteQueueBootstrapIfPossible()
    }

    func applicationShouldRestoreApplicationState(_ application: NSApplication) -> Bool {
        _ = application
        return false
    }

    func applicationShouldSaveApplicationState(_ application: NSApplication) -> Bool {
        _ = application
        return false
    }

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        _ = application
        NotificationCenter.default.post(name: .macAppTerminationRequested, object: nil)
        return .terminateNow
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
            let redactedURL = LogRedaction.redactedURLString(url)
            deepLinkLogger.info("Handling deep link: \(redactedURL, privacy: .public)")
            handleOrQueueDeepLink(url)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = center
        AppEnvironment.shared?.handleRemoteNotification(notification.request.content.userInfo)
        completionHandler([.badge, .banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = center
        let userInfo = response.notification.request.content.userInfo
        AppEnvironment.shared?.handleRemoteNotification(userInfo)
        if let route = NotificationRoute(userInfo: userInfo) {
            handleOrQueueDeepLink(route.url)
        }
        completionHandler()
    }

    static func flushQueuedDeepLinks(using environment: AppEnvironment) {
        guard !queuedDeepLinks.isEmpty else { return }
        let queued = queuedDeepLinks
        queuedDeepLinks.removeAll()
        for url in queued {
            environment.handleDeepLink(url)
        }
    }

    static func requestWebsiteQueueBootstrapIfPossible() {
        if let environment = AppEnvironment.shared {
            environment.bootstrapMacWindowlessWebsiteQueueHost()
            return
        }
        shouldBootstrapWebsiteQueueWhenEnvironmentReady = true
    }

    static func flushQueuedWebsiteQueueBootstrap(using environment: AppEnvironment) {
        guard shouldBootstrapWebsiteQueueWhenEnvironmentReady else { return }
        shouldBootstrapWebsiteQueueWhenEnvironmentReady = false
        environment.bootstrapMacWindowlessWebsiteQueueHost()
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

    private func scheduleRemoteNotificationRegistration() {
        Task { @MainActor in
            await Task.yield()
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    private func purgeGeneratedSwiftUIWindowFrames() {
        MacWindowFramePersistence.purgeGeneratedSwiftUIWindowFrames()
    }

    private func restoreMainWindowFrameIfNeeded() {
        Task { @MainActor in
            for _ in 0..<40 {
                if let window = mainApplicationWindow() {
                    restoreMainWindowFrameIfNeeded(for: window)
                    return
                }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }
            var didRequestOpenMainWindow = false
            for _ in 0..<40 {
                if let window = mainApplicationWindow() {
                    restoreMainWindowFrameIfNeeded(for: window)
                    return
                }
                if !didRequestOpenMainWindow, MacMainWindowSceneBridge.openMainWindowIfAvailable() {
                    didRequestOpenMainWindow = true
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @MainActor
    private func mainApplicationWindow() -> NSWindow? {
        if let mainWindow = NSApplication.shared.mainWindow, mainWindow.sheetParent == nil {
            return mainWindow
        }

        return NSApplication.shared.windows.first { window in
            window.sheetParent == nil && !(window is NSPanel)
        }
    }

    @MainActor
    private func restoreMainWindowFrameIfNeeded(for window: NSWindow) {
        window.setFrameAutosaveName(MacWindowConfiguration.mainWindowID)
        let shouldRestoreFrame = MacWindowFramePersistence.shouldRestoreSavedWindowFrame(
            isVisible: window.isVisible,
            isKeyWindow: window.isKeyWindow,
            isMainWindow: window.isMainWindow
        )
        let restoredFrame = shouldRestoreFrame && MacWindowFramePersistence.restoreSavedWindowFrameIfNeeded(
            window,
            autosaveName: MacWindowConfiguration.mainWindowID
        )
        if shouldRestoreFrame && !restoredFrame {
            window.center()
        }
        let recentered = restoredFrame && MacWindowFramePersistence.recenterWindowIfNeeded(
            window,
            preferredScreen: NSScreen.main,
            enforcePreferredScreen: true
        )
        if recentered {
            MacWindowFramePersistence.persistWindowFrameIfNeeded(window)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
