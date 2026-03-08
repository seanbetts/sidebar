import SwiftUI

enum CompactPhoneSearchDockSearchPresentation: Equatable {
    case collapsedIcon
    case expandedField
}

enum CompactPhoneSearchDockActionPresentation: Equatable {
    case none
    case buttons
    case collapsedMenu
}

struct CompactPhoneSearchDockDisplayModel: Equatable {
    let searchPresentation: CompactPhoneSearchDockSearchPresentation
    let actionPresentation: CompactPhoneSearchDockActionPresentation
}

struct CompactPhoneSearchDockDescriptor: Equatable {
    let placeholder: String
}

private struct CompactPhoneSearchDockView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let section: AppSection
    let searchText: Binding<String>
    let placeholder: String
    let actionCount: Int
    let actionContent: (CompactPhoneSearchDockActionPresentation) -> AnyView

    @FocusState private var isSearchFocused: Bool

    private var displayModel: CompactPhoneSearchDockDisplayModel {
        ContentView.makeCompactPhoneSearchDockDisplayModel(
            searchText: searchText.wrappedValue,
            isSearchFocused: isSearchFocused,
            actionCount: actionCount
        )
    }

    var body: some View {
        PhoneFloatingActionDock {
            HStack(spacing: PhoneFloatingActionMetrics.contentSpacing) {
                searchContent
                    .frame(maxWidth: displayModel.searchPresentation == .expandedField ? .infinity : nil)

                if displayModel.actionPresentation != .none {
                    PhoneFloatingActionDivider()
                    actionContent(displayModel.actionPresentation)
                }
            }
        }
        .frame(
            maxWidth: displayModel.searchPresentation == .expandedField
                ? PhoneFloatingActionMetrics.expandedDockMaxWidth
                : nil
        )
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == section else { return }
            guard event.action == .focusSearch else { return }
            isSearchFocused = true
        }
        .animation(.easeInOut(duration: DesignTokens.Animation.standard), value: displayModel)
    }

    @ViewBuilder
    private var searchContent: some View {
        switch displayModel.searchPresentation {
        case .collapsedIcon:
            Button {
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .appFont(.labelMd)
                    .frame(
                        width: PhoneFloatingActionMetrics.buttonSize,
                        height: PhoneFloatingActionMetrics.buttonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
        case .expandedField:
            SearchField(
                text: searchText,
                placeholder: placeholder,
                isFocused: $isSearchFocused,
                chrome: .dock
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ContentView {
    static func compactPhoneSearchDockDescriptor(
        for section: AppSection
    ) -> CompactPhoneSearchDockDescriptor? {
        switch section {
        case .chat:
            CompactPhoneSearchDockDescriptor(placeholder: "Search chats")
        case .notes:
            CompactPhoneSearchDockDescriptor(placeholder: "Search notes")
        case .tasks:
            CompactPhoneSearchDockDescriptor(placeholder: "Search tasks")
        case .websites:
            CompactPhoneSearchDockDescriptor(placeholder: "Search websites")
        case .files:
            CompactPhoneSearchDockDescriptor(placeholder: "Search files")
        case .skillsStore:
            CompactPhoneSearchDockDescriptor(placeholder: "Search skills")
        case .settings:
            nil
        }
    }

    static func shouldShowCompactPhoneInlineSearch(
        isCompact: Bool,
        isPhoneIdiom: Bool
    ) -> Bool {
        !(isCompact && isPhoneIdiom)
    }

    static func makeCompactPhoneSearchDockDisplayModel(
        searchText: String,
        isSearchFocused: Bool,
        actionCount: Int
    ) -> CompactPhoneSearchDockDisplayModel {
        let isExpanded = isCompactPhoneSearchDockExpanded(
            searchText: searchText,
            isSearchFocused: isSearchFocused
        )

        let actionPresentation: CompactPhoneSearchDockActionPresentation
        if actionCount <= 0 {
            actionPresentation = .none
        } else if shouldCollapseCompactPhoneSearchDockActions(
            actionCount: actionCount,
            isSearchExpanded: isExpanded
        ) {
            actionPresentation = .collapsedMenu
        } else {
            actionPresentation = .buttons
        }

        return CompactPhoneSearchDockDisplayModel(
            searchPresentation: isExpanded ? .expandedField : .collapsedIcon,
            actionPresentation: actionPresentation
        )
    }

    var compactPhoneSearchDockDescriptor: CompactPhoneSearchDockDescriptor? {
        Self.compactPhoneSearchDockDescriptor(for: compactWorkspaceSection)
    }

    var compactPhoneSearchDockActionCount: Int {
        switch compactWorkspaceSection {
        case .chat, .websites:
            1
        case .notes, .files:
            2
        case .tasks:
            isPhonePanelListVisible ? 3 : 1
        case .skillsStore, .settings:
            0
        }
    }

    var compactPhoneSearchDockSearchText: Binding<String> {
        switch compactWorkspaceSection {
        case .chat:
            $compactPhoneChatSearchQuery
        case .notes:
            Binding(
                get: { environment.notesRuntime.viewModel.searchQuery },
                set: { environment.notesRuntime.viewModel.searchQuery = $0 }
            )
        case .tasks:
            Binding(
                get: { environment.tasksViewModel.searchQuery },
                set: { environment.tasksViewModel.updateSearch(query: $0) }
            )
        case .websites:
            Binding(
                get: { environment.websitesViewModel.panelSearchQuery },
                set: { environment.websitesViewModel.panelSearchQuery = $0 }
            )
        case .files:
            Binding(
                get: { environment.ingestionViewModel.panelSearchQuery },
                set: { environment.ingestionViewModel.panelSearchQuery = $0 }
            )
        case .skillsStore:
            $compactPhoneSkillsStoreSearchQuery
        case .settings:
            .constant("")
        }
    }

    var compactPhoneSearchDock: some View {
        CompactPhoneSearchDockView(
            section: compactWorkspaceSection,
            searchText: compactPhoneSearchDockSearchText,
            placeholder: compactPhoneSearchDockDescriptor?.placeholder ?? "Search",
            actionCount: compactPhoneSearchDockActionCount,
            actionContent: compactPhoneSearchDockActionView(for:)
        )
    }

    func compactPhoneSearchDockActionView(
        for presentation: CompactPhoneSearchDockActionPresentation
    ) -> AnyView {
        switch compactWorkspaceSection {
        case .notes:
            return AnyView(notesCompactPhoneSearchDockActions(presentation: presentation))
        case .tasks:
            return AnyView(tasksCompactPhoneSearchDockActions(presentation: presentation))
        case .websites:
            return AnyView(
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "Add website"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            )
        case .files:
            return AnyView(filesCompactPhoneSearchDockActions(presentation: presentation))
        case .chat:
            return AnyView(
                PhoneFloatingActionButton(
                    systemName: "plus",
                    accessibilityLabel: "New chat"
                ) {
                    environment.emitShortcutAction(.newItem)
                }
            )
        case .skillsStore, .settings:
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private func notesCompactPhoneSearchDockActions(
        presentation: CompactPhoneSearchDockActionPresentation
    ) -> some View {
        switch presentation {
        case .collapsedMenu:
            Menu {
                Button {
                    environment.emitShortcutAction(.createFolder)
                } label: {
                    Label("Add folder", systemImage: "folder")
                }
                Button {
                    environment.emitShortcutAction(.newItem)
                } label: {
                    Label("Add note", systemImage: "plus")
                }
            } label: {
                compactPhoneSearchDockMenuLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        case .buttons:
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
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func tasksCompactPhoneSearchDockActions(
        presentation: CompactPhoneSearchDockActionPresentation
    ) -> some View {
        switch presentation {
        case .collapsedMenu, .buttons:
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
                compactPhoneSearchDockMenuLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func filesCompactPhoneSearchDockActions(
        presentation: CompactPhoneSearchDockActionPresentation
    ) -> some View {
        switch presentation {
        case .collapsedMenu:
            Menu {
                Button {
                    environment.emitShortcutAction(.addYouTubeVideo)
                } label: {
                    Label("Add YouTube video", systemImage: "play.rectangle")
                }
                Button {
                    environment.emitShortcutAction(.newItem)
                } label: {
                    Label("Add file", systemImage: "plus")
                }
            } label: {
                compactPhoneSearchDockMenuLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        case .buttons:
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
        case .none:
            EmptyView()
        }
    }

    private var compactPhoneSearchDockMenuLabel: some View {
        Image(systemName: "plus")
            .appFont(.labelMd)
            .frame(
                width: PhoneFloatingActionMetrics.buttonSize,
                height: PhoneFloatingActionMetrics.buttonSize
            )
            .contentShape(Rectangle())
    }
}
