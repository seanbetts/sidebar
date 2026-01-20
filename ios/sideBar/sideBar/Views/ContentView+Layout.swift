import SwiftUI

extension ContentView {
    @ViewBuilder
    private var mainView: some View {
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

    private func presentAlert(_ alert: ActiveAlert) {
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

    private func enqueueAlertAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }

    private var splitView: some View {
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

    private var compactView: some View {
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
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(separatorColor, lineWidth: 1)
                            )
                            .accessibilityLabel("Scratchpad")
                            .padding(.trailing, 16)
                            .padding(.bottom, proxy.safeAreaInsets.bottom + 32)
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

    private func detailView(for section: AppSection?) -> some View {
        detailViewDefinition(for: section)
    }

    private func swapPrimaryAndSecondary() {
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

    private func handleNonChatSelection(_ section: AppSection) {
        if primarySection == .chat {
            secondarySection = section
        } else {
            primarySection = section
        }
        lastNonChatSection = section
    }

    private func handleReadyFileNotification(_ notification: ReadyFileNotification) {
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

    private func openReadyFile(_ notification: ReadyFileNotification) {
        navigateToFilesSection()
        Task { await environment.ingestionViewModel.selectFile(fileId: notification.fileId, forceRefresh: true) }
    }

    private func navigateToFilesSection() {
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
