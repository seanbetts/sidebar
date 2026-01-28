import Foundation
import os
#if os(iOS)
import Security
import UIKit
#elseif os(macOS)
import AppKit
import Security
#endif

#if os(iOS) || os(macOS)
extension AppEnvironment {
    private var pushLogger: Logger {
        Logger(subsystem: "sideBar", category: "Push")
    }

    func registerForRemoteNotificationsIfNeeded() {
#if os(iOS)
        logPushEntitlementsIfNeeded()
        UIApplication.shared.registerForRemoteNotifications()
#elseif os(macOS)
        logPushEntitlementsIfNeeded()
        NSApplication.shared.registerForRemoteNotifications()
#endif
    }

    func updateDeviceToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deviceToken = trimmed
        registerDeviceTokenIfNeeded()
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard isAuthenticated else { return }
        Task { @MainActor in
            await tasksViewModel.loadCounts(force: true)
            let selection = tasksStore.selection
            if selection != .none {
                await tasksViewModel.load(selection: selection, force: true)
            }
        }
    }

    func registerDeviceTokenIfNeeded() {
        guard isAuthenticated else { return }
        guard let token = deviceToken else { return }
        guard let userId = container.authSession.userId else { return }
        if lastRegisteredDeviceToken == token, lastRegisteredUserId == userId {
            return
        }
        let environment = pushEnvironment
        let platform = pushPlatform
        Task {
            do {
                try await container.deviceTokensAPI.register(
                    token: token,
                    platform: platform,
                    environment: environment
                )
                await MainActor.run {
                    self.lastRegisteredDeviceToken = token
                    self.lastRegisteredUserId = userId
                }
            } catch {
                self.pushLogger.error("Device token registration failed.")
                return
            }
        }
    }

    func disableDeviceTokenIfNeeded() async {
        guard let token = deviceToken else { return }
        do {
            try await container.deviceTokensAPI.disable(token: token)
        } catch {
            return
        }
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "dev"
        #else
        return "prod"
        #endif
    }

    private var pushPlatform: String {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    private func logPushEntitlementsIfNeeded() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "aps-environment" as CFString, nil) else {
            pushLogger.error("Missing aps-environment entitlement.")
            return
        }
        if let environment = value as? String {
            pushLogger.info("aps-environment entitlement: \(environment, privacy: .public)")
        } else {
            pushLogger.info("aps-environment entitlement present.")
        }
    }
}
#endif
