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

    public func refreshAuthState(scheduleActivation: Bool = true) {
        let previousAuthState = authState
        let wasAuthenticated = isAuthenticated
        let wasProtectedContentReady = isProtectedContentReady
        authState = container.authSession.authState
        syncBiometricUnlockState(previousAuthState: previousAuthState)
        let becameActive = previousAuthState != .active && authState == .active
        let isAuthenticated = self.isAuthenticated
        let becameAuthenticated = !wasAuthenticated && isAuthenticated
        let becameProtectedContentReady = !wasProtectedContentReady && isProtectedContentReady

        let storedCacheScopeUserId = storage.userDefaults.string(forKey: AppStorageKeys.cacheScopeUserId)
        let hasRecoverableSignedOutSession =
            authState == .signedOut &&
            container.offlineAccessRestorer?.canRestoreOfflineSession == true
        let requiresSignedOutReset = authState == .signedOut
            && !hasRecoverableSignedOutSession
            && (previousAuthState != .signedOut || storedCacheScopeUserId != nil)
        if requiresSignedOutReset {
            clearStoredCacheScopeUserId()
            resetSignedInData(
                clearNavigationState: true,
                preserveExtensionHandoffs: true
            )
            storage.userDefaults.set(false, forKey: AppStorageKeys.widgetAuthStateMirror)
            storage.userDefaults.set(
                WidgetDisplayAuthorization.DisplayState.signedOut.rawValue,
                forKey: AppStorageKeys.widgetAuthDisplayStateMirror
            )
        }
        if previousAuthState != .reauthenticationRequired && authState == .reauthenticationRequired {
            Task { [spotlightIndexer] in
                await spotlightIndexer.clearAllIndexes()
            }
        }
        if isAuthenticated {
            reconcileCacheScopeForAuthenticatedUser()
            biometricMonitor.startMonitoring()
            if authState == .active {
                currentLocationViewModel.startTrackingIfAuthorized()
            }
            #if os(iOS) || os(macOS)
            if authState == .active {
                hydratePushDiagnosticsStateFromStorage()
                registerForRemoteNotificationsIfNeeded()
                registerDeviceTokenIfNeeded()
            }
            #endif
            if scheduleActivation {
                Task { [weak self] in
                    guard let self, self.isAuthenticated else { return }
                    if becameActive || becameAuthenticated {
                        await self.handleSignedInActivation()
                    } else {
                        self.websiteQueueCoordinator.authDidBecomeRunnable()
                        await self.consumeWidgetCompletions()
                    }
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
            syncWidgetAuthStateIfNeeded(
                displayState: widgetDisplayStateForCurrentAuthState(
                    hasRecoverableSignedOutSession: hasRecoverableSignedOutSession
                )
            )
        }
    }

    func syncBiometricUnlockState(previousAuthState: AuthState) {
        guard isAuthenticated else {
            isBiometricUnlocked = false
            biometricBackgroundedAt = nil
            return
        }

        if previousAuthState == .signedOut || previousAuthState == .reauthenticationRequired {
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

    func handleProtectedAuthRejected(rejectedToken: String? = nil) {
        guard authState != .reauthenticationRequired else { return }
        if let scopedInvalidating = container.authSession as? AuthSessionTokenScopedInvalidating {
            scopedInvalidating.markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: rejectedToken)
        } else {
            (container.authSession as? AuthSessionInvalidating)?
                .markSessionReauthenticationRequiredAfterAuthorizationFailure()
        }
        refreshAuthState()
        toastCenter.dismiss()
    }

    func updateBiometricUnlockPreference(isEnabled: Bool) {
        guard isAuthenticated else {
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
        guard isAuthenticated, isBiometricUnlockEnabled else {
            biometricBackgroundedAt = nil
            return
        }
        biometricBackgroundedAt = Date()
    }

    func noteProtectedContentBecameActive() {
        defer { biometricBackgroundedAt = nil }
        guard isAuthenticated else { return }
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
        guard isAuthenticated else { return }
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
        let normalizedStoredUserId = storedUserId.map(Self.normalizedCacheScopeUserId)
        guard normalizedStoredUserId != currentUserId else {
            if storedUserId != currentUserId {
                defaults.set(currentUserId, forKey: AppStorageKeys.cacheScopeUserId)
            }
            return
        }

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
        let trimmedUserId = Self.normalizedCacheScopeUserId(rawUserId)
        guard !trimmedUserId.isEmpty else { return nil }
        return trimmedUserId
    }

    private static func normalizedCacheScopeUserId(_ userId: String) -> String {
        userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func clearStoredCacheScopeUserId() {
        storage.userDefaults.removeObject(forKey: AppStorageKeys.cacheScopeUserId)
    }

    nonisolated static func widgetDisplayState(
        authState: AuthState,
        hasRecoverableSignedOutSession: Bool = false
    ) -> WidgetDisplayAuthorization.DisplayState {
        switch authState {
        case .active, .staleRecoverable:
            return .authenticated
        case .reauthenticationRequired:
            return .reauthenticationRequired
        case .signedOut:
            return hasRecoverableSignedOutSession ? .transientlyUnavailable : .signedOut
        }
    }

    func widgetDisplayStateForCurrentAuthState(
        hasRecoverableSignedOutSession: Bool = false
    ) -> WidgetDisplayAuthorization.DisplayState {
        Self.widgetDisplayState(
            authState: authState,
            hasRecoverableSignedOutSession: hasRecoverableSignedOutSession
        )
    }

    func syncWidgetAuthStateIfNeeded(isAuthenticated: Bool) {
        syncWidgetAuthStateIfNeeded(
            displayState: isAuthenticated ? .authenticated : .signedOut
        )
    }

    func syncWidgetAuthStateIfNeeded(displayState: WidgetDisplayAuthorization.DisplayState) {
        let defaults = storage.userDefaults
        let isAuthenticated = displayState == .authenticated
        let mirroredState = defaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool
        let mirroredDisplayState = defaults.string(forKey: AppStorageKeys.widgetAuthDisplayStateMirror)
            .flatMap(WidgetDisplayAuthorization.DisplayState.init(rawValue:))
        let widgetState = storage.widgetDataManager.isAuthenticated()
        let widgetDisplayState = storage.widgetDataManager.storedDisplayState()
        let shouldSyncWidgetState: Bool

        if isAuthenticated {
            shouldSyncWidgetState =
                mirroredState != true ||
                !widgetState ||
                mirroredDisplayState != displayState ||
                widgetDisplayState != displayState
        } else if displayState == .signedOut {
            shouldSyncWidgetState =
                mirroredState == true ||
                widgetState ||
                mirroredDisplayState == .authenticated ||
                mirroredDisplayState == .transientlyUnavailable ||
                mirroredDisplayState == .reauthenticationRequired ||
                widgetDisplayState == .authenticated ||
                widgetDisplayState == .transientlyUnavailable ||
                widgetDisplayState == .reauthenticationRequired
        } else {
            shouldSyncWidgetState =
                mirroredState != false ||
                widgetState ||
                mirroredDisplayState != displayState ||
                widgetDisplayState != displayState
        }

        if shouldSyncWidgetState {
            storage.widgetDataManager.updateAuthDisplayState(displayState)
        }
        defaults.set(isAuthenticated, forKey: AppStorageKeys.widgetAuthStateMirror)
        defaults.set(displayState.rawValue, forKey: AppStorageKeys.widgetAuthDisplayStateMirror)
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
        defaults.removeObject(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
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
        #if os(iOS) || os(macOS)
        await disableDeviceTokenIfNeeded()
        #endif
        await container.authSession.signOut()
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
        switch authState {
        case .staleRecoverable:
            await container.authSession.refreshSession()
            refreshAuthState(scheduleActivation: false)
        case .active:
            await container.authSession.refreshSessionIfStale()
            refreshAuthState(scheduleActivation: false)
        case .reauthenticationRequired, .signedOut:
            break
        }

        if authState == .active {
            let context = currentRefreshContext()
            await refreshCoordinator.handleActivation(
                ActivationRefreshRequest(
                    includeDeferredRefresh: includeDeferredRefresh,
                    activeSection: activeSection,
                    context: context
                )
            )
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

}
