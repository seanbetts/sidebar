import SwiftUI
#if os(iOS)
import UIKit
#endif

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
            isRightSidebarCollapsed: $isWorkspaceExpanded,
            shouldAnimateSidebar: hasCompletedInitialSetup,
            onShowSettings: { isSettingsPresented = true },
            header: {
                SiteHeaderBar(
                    onSwapContent: swapPrimaryAndSecondary,
                    onShowSettings: { isSettingsPresented = true },
                    isLeftPanelExpanded: isLeftPanelExpanded,
                    shouldAnimateSidebar: hasCompletedInitialSetup
                )
            },
            mainContent: {
                AnyView(
                    detailView(for: primarySection)
                        .environment(\.workspaceColumn, .primary)
                )
            },
            rightSidebar: {
                AnyView(
                    detailView(for: secondarySection)
                        .environment(\.workspaceColumn, .secondary)
                )
            }
        )
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
            if shouldShowPhoneFloatingActionDock {
                phoneFloatingActionDock
                    .padding(.trailing, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeInOut(duration: DesignTokens.Animation.standard),
            value: phoneSelection
        )
        .sheet(isPresented: $isPhoneScratchpadPresented) {
            ScratchpadPopoverView(
                api: environment.container.scratchpadAPI,
                cache: environment.container.cacheClient,
                scratchpadStore: environment.scratchpadStore
            )
            .phoneSheetGrabBarVisible()
        }
    }

    private var shouldShowPhoneFloatingActionDock: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    @ViewBuilder
    private var phoneFloatingActionDock: some View {
        switch phoneSelection {
        case .notes:
            PhoneFloatingActionDock {
                PhoneFloatingActionButton(
                    systemName: "folder",
                    accessibilityLabel: "Add folder"
                ) {
                    environment.emitShortcutAction(.createFolder)
                }
                PhoneFloatingActionDivider()
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "Add note"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            }
        case .tasks:
            PhoneFloatingActionDock {
                Menu {
                    Button {
                        environment.emitShortcutAction(.newItem)
                    } label: {
                        Label("New task", systemImage: "checkmark.circle")
                    }
                    Button {
                        environment.emitShortcutAction(.createTaskGroup)
                    } label: {
                        Label("New group", systemImage: "folder")
                    }
                    Button {
                        environment.emitShortcutAction(.createTaskProject)
                    } label: {
                        Label("New project", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(DesignTokens.Typography.labelMd)
                        .frame(width: DesignTokens.Size.touchTarget, height: DesignTokens.Size.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
            }
        case .websites:
            PhoneFloatingActionDock {
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "Add website"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            }
        case .files:
            PhoneFloatingActionDock {
                PhoneFloatingActionButton(
                    systemName: "play.rectangle",
                    accessibilityLabel: "Add YouTube video"
                ) {
                    environment.emitShortcutAction(.addYouTubeVideo)
                }
                PhoneFloatingActionDivider()
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "Add file"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            }
        case .chat:
            PhoneFloatingActionDock {
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "New chat"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            }
        case .settings:
            EmptyView()
        }
    }

    func detailView(for section: AppSection?) -> some View {
        detailViewDefinition(for: section)
            .trackShortcutFocus(section: section)
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
