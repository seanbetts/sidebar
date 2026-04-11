import Foundation
import os
#if os(iOS)
import Security
import UIKit
import UserNotifications
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

#if os(iOS)
    func enableNotificationsIfNeeded(
        notificationSettings: @escaping (@escaping (UNAuthorizationStatus) -> Void) -> Void = { completion in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                completion(settings.authorizationStatus)
            }
        },
        requestAuthorization: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
            UNUserNotificationCenter.current().requestAuthorization(
                options: NotificationAuthorizationPolicy.visibleRemoteNotificationRequestOptions
            ) { granted, _ in
                completion(granted)
            }
        },
        registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void = {
#if targetEnvironment(simulator)
            Logger(subsystem: "sideBar", category: "Push").debug(
                "Skipping remote notification registration on iOS simulator."
            )
#else
            UIApplication.shared.registerForRemoteNotifications()
#endif
        }
    ) async -> Bool {
        let status = await withCheckedContinuation { continuation in
            notificationSettings { currentStatus in
                continuation.resume(returning: currentStatus)
            }
        }

        switch status {
        case .authorized, .provisional, .ephemeral:
            registerForRemoteNotifications()
            return true
        case .notDetermined:
            let isGranted = await withCheckedContinuation { continuation in
                requestAuthorization { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard isGranted else { return false }
            registerForRemoteNotifications()
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
#endif

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
        if inFlightDeviceToken == token, inFlightDeviceTokenUserId == userId {
            return
        }
        let environment = pushEnvironment
        let platform = pushPlatform
        inFlightDeviceToken = token
        inFlightDeviceTokenUserId = userId
        Task {
            do {
                try await container.deviceTokensAPI.register(
                    token: token,
                    platform: platform,
                    environment: environment
                )
                if self.inFlightDeviceToken == token, self.inFlightDeviceTokenUserId == userId {
                    self.lastRegisteredDeviceToken = token
                    self.lastRegisteredUserId = userId
                    self.inFlightDeviceToken = nil
                    self.inFlightDeviceTokenUserId = nil
                    self.reportCurrentDevicePresenceIfNeeded()
                }
            } catch {
                if self.inFlightDeviceToken == token, self.inFlightDeviceTokenUserId == userId {
                    self.inFlightDeviceToken = nil
                    self.inFlightDeviceTokenUserId = nil
                }
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

    func ensureDevicePresenceReporter() -> DevicePresenceReporter {
        if let devicePresenceReporter {
            return devicePresenceReporter
        }

        let reporter = DevicePresenceReporter { [weak self] token, isForeground, lastSeenAt in
            guard let self else { return }
            guard self.authState == .active else { return }
            do {
                try await self.container.deviceTokensAPI.updatePresence(
                    token: token,
                    isForeground: isForeground,
                    lastSeenAt: lastSeenAt
                )
            } catch {
                self.pushLogger.error("Device presence update failed.")
            }
        }
        devicePresenceReporter = reporter
        return reporter
    }

    func reportDevicePresence(isForeground: Bool) {
        let reporter = ensureDevicePresenceReporter()
        let token = deviceToken
        Task { @MainActor in
            await reporter.report(isForeground: isForeground, token: token)
        }
    }

    func reportCurrentDevicePresenceIfNeeded() {
        let reporter = ensureDevicePresenceReporter()
        let token = deviceToken
        let isForeground = currentPresenceForegroundState
        Task { @MainActor in
            await reporter.report(isForeground: isForeground, token: token)
        }
    }

    private var currentPresenceForegroundState: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #elseif os(macOS)
        NSApplication.shared.isActive
        #else
        false
        #endif
    }

    // Entitlement logging removed after verification.
}
#endif
