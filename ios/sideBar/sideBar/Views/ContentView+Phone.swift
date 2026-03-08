import SwiftUI

private enum PhoneChatDetailRouteID {
    static let draft = "__chat-draft__"
}

extension ContentView {
    func phoneTabView(for section: AppSection) -> some View {
        NavigationStack {
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
    }

    var phoneSections: [AppSection] {
        AppSection.primaryNavigationSections
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
        sectionDefinition(for: section).panelView()
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
                    get: { environment.notesRuntime.viewModel.selectedNoteId.map(PhoneDetailRoute.init) },
                    set: { route in
                        guard route == nil else { return }
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

}

private struct CompactPhoneRootSafeAreaView<Content: View>: View {
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
