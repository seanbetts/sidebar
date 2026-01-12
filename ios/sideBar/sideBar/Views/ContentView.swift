import SwiftUI

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

    public init() {
    }

    public var body: some View {
        if let configError = environment.configError {
            ConfigErrorView(error: configError)
        } else if !environment.isAuthenticated {
            LoginView()
        } else {
            Group {
                if biometricUnlockEnabled && !isBiometricUnlocked {
                    BiometricLockView(
                        onUnlock: { isBiometricUnlocked = true },
                        onSignOut: {
                            Task {
                                await environment.container.authSession.signOut()
                                environment.refreshAuthState()
                            }
                        }
                    )
                } else {
                    GeometryReader { proxy in
                        mainView
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(DesignTokens.Colors.background)
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
            #if os(iOS)
            .background(
                KeyboardShortcutHandler()
                    .environmentObject(environment)
                    .frame(width: 0, height: 0)
            )
            #endif
            .onChange(of: scenePhase) { _, newValue in
                if newValue != .active && biometricUnlockEnabled {
                    isBiometricUnlocked = false
                }
            }
            .onChange(of: phoneSelection) { _, newValue in
                sidebarSelection = newValue
                primarySection = newValue
                Task { await loadPhoneSectionIfNeeded(newValue) }
            }
            .onReceive(environment.notesViewModel.$selectedNoteId) { newValue in
                guard newValue != nil else { return }
                handleNonChatSelection(.notes)
            }
            .onReceive(environment.ingestionViewModel.$selectedFileId) { newValue in
                guard newValue != nil else { return }
                handleNonChatSelection(.files)
            }
            .onReceive(environment.websitesViewModel.$active) { newValue in
                guard newValue != nil else { return }
                handleNonChatSelection(.websites)
            }
            .onChange(of: environment.commandSelection) { _, newValue in
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
            }
            .onChange(of: environment.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    if biometricUnlockEnabled {
                        isBiometricUnlocked = false
                    } else {
                        isBiometricUnlocked = true
                    }
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
            }
            .onChange(of: biometricUnlockEnabled) { _, isEnabled in
                isBiometricUnlocked = !isEnabled
            }
            .onChange(of: environment.settingsViewModel.settings?.location) { _, _ in
                Task {
                    await refreshWeatherIfPossible()
                }
            }
            .task {
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
            }
            #if !os(macOS)
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
                    .environmentObject(environment)
            }
            #endif
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

    private var splitView: some View {
        WorkspaceLayout(
            selection: $sidebarSelection,
            isLeftPanelExpanded: $isLeftPanelExpanded,
            onShowSettings: { isSettingsPresented = true },
            header: {
                SiteHeaderBar(
                    onSwapContent: swapPrimaryAndSecondary,
                    onShowSettings: { isSettingsPresented = true }
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
                cache: environment.container.cacheClient
            )
        }
    }

    private func detailView(for section: AppSection?) -> some View {
        SectionDetailView(section: section)
    }

    private func swapPrimaryAndSecondary() {
        let temp = primarySection
        primarySection = secondarySection
        secondarySection = temp
        if primarySection != .chat, let primarySection {
            lastNonChatSection = primarySection
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

    private func phoneTabView(for section: AppSection) -> some View {
        NavigationStack {
            phonePanelView(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                #if !os(macOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(item: phoneDetailItemBinding(for: section)) { _ in
                    detailView(for: section)
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
        switch section {
        case .chat:
            ConversationsPanel()
        case .notes:
            NotesPanel()
        case .tasks:
            TasksPanel()
        case .files:
            FilesPanel()
        case .websites:
            WebsitesPanel()
        case .settings:
            SettingsView()
        }
    }

    private func phoneDetailItemBinding(for section: AppSection) -> Binding<PhoneDetailRoute?> {
        switch section {
        case .chat:
            return Binding(
                get: { environment.chatViewModel.selectedConversationId.map(PhoneDetailRoute.init) },
                set: { route in
                    guard route == nil else { return }
                    Task { await environment.chatViewModel.selectConversation(id: nil) }
                }
            )
        case .notes:
            return Binding(
                get: { environment.notesViewModel.selectedNoteId.map(PhoneDetailRoute.init) },
                set: { route in
                    guard route == nil else { return }
                    environment.notesViewModel.clearSelection()
                }
            )
        case .files:
            return Binding(
                get: { environment.ingestionViewModel.selectedFileId.map(PhoneDetailRoute.init) },
                set: { route in
                    guard route == nil else { return }
                    environment.ingestionViewModel.clearSelection()
                }
            )
        case .websites:
            return Binding(
                get: { environment.websitesViewModel.selectedWebsiteId.map(PhoneDetailRoute.init) },
                set: { route in
                    guard route == nil else { return }
                    environment.websitesViewModel.clearSelection()
                }
            )
        case .tasks, .settings:
            return Binding(get: { nil }, set: { _ in })
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

public struct SectionDetailView: View {
    public let section: AppSection?

    public init(section: AppSection?) {
        self.section = section
    }

    public var body: some View {
        // TODO: Swap placeholders for native views per platform conventions.
        switch section {
        case .chat:
            ChatView()
        case .notes:
            NotesView()
        case .files:
            FilesView()
        case .websites:
            WebsitesView()
        case .settings:
            SettingsView()
        case .tasks:
            TasksView()
        case .none:
            WelcomeEmptyView()
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

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        VStack {
            Text(title)
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
