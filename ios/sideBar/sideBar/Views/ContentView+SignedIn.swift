import LocalAuthentication
import OSLog
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif
// MARK: - ContentView+SignedIn
extension ContentView {
    var signedInContent: AnyView {
        var content: AnyView = AnyView(
            SignedInContentView(
                biometricUnlockEnabled: biometricUnlockEnabled,
                isBiometricUnlocked: $isBiometricUnlocked,
                showsTopSafeAreaOverlay: shouldShowGlobalTopSafeAreaOverlay,
                topSafeAreaBackground: topSafeAreaBackground,
                onSignOut: { Task { await environment.beginSignOut() } },
                mainView: { mainView },
                scenePhase: scenePhase
            )
        )
        #if os(iOS)
        content = AnyView(content.sheet(isPresented: $isShortcutsPresented) {
            KeyboardShortcutsView()
                .phoneSheetGrabBarVisible()
        })
        #endif
        content = AnyView(content.sheet(item: $pendingWriteConflict) { conflict in
            WriteConflictResolutionSheet(conflict: conflict) { resolution in
                Task {
                    await environment.writeQueue.resolveConflict(id: conflict.id, resolution: resolution)
                    await refreshPendingWriteConflict()
                }
            }
            .phoneSheetGrabBarVisible()
        })
        content = AnyView(content.overlay(alignment: .top) {
            if let toast = environment.toastCenter.toast {
                ToastBanner(toast: toast)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        environment.toastCenter.dismiss()
                }
            }
        })
        #if os(macOS)
        content = AnyView(content.overlay {
            if environment.isMacSettingsPresented {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            environment.dismissMacSettings()
                        }

                    SettingsView(
                        presentationStyle: .macModal,
                        onClose: { environment.dismissMacSettings() }
                    )
                        .environmentObject(environment)
                        .padding(DesignTokens.Spacing.xl)
                }
                .transition(.opacity)
            }
        })
        content = AnyView(content.onKeyPress(.escape) {
            guard environment.isMacSettingsPresented else { return .ignored }
            environment.dismissMacSettings()
            return .handled
        })
        content = AnyView(content.animation(.easeInOut(duration: 0.2), value: environment.isMacSettingsPresented))
        #endif
        content = AnyView(content.animation(.easeOut(duration: 0.2), value: environment.toastCenter.toast))
        content = AnyView(content.onChange(of: scenePhase) { _, newValue in
            if newValue == .inactive || newValue == .background {
                Task {
                    await environment.notesRuntime.editorViewModel.saveIfNeeded()
                }
            }
            if newValue == .background {
                // Record when we went to background for biometric grace period
                if biometricUnlockEnabled {
                    backgroundedAt = Date()
                }
                #if os(iOS)
                // Schedule background task for widget refresh (auth refresh is foreground-only)
                if environment.isAuthenticated {
                    AppLaunchDelegate.scheduleWidgetRefresh()
                }
                #endif
            }
            if newValue == .active {
                // Check if we need to require biometric based on grace period
                if biometricUnlockEnabled && isBiometricUnlocked {
                    if let backgrounded = backgroundedAt {
                        let elapsed = Date().timeIntervalSince(backgrounded)
                        if elapsed > biometricGracePeriod {
                            isBiometricUnlocked = false
                        }
                    }
                }
                backgroundedAt = nil
                Task {
                    await environment.handleSignedInActivation()
                }
            }
        })
        #if os(iOS)
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                if environment.authState == .active {
                    await environment.consumeExtensionEvents()
                    await environment.consumeWidgetCompletions()
                    await environment.consumeWidgetQuickSave()
                }
                environment.consumeWidgetAddTask()
                environment.consumeWidgetAddNote()
            }
        })
        #endif
        content = AnyView(content.onChange(of: environment.biometricMonitor.isAvailable) { _, isAvailable in
            guard biometricUnlockEnabled, !isAvailable, environment.isAuthenticated else { return }
            enqueueAlertAction {
                presentAlert(.biometricUnavailable)
            }
        })
        content = AnyView(content.onChange(of: phoneSelection) { oldValue, newValue in
            if Self.shouldResetCompactPhoneSearchDock(
                previousSection: oldValue,
                nextSection: newValue
            ) {
                clearCompactPhoneSearchDockQuery(
                    for: oldValue,
                    deferObservableUpdates: true
                )
                isCompactPhoneSearchDockExplicitlyExpanded = false
            }
            syncCompactPhoneTabSelection(for: newValue)
            environment.focusedSection = newValue
            environment.focusedWorkspacePane = .primary
            sidebarSelection = newValue
            #if !os(macOS)
            if horizontalSizeClass == .compact {
                environment.workspaceStore.dispatch(
                    .setLayout(.compact),
                    source: "phone_selection_layout"
                )
                environment.workspaceStore.dispatch(
                    .selectSection(newValue),
                    source: "phone_selection_change"
                )
            }
            #endif
            Task { await loadPhoneSectionIfNeeded(newValue) }
            if newValue == .chat {
                Task { await ensureInitialPhoneChatInterfaceIfNeeded() }
            }
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: sidebarSelection) { _, newValue in
            handleSidebarSelectionChange(newValue)
        })
        content = AnyView(content.onReceive(environment.workspaceStore.$state.dropFirst()) { state in
            syncLocalSectionSelectionFromWorkspaceState(state)
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: isSettingsPresented) { _, _ in
            environment.workspaceStore.dispatch(
                .setSettingsPresented(isSettingsPresented),
                source: "settings_presented_change"
            )
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: isLeftPanelExpanded) { _, _ in
            environment.workspaceStore.dispatch(
                .setLeftPanelExpanded(isLeftPanelExpanded),
                source: "left_panel_expanded_change"
            )
        })
        #if !os(macOS)
        content = AnyView(content.onChange(of: horizontalSizeClass) { oldValue, newValue in
            handleHorizontalSizeClassChange(oldValue: oldValue, newValue: newValue)
        })
        #endif
        content = AnyView(content.onReceive(environment.notesRuntime.viewModel.$selectedNoteId) { newValue in
            #if !os(macOS)
            if horizontalSizeClass == .compact { environment.notesPhoneDetailRouteId = newValue }
            #endif
            if newValue != nil { handleNonChatSelection(.notes) }
        })
        content = AnyView(content.onReceive(environment.ingestionViewModel.$selectedFileId) { newValue in
            guard newValue != nil else { return }
            handleNonChatSelection(.files)
        })
        content = AnyView(content.onChange(of: environment.ingestionViewModel.readyFileNotification) { _, notification in
            guard let notification else { return }
            handleReadyFileNotification(notification)
        })
        content = AnyView(content.onReceive(environment.websitesViewModel.$selectedWebsiteId) { newValue in
            guard newValue != nil else { return }
            handleNonChatSelection(.websites)
        })
        content = AnyView(content.onChange(of: environment.commandSelection) { _, newValue in
            guard let newValue else { return }
            #if !os(macOS)
            if horizontalSizeClass == .compact {
                environment.focusedWorkspacePane = .primary
            }
            #endif
            if newValue == .settings {
                #if os(macOS)
                environment.presentMacSettings()
                #else
                isSettingsPresented = true
                #endif
                environment.commandSelection = nil
                return
            }
            environment.focusedSection = newValue
            if newValue != .chat {
                handleNonChatSelection(newValue)
            } else {
                environment.workspaceStore.dispatch(
                    .selectSection(.chat),
                    source: "command_selection_change"
                )
            }
            // Handle pending scratchpad deep link
            if newValue == .chat && environment.pendingScratchpadDeepLink {
                environment.pendingScratchpadDeepLink = false
                #if !os(macOS)
                isPhoneScratchpadPresented = true
                #endif
            }
            sidebarSelection = newValue
            if !isLeftPanelExpanded {
                isLeftPanelExpanded = true
            }
                #if !os(macOS)
                phoneSelection = newValue
                #endif
                environment.commandSelection = nil
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: isWorkspaceExpanded) { _, newValue in
            environment.workspaceStore.dispatch(
                .setWorkspaceExpanded(newValue),
                source: "workspace_expanded_change"
            )
            handleWorkspaceExpandedChange(isExpanded: newValue)
        })
        #if os(iOS)
        content = AnyView(content.onChange(of: isWorkspaceExpandedByRotation) { _, newValue in
            environment.workspaceStore.dispatch(
                .setWorkspaceExpandedByRotation(newValue),
                source: "workspace_rotation_flag_change"
            )
        })
        #endif
        #if os(iOS)
        content = AnyView(content.background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size) { _, newValue in
                handleRootSizeChange(newValue)
            }
        }))
        #endif
        content = AnyView(content.onReceive(environment.writeQueue.$isPausedForConflict) { isPaused in
            if isPaused {
                Task {
                    await refreshPendingWriteConflict()
                }
            } else {
                pendingWriteConflict = nil
            }
        })
        content = AnyView(content.onChange(of: environment.authState) { oldValue, newValue in
            let oldSignedIn = oldValue != .signedOut
            let isAuthenticated = newValue != .signedOut
            activeAlert = nil
            pendingBiometricUnavailableAlert = false
            isSigningOut = false
            if isAuthenticated {
                Task {
                    if environment.authState == .active {
                        await environment.consumeExtensionEvents()
                        await environment.consumeWidgetCompletions()
                    }
                }
                // When user just signed in (transitioned from not authenticated to authenticated),
                // consider them already unlocked since they authenticated with password.
                // Biometric lock should only apply when returning from background.
                let justSignedIn = !oldSignedIn
                if justSignedIn {
                    isBiometricUnlocked = true
                } else if biometricUnlockEnabled {
                    isBiometricUnlocked = false
                } else {
                    isBiometricUnlocked = true
                }
                #if os(iOS)
                if environment.biometricMonitor.isAvailable
                    && !biometricUnlockEnabled
                    && !hasShownBiometricHint {
                    hasShownBiometricHint = true
                    enqueueAlertAction {
                        if activeAlert == nil {
                            activeAlert = .biometricHint
                        }
                    }
                }
                #endif
                if !didLoadSettings {
                    didLoadSettings = true
                    Task {
                        guard environment.authState == .active else { return }
                        environment.currentLocationViewModel.startTracking()
                        await environment.settingsViewModel.load(force: true)
                        await environment.settingsViewModel.loadProfileImage()
                        await refreshWeatherIfPossible()
                    }
                }
                Task { await ensureInitialPhoneChatInterfaceIfNeeded() }
                } else {
                    didEnsureInitialPhoneChatInterface = false
                    didLoadSettings = false
                    isBiometricUnlocked = false
                }
        })
        content = AnyView(content.onChange(of: biometricUnlockEnabled) { _, isEnabled in
            isBiometricUnlocked = !isEnabled
        })
        content = AnyView(content.onChange(of: environment.settingsViewModel.settings?.location) { _, _ in
            Task {
                await refreshWeatherIfPossible()
            }
        })
        content = AnyView(content.onChange(of: environment.currentLocationViewModel.locationRevision) { _, _ in
            Task {
                await refreshWeatherIfPossible()
            }
        })
        #if os(iOS)
        content = AnyView(content.onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event else { return }
            switch event.action {
            case .showShortcuts:
                isShortcutsPresented = true
            case .toggleSidebar:
                if horizontalSizeClass != .compact {
                    isLeftPanelExpanded.toggle()
                }
            case .openScratchpad:
                if horizontalSizeClass == .compact {
                    isPhoneScratchpadPresented = true
                }
            default:
                break
            }
        })
        #endif
        content = AnyView(content.task {
            applyInitialSelectionIfNeeded()
            if environment.authState == .active && !didLoadSettings {
                didLoadSettings = true
                isBiometricUnlocked = !biometricUnlockEnabled
                Task {
                    environment.currentLocationViewModel.startTracking()
                    await environment.settingsViewModel.load(force: true)
                    await environment.settingsViewModel.loadProfileImage()
                    await refreshWeatherIfPossible()
                }
            }
        })
        #if !os(macOS)
        content = AnyView(content.sheet(isPresented: $isSettingsPresented) {
            SettingsView()
                .environmentObject(environment)
                .settingsSheetGrabBarVisible()
        })
        #endif
        content = AnyView(content.onChange(of: environment.signOutEvent) { _, _ in
            enqueueAlertAction {
                pendingBiometricUnavailableAlert = false
                activeAlert = nil
                isSigningOut = true
            }
        })
        content = AnyView(content.onAppear {
            if isWorkspaceExpanded {
                isWorkspaceExpanded = false
                #if os(iOS)
                isWorkspaceExpandedByRotation = false
                #endif
            }
        })
        content = AnyView(content.onChange(of: environment.authState) { _, newValue in
            guard newValue == .signedOut else { return }
            enqueueAlertAction {
                pendingBiometricUnavailableAlert = false
                activeAlert = nil
                isSigningOut = false
            }
        })
        content = AnyView(content.onChange(of: activeAlert) { _, newValue in
            guard newValue == nil else { return }
            enqueueAlertAction {
                if pendingBiometricUnavailableAlert {
                    pendingBiometricUnavailableAlert = false
                    activeAlert = .biometricUnavailable
                    return
                }
                if let notification = pendingReadyFileNotification {
                    pendingReadyFileNotification = nil
                    handleReadyFileNotification(notification)
                }
            }
        })
        content = AnyView(content.alert(item: $activeAlert) { alert in
            switch alert {
            case .biometricUnavailable:
                return Alert(
                    title: Text("Biometric Unlock Unavailable"),
                    message: Text(
                        "Biometric unlock is no longer available on this device. " +
                            "You can re-enable it in Settings once Face ID or Touch ID is available again."
                    ),
                    dismissButton: .default(Text("OK"))
                )
            case .biometricHint:
                return Alert(
                    title: Text(biometricHintTitle),
                    message: Text(biometricHintMessage),
                    primaryButton: .default(Text("Enable in Settings"), action: {
                        enqueueAlertAction {
                            isSettingsPresented = true
                        }
                    }),
                    secondaryButton: .cancel()
                )
            case .fileReady(let notification):
                return Alert(
                    title: Text("File Ready"),
                    message: Text("\"\(notification.filename)\" is ready to view."),
                    primaryButton: .default(Text("Open File"), action: {
                        enqueueAlertAction {
                            openReadyFile(notification)
                        }
                    }),
                        secondaryButton: .cancel(Text("Stay Here"))
                )
            }
        })
        return content
    }

    func logStartup(_ message: String) {
        #if DEBUG
        #if os(iOS)
        AppLaunchMetrics.shared.mark(message)
        #else
        let logger = Logger(subsystem: "sideBar", category: "Startup")
        logger.info("\(message, privacy: .public)")
        #endif
        #endif
    }

    var biometricHintTitle: String {
        switch environment.biometricMonitor.biometryType {
        case .touchID:
            return "Enable Touch ID?"
        default:
            return "Enable Face ID?"
        }
    }

    var biometricHintMessage: String {
        switch environment.biometricMonitor.biometryType {
        case .touchID:
            return "Unlock sideBar quickly and securely with Touch ID."
        default:
            return "Unlock sideBar quickly and securely with Face ID."
        }
    }

    @MainActor
    private func refreshPendingWriteConflict() async {
        if environment.writeQueue.isPausedForConflict {
            do {
                pendingWriteConflict = try await environment.writeQueue.fetchNextConflict()
            } catch {
                let logger = Logger(subsystem: "sideBar", category: "ContentView")
                logger.error("Failed to fetch write conflict: \(error.localizedDescription, privacy: .public)")
                pendingWriteConflict = nil
            }
        } else {
            pendingWriteConflict = nil
        }
    }
}
