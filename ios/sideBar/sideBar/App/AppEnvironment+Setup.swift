import Combine
import Foundation
import sideBarShared
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
        syncCoordinator.start()
        setupTaskBadgeUpdates()
        ingestionViewModel.resumePendingUploads()
        runOfflineMaintenance()

        // Migrate widget data to new generic keys (one-time)
        WidgetDataManager.shared.migrateIfNeeded()

        // Sync initial auth state to widgets
        WidgetDataManager.shared.updateAuthState(isAuthenticated: isAuthenticated)
    }

    func runOfflineMaintenance() {
        Task { [weak self] in
            guard let self else { return }
            try? self.draftStorage.cleanupSyncedDrafts(olderThan: 7)
            await self.offlineStore.cleanupSnapshots()
            PendingShareStore.shared.cleanup(olderThan: 7)
        }
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
                if !isOffline {
                    Task { [weak self] in
                        await self?.consumePendingShares()
                    }
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
