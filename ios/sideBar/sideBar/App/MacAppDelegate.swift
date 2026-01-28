#if os(macOS)
import AppKit
import os

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "sideBar", category: "Push")

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
#endif
