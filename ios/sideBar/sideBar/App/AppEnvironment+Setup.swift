import Combine
import Foundation
import sideBarShared
#if os(iOS)
import UIKit
import UserNotifications
#elseif os(macOS)
import AppKit
#endif

extension AppEnvironment {
    func configureWebsiteSaveHandoffObserver() {
        guard websiteSaveHandoffObserver == nil else { return }
        websiteSaveHandoffObserver = WebsiteSaveHandoffNotifier.observe { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.websiteQueueCoordinator.queueDidChange(trigger: .handoff)
            }
        }
    }

    func configureWidgetTaskCompletionObserver() {
        guard widgetTaskCompletionObserver == nil else { return }
        widgetTaskCompletionObserver = WidgetTaskCompletionHandoffNotifier.observe { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.consumeWidgetTaskCompletionHandoff()
            }
        }
    }

    func configureWidgetIntentObserver() {
        guard widgetIntentObserver == nil else { return }
        widgetIntentObserver = WidgetIntentHandoffNotifier.observe { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.consumeWidgetIntentHandoff()
            }
        }
    }

    func configureSubscriptions() {
        if let authSession = container.observableAuthSession {
            bindAuthSession(authSession)
        }
        forwardObjectWillChange()
        configureDevicePresenceReporting()
        monitorNetwork()
        syncCoordinator.start()
        setupTaskBadgeUpdates()
        ingestionViewModel.resumePendingUploads()
        runOfflineMaintenance()

        // Migrate widget data to new generic keys (one-time)
        storage.widgetDataManager.migrateIfNeeded()
        storage.widgetDataManager.sanitizePendingTaskCompletions()

        // Sync initial auth state to widgets
        storage.widgetDataManager.updateAuthState(isAuthenticated: isAuthenticated)
        storage.widgetDataManager.updateFaviconConfiguration(
            r2Endpoint: container.config.r2Endpoint,
            r2FaviconBucket: container.config.r2FaviconBucket,
            r2FaviconPublicBaseUrl: container.config.r2FaviconPublicBaseUrl
        )
    }

    func runOfflineMaintenance() {
        Task { [weak self] in
            guard let self else { return }
            try? self.draftStorage.cleanupSyncedDrafts(olderThan: 7)
            await self.offlineStore.cleanupSnapshots()
            self.storage.pendingShareStore.cleanup(olderThan: 7)
        }
    }

    func configureRealtimeClient() {
        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
    }

    private func bindAuthSession(_ authSession: any AuthSessionObserving) {
        authSession.accessTokenPublisher
            .sink { [weak self] _ in
                self?.refreshAuthState()
            }
            .store(in: &cancellables)

        authSession.authStatePublisher
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshAuthState()
            }
            .store(in: &cancellables)

        authSession.authErrorPublisher
            .sink { [weak self] event in
                self?.toastCenter.show(message: event.message)
                authSession.clearAuthError()
            }
            .store(in: &cancellables)
    }

    private func forwardObjectWillChange() {
        settingsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        navigation.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        websitesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        websitesStore.$items
            .sink { [weak self] _ in
                self?.reconcileQueuedWebsitesWithSavedItems()
            }
            .store(in: &cancellables)

        ingestionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        toastCenter.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        weatherViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        currentLocationViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)

        writeQueue.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleForwardedObjectWillChange()
            }
            .store(in: &cancellables)
    }

    private func scheduleForwardedObjectWillChange() {
        guard !hasPendingForwardedObjectWillChange else { return }
        hasPendingForwardedObjectWillChange = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.hasPendingForwardedObjectWillChange = false
            self.objectWillChange.send()
        }
    }

    private func monitorNetwork() {
        connectivityMonitor.$isOffline
            .removeDuplicates()
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
                if !isOffline {
                    self?.resetStoreRefreshBackoff()
                    self?.websiteQueueCoordinator.connectivityDidRecover()
                }
            }
            .store(in: &cancellables)

        connectivityMonitor.$isNetworkAvailable
            .removeDuplicates()
            .sink { [weak self] isAvailable in
                self?.isNetworkAvailable = isAvailable
                if isAvailable {
                    self?.resetStoreRefreshBackoff()
                }
            }
            .store(in: &cancellables)

        connectivityMonitor.$isServerReachable
            .removeDuplicates()
            .sink { [weak self] isReachable in
                self?.isServerReachable = isReachable
            }
            .store(in: &cancellables)
    }

    private func setupTaskBadgeUpdates() {
#if os(iOS)
        Publishers.CombineLatest($authState, tasksStore.$counts)
            .receive(on: DispatchQueue.main)
            .sink { authState, counts in
                let badgeCount = authState != .signedOut ? (counts?.counts.today ?? 0) : 0
                UNUserNotificationCenter.current().setBadgeCount(badgeCount, withCompletionHandler: nil)
            }
            .store(in: &cancellables)
#endif
    }

    private func resetStoreRefreshBackoff() {
        chatStore.resetBackgroundRefreshBackoff()
        notesStore.resetBackgroundRefreshBackoff()
        websitesStore.resetBackgroundRefreshBackoff()
        ingestionStore.resetBackgroundRefreshBackoff()
    }

    private func configureDevicePresenceReporting() {
        #if os(iOS) || os(macOS)
        guard !hasConfiguredDevicePresenceReporting else { return }
        hasConfiguredDevicePresenceReporting = true
        _ = ensureDevicePresenceReporter()

        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.reportDevicePresence(isForeground: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.reportDevicePresence(isForeground: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.reportDevicePresence(isForeground: false)
            }
            .store(in: &cancellables)
        #elseif os(macOS)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.reportDevicePresence(isForeground: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.reportDevicePresence(isForeground: false)
            }
            .store(in: &cancellables)
        #endif

        reportCurrentDevicePresenceIfNeeded()
        #endif
    }

}
