import Foundation
import os
#if os(iOS)
import Security
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(iOS) || os(macOS)
extension AppEnvironment {
    private var pushLogger: Logger {
        Logger(subsystem: "sideBar", category: "Push")
    }

    func registerForRemoteNotificationsIfNeeded() {
#if os(iOS)
#if targetEnvironment(simulator)
        pushLogger.debug(
            "Skipping remote notification registration on iOS simulator."
        )
#else
        UIApplication.shared.registerForRemoteNotifications()
#endif
#elseif os(macOS)
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
        guard authState == .active else { return }
        Task { @MainActor in
            await tasksViewModel.loadCounts(force: true)
            let selection = tasksStore.selection
            if selection != .none {
                await tasksViewModel.load(selection: selection, force: true)
            }
            // Refresh all widget data on push, regardless of current view
            async let tasks: () = tasksViewModel.refreshWidgetData()
            async let notes: () = notesViewModel.refreshWidgetData()
            async let websites: () = websitesViewModel.refreshWidgetData()
            async let files: () = ingestionViewModel.refreshWidgetData()
            _ = await (tasks, notes, websites, files)
        }
    }

    func registerDeviceTokenIfNeeded() {
        guard authState == .active else { return }
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

    // Entitlement logging removed after verification.
}
#endif
