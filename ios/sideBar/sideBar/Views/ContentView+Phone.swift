import SwiftUI

private enum PhoneChatDetailRouteID {
    static let draft = "__chat-draft__"
}

extension ContentView {
    static func shouldShowCompactPhoneMoreSettingsAvatar(isCompact: Bool) -> Bool {
        isCompact
    }

    var compactPhoneSearchDockSection: AppSection? {
        guard isCompact else { return nil }
        guard isPhoneIdiom else { return nil }
        return compactWorkspaceSection
    }

    func phoneTabView(for section: AppSection) -> some View {
        NavigationStack {
            phoneSectionContentView(for: section)
        }
    }

    var phoneSections: [AppSection] {
        AppSection.primaryNavigationSections
    }

    var compactPhoneMoreView: some View {
        NavigationStack(path: $compactPhoneMoreNavigationPath) {
            CompactPhoneRootSafeAreaView(
                backgroundColor: Self.compactPhoneMoreRootTopSafeAreaStyle().color
            ) {
                CompactPhoneMoreRootView(
                    sections: Self.compactPhoneOverflowSections,
                    iconName: phoneIconName(for:)
                )
            }
            .navigationDestination(for: AppSection.self) { section in
                phoneMoreDestinationContentView(for: section)
            }
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(Self.compactPhoneMoreRootTopSafeAreaStyle().color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
    }

    func phoneIconName(for section: AppSection) -> String {
        switch section {
        case .notes:
            return "text.document"
        case .tasks:
            return "checkmark.square"
        case .websites:
            return "globe"
        case .files:
            return "folder"
        case .skillsStore:
            return "command.circle"
        case .chat:
            return "bubble"
        default:
            return "square.grid.2x2"
        }
    }

    @ViewBuilder
    func phonePanelView(for section: AppSection) -> some View {
        switch section {
        case .chat:
            ConversationsPanel(searchQuery: $compactPhoneChatSearchQuery)
        default:
            sectionDefinition(for: section).panelView()
        }
    }

    @ViewBuilder
    func phoneSectionContentView(for section: AppSection) -> some View {
        phoneRootPanelView(for: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: phoneDetailItemBinding(for: section)) { _ in
                detailView(for: workspaceCompactDetailDescriptor(for: section))
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
    }

    @ViewBuilder
    func phoneMoreDestinationContentView(for section: AppSection) -> some View {
        let backgroundStyle = Self.compactPhoneMoreDestinationBackgroundStyle(for: section)

        if Self.compactPhoneMoreDestinationUsesDedicatedScaffold(for: section) {
            CompactPhoneMoreDestinationScaffold(
                title: section.title,
                backgroundColor: backgroundStyle.color,
                onBack: popCompactPhoneMoreDestination
            ) {
                phoneMoreDestinationBodyView(for: section)
            }
            .onAppear {
                phoneSelection = section
            }
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: phoneDetailItemBinding(for: section)) { _ in
                detailView(for: workspaceCompactDetailDescriptor(for: section))
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                #endif
            }
        } else {
            let navigationBarAppearanceStyle = Self.compactPhoneMoreDestinationNavigationBarAppearanceStyle(for: section)

            phoneMorePanelView(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    backgroundStyle.color
                        .ignoresSafeArea()
                }
                .navigationTitle(section.title)
                .onAppear {
                    phoneSelection = section
                }
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(backgroundStyle.color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .background(
                    CompactPhoneNavBarAppearanceConfigurator(
                        backgroundColor: navigationBarAppearanceStyle.backgroundStyle.color,
                        isOpaque: navigationBarAppearanceStyle.isOpaque
                    )
                )
                #endif
                .navigationDestination(item: phoneDetailItemBinding(for: section)) { _ in
                    detailView(for: workspaceCompactDetailDescriptor(for: section))
                    #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                }
        }
    }

    func phoneDetailItemBinding(for section: AppSection) -> Binding<PhoneDetailRoute?> {
        sectionDefinition(for: section).phoneSelection()
    }

    func workspaceCompactDetailDescriptor(for section: AppSection) -> WorkspaceContentDescriptor {
        compactDetailDescriptor(for: section)
    }

    func detailViewDefinition(for section: AppSection?) -> AnyView {
        workspaceBuiltInSectionRegistry.detailView(for: section)
    }

    func sectionDefinition(for section: AppSection) -> SectionDefinition {
        workspaceBuiltInSectionRegistry.definition(for: section)
            ?? settingsSectionDefinition
    }

    var workspaceBuiltInSectionRegistry: WorkspaceBuiltInSectionRegistry {
        WorkspaceBuiltInSectionRegistry(
            definitions: [
                .chat: chatSectionDefinition,
                .notes: notesSectionDefinition,
                .files: filesSectionDefinition,
                .websites: websitesSectionDefinition,
                .skillsStore: skillsStoreSectionDefinition,
                .settings: settingsSectionDefinition,
                .tasks: tasksSectionDefinition
            ]
        )
    }

    private var chatSectionDefinition: SectionDefinition {
        SectionDefinition(
            section: .chat,
            panelView: { AnyView(ConversationsPanel()) },
            detailView: { AnyView(ChatView()) },
            phoneSelection: {
                Binding(
                    get: {
                        if let selectedConversationId = environment.chatViewModel.selectedConversationId {
                            return PhoneDetailRoute(id: selectedConversationId)
                        }
                        if environment.chatViewModel.isDraftConversationActive {
                            return PhoneDetailRoute(id: PhoneChatDetailRouteID.draft)
                        }
                        return nil
                    },
                    set: { route in
                        guard route == nil else { return }
                        Task { await environment.chatViewModel.selectConversation(id: nil) }
                    }
                )
            }
        )
    }

    private var notesSectionDefinition: SectionDefinition {
        SectionDefinition(
            section: .notes,
            panelView: { AnyView(NotesPanel()) },
            detailView: { AnyView(NotesView()) },
            phoneSelection: {
                Binding(
                    get: { environment.notesPhoneDetailRouteId.map(PhoneDetailRoute.init) },
                    set: { route in
                        guard route == nil else { return }
                        environment.notesPhoneDetailRouteId = nil
                        Task {
                            await environment.notesRuntime.editorViewModel.saveIfNeeded()
                            environment.notesRuntime.viewModel.clearSelection()
                        }
                    }
                )
            }
        )
    }

    private var filesSectionDefinition: SectionDefinition {
        SectionDefinition(
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
    }

    private var websitesSectionDefinition: SectionDefinition {
        SectionDefinition(
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
    }

    private var settingsSectionDefinition: SectionDefinition {
        SectionDefinition(
            section: .settings,
            panelView: { AnyView(SettingsView()) },
            detailView: { AnyView(SettingsView()) },
            phoneSelection: { Binding(get: { nil }, set: { _ in }) }
        )
    }

    private var tasksSectionDefinition: SectionDefinition {
        SectionDefinition(
            section: .tasks,
            panelView: { AnyView(TasksPanel()) },
            detailView: { AnyView(TasksView()) },
            phoneSelection: {
                Binding(
                    get: { environment.tasksPhoneDetailRouteId.map(PhoneDetailRoute.init) },
                    set: { route in
                        guard route == nil else { return }
                        environment.tasksPhoneDetailRouteId = nil
                    }
                )
            }
        )
    }

    private var skillsStoreSectionDefinition: SectionDefinition {
        SectionDefinition(
            section: .skillsStore,
            panelView: { AnyView(SkillsStorePanel()) },
            detailView: { AnyView(SkillsStoreView()) },
            phoneSelection: { Binding(get: { nil }, set: { _ in }) }
        )
    }

    @ViewBuilder
    private func phoneRootPanelView(for section: AppSection) -> some View {
        let panelView = phonePanelView(for: section)

        if isCompact && isPhoneIdiom {
            CompactPhoneRootSafeAreaView(
                backgroundColor: Self.compactPhoneRootTopSafeAreaStyle(for: section).color
            ) {
                panelView
            }
        } else {
            panelView
        }
    }

    @ViewBuilder
    private func phoneMorePanelView(for section: AppSection) -> some View {
        phoneRootPanelView(for: section)
    }

    @ViewBuilder
    private func phoneMoreDestinationBodyView(for section: AppSection) -> some View {
        switch section {
        case .files:
            FilesPanel(showsHeader: false)
        case .skillsStore:
            SkillsStoreView(searchQuery: $compactPhoneSkillsStoreSearchQuery)
        case .chat, .notes, .tasks, .websites, .settings:
            phoneMorePanelView(for: section)
        }
    }

    private func popCompactPhoneMoreDestination() {
        guard !compactPhoneMoreNavigationPath.isEmpty else { return }
        compactPhoneMoreNavigationPath.removeLast()
    }

}

struct CompactPhoneRootSafeAreaView<Content: View>: View {
    let backgroundColor: Color
    let content: Content

    init(
        backgroundColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(backgroundColor)
                        .frame(height: proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct CompactPhoneMoreRootView: View {
    let sections: [AppSection]
    let iconName: (AppSection) -> String
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "More") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if shouldShowSettingsAvatar {
                        SettingsAvatarButton()
                    }
                }
                .frame(height: 28)
            }

            List {
                ForEach(sections, id: \.self) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: iconName(section))
                            .appFont(.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                }
            }
            .sidebarPanelListStyle()
            .scrollContentBackground(.hidden)
            .background(ContentView.compactPhoneMoreRootBackgroundStyle().color)
        }
        .background(ContentView.compactPhoneMoreRootBackgroundStyle().color)
    }

    private var shouldShowSettingsAvatar: Bool {
        #if os(macOS)
        return false
        #else
        return ContentView.shouldShowCompactPhoneMoreSettingsAvatar(
            isCompact: horizontalSizeClass == .compact
        )
        #endif
    }
}
