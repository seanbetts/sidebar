import SwiftUI
import LocalAuthentication

public enum AppSection: String, CaseIterable, Identifiable {
    case chat
    case notes
    case files
    case websites
    case settings
    case tasks

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sidebarSelection: AppSection? = nil
    @State private var primarySection: AppSection? = nil
    @State private var secondarySection: AppSection? = .chat
    @State private var lastNonChatSection: AppSection? = nil
    @AppStorage(AppStorageKeys.leftPanelExpanded) private var isLeftPanelExpanded: Bool = true
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled: Bool = false
    @State private var isSettingsPresented = false
    @State private var phoneSelection: AppSection = .chat
    @State private var isPhoneScratchpadPresented = false
    @State private var didSetInitialSelection = false
    @State private var didLoadSettings = false
    @State private var isBiometricUnlocked = false
    @State private var activeAlert: ActiveAlert?
    @State private var pendingSessionExpiryAlert = false
    @State private var pendingBiometricUnavailableAlert = false
    @State private var isSigningOut = false
    @State private var pendingReadyFileNotification: ReadyFileNotification?
    #if os(iOS)
    @AppStorage(AppStorageKeys.hasShownBiometricHint) private var hasShownBiometricHint = false
    #endif

    public init() {
    }

    public var body: some View {
        if let configError = environment.configError {
            ConfigErrorView(error: configError)
        } else if !environment.isAuthenticated {
            LoginView()
        } else {
            signedInContent
        }
    }

    private var signedInContent: AnyView {
        var content: AnyView = AnyView(
            SignedInContentView(
                biometricUnlockEnabled: biometricUnlockEnabled,
                isBiometricUnlocked: $isBiometricUnlocked,
                topSafeAreaBackground: topSafeAreaBackground,
                onSignOut: { Task { await environment.beginSignOut() } },
                mainView: { mainView }
            )
        )
        #if os(iOS)
        content = AnyView(
            content.background(
                KeyboardShortcutHandler()
                    .environmentObject(environment)
                    .frame(width: 0, height: 0)
            )
        )
        #endif
        content = AnyView(content.overlay(alignment: .top) {
            if let toast = environment.toastCenter.toast {
                ToastBanner(toast: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        environment.toastCenter.dismiss()
                    }
            }
        })
        content = AnyView(content.animation(.easeOut(duration: 0.2), value: environment.toastCenter.toast))
        content = AnyView(content.onChange(of: scenePhase) { _, newValue in
            if newValue == .background && biometricUnlockEnabled {
                isBiometricUnlocked = false
            }
        })
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
        })
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
        })
        content = AnyView(content.onChange(of: environment.isAuthenticated) { _, isAuthenticated in
            activeAlert = nil
            pendingSessionExpiryAlert = false
            pendingBiometricUnavailableAlert = false
            environment.sessionExpiryWarning = nil
            isSigningOut = false
            if isAuthenticated {
                if biometricUnlockEnabled {
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
                    message: Text("Biometric unlock is no longer available on this device. You can re-enable it in Settings once Face ID or Touch ID is available again."),
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

    private var biometricHintTitle: String {
        switch environment.biometricMonitor.biometryType {
        case .touchID:
            return "Enable Touch ID?"
        default:
            return "Enable Face ID?"
        }
    }

    private var biometricHintMessage: String {
        switch environment.biometricMonitor.biometryType {
        case .touchID:
            return "Unlock sideBar quickly and securely with Touch ID."
        default:
            return "Unlock sideBar quickly and securely with Face ID."
        }
    }

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
            onShowSettings: { isSettingsPresented = true },
            header: {
                SiteHeaderBar(
                    onSwapContent: swapPrimaryAndSecondary,
                    onShowSettings: { isSettingsPresented = true },
                    isLeftPanelExpanded: isLeftPanelExpanded
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
            Task { await environment.ingestionViewModel.selectFile(fileId: notification.fileId) }
            return
        }
        presentAlert(.fileReady(notification))
    }

    private func openReadyFile(_ notification: ReadyFileNotification) {
        navigateToFilesSection()
        Task { await environment.ingestionViewModel.selectFile(fileId: notification.fileId) }
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

    private func phoneTabView(for section: AppSection) -> some View {
        NavigationStack {
            phonePanelView(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                #if !os(macOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(item: phoneDetailItemBinding(for: section)) { _ in
                    detailViewDefinition(for: section)
                    #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                }
        }
    }

    private var phoneSections: [AppSection] {
        [.notes, .tasks, .websites, .files, .chat]
    }

    private func phoneIconName(for section: AppSection) -> String {
        switch section {
        case .notes:
            return "text.document"
        case .tasks:
            return "checkmark.square"
        case .websites:
            return "globe"
        case .files:
            return "folder"
        case .chat:
            return "bubble"
        default:
            return "square.grid.2x2"
        }
    }

    @ViewBuilder
    private func phonePanelView(for section: AppSection) -> some View {
        sectionDefinition(for: section).panelView()
    }

    private func phoneDetailItemBinding(for section: AppSection) -> Binding<PhoneDetailRoute?> {
        sectionDefinition(for: section).phoneSelection()
    }

    private func detailViewDefinition(for section: AppSection?) -> AnyView {
        guard let section else {
            return AnyView(WelcomeEmptyView())
        }
        return sectionDefinition(for: section).detailView()
    }

    private func sectionDefinition(for section: AppSection) -> SectionDefinition {
        switch section {
        case .chat:
            return SectionDefinition(
                section: .chat,
                panelView: { AnyView(ConversationsPanel()) },
                detailView: { AnyView(ChatView()) },
                phoneSelection: {
                    Binding(
                        get: { environment.chatViewModel.selectedConversationId.map(PhoneDetailRoute.init) },
                        set: { route in
                            guard route == nil else { return }
                            Task { await environment.chatViewModel.selectConversation(id: nil) }
                        }
                    )
                }
            )
        case .notes:
            return SectionDefinition(
                section: .notes,
                panelView: { AnyView(NotesPanel()) },
                detailView: { AnyView(NotesView()) },
                phoneSelection: {
                    Binding(
                        get: { environment.notesViewModel.selectedNoteId.map(PhoneDetailRoute.init) },
                        set: { route in
                            guard route == nil else { return }
                            environment.notesViewModel.clearSelection()
                        }
                    )
                }
            )
        case .files:
            return SectionDefinition(
                section: .files,
                panelView: { AnyView(FilesPanel()) },
                detailView: { AnyView(FilesView()) },
                phoneSelection: {
                    Binding(
                        get: { environment.ingestionViewModel.selectedFileId.map(PhoneDetailRoute.init) },
                        set: { route in
                            guard route == nil else { return }
                            environment.ingestionViewModel.clearSelection()
                        }
                    )
                }
            )
        case .websites:
            return SectionDefinition(
                section: .websites,
                panelView: { AnyView(WebsitesPanel()) },
                detailView: { AnyView(WebsitesView()) },
                phoneSelection: {
                    Binding(
                        get: { environment.websitesViewModel.selectedWebsiteId.map(PhoneDetailRoute.init) },
                        set: { route in
                            guard route == nil else { return }
                            environment.websitesViewModel.clearSelection()
                        }
                    )
                }
            )
        case .settings:
            return SectionDefinition(
                section: .settings,
                panelView: { AnyView(SettingsView()) },
                detailView: { AnyView(SettingsView()) },
                phoneSelection: { Binding(get: { nil }, set: { _ in }) }
            )
        case .tasks:
            return SectionDefinition(
                section: .tasks,
                panelView: { AnyView(TasksPanel()) },
                detailView: { AnyView(TasksView()) },
                phoneSelection: { Binding(get: { nil }, set: { _ in }) }
            )
        }
    }

    private func refreshWeatherIfPossible() async {
        guard environment.isAuthenticated else { return }
        let location = environment.settingsViewModel.settings?.location?.trimmed ?? ""
        guard !location.isEmpty else { return }
        await environment.weatherViewModel.load(location: location)
    }

    private func loadPhoneSectionIfNeeded(_ section: AppSection) async {
        switch section {
        case .notes:
            await environment.notesViewModel.loadTree()
        case .websites:
            await environment.websitesViewModel.load()
        case .files:
            await environment.ingestionViewModel.load()
        case .chat:
            await environment.chatViewModel.loadConversations()
        case .tasks, .settings:
            break
        }
    }

    private var topSafeAreaBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.background
        #else
        if isCompact && isPhonePanelListVisible {
            return DesignTokens.Colors.surface
        }
        return DesignTokens.Colors.background
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isFilesSectionVisible: Bool {
        #if os(macOS)
        return primarySection == .files || secondarySection == .files
        #else
        if isCompact {
            return phoneSelection == .files
        }
        return primarySection == .files || secondarySection == .files
        #endif
    }

    private var isPhonePanelListVisible: Bool {
        guard isCompact else { return false }
        switch phoneSelection {
        case .chat:
            return environment.chatViewModel.selectedConversationId == nil
        case .notes:
            return environment.notesViewModel.selectedNoteId == nil
        case .files:
            return environment.ingestionViewModel.selectedFileId == nil
        case .websites:
            return environment.websitesViewModel.selectedWebsiteId == nil
        case .tasks, .settings:
            return true
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard !didSetInitialSelection else { return }
        didSetInitialSelection = true
#if os(iOS)
        if horizontalSizeClass == .compact {
            phoneSelection = .chat
            sidebarSelection = .chat
            primarySection = .chat
        } else {
            primarySection = nil
            secondarySection = .chat
            lastNonChatSection = nil
            isLeftPanelExpanded = false
        }
#else
        primarySection = .notes
        secondarySection = .chat
        lastNonChatSection = .notes
        sidebarSelection = .notes
        isLeftPanelExpanded = true
#endif
    }


    private var tabBarTint: Color {
        #if os(macOS)
        return Color.accentColor
        #else
        return colorScheme == .dark ? Color.white : Color.black
        #endif
    }

    private var tabAccessoryBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.surface
        #else
        return DesignTokens.Colors.surface
        #endif
    }

    private var tabAccessoryBorder: Color {
        #if os(macOS)
        return DesignTokens.Colors.border
        #else
        return DesignTokens.Colors.border
        #endif
    }

    private var separatorColor: Color {
        #if os(macOS)
        return DesignTokens.Colors.border
        #else
        return DesignTokens.Colors.border
        #endif
    }

}

private struct PhoneDetailRoute: Identifiable, Hashable {
    let id: String
}

private struct SectionDefinition {
    let section: AppSection
    let panelView: () -> AnyView
    let detailView: () -> AnyView
    let phoneSelection: () -> Binding<PhoneDetailRoute?>
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ConfigErrorView: View {
    public let error: EnvironmentConfigLoadError

    public init(error: EnvironmentConfigLoadError) {
        self.error = error
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Configuration Error")
                .font(.title2)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Check your SideBar.local.xcconfig values and rebuild.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

private enum ActiveAlert: Identifiable, Equatable {
    case biometricUnavailable
    case biometricHint
    case sessionExpiry
    case fileReady(ReadyFileNotification)

    var id: String {
        switch self {
        case .biometricUnavailable:
            return "biometricUnavailable"
        case .biometricHint:
            return "biometricHint"
        case .sessionExpiry:
            return "sessionExpiry"
        case .fileReady(let notification):
            return "fileReady-\(notification.id)"
        }
    }
}

private struct SignedInContentView<Main: View>: View {
    let biometricUnlockEnabled: Bool
    @Binding var isBiometricUnlocked: Bool
    let topSafeAreaBackground: Color
    let onSignOut: () -> Void
    let mainView: () -> Main
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if biometricUnlockEnabled && !isBiometricUnlocked {
                BiometricLockView(
                    onUnlock: { isBiometricUnlocked = true },
                    onSignOut: onSignOut
                )
            } else {
                GeometryReader { proxy in
                    mainView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DesignTokens.Colors.background)
                        .coordinateSpace(name: "appRoot")
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(topSafeAreaBackground)
                                .frame(height: proxy.safeAreaInsets.top)
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        }
                }
            }
        }
    }
}

public struct WelcomeEmptyView: View {
    public init() {
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.7)
            Text("Welcome to sideBar")
                .font(.title3.weight(.semibold))
            Text("Select a note, website, or file to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct PlaceholderView: View {
    public let title: String
    public let subtitle: String?
    public let actionTitle: String?
    public let action: (() -> Void)?
    public let iconName: String?

    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        iconName: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.iconName = iconName
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title2)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
