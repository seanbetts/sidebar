import Foundation
import OSLog
import sideBarShared

extension AppEnvironment {
    private var biometricGracePeriod: TimeInterval {
        300
    }

    private var authLogger: Logger {
        Logger(subsystem: "sideBar", category: "AppEnvironmentAuth")
    }

    func consumeWidgetTaskCompletionHandoff() async {
        await consumeWidgetCompletions()
    }

    func consumeWebsiteSaveHandoff() async {
        guard authState == .active, isProtectedContentReady else { return }
        await refreshWebsiteQueueHandoff(awaitPendingShareReplay: true)
    }

    public func refreshAuthState() {
        let previousAuthState = authState
        let wasProtectedContentReady = isProtectedContentReady
        authState = container.authSession.authState
        syncBiometricUnlockState(previousAuthState: previousAuthState)
        let becameActive = previousAuthState != .active && authState == .active
        let wasAuthenticated = previousAuthState != .signedOut
        let isAuthenticated = authState != .signedOut
        let becameProtectedContentReady = !wasProtectedContentReady && isProtectedContentReady

        let storedCacheScopeUserId = storage.userDefaults.string(forKey: AppStorageKeys.cacheScopeUserId)
        let requiresSignedOutReset = authState == .signedOut
            && (previousAuthState != .signedOut || storedCacheScopeUserId != nil)
        let becameStale = previousAuthState != .stale && authState == .stale
        let recoveredFromStale = previousAuthState == .stale && authState != .stale
        if requiresSignedOutReset {
            cancelStaleAuthRetryBannerReveal()
            shouldShowStaleAuthRetryBanner = false
            clearStoredCacheScopeUserId()
            resetSignedInData(clearNavigationState: true)
            storage.userDefaults.set(false, forKey: AppStorageKeys.widgetAuthStateMirror)
        }
        if becameStale && wasAuthenticated {
            shouldShowStaleAuthRetryBanner = false
            scheduleStaleAuthRetryBannerReveal()
        }
        if recoveredFromStale {
            cancelStaleAuthRetryBannerReveal()
            shouldShowStaleAuthRetryBanner = false
        }
        if isAuthenticated {
            reconcileCacheScopeForAuthenticatedUser()
            biometricMonitor.startMonitoring()
            if authState == .active {
                currentLocationViewModel.startTrackingIfAuthorized()
            }
            #if os(iOS) || os(macOS)
            if authState == .active {
                registerDeviceTokenIfNeeded()
            }
            #endif
            Task { [weak self] in
                guard let self, self.authState == .active else { return }
                if becameActive {
                    await self.handleSignedInActivation()
                } else {
                    self.websiteQueueCoordinator.authDidBecomeRunnable()
                    await self.consumeWidgetCompletions()
                }
            }
        } else {
            biometricMonitor.stopMonitoring()
            currentLocationViewModel.stopTracking()
        }
        if becameProtectedContentReady {
            Task { [weak self] in
                await self?.replayProtectedDeferredActionsIfReady()
            }
        }
        realtimeClientStopStart()

        if previousAuthState == .signedOut && isAuthenticated {
            bootstrapWidgetBridgeForCurrentAuthState()
        } else {
            syncWidgetAuthStateIfNeeded(isAuthenticated: isAuthenticated)
        }
    }

    func syncBiometricUnlockState(previousAuthState: AuthState) {
        guard authState != .signedOut else {
            isBiometricUnlocked = false
            biometricBackgroundedAt = nil
            return
        }

        if previousAuthState == .signedOut {
            // A successful primary-auth flow counts as the unlock for the new session.
            isBiometricUnlocked = true
            biometricBackgroundedAt = nil
            return
        }

        if !isBiometricUnlockEnabled {
            isBiometricUnlocked = true
            biometricBackgroundedAt = nil
            return
        }
        // Preserve the local biometric gate across token refreshes and
        // stale/active auth transitions within the same signed-in session.
    }

    func updateBiometricUnlockPreference(isEnabled: Bool) {
        guard authState != .signedOut else {
            isBiometricUnlocked = false
            biometricBackgroundedAt = nil
            return
        }

        biometricBackgroundedAt = nil
        isBiometricUnlocked = !isEnabled

        guard !isEnabled else { return }
        Task { [weak self] in
            await self?.replayProtectedDeferredActionsIfReady()
        }
    }

    func noteProtectedContentBackgrounded() {
        guard authState != .signedOut, isBiometricUnlockEnabled else {
            biometricBackgroundedAt = nil
            return
        }
        biometricBackgroundedAt = Date()
    }

    func noteProtectedContentBecameActive() {
        defer { biometricBackgroundedAt = nil }
        guard authState != .signedOut else { return }
        guard isBiometricUnlockEnabled, isBiometricUnlocked else { return }
        guard let biometricBackgroundedAt else { return }

        let elapsed = Date().timeIntervalSince(biometricBackgroundedAt)
        if elapsed > biometricGracePeriod {
            isBiometricUnlocked = false
        }
    }

    func queueProtectedDeepLink(_ url: URL) {
        queuedProtectedDeepLinks.append(url)
    }

    func completeBiometricUnlock() async {
        guard authState != .signedOut else { return }
        isBiometricUnlocked = true
        biometricBackgroundedAt = nil
        await replayProtectedDeferredActionsIfReady()
    }

    func completeSettingsPasswordChange(newPassword: String) async throws {
        try await container.passwordChangeManager.changePassword(newPassword: newPassword)
        passwordResetSuccessMessage = "Password updated. Sign in with your new password."
        passwordResetSuccessDetail = nil
        await container.authSession.signOut()
        refreshAuthState()
    }

    func replayProtectedDeferredActionsIfReady() async {
        guard isProtectedContentReady else { return }

        let queuedDeepLinks = queuedProtectedDeepLinks
        queuedProtectedDeepLinks.removeAll()
        for url in queuedDeepLinks {
            handleDeepLink(url)
        }

        guard authState == .active else { return }
        websiteQueueCoordinator.protectedContentDidBecomeReady()
    }

    private func reconcileCacheScopeForAuthenticatedUser() {
        guard let currentUserId = currentAuthUserId else { return }
        let defaults = storage.userDefaults
        let storedUserId = defaults.string(forKey: AppStorageKeys.cacheScopeUserId)
        guard storedUserId != currentUserId else { return }

        // Run a one-time migration clear for existing installs with unscoped cache keys.
        let shouldResetSignedInData = storedUserId != nil || authState == .active
        if shouldResetSignedInData {
            let previousScope = storedUserId ?? "<none>"
            authLogger.notice(
                """
                Resetting cached data for user scope change from \
                \(previousScope, privacy: .public) to \(currentUserId, privacy: .public)
                """
            )
            resetSignedInData(
                clearNavigationState: false,
                preserveExtensionHandoffs: true
            )
        }
        defaults.set(currentUserId, forKey: AppStorageKeys.cacheScopeUserId)
    }

    private var currentAuthUserId: String? {
        guard let rawUserId = container.authSession.userId else { return nil }
        let trimmedUserId = rawUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else { return nil }
        return trimmedUserId
    }

    private func clearStoredCacheScopeUserId() {
        storage.userDefaults.removeObject(forKey: AppStorageKeys.cacheScopeUserId)
    }

    func syncWidgetAuthStateIfNeeded(isAuthenticated: Bool) {
        let defaults = storage.userDefaults
        let lastSyncedState = defaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool ?? false
        guard lastSyncedState != isAuthenticated else {
            defaults.set(isAuthenticated, forKey: AppStorageKeys.widgetAuthStateMirror)
            return
        }
        storage.widgetDataManager.updateAuthState(isAuthenticated: isAuthenticated)
        defaults.set(isAuthenticated, forKey: AppStorageKeys.widgetAuthStateMirror)
    }

    private func resetSignedInData(
        clearNavigationState: Bool,
        preserveExtensionHandoffs: Bool = false
    ) {
        dismissMacSettings()
        flushSignedInPersistence(preserveExtensionHandoffs: preserveExtensionHandoffs)
        chatStore.reset()
        notesStore.reset()
        websitesStore.reset()
        ingestionStore.reset()
        tasksStore.reset()
        chatViewModel.reset()
        tasksViewModel.reset()
        settingsViewModel.reset()
        notesViewModel.clearSelection()
        notesViewModel.searchQuery = ""
        websitesViewModel.clearSelection()
        websitesViewModel.panelSearchQuery = ""
        websitesViewModel.errorMessage = nil
        websitesViewModel.saveErrorMessage = nil
        websitesViewModel.pendingWebsite = nil
        websitesViewModel.isSavingWebsite = false
        ingestionViewModel.clearSelection()
        ingestionViewModel.panelSearchQuery = ""
        ingestionViewModel.errorMessage = nil
        currentLocationViewModel.stopTracking()
        if clearNavigationState {
            isTasksFocused = false
            navigation.resetForSignOut()
        }
        Task {
            await spotlightIndexer.clearAllIndexes()
        }
    }

    private func flushSignedInPersistence(preserveExtensionHandoffs: Bool = false) {
        container.cacheClient.clear()
        offlineStore.clearAllSnapshots()
        let defaults = storage.userDefaults
        defaults.removeObject(forKey: AppStorageKeys.lastSignInEmail)
        defaults.removeObject(forKey: AppStorageKeys.lastAuthTimestamp)
        storage.widgetDataManager.clearAllDataForSignOut()
        clearSharedExtensionAuthState()
        if !preserveExtensionHandoffs {
            storage.pendingShareStore.clearAll()
            storage.extensionEventStore.clear()
        }
        do {
            try draftStorage.clearAllDrafts()
        } catch {
            authLogger.error("Failed to clear local drafts on sign-out: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearSharedExtensionAuthState() {
        do {
            try SupabaseAuthRecovery.clearPersistedAuthState(
                stateStore: ExtensionAuthStateStoreFactory.makeSharedStore()
            )
        } catch {
            authLogger.error(
                "Failed to clear shared extension auth state on sign-out: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        cancelStaleAuthRetryBannerReveal()
        shouldShowStaleAuthRetryBanner = false
        #if os(iOS) || os(macOS)
        await disableDeviceTokenIfNeeded()
        #endif
        await container.authSession.signOut()
        refreshAuthState()
    }

    public func retryStaleAuthSession() async {
        guard authState == .stale, !isRetryingStaleAuth else { return }
        isRetryingStaleAuth = true
        defer { isRetryingStaleAuth = false }

        await container.authSession.refreshSession()
        refreshAuthState()
    }

    /// Handles signed-in foreground activation work shared by iOS and macOS.
    public func handleSignedInActivation(includeDeferredRefresh: Bool = true) async {
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "app_activation",
            stage: "begin",
            message: "Handling signed-in activation.",
            metadata: ["auth_state": authState.rawValue]
        )
        await refreshCoordinator.handleActivation(
            ActivationRefreshRequest(
                includeDeferredRefresh: includeDeferredRefresh,
                activeSection: activeSection,
                context: currentRefreshContext()
            )
        )
        if authState != .signedOut {
            if authState == .stale {
                await container.authSession.refreshSession()
            } else {
                await container.authSession.refreshSessionIfStale()
            }
        }

        if authState == .active {
            await refreshWebsiteQueueHandoff(awaitPendingShareReplay: false)
            await consumeWidgetCompletions()
            if includeDeferredRefresh {
                await refreshWidgetDataBridges()
            }
        }
        #if os(iOS)
        runOfflineMaintenance()
        #endif
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "app_activation",
            stage: "end",
            message: "Finished signed-in activation.",
            metadata: ["auth_state": authState.rawValue]
        )
    }

    private func scheduleStaleAuthRetryBannerReveal() {
        cancelStaleAuthRetryBannerReveal()
        staleAuthRetryBannerRevealTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: staleAuthRetryBannerDelayNanoseconds)
            guard !Task.isCancelled, authState == .stale else { return }
            shouldShowStaleAuthRetryBanner = true
        }
    }

    private func cancelStaleAuthRetryBannerReveal() {
        staleAuthRetryBannerRevealTask?.cancel()
        staleAuthRetryBannerRevealTask = nil
    }

}
