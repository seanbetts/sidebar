import LocalAuthentication
import OSLog
import SwiftUI
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
                topSafeAreaBackground: topSafeAreaBackground,
                onSignOut: { Task { await environment.beginSignOut() } },
                mainView: { mainView },
                scenePhase: scenePhase
            )
        )
        #if os(iOS)
        content = AnyView(content.sheet(isPresented: $isShortcutsPresented) {
            KeyboardShortcutsView()
        })
        #endif
        content = AnyView(content.sheet(item: $pendingWriteConflict) { conflict in
            WriteConflictResolutionSheet(conflict: conflict) { resolution in
                Task {
                    await environment.writeQueue.resolveConflict(id: conflict.id, resolution: resolution)
                    await refreshPendingWriteConflict()
                }
            }
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
        content = AnyView(content.animation(.easeOut(duration: 0.2), value: environment.toastCenter.toast))
        content = AnyView(content.onChange(of: scenePhase) { _, newValue in
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

                // Refresh session on activation for both iOS and macOS.
                if environment.authState != .signedOut {
                    Task {
                        if environment.authState == .stale {
                            await environment.container.authSession.refreshSession()
                        } else {
                            await environment.container.authSession.refreshSessionIfStale()
                        }
                    }
                }

                #if os(iOS)
                Task {
                    if environment.authState == .active {
                        await environment.consumeExtensionEvents()
                        await environment.consumeWidgetCompletions()
                        await environment.consumeWidgetQuickSave()
                    }
                    environment.consumeWidgetAddTask()
                    environment.consumeWidgetAddNote()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if environment.authState == .active {
                        await environment.consumeExtensionEvents()
                        await environment.websitesViewModel.load(force: true)
                    }
                }
                environment.runOfflineMaintenance()
                #endif
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
        content = AnyView(content.onChange(of: phoneSelection) { _, newValue in
            sidebarSelection = newValue
            primarySection = newValue
            Task { await loadPhoneSectionIfNeeded(newValue) }
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: sidebarSelection) { _, newValue in
            updateActiveSection()
            #if !os(macOS)
            guard horizontalSizeClass != .compact else { return }
            guard let newValue else { return }
            if newValue == .chat {
                primarySection = nil
                secondarySection = .chat
                return
            }
            handleNonChatSelection(newValue)
            #endif
        })
        content = AnyView(content.onChange(of: primarySection) { _, _ in
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: secondarySection) { _, _ in
            updateActiveSection()
        })
        content = AnyView(content.onChange(of: isSettingsPresented) { _, _ in
            updateActiveSection()
        })
        #if !os(macOS)
        content = AnyView(content.onChange(of: horizontalSizeClass) { _, _ in
            updateActiveSection()
        })
        #endif
        content = AnyView(content.onReceive(environment.notesViewModel.$selectedNoteId) { newValue in
            guard newValue != nil else { return }
            handleNonChatSelection(.notes)
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
            if newValue == .settings {
                #if os(macOS)
                #else
                isSettingsPresented = true
                #endif
                environment.commandSelection = nil
                return
            }
            if newValue != .chat {
                handleNonChatSelection(newValue)
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
            handleWorkspaceExpandedChange(isExpanded: newValue)
        })
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
                #if os(iOS)
                Task {
                    if environment.authState == .active {
                        await environment.consumeExtensionEvents()
                        await environment.consumeWidgetCompletions()
                    }
                }
                #endif
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
                        await environment.settingsViewModel.load()
                        await environment.settingsViewModel.loadProfileImage()
                        await refreshWeatherIfPossible()
                    }
                }
                } else {
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
        #if os(iOS)
        content = AnyView(content.onReceive(environment.$shortcutActionEvent) { event in
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
                    await environment.settingsViewModel.load()
                    await environment.settingsViewModel.loadProfileImage()
                    await refreshWeatherIfPossible()
                }
            }
        })
        #if !os(macOS)
        content = AnyView(content.sheet(isPresented: $isSettingsPresented) {
            SettingsView()
                .environmentObject(environment)
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
            pendingWriteConflict = await environment.writeQueue.fetchNextConflict()
        } else {
            pendingWriteConflict = nil
        }
    }
}

extension ContentView {
    private func handleWorkspaceExpandedChange(isExpanded: Bool) {
        if isExpanded {
            if workspaceExpandedPreviousLeftPanelExpanded == nil {
                workspaceExpandedPreviousLeftPanelExpanded = isLeftPanelExpanded
            }
            if isLeftPanelExpanded {
                isLeftPanelExpanded = false
            }
        } else if let previous = workspaceExpandedPreviousLeftPanelExpanded {
            isLeftPanelExpanded = previous
            workspaceExpandedPreviousLeftPanelExpanded = nil
            #if os(iOS)
            isWorkspaceExpandedByRotation = false
            #endif
        }
    }

    #if os(iOS)
    private func handleRootSizeChange(_ size: CGSize) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let isPortrait = size.height >= size.width
        if lastWorkspaceIsPortrait == isPortrait {
            return
        }
        lastWorkspaceIsPortrait = isPortrait
        guard let section = primaryWorkspaceSectionForRotation,
              [.chat, .websites, .notes, .tasks, .files].contains(section) else { return }
        if isPortrait {
            if !isWorkspaceExpanded {
                isWorkspaceExpandedByRotation = true
                isWorkspaceExpanded = true
            }
        } else if isWorkspaceExpandedByRotation {
            isWorkspaceExpandedByRotation = false
            isWorkspaceExpanded = false
        }
    }

    private var primaryWorkspaceSectionForRotation: AppSection? {
        #if os(macOS)
        return primarySection ?? sidebarSelection
        #else
        if horizontalSizeClass == .compact {
            return nil
        }
        return primarySection ?? sidebarSelection
        #endif
    }
    #endif
}
