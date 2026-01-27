import SwiftUI

extension ContentView {
    func phoneTabView(for section: AppSection) -> some View {
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

    var phoneSections: [AppSection] {
        [.notes, .tasks, .websites, .files, .chat]
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

    func detailViewDefinition(for section: AppSection?) -> AnyView {
        guard let section else {
            return AnyView(WelcomeEmptyView())
        }
        return sectionDefinition(for: section).detailView()
    }

    func sectionDefinition(for section: AppSection) -> SectionDefinition {
        switch section {
        case .chat:
            return chatSectionDefinition
        case .notes:
            return notesSectionDefinition
        case .files:
            return filesSectionDefinition
        case .websites:
            return websitesSectionDefinition
        case .settings:
            return settingsSectionDefinition
        case .tasks:
            return tasksSectionDefinition
        }
    }

    private var chatSectionDefinition: SectionDefinition {
        SectionDefinition(
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
    }

    private var notesSectionDefinition: SectionDefinition {
        SectionDefinition(
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
                    get: { environment.tasksViewModel.phoneDetailRouteId.map(PhoneDetailRoute.init) },
                    set: { route in
                        guard route == nil else { return }
                        environment.tasksViewModel.phoneDetailRouteId = nil
                    }
                )
            }
        )
    }

}
