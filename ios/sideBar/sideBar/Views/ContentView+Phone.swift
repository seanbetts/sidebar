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

}
