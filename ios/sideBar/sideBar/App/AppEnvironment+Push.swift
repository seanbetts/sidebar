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
        let loadStatus = {
            await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
                notificationSettings { currentStatus in
                    continuation.resume(returning: currentStatus)
                }
            }
        }

        let status = await loadStatus()
        guard NotificationAuthorizationPolicy.shouldRequestVisibleRemoteNotificationAuthorization(
            for: status
        ) else {
            return false
        }

        let isGranted = await withCheckedContinuation { continuation in
            requestAuthorization { granted in
                continuation.resume(returning: granted)
            }
        }
        let resolvedStatus = isGranted ? status : await loadStatus()
        guard isGranted
                || NotificationAuthorizationPolicy.isVisibleRemoteNotificationAuthorized(
                    resolvedStatus
                ) else {
            return false
        }

        registerForRemoteNotifications()
        return true
    }
#endif

    func updateDeviceToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deviceToken = trimmed
        pushDiagnosticsState = pushDiagnosticsState.updating(
            currentDeviceInstallationId: deviceInstallationId,
            currentDeviceTokenSuffix: Self.deviceTokenSuffix(for: trimmed)
        )
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
        let installationId = deviceInstallationId
        pushDiagnosticsState = pushDiagnosticsState.updating(
            currentDeviceInstallationId: installationId,
            currentDeviceTokenSuffix: Self.deviceTokenSuffix(for: token)
        )
        if lastRegisteredDeviceInstallationId == installationId,
           lastRegisteredDeviceToken == token,
           lastRegisteredUserId == userId {
            return
        }
        if inFlightDeviceInstallationId == installationId,
           inFlightDeviceToken == token,
           inFlightDeviceTokenUserId == userId {
            return
        }
        let environment = pushEnvironment
        let platform = pushPlatform
        pushDiagnosticsState = pushDiagnosticsState.updating(
            lastDeviceRegistrationAttemptAt: Date()
        )
        inFlightDeviceInstallationId = installationId
        inFlightDeviceToken = token
        inFlightDeviceTokenUserId = userId
        Task {
            do {
                try await container.deviceTokensAPI.register(
                    installationId: installationId,
                    token: token,
                    platform: platform,
                    environment: environment
                )
                if self.inFlightDeviceInstallationId == installationId,
                   self.inFlightDeviceToken == token,
                   self.inFlightDeviceTokenUserId == userId {
                    self.lastRegisteredDeviceInstallationId = installationId
                    self.lastRegisteredDeviceToken = token
                    self.lastRegisteredUserId = userId
                    self.pushDiagnosticsState = self.pushDiagnosticsState.updating(
                        lastDeviceRegistrationResult: .success
                    )
                    self.inFlightDeviceInstallationId = nil
                    self.inFlightDeviceToken = nil
                    self.inFlightDeviceTokenUserId = nil
                    self.reportCurrentDevicePresenceIfNeeded()
                }
            } catch {
                if self.inFlightDeviceInstallationId == installationId,
                   self.inFlightDeviceToken == token,
                   self.inFlightDeviceTokenUserId == userId {
                    self.inFlightDeviceInstallationId = nil
                    self.inFlightDeviceToken = nil
                    self.inFlightDeviceTokenUserId = nil
                    self.pushDiagnosticsState = self.pushDiagnosticsState.updating(
                        lastDeviceRegistrationResult: .failure
                    )
                }
                self.pushLogger.error("Device token registration failed.")
                return
            }
        }
    }

    func disableDeviceTokenIfNeeded() async {
        guard let token = deviceToken else { return }
        let installationId = deviceInstallationId
        clearDeviceRegistrationState()
        do {
            try await container.deviceTokensAPI.disable(
                installationId: installationId,
                token: token
            )
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
            let installationId = self.deviceInstallationId
            do {
                try await self.container.deviceTokensAPI.updatePresence(
                    installationId: installationId,
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
        pushDiagnosticsState = pushDiagnosticsState.updating(
            lastDevicePresenceUpdateAt: Date(),
            currentDevicePresenceIsForeground: isForeground
        )
        Task { @MainActor in
            await reporter.report(isForeground: isForeground, token: token)
        }
    }

    func reportCurrentDevicePresenceIfNeeded() {
        let reporter = ensureDevicePresenceReporter()
        let token = deviceToken
        let isForeground = currentPresenceForegroundState
        pushDiagnosticsState = pushDiagnosticsState.updating(
            lastDevicePresenceUpdateAt: Date(),
            currentDevicePresenceIsForeground: isForeground
        )
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

    private var deviceInstallationId: String {
        let defaults = storage.userDefaults
        if let existing = defaults.string(forKey: AppStorageKeys.deviceInstallationId),
           !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: AppStorageKeys.deviceInstallationId)
        return generated
    }

    private func clearDeviceRegistrationState() {
        lastRegisteredDeviceInstallationId = nil
        lastRegisteredDeviceToken = nil
        lastRegisteredUserId = nil
        inFlightDeviceInstallationId = nil
        inFlightDeviceToken = nil
        inFlightDeviceTokenUserId = nil
    }

    private static func deviceTokenSuffix(for token: String, length: Int = 6) -> String {
        String(token.suffix(length))
    }
}
#endif
