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
        purgeGeneratedSwiftUIWindowFrames()
        restoreMainWindowFrameIfNeeded()
        scheduleRemoteNotificationRegistration()
    }

    func applicationShouldRestoreApplicationState(_ application: NSApplication) -> Bool {
        _ = application
        return false
    }

    func applicationShouldSaveApplicationState(_ application: NSApplication) -> Bool {
        _ = application
        return false
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
        let restoredFrame = window.setFrameUsingName(MacWindowConfiguration.mainWindowID)
        if !restoredFrame {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
