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
                showsTopSafeAreaOverlay: shouldShowGlobalTopSafeAreaOverlay,
                topSafeAreaBackground: topSafeAreaBackground,
                onSignOut: { Task { await environment.beginSignOut() } },
                onOpenSettings: { presentSettingsSurface() },
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
        content = AnyView(content.overlay(alignment: .top) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                if let toast = environment.toastCenter.toast {
                    ToastBanner(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            environment.toastCenter.dismiss()
                        }
                }
            }
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
        })
        #if os(macOS)
        content = AnyView(content.overlay {
            if environment.isMacSettingsPresented {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            Task { @MainActor in
                                environment.dismissMacSettings()
                            }
                        }

                    SettingsView(
                        presentationStyle: .macModal,
                        onClose: {
                            Task { @MainActor in
                                environment.dismissMacSettings()
                            }
                        }
                    )
                        .environmentObject(environment)
                        .padding(DesignTokens.Spacing.xl)
                }
                .transition(.opacity)
            }
        })
        content = AnyView(content.onKeyPress(.escape) {
            guard environment.isMacSettingsPresented else { return .ignored }
            Task { @MainActor in
                environment.dismissMacSettings()
            }
            return .handled
        })
        content = AnyView(
            content.animation(Motion.quick(reduceMotion: reduceMotion), value: environment.isMacSettingsPresented)
        )
        #endif
        content = AnyView(content.animation(Motion.quick(reduceMotion: reduceMotion), value: environment.toastCenter.toast))
        content = AnyView(content.onChange(of: scenePhase) { _, newValue in
            if newValue == .inactive || newValue == .background {
                Task {
                    await environment.notesRuntime.editorViewModel.saveIfNeeded()
                }
            }
            if newValue == .background {
                environment.noteProtectedContentBackgrounded()
                #if os(iOS)
                let continuationPlan = Self.signedInBackgroundContinuationPlan(
                    isAuthenticated: environment.isAuthenticated,
                    pendingWriteCount: environment.writeQueue.pendingCount
                )
                if continuationPlan.shouldScheduleTokenRefresh {
                    AppLaunchDelegate.scheduleTokenRefresh()
                }
                if continuationPlan.shouldScheduleWidgetRefresh {
                    AppLaunchDelegate.scheduleWidgetRefresh()
                }
                if continuationPlan.shouldScheduleWriteQueueFlush {
                        AppLaunchDelegate.scheduleWriteQueueFlush()
                }
                if continuationPlan.shouldNotifyWebsiteQueueCoordinator {
                    environment.websiteQueueCoordinator.appDidEnterBackground()
                }
                #endif
            }
            if newValue == .active {
                environment.noteProtectedContentBecameActive()
                Task {
                    await environment.handleSignedInActivation()
                }
            }
        })
        #if os(iOS)
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                if environment.authState == .active {
                    environment.websiteQueueCoordinator.appDidBecomeActive()
                    await environment.consumeWidgetCompletions()
                }
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
            saveCurrentWorkspaceRestorationSnapshot()
        })
        content = AnyView(content.onChange(of: sidebarSelection) { _, newValue in
            handleSidebarSelectionChange(newValue)
        })
        content = AnyView(content.onReceive(environment.workspaceStore.$state.dropFirst()) { state in
            syncLocalSectionSelectionFromWorkspaceState(state)
            updateActiveSection()
            saveCurrentWorkspaceRestorationSnapshot()
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
            saveCurrentWorkspaceRestorationSnapshot()
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
        let workspaceRestorationSaveTriggers = Publishers.MergeMany([
            environment.notesRuntime.viewModel.$selectedNoteId.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.ingestionViewModel.$selectedFileId.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.websitesViewModel.$selectedWebsiteId.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.chatViewModel.$selectedConversationId.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.chatViewModel.$isDraftConversationActive.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.chatViewModel.$draftText.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.chatViewModel.$attachments.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.navigation.$tasksPhoneDetailRouteId.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            environment.navigation.$focusedWorkspacePane.dropFirst().removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ])
        content = AnyView(content.onReceive(workspaceRestorationSaveTriggers) { _ in
            saveCurrentWorkspaceRestorationSnapshot()
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
            if newValue == .chat,
               environment.consumePendingSidebarDeepLink(host: "scratchpad") != nil {
                #if os(macOS)
                environment.emitShortcutAction(.openScratchpad)
                #else
                switch WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: isPhoneIdiom) {
                case .sheet:
                    isPhoneScratchpadPresented = true
                case .anchoredPopover:
                    environment.emitShortcutAction(.openScratchpad)
                }
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
            saveCurrentWorkspaceRestorationSnapshot()
        })
        content = AnyView(content.onChange(of: environment.pendingSidebarDeepLink) { _, _ in
            guard environment.consumePendingSidebarDeepLink(host: "digest", path: "/morning") != nil else {
                return
            }
            isMorningDigestPresented = true
        })
        content = AnyView(content.onAppear {
            guard environment.consumePendingSidebarDeepLink(host: "digest", path: "/morning") != nil else {
                return
            }
            isMorningDigestPresented = true
        })
        content = AnyView(content.onChange(of: isWorkspaceExpanded) { _, newValue in
            environment.workspaceStore.dispatch(
                .setWorkspaceExpanded(newValue),
                source: "workspace_expanded_change"
            )
            handleWorkspaceExpandedChange(isExpanded: newValue)
            saveCurrentWorkspaceRestorationSnapshot()
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
        content = AnyView(content.onChange(of: environment.authState) { _, _ in
            let isAuthenticated = environment.isAuthenticated
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
                triggerSignedInProtectedContentLoadIfNeeded()
                Task { await ensureInitialPhoneChatInterfaceIfNeeded() }
            } else {
                resetSignedInBootstrapState()
            }
        })
        content = AnyView(content.onChange(of: biometricUnlockEnabled) { _, isEnabled in
            environment.updateBiometricUnlockPreference(isEnabled: isEnabled)
        })
        content = AnyView(content.onChange(of: environment.isBiometricUnlocked) { _, _ in
            triggerSignedInProtectedContentLoadIfNeeded()
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
        content = AnyView(content.onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event else { return }
            switch event.action {
            case .showShortcuts:
                #if os(iOS)
                isShortcutsPresented = true
                #endif
            case .toggleSidebar:
                #if os(macOS)
                isLeftPanelExpanded.toggle()
                #else
                if horizontalSizeClass != .compact {
                    isLeftPanelExpanded.toggle()
                }
                #endif
            case .openScratchpad:
                switch WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: isPhoneIdiom) {
                case .sheet:
                    isPhoneScratchpadPresented = true
                case .anchoredPopover:
                    break
                }
            default:
                break
            }
        })
        content = AnyView(content.task {
            applyInitialSelectionIfNeeded()
            triggerSignedInProtectedContentLoadIfNeeded()
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
                    primaryButton: .default(Text("Enable in Settings"), action: {
                        enqueueAlertAction {
                            presentSettingsSurface()
                        }
                    }),
                    secondaryButton: .cancel()
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
