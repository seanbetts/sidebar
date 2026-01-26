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
            if newValue == .background && biometricUnlockEnabled {
                // Record when we went to background (don't lock yet)
                backgroundedAt = Date()
            }
            #if os(iOS)
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
                    await environment.consumeExtensionEvents()
                    await environment.consumeWidgetCompletions()
                    environment.consumeWidgetAddTask()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await environment.consumeExtensionEvents()
                    await environment.websitesViewModel.load(force: true)
                }
            }
            #endif
        })
        #if os(iOS)
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await environment.consumeExtensionEvents()
                await environment.consumeWidgetCompletions()
                environment.consumeWidgetAddTask()
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
        content = AnyView(content.onChange(of: environment.isAuthenticated) { oldValue, isAuthenticated in
            activeAlert = nil
            pendingSessionExpiryAlert = false
            pendingBiometricUnavailableAlert = false
            environment.sessionExpiryWarning = nil
            isSigningOut = false
            if isAuthenticated {
                #if os(iOS)
                Task {
                    await environment.consumeExtensionEvents()
                    await environment.consumeWidgetCompletions()
                }
                #endif
                // When user just signed in (transitioned from not authenticated to authenticated),
                // consider them already unlocked since they authenticated with password.
                // Biometric lock should only apply when returning from background.
                let justSignedIn = !oldValue
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
            if environment.isAuthenticated && !didLoadSettings {
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
        content = AnyView(content.onChange(of: environment.sessionExpiryWarning) { _, newValue in
            enqueueAlertAction {
                guard environment.isAuthenticated, !isSigningOut else { return }
                if newValue != nil {
                    presentAlert(.sessionExpiry)
                } else {
                    pendingSessionExpiryAlert = false
                }
            }
        })
        content = AnyView(content.onChange(of: environment.signOutEvent) { _, _ in
            enqueueAlertAction {
                pendingSessionExpiryAlert = false
                pendingBiometricUnavailableAlert = false
                activeAlert = nil
                isSigningOut = true
            }
        })
        content = AnyView(content.onChange(of: environment.isAuthenticated) { _, isAuthenticated in
            guard !isAuthenticated else { return }
            enqueueAlertAction {
                pendingSessionExpiryAlert = false
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
                if pendingSessionExpiryAlert,
                   environment.isAuthenticated,
                   !isSigningOut,
                   environment.sessionExpiryWarning != nil {
                    pendingSessionExpiryAlert = false
                    activeAlert = .sessionExpiry
                    return
                }
                pendingSessionExpiryAlert = false
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
            case .sessionExpiry:
                return Alert(
                    title: Text("Session Expiring Soon"),
                    message: Text("Your session will expire soon. Would you like to stay signed in?"),
                    primaryButton: .default(Text("Stay Signed In"), action: {
                        enqueueAlertAction {
                            Task { await environment.container.authSession.refreshSession() }
                            environment.sessionExpiryWarning = nil
                        }
                    }),
                    secondaryButton: .destructive(Text("Sign Out"), action: {
                        enqueueAlertAction {
                            pendingSessionExpiryAlert = false
                            Task {
                                await environment.beginSignOut()
                            }
                        }
                    })
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
}
