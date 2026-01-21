import SwiftUI

// MARK: - ContentView+Layout

extension ContentView {
    @ViewBuilder
    var mainView: some View {
        #if os(macOS)
        splitView
        #else
        if horizontalSizeClass == .compact {
            compactView
        } else {
            splitView
        }
        #endif
    }

    func presentAlert(_ alert: ActiveAlert) {
        if activeAlert == nil {
            activeAlert = alert
            return
        }
        switch alert {
        case .biometricUnavailable:
            pendingBiometricUnavailableAlert = true
        case .sessionExpiry:
            pendingSessionExpiryAlert = true
        case .biometricHint:
            break
        case .fileReady(let notification):
            pendingReadyFileNotification = notification
        }
    }

    func enqueueAlertAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }

    var splitView: some View {
        WorkspaceLayout(
            selection: $sidebarSelection,
            isLeftPanelExpanded: $isLeftPanelExpanded,
            shouldAnimateSidebar: hasCompletedInitialSetup,
            onShowSettings: { isSettingsPresented = true },
            header: {
                SiteHeaderBar(
                    onSwapContent: swapPrimaryAndSecondary,
                    onShowSettings: { isSettingsPresented = true },
                    isLeftPanelExpanded: isLeftPanelExpanded,
                    shouldAnimateSidebar: hasCompletedInitialSetup
                )
            }
        ) {
            detailView(for: primarySection)
        } rightSidebar: {
            detailView(for: secondarySection)
        }
    }

    var compactView: some View {
        TabView(selection: $phoneSelection) {
            ForEach(phoneSections, id: \.self) { section in
                phoneTabView(for: section)
                    .tag(section)
                    .tabItem {
                        Label {
                            Text(section.title)
                        } icon: {
                            Image(systemName: phoneIconName(for: section))
                                .symbolVariant(.none)
                        }
                    }
            }
        }
        .tint(tabBarTint)
        .overlay(alignment: .bottomTrailing) {
            if phoneSelection != .chat {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                isPhoneScratchpadPresented = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(DesignTokens.Typography.titleLg)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(separatorColor, lineWidth: 1)
                            )
                            .accessibilityLabel("Scratchpad")
                            .padding(.trailing, DesignTokens.Spacing.md)
                            .padding(.bottom, proxy.safeAreaInsets.bottom + DesignTokens.Spacing.xxl)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .sheet(isPresented: $isPhoneScratchpadPresented) {
            ScratchpadPopoverView(
                api: environment.container.scratchpadAPI,
                cache: environment.container.cacheClient,
                scratchpadStore: environment.scratchpadStore
            )
        }
    }

    func detailView(for section: AppSection?) -> some View {
        detailViewDefinition(for: section)
    }

    func swapPrimaryAndSecondary() {
        let performSwap = {
            let temp = primarySection
            primarySection = secondarySection
            secondarySection = temp
            if primarySection != .chat, let primarySection {
                lastNonChatSection = primarySection
            }
        }
        if reduceMotion {
            performSwap()
        } else {
            withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
                performSwap()
            }
        }
    }

    func handleNonChatSelection(_ section: AppSection) {
        if primarySection == .chat {
            secondarySection = section
        } else {
            primarySection = section
        }
        lastNonChatSection = section
    }

    func handleReadyFileNotification(_ notification: ReadyFileNotification) {
        environment.ingestionViewModel.clearReadyFileNotification()
        if environment.ingestionViewModel.selectedFileId == notification.fileId {
            return
        }
        if isFilesSectionVisible {
            Task { await environment.ingestionViewModel.selectFile(fileId: notification.fileId, forceRefresh: true) }
            return
        }
        presentAlert(.fileReady(notification))
    }

    func openReadyFile(_ notification: ReadyFileNotification) {
        navigateToFilesSection()
        Task { await environment.ingestionViewModel.selectFile(fileId: notification.fileId, forceRefresh: true) }
    }

    func navigateToFilesSection() {
        #if !os(macOS)
        if horizontalSizeClass == .compact {
            phoneSelection = .files
            return
        }
        #endif
        sidebarSelection = .files
        if !isLeftPanelExpanded {
            isLeftPanelExpanded = true
        }
        handleNonChatSelection(.files)
    }

}
