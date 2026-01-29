import Combine
import Foundation
#if os(iOS)
import UIKit
import UserNotifications
#endif

extension AppEnvironment {
    func configureSubscriptions() {
        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            bindAuthAdapter(authAdapter)
        }
        forwardObjectWillChange()
        monitorNetwork()
        setupTaskBadgeUpdates()
        ingestionViewModel.resumePendingUploads()

        // Migrate widget data to new generic keys (one-time)
        WidgetDataManager.shared.migrateIfNeeded()

        // Sync initial auth state to widgets
        WidgetDataManager.shared.updateAuthState(isAuthenticated: isAuthenticated)
    }

    func configureRealtimeClient() {
        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
    }

    private func bindAuthAdapter(_ authAdapter: SupabaseAuthAdapter) {
        authAdapter.$accessToken
            .sink { [weak self] _ in
                self?.refreshAuthState()
            }
            .store(in: &cancellables)

        authAdapter.$authError
            .compactMap { $0 }
            .sink { [weak self, weak authAdapter] event in
                self?.toastCenter.show(message: event.message)
                authAdapter?.clearAuthError()
            }
            .store(in: &cancellables)

        authAdapter.$sessionExpiryWarning
            .sink { [weak self] warning in
                DispatchQueue.main.async {
                    self?.sessionExpiryWarning = warning
                }
            }
            .store(in: &cancellables)
    }

    private func forwardObjectWillChange() {
        settingsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        chatViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesEditorViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        websitesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ingestionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        weatherViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        writeQueue.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func monitorNetwork() {
        connectivityMonitor.$isOffline
            .removeDuplicates()
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
                if isOffline == false {
                    self?.refreshOnReconnect()
                }
            }
            .store(in: &cancellables)

        connectivityMonitor.$isNetworkAvailable
            .removeDuplicates()
            .sink { [weak self] isAvailable in
                self?.isNetworkAvailable = isAvailable
            }
            .store(in: &cancellables)
    }

    private func setupTaskBadgeUpdates() {
#if os(iOS)
        requestBadgeAuthorizationIfNeeded()
        registerForRemoteNotificationsIfNeeded()
        Publishers.CombineLatest($isAuthenticated, tasksViewModel.$counts)
            .receive(on: DispatchQueue.main)
            .sink { isAuthenticated, counts in
                let badgeCount = isAuthenticated ? (counts?.counts.today ?? 0) : 0
                UNUserNotificationCenter.current().setBadgeCount(badgeCount, withCompletionHandler: nil)
            }
            .store(in: &cancellables)
#elseif os(macOS)
        registerForRemoteNotificationsIfNeeded()
#endif
    }

#if os(iOS)
    private func requestBadgeAuthorizationIfNeeded() {
        let key = "sideBar.didRequestBadgePermission"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
    }
#endif
}
