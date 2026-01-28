import Foundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)
extension AppEnvironment {
    func registerForRemoteNotificationsIfNeeded() {
        UIApplication.shared.registerForRemoteNotifications()
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
        Task {
            do {
                try await container.deviceTokensAPI.register(
                    token: token,
                    platform: "ios",
                    environment: environment
                )
                await MainActor.run {
                    self.lastRegisteredDeviceToken = token
                    self.lastRegisteredUserId = userId
                }
            } catch {
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
}
#endif
