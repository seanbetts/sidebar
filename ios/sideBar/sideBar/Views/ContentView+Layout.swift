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
        return WorkspaceLayout(
            selection: $sidebarSelection,
            isLeftPanelExpanded: $isLeftPanelExpanded,
            isRightSidebarCollapsed: $isWorkspaceExpanded,
            shouldAnimateSidebar: hasCompletedInitialSetup,
            onShowSettings: { isSettingsPresented = true },
            leftPanelContent: workspacePanelView(for:),
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
                    detailView(for: primaryWorkspaceDescriptor)
                        .environment(\.workspaceColumn, .primary)
                )
            },
            rightSidebar: {
                AnyView(
                    detailView(for: secondaryWorkspaceDescriptor)
                        .environment(\.workspaceColumn, .secondary)
                )
            }
        )
    }

    var compactView: some View {
        TabView(selection: compactPhoneTabSelectionBinding()) {
            if isPhoneIdiom {
                ForEach(compactPhoneTabs, id: \.self) { tab in
                    Group {
                        switch tab {
                        case .section(let section):
                            phoneTabView(for: section)
                        case .more:
                            compactPhoneMoreView
                        }
                    }
                    .tag(tab)
                    .tabItem {
                        Label {
                            Text(compactPhoneTabTitle(for: tab))
                        } icon: {
                            Image(systemName: compactPhoneTabIconName(for: tab))
                                .symbolVariant(.none)
                        }
                    }
                }
            } else {
                ForEach(phoneSections, id: \.self) { section in
                    phoneTabView(for: section)
                        .tag(CompactPhoneTab.section(section))
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
        }
        .tint(tabBarTint)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowPhoneFloatingActionDock {
                HStack {
                    Spacer(minLength: 0)
                    phoneFloatingActionDock
                        .padding(.trailing, DesignTokens.Spacing.lg)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        Self.shouldDisplayPhoneFloatingActionDock(
            isPhoneIdiom: UIDevice.current.userInterfaceIdiom == .phone,
            isPhonePanelListVisible: isPhonePanelListVisible,
            phoneSelection: compactWorkspaceSection,
            isCompactPhoneMoreRootVisible: isCompactPhoneMoreRootVisible
        )
        #else
        false
        #endif
    }

    @ViewBuilder
    private var phoneFloatingActionDock: some View {
        switch compactWorkspaceSection {
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
                if isPhonePanelListVisible {
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
                            .appFont(.labelMd)
                            .frame(
                                width: PhoneFloatingActionMetrics.buttonSize,
                                height: PhoneFloatingActionMetrics.buttonSize
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                } else {
                    PhoneFloatingActionButton(
                        systemName: "plus",
                        accessibilityLabel: "New task"
                    ) {
                        environment.tasksViewModel.startNewTask()
                    }
                }
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
        case .skillsStore:
            EmptyView()
        }
    }

    func detailView(for section: AppSection?) -> some View {
        detailViewDefinition(for: section)
            .trackShortcutFocus(section: section)
    }

    func detailView(for descriptor: WorkspaceContentDescriptor) -> some View {
        workspaceRendererRegistry.render(descriptor)
    }

    func workspacePanelView(for section: AppSection?) -> AnyView {
        workspaceBuiltInSectionRegistry.panelView(for: section)
    }

    var workspaceRendererRegistry: WorkspaceRendererRegistry {
        WorkspaceRendererRegistry(
            emptyRenderer: {
                AnyView(WelcomeEmptyView().trackShortcutFocus(section: nil))
            },
            builtInRenderer: { section in
                AnyView(detailView(for: section))
            },
            agentSurfaceRenderer: { surface in
                return AnyView(
                    AgentWorkspaceSurfaceView(surface: surface)
                    .trackShortcutFocus(section: nil)
                )
            }
        )
    }

    func swapPrimaryAndSecondary() {
        let performSwap = {
            environment.workspaceStore.dispatch(
                .swapPanes,
                source: "content_view_swap_panes"
            )
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
        sidebarSelection = section
        environment.workspaceStore.dispatch(
            .selectSection(section),
            source: "content_non_chat_selection"
        )
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
