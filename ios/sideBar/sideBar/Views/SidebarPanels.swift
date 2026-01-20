import SwiftUI
import Foundation
import UniformTypeIdentifiers

private func panelHeaderBackground(_ colorScheme: ColorScheme) -> Color {
    #if os(macOS)
    if colorScheme == .light {
        return DesignTokens.Colors.sidebar
    }
    return DesignTokens.Colors.surface
    #else
    return DesignTokens.Colors.surface
    #endif
}

public struct ConversationsPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        ConversationsPanelView(viewModel: environment.chatViewModel)
            .task {
                await environment.chatViewModel.loadConversations()
            }
    }
}

public struct TasksPanel: View {
    public init() {
    }

    public var body: some View {
        TasksPanelView()
    }
}

private struct TasksPanelView: View {
    @State private var searchQuery: String = ""
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            SidebarPanelPlaceholder(title: "Tasks")
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Tasks") {
                HStack(spacing: 30) {
                    Button {
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add task")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search tasks")
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

}

private struct ConversationsPanelView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var renameConversationId: String? = nil
    @State private var renameValue: String = ""
    @State private var deleteConversationId: String? = nil
    @State private var deleteConversationTitle: String = ""
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                    SidebarListSkeleton(rowCount: 6, showSubtitle: true)
                } else if filteredGroups.isEmpty {
                    SidebarPanelPlaceholder(title: searchQuery.isEmpty ? "No conversations" : "No matching conversations")
                } else {
                    conversationsList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .alert("Rename chat", isPresented: isRenameDialogPresented) {
            TextField("Chat name", text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                }
            Button("Rename") {
                commitRename()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                clearRenameTarget()
            }
        }
        .alert(
            "Delete conversation",
            isPresented: isDeleteDialogPresented
        ) {
            Button("Delete", role: .destructive) {
                let targetId = deleteConversationId
                clearDeleteTarget()
                Task {
                    if let id = targetId {
                        await viewModel.deleteConversation(id: id)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                clearDeleteTarget()
            }
        } message: {
            Text(deleteDialogTitle)
        }
        .onReceive(environment.$shortcutActionEvent.compactMap { $0 }) { event in
            guard event.section == .chat else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .renameItem:
                guard let id = viewModel.selectedConversationId,
                      let conversation = viewModel.conversations.first(where: { $0.id == id }) else { return }
                beginRename(conversation)
            case .deleteItem:
                guard let id = viewModel.selectedConversationId,
                      let conversation = viewModel.conversations.first(where: { $0.id == id }) else { return }
                presentDelete(conversation)
            case .navigateList(let direction):
                navigateConversationList(direction: direction)
            default:
                break
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Chat") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if showNewChatButton {
                        Button {
                            Task {
                                await viewModel.startNewConversation()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New chat")
                    }
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
                .frame(height: 28)
            }
            SearchField(text: $searchQuery, placeholder: "Search chats", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var showNewChatButton: Bool {
        guard viewModel.selectedConversationId != nil else {
            return false
        }
        return !viewModel.isBlankConversation
    }

    private var conversationsList: some View {
        List {
            ForEach(filteredGroups) { group in
                Section(group.title) {
                    ForEach(group.conversations) { conversation in
                        SelectableRow(isSelected: viewModel.selectedConversationId == conversation.id) {
                            ConversationRow(
                                conversation: conversation,
                                isSelected: viewModel.selectedConversationId == conversation.id,
                                onRename: { beginRename(conversation) },
                                onDelete: { presentDelete(conversation) }
                            )
                        }
                        .onTapGesture {
                            Task { await viewModel.selectConversation(id: conversation.id) }
                        }
                        #if os(iOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("Rename") {
                                beginRename(conversation)
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete") {
                                presentDelete(conversation)
                            }
                            .tint(.red)
                        }
                        #endif
                    }
                }
            }
        }
        .transaction { transaction in
            if deleteConversationId != nil {
                transaction.disablesAnimations = true
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.refreshConversations()
        }
    }

    private var filteredGroups: [ConversationGroup] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return viewModel.groupedConversations
        }
        return viewModel.groupedConversations.compactMap { group in
            let filtered = group.conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(query)
            }
            guard !filtered.isEmpty else { return nil }
            return ConversationGroup(id: group.id, title: group.title, conversations: filtered)
        }
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { renameConversationId != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameTarget()
                }
            }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteConversationId != nil },
            set: { isPresented in
                if !isPresented {
                    clearDeleteTarget()
                }
            }
        )
    }

    private func beginRename(_ conversation: Conversation) {
        renameConversationId = conversation.id
        renameValue = conversation.title
    }

    private func clearRenameTarget() {
        renameConversationId = nil
        renameValue = ""
    }

    private func commitRename() {
        let targetId = renameConversationId
        let updatedTitle = renameValue
        clearRenameTarget()
        if let id = targetId {
            Task {
                await viewModel.renameConversation(id: id, title: updatedTitle)
            }
        }
    }

    private func presentDelete(_ conversation: Conversation) {
        deleteConversationId = conversation.id
        let trimmed = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteConversationTitle = trimmed.isEmpty ? "conversation" : trimmed
    }

    private func clearDeleteTarget() {
        deleteConversationId = nil
        deleteConversationTitle = ""
    }

    private var deleteDialogTitle: String {
        let truncated = truncatedDeleteTitle(deleteConversationTitle)
        return "Delete \"\(truncated)\"?"
    }

    private func truncatedDeleteTitle(_ title: String) -> String {
        let maxLength = 32
        guard title.count > maxLength else {
            return title
        }
        let index = title.index(title.startIndex, offsetBy: maxLength)
        return "\(title[..<index])..."
    }
}

private struct ConversationRow: View, Equatable {
    let conversation: Conversation
    let isSelected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void
    private let subtitleText: String

    init(
        conversation: Conversation,
        isSelected: Bool,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.conversation = conversation
        self.isSelected = isSelected
        self.onRename = onRename
        self.onDelete = onDelete
        let formattedDate = ConversationRow.formattedDate(from: conversation.updatedAt)
        let count = conversation.messageCount
        let label = count == 1 ? "1 message" : "\(count) messages"
        self.subtitleText = "\(formattedDate) | \(label)"
    }

    static func == (lhs: ConversationRow, rhs: ConversationRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.conversation.id == rhs.conversation.id &&
        lhs.conversation.title == rhs.conversation.title &&
        lhs.conversation.updatedAt == rhs.conversation.updatedAt &&
        lhs.conversation.messageCount == rhs.conversation.messageCount
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(conversation.title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? selectedSecondaryText.opacity(0.85) : secondaryTextColor)
            }
            Spacer(minLength: 0)
            #if os(macOS)
            let menu = Menu {
                Button("Rename") {
                    onRename()
                }
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .accessibilityLabel("Conversation actions")

            if #available(macOS 13.0, *) {
                menu.menuIndicator(.hidden)
            } else {
                menu
            }
            #endif
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var selectedSecondaryText: Color {
        DesignTokens.Colors.textSecondary
    }

    private var formattedDate: String {
        ConversationRow.formattedDate(from: conversation.updatedAt)
    }
    private static func formattedDate(from value: String) -> String {
        guard let date = DateParsing.parseISO8601(value) else {
            return value
        }
        return DateFormatter.chatList.string(from: date)
    }
}

private extension DateFormatter {
    static let chatList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

public struct NotesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        NotesPanelView(viewModel: environment.notesViewModel)
    }
}

private struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasLoaded = false
    @State private var isArchiveExpanded = false
    @State private var isNewNotePresented = false
    @State private var isNewFolderPresented = false
    @State private var newNoteName: String = ""
    @State private var newFolderName: String = ""
    @State private var newFolderParent: String = ""
    @State private var isCreatingNote = false
    @State private var isCreatingFolder = false
    @State private var renameTarget: FileNodeItem? = nil
    @State private var renameValue: String = ""
    @State private var deleteTarget: FileNodeItem? = nil
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            notesPanelContentWithArchive
            #else
            notesPanelContent
            #endif
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.loadTree() }
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            viewModel.updateSearch(query: newValue)
        }
        .alert("New Note", isPresented: $isNewNotePresented) {
            TextField("Note title", text: $newNoteName)
                .submitLabel(.done)
                .onSubmit {
                    createNote()
                }
            Button("Create") {
                createNote()
            }
            .disabled(isCreatingNote || newNoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                newNoteName = ""
            }
        }
        .sheet(isPresented: $isNewFolderPresented) {
            NewFolderSheet(
                name: $newFolderName,
                selectedFolder: $newFolderParent,
                options: folderOptions,
                isSaving: isCreatingFolder,
                onCreate: createFolder
            )
        }
        .alert(renameDialogTitle, isPresented: isRenameDialogPresented) {
            TextField(renameDialogPlaceholder, text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                }
            Button("Rename") {
                commitRename()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameValue = ""
            }
        }
        .alert(deleteDialogTitle, isPresented: isDeleteDialogPresented) {
            Button("Delete", role: .destructive) {
                let target = deleteTarget
                deleteTarget = nil
                Task {
                    if let target {
                        if target.isFile {
                            await viewModel.deleteNote(id: target.id)
                        } else {
                            await viewModel.deleteFolder(path: target.id)
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(deleteDialogMessage)
        }
        .onReceive(environment.$shortcutActionEvent.compactMap { $0 }) { event in
            guard event.section == .notes else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                newNoteName = ""
                isNewNotePresented = true
            case .createFolder:
                newFolderName = ""
                newFolderParent = ""
                isNewFolderPresented = true
            case .navigateList(let direction):
                navigateNotesList(direction: direction)
            default:
                break
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Notes") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newFolderName = ""
                        newFolderParent = ""
                        isNewFolderPresented = true
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add folder")
                    Button {
                        newNoteName = ""
                        isNewNotePresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add note")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $viewModel.searchQuery, placeholder: "Search notes", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var folderOptions: [NotesFolderOption] {
        NotesFolderOption.build(from: viewModel.tree?.children ?? [])
    }

    private func createNote() {
        let trimmed = newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreatingNote else { return }
        isCreatingNote = true
        // Set the flag BEFORE creating the note so it's ready when currentNoteId changes
        environment.notesEditorViewModel.requestEditingOnNextLoad()
        Task {
            let created = await viewModel.createNote(title: trimmed, folder: nil)
            await MainActor.run {
                isCreatingNote = false
                if created != nil {
                    isNewNotePresented = false
                } else {
                    // Reset flag if creation failed
                    environment.notesEditorViewModel.wantsEditingOnNextLoad = false
                }
            }
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreatingFolder else { return }
        isCreatingFolder = true
        Task {
            let destination = newFolderParent.isEmpty ? trimmed : "\(newFolderParent)/\(trimmed)"
            let created = await viewModel.createFolder(path: destination)
            await MainActor.run {
                isCreatingFolder = false
                if created {
                    isNewFolderPresented = false
                }
            }
        }
    }

    private var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                    renameValue = ""
                }
            }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    deleteTarget = nil
                }
            }
        )
    }

    private var renameDialogTitle: String {
        renameTarget?.isFile == true ? "Rename note" : "Rename folder"
    }

    private var renameDialogPlaceholder: String {
        renameTarget?.isFile == true ? "Note name" : "Folder name"
    }

    private var deleteDialogTitle: String {
        deleteTarget?.isFile == true ? "Delete note" : "Delete folder"
    }

    private var deleteDialogMessage: String {
        deleteTarget?.isFile == true
            ? "This will remove the note and cannot be undone."
            : "This will remove the folder and its contents."
    }

    private func beginRename(for item: FileNodeItem) {
        renameTarget = item
        renameValue = item.displayName
    }

    private func confirmDelete(for item: FileNodeItem) {
        deleteTarget = item
    }

    private func commitRename() {
        let target = renameTarget
        let updated = renameValue
        renameTarget = nil
        renameValue = ""
        guard let target else { return }
        Task {
            if target.isFile {
                await viewModel.renameNote(id: target.id, newName: updated)
            } else {
                await viewModel.renameFolder(path: target.id, newName: updated)
            }
        }
    }

    private func navigateNotesList(direction: ShortcutListDirection) {
        let items = noteNavigationItems()
        guard !items.isEmpty else { return }
        let currentId = viewModel.selectedNoteId
        let nextIndex: Int
        if let currentId, let index = items.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(items.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : items.count - 1
        }
        let nextId = items[nextIndex]
        Task { await viewModel.selectNote(id: nextId) }
    }

    private func noteNavigationItems() -> [String] {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return viewModel.searchResults.map { $0.path }
        }
        let pinnedIds = pinnedItems.map { $0.id }
        let mainIds = flattenNoteIds(from: mainNodes)
        return pinnedIds + mainIds
    }

    private func flattenNoteIds(from nodes: [FileNode]) -> [String] {
        var results: [String] = []
        for node in nodes {
            if node.type == .file {
                results.append(node.path)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: flattenNoteIds(from: children))
            }
        }
        return results
    }

    private var searchResultsView: some View {
        List {
            Section("Results") {
                if let error = viewModel.errorMessage,
                   !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SidebarPanelPlaceholder(
                        title: "Search failed",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        viewModel.updateSearch(query: viewModel.searchQuery)
                    }
                } else if viewModel.isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.searchResults.isEmpty {
                    Text("No matching notes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults, id: \.path) { node in
                        NotesTreeRow(
                            item: FileNodeItem(
                                id: node.path,
                                name: node.name,
                                type: node.type,
                                children: nil
                            ),
                            isSelected: viewModel.selectedNoteId == node.path
                        ) {
                            Task { await viewModel.selectNote(id: node.path) }
                        } onRename: {
                            beginRename(for: FileNodeItem(id: node.path, name: node.name, type: node.type, children: nil))
                        } onDelete: {
                            confirmDelete(for: FileNodeItem(id: node.path, name: node.name, type: node.type, children: nil))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
    }

    private func navigateConversationList(direction: ShortcutListDirection) {
        let ids = filteredGroups.flatMap { $0.conversations.map { $0.id } }
        guard !ids.isEmpty else { return }
        let currentId = viewModel.selectedConversationId
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        let nextId = ids[nextIndex]
        Task { await viewModel.selectConversation(id: nextId) }
    }

    private var notesPanelContent: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsView
            } else {
                notesTreeView
            }
        }
    }

    private var notesPanelContentWithArchive: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsView
            } else {
                VStack(spacing: 0) {
                    notesTreeListView
                    notesArchiveSection
                }
            }
        }
    }

    private func buildItems(from nodes: [FileNode]) -> [FileNodeItem] {
        nodes.map { node in
            let children = node.type == .directory ? buildItems(from: node.children ?? []) : nil
            return FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: children
            )
        }
    }

    private var notesTreeListView: some View {
        List {
            Section("Pinned") {
                if pinnedItems.isEmpty {
                    Text("No pinned notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinnedItems) { item in
                        NotesTreeRow(
                            item: item,
                            isSelected: viewModel.selectedNoteId == item.id
                        ) {
                            Task { await viewModel.selectNote(id: item.id) }
                        } onRename: {
                            beginRename(for: item)
                        } onDelete: {
                            confirmDelete(for: item)
                        }
                    }
                }
            }

            Section("Notes") {
                mainOutlineGroup
            }
#if !os(macOS)
            Section {
                DisclosureGroup(
                    isExpanded: $isArchiveExpanded,
                    content: {
                        if archivedNodes.isEmpty {
                            Text("No archived notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                                NotesTreeRow(
                                    item: item,
                                    isSelected: viewModel.selectedNoteId == item.id
                                ) {
                                    if item.isFile {
                                        Task { await viewModel.selectNote(id: item.id) }
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                            }
                            .listRowBackground(rowBackground)
                        }
                    },
                    label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                )
                .listRowBackground(rowBackground)
            }
#endif
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.loadTree()
        }
    }

    private var notesTreeView: some View {
        notesTreeListView
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var mainOutlineGroup: some View {
        OutlineGroup(buildItems(from: mainNodes), children: \.children) { item in
            NotesTreeRow(
                item: item,
                isSelected: viewModel.selectedNoteId == item.id
            ) {
                if item.isFile {
                    Task { await viewModel.selectNote(id: item.id) }
                }
            } onRename: {
                beginRename(for: item)
            } onDelete: {
                confirmDelete(for: item)
            }
        }
        .listRowBackground(rowBackground)
    }

    private var notesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if archivedNodes.isEmpty {
                        Text("No archived notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                                NotesTreeRow(
                                    item: item,
                                    isSelected: viewModel.selectedNoteId == item.id,
                                    useListStyling: false
                                ) {
                                    if item.isFile {
                                        Task { await viewModel.selectNote(id: item.id) }
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                            }
                        }
                        .frame(maxHeight: 650)
                    }
                },
                label: {
                    Label("Archive", systemImage: "archivebox")
                        .font(.subheadline)
                }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(panelBackground)
    }

    private var pinnedItems: [FileNodeItem] {
        let pinned = collectPinnedNodes(from: viewModel.tree?.children ?? [])
        let sorted = pinned.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted.map { node in
            FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: nil
            )
        }
    }

    private var mainNodes: [FileNode] {
        filterNodes(viewModel.tree?.children ?? [], includeArchived: false)
    }

    private var archivedNodes: [FileNode] {
        let nodes = filterNodes(viewModel.tree?.children ?? [], includeArchived: true)
        return normalizeArchivedNodes(nodes)
    }

    private func normalizeArchivedNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in
            if node.type == .directory, node.name.lowercased() == "archive" {
                return node.children ?? []
            }
            return [node]
        }
    }

    private func collectPinnedNodes(from nodes: [FileNode]) -> [FileNode] {
        var results: [FileNode] = []
        for node in nodes {
            if node.type == .file, node.pinned == true, node.archived != true {
                results.append(node)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: collectPinnedNodes(from: children))
            }
        }
        return results
    }

    private func filterNodes(_ nodes: [FileNode], includeArchived: Bool) -> [FileNode] {
        nodes.compactMap { node in
            if node.type == .directory {
                let children = filterNodes(node.children ?? [], includeArchived: includeArchived)
                if !includeArchived && node.name.lowercased() == "archive" {
                    return nil
                }
                return FileNode(
                    name: node.name,
                    path: node.path,
                    type: node.type,
                    size: node.size,
                    modified: node.modified,
                    children: children,
                    expanded: node.expanded,
                    pinned: node.pinned,
                    pinnedOrder: node.pinnedOrder,
                    archived: node.archived,
                    folderMarker: node.folderMarker
                )
            }
            let archived = node.archived == true
            let pinned = node.pinned == true
            if includeArchived {
                return archived ? node : nil
            }
            return (!archived && !pinned) ? node : nil
        }
    }
}

private struct NotesFolderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let depth: Int

    static func build(from nodes: [FileNode]) -> [NotesFolderOption] {
        var options: [NotesFolderOption] = [
            NotesFolderOption(id: "", label: "Notes", value: "", depth: 0)
        ]

        func walk(_ items: [FileNode], depth: Int) {
            for item in items {
                guard item.type == .directory else { continue }
                if item.name.lowercased() == "archive" { continue }
                let folderPath = item.path.replacingOccurrences(of: "folder:", with: "")
                options.append(
                    NotesFolderOption(
                        id: folderPath,
                        label: item.name,
                        value: folderPath,
                        depth: depth
                    )
                )
                if let children = item.children, !children.isEmpty {
                    walk(children, depth: depth + 1)
                }
            }
        }

        walk(nodes, depth: 1)
        return options
    }
}

private struct NewFolderSheet: View {
    @Binding var name: String
    @Binding var selectedFolder: String
    let options: [NotesFolderOption]
    let isSaving: Bool
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder") {
                    TextField("Folder name", text: $name)
                        .submitLabel(.done)
                        .onSubmit {
                            onCreate()
                        }
                        .focused($isNameFocused)
                }
                Section("Location") {
                    Picker("Location", selection: $selectedFolder) {
                        ForEach(options) { option in
                            Text(optionLabel(option))
                                .tag(option.value)
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private func optionLabel(_ option: NotesFolderOption) -> String {
        let indent = String(repeating: "  ", count: max(0, option.depth))
        return indent + option.label
    }
}

private struct NotesTreeRow: View {
    let item: FileNodeItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?
    let useListStyling: Bool

    init(
        item: FileNodeItem,
        isSelected: Bool,
        useListStyling: Bool = true,
        onSelect: @escaping () -> Void,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.useListStyling = useListStyling
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
    }

    var body: some View {
        let row = SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            verticalPadding: rowVerticalPadding,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "doc.text" : "folder")
                    .foregroundStyle(isSelected ? selectedTextColor : (item.isFile ? secondaryTextColor : primaryTextColor))
                Text(item.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
            }
        }

        Group {
            if item.isFile {
                row.onTapGesture {
                    onSelect()
                }
            } else {
                row
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onRename {
                Button("Rename") {
                    onRename()
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete {
                Button("Delete") {
                    onDelete()
                }
                .tint(.red)
            }
        }
        #endif
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = item.isFile ? DesignTokens.Spacing.sm : DesignTokens.Spacing.xs
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }

    private var rowVerticalPadding: CGFloat {
        #if os(macOS)
        return DesignTokens.Spacing.xs
        #else
        return item.isFile ? DesignTokens.Spacing.xs : DesignTokens.Spacing.xxs
        #endif
    }
}

private struct FileNodeItem: Identifiable {
    let id: String
    let name: String
    let type: FileNodeType
    let children: [FileNodeItem]?

    var isFile: Bool { type == .file }

    var displayName: String {
        if isFile, name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }
}

public struct FilesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        FilesPanelView(viewModel: environment.ingestionViewModel)
    }
}

private struct FilesPanelView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var viewModel: IngestionViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasLoaded = false
    @State private var expandedCategories: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var listAppeared = false
    @State private var isDeleteAlertPresented = false
    @State private var deleteTarget: IngestionListItem? = nil
    @State private var pinTarget: IngestionListItem? = nil
    @State private var isFileImporterPresented = false
    @State private var isYouTubeAlertPresented = false
    @State private var newYouTubeUrl: String = ""
    @State private var knownFileIds: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoading && viewModel.items.isEmpty {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if let message = viewModel.errorMessage {
                SidebarPanelPlaceholder(
                    title: "Unable to load files",
                    subtitle: message,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.load() }
                }
            } else if filteredItems.isEmpty {
                if searchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(title: "No files yet.")
                } else {
                    SidebarPanelPlaceholder(title: "No results.")
                }
            } else {
                filesListView
            }
        }
        .frame(maxHeight: .infinity)
        .alert(deleteDialogTitle, isPresented: $isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                clearDeleteTarget()
            }
        } message: {
            Text("This will remove the file and cannot be undone.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("Add YouTube video", isPresented: $isYouTubeAlertPresented) {
            TextField("youtube.com", text: $newYouTubeUrl)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    addYouTube()
                }
            Button(viewModel.isIngestingYouTube ? "Adding..." : "Add") {
                addYouTube()
            }
            .disabled(viewModel.isIngestingYouTube || newYouTubeUrl.trimmed.isEmpty)
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                newYouTubeUrl = ""
            }
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            initializeExpandedCategoriesIfNeeded()
            knownFileIds = Set(viewModel.items.map { $0.file.id })
        }
        .onChange(of: categoriesWithItems) { _, _ in
            initializeExpandedCategoriesIfNeeded()
        }
        .onChange(of: viewModel.items.map { $0.file.id }) { _, newIds in
            let newIdSet = Set(newIds)
            let addedIds = newIdSet.subtracting(knownFileIds)
            if !addedIds.isEmpty {
                for item in viewModel.items where addedIds.contains(item.file.id) {
                    if item.file.mimeOriginal.lowercased().contains("youtube") {
                        expandedCategories.insert("video")
                        break
                    }
                }
            }
            knownFileIds = newIdSet
        }
        .onReceive(environment.$shortcutActionEvent.compactMap { $0 }) { event in
            guard event.section == .files else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                isFileImporterPresented = true
            case .navigateList(let direction):
                navigateFilesList(direction: direction)
            default:
                break
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Files") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newYouTubeUrl = ""
                        isYouTubeAlertPresented = true
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add YouTube video")
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add file")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search files", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var filesListView: some View {
        List {
            if !searchQuery.trimmed.isEmpty {
                ForEach(Array(searchResults.enumerated()), id: \.element.file.id) { index, item in
                    let row = FilesIngestionRow(
                        item: item,
                        isSelected: viewModel.selectedFileId == item.file.id,
                        onPinToggle: pinAction(for: item),
                        onDelete: deleteAction(for: item)
                    )
                    if isFolder(item) {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                    } else {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                            .onTapGesture { open(item: item) }
                    }
                }
            } else {
                if !pinnedItems.isEmpty {
                    Section("Pinned") {
                        ForEach(Array(pinnedItems.enumerated()), id: \.element.file.id) { index, item in
                            let row = FilesIngestionRow(
                                item: item,
                                isSelected: viewModel.selectedFileId == item.file.id,
                                onPinToggle: pinAction(for: item),
                                onDelete: deleteAction(for: item)
                            )
                            if isFolder(item) {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                            } else {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                                    .onTapGesture { open(item: item) }
                            }
                        }
                    }
                }

                if !categorizedItems.isEmpty {
                    Section("Files") {
                        ForEach(Array(categoryOrder.enumerated()), id: \.element) { categoryIndex, category in
                            if let items = categorizedItems[category], !items.isEmpty {
                                DisclosureGroup(
                                    isExpanded: bindingForCategory(category)
                                ) {
                                    ForEach(Array(items.enumerated()), id: \.element.file.id) { itemIndex, item in
                                        let row = FilesIngestionRow(
                                            item: item,
                                            isSelected: viewModel.selectedFileId == item.file.id,
                                            onPinToggle: pinAction(for: item),
                                            onDelete: deleteAction(for: item)
                                        )
                                        if isFolder(item) {
                                            row
                                                .staggeredAppear(
                                                    index: categoryIndex + itemIndex,
                                                    isActive: listAppeared
                                                )
                                        } else {
                                            row
                                                .staggeredAppear(
                                                    index: categoryIndex + itemIndex,
                                                    isActive: listAppeared
                                                )
                                                .onTapGesture { open(item: item) }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: categoryIconName(category))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .center)
                                        Text(categoryLabels[category] ?? "Files")
                                    }
                                    .font(.subheadline)
                                }
                                .listRowBackground(rowBackground)
                            }
                        }
                    }
                }
            }

        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.load()
        }
        .onAppear {
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
    }

    private func open(item: IngestionListItem) {
        open(fileId: item.file.id)
    }

    private func open(fileId: String) {
        viewModel.prepareSelection(fileId: fileId)
        Task { await viewModel.selectFile(fileId: fileId) }
    }

    private func pinAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            pinTarget = item
            Task { await togglePin() }
        }
    }

    private func deleteAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            presentDelete(for: item)
        }
    }

    private func togglePin() async {
        guard let item = pinTarget else { return }
        let isPinned = item.file.pinned ?? false
        await viewModel.togglePinned(fileId: item.file.id, pinned: !isPinned)
        pinTarget = nil
    }

    private func presentDelete(for item: IngestionListItem) {
        deleteTarget = item
        isDeleteAlertPresented = true
    }

    private func confirmDelete() {
        guard let item = deleteTarget else { return }
        Task {
            let success = await viewModel.deleteFile(fileId: item.file.id)
            if !success {
                environment.toastCenter.show(message: "Failed to delete file")
            }
        }
        clearDeleteTarget()
    }

    private func clearDeleteTarget() {
        deleteTarget = nil
        isDeleteAlertPresented = false
    }

    private func navigateFilesList(direction: ShortcutListDirection) {
        let ids = filesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = viewModel.selectedFileId
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        open(fileId: ids[nextIndex])
    }

    private func filesNavigationItems() -> [String] {
        if !searchQuery.trimmed.isEmpty {
            return searchResults.filter { !isFolder($0) }.map { $0.file.id }
        }
        var ids: [String] = []
        ids.append(contentsOf: pinnedItems.filter { !isFolder($0) }.map { $0.file.id })
        for category in categoryOrder {
            if let items = categorizedItems[category] {
                ids.append(contentsOf: items.filter { !isFolder($0) }.map { $0.file.id })
            }
        }
        return ids
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addUploads(urls: urls)
        case .failure:
            environment.toastCenter.show(message: "Failed to add files")
        }
    }

    private func addYouTube() {
        let url = newYouTubeUrl.trimmed
        guard !url.isEmpty else { return }
        newYouTubeUrl = ""
        isYouTubeAlertPresented = false
        Task {
            if let message = await viewModel.ingestYouTube(url: url) {
                environment.toastCenter.show(message: message)
            }
        }
    }

    private var deleteDialogTitle: String {
        guard let deleteTarget else {
            return "Delete file"
        }
        let name = stripFileExtension(deleteTarget.file.filenameOriginal)
        return "Delete \"\(name)\"?"
    }

    private func isFolder(_ item: IngestionListItem) -> Bool {
        item.file.category == "folder"
    }

    private func bindingForCategory(_ category: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
            }
        )
    }

    private func initializeExpandedCategoriesIfNeeded() {
        if expandedCategories.isEmpty {
            expandedCategories = []
        }
    }

    private var filteredItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    private var searchResults: [IngestionListItem] {
        filteredItems.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private var pinnedItems: [IngestionListItem] {
        filteredItems
            .filter { isReady($0) && ($0.file.pinned ?? false) }
            .sorted { lhs, rhs in
                let left = lhs.file.pinnedOrder ?? Int.max
                let right = rhs.file.pinnedOrder ?? Int.max
                if left != right {
                    return left < right
                }
                let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private var categorizedItems: [String: [IngestionListItem]] {
        let unpinned = filteredItems.filter { !($0.file.pinned ?? false) }
        let grouped = unpinned.reduce(into: [String: [IngestionListItem]]()) { result, item in
            let category = categoryFor(item)
            result[category, default: []].append(item)
        }
        return grouped.mapValues { items in
            items.sorted { lhs, rhs in
                let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return leftDate > rightDate
            }
        }
    }

    private var categoriesWithItems: [String] {
        categoryOrder.filter { categorizedItems[$0]?.isEmpty == false }
    }

    private var categoryLabels: [String: String] {
        [
            "documents": "Documents",
            "images": "Images",
            "audio": "Audio",
            "video": "Video",
            "spreadsheets": "Spreadsheets",
            "reports": "Reports",
            "presentations": "Presentations",
            "other": "Other"
        ]
    }

    private var categoryOrder: [String] {
        ["documents", "images", "audio", "video", "spreadsheets", "reports", "presentations", "other"]
    }

    private func isReady(_ item: IngestionListItem) -> Bool {
        (item.job.status ?? "") == "ready" && item.recommendedViewer != nil
    }

    private func categoryFor(_ item: IngestionListItem) -> String {
        if let category = item.file.category, !category.isEmpty {
            return category
        }
        let normalized = item.file.mimeOriginal.split(separator: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? item.file.mimeOriginal
        if normalized == "video/youtube" || normalized.hasPrefix("video/") {
            return "video"
        }
        if normalized.hasPrefix("image/") {
            return "images"
        }
        if normalized.hasPrefix("audio/") {
            return "audio"
        }
        if normalized == "application/pdf"
            || normalized == "text/plain"
            || normalized == "text/markdown"
            || normalized == "text/html"
            || normalized == "application/msword"
            || normalized == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" {
            return "documents"
        }
        if normalized == "application/vnd.ms-excel"
            || normalized == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            || normalized == "text/csv" {
            return "spreadsheets"
        }
        if normalized == "application/vnd.ms-powerpoint"
            || normalized == "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
            return "presentations"
        }
        return "other"
    }

    private func categoryIconName(_ category: String) -> String {
        switch category {
        case "documents":
            return "doc.text"
        case "images":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        case "spreadsheets":
            return "tablecells"
        case "reports":
            return "chart.line.text.clipboard"
        case "presentations":
            return "rectangle.on.rectangle.angled"
        default:
            return "folder"
        }
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

}

private struct FilesIngestionRow: View, Equatable {
    let item: IngestionListItem
    let isSelected: Bool
    let onPinToggle: (() -> Void)?
    let onDelete: (() -> Void)?

    init(
        item: IngestionListItem,
        isSelected: Bool,
        onPinToggle: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onPinToggle = onPinToggle
        self.onDelete = onDelete
    }

    static func == (lhs: FilesIngestionRow, rhs: FilesIngestionRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.item.file.id == rhs.item.file.id &&
        lhs.item.file.filenameOriginal == rhs.item.file.filenameOriginal &&
        lhs.item.file.category == rhs.item.file.category &&
        lhs.item.file.pinned == rhs.item.file.pinned &&
        lhs.item.file.pinnedOrder == rhs.item.file.pinnedOrder &&
        lhs.item.job.status == rhs.item.job.status &&
        lhs.item.job.stage == rhs.item.job.stage &&
        lhs.item.job.progress == rhs.item.job.progress &&
        lhs.item.job.errorMessage == rhs.item.job.errorMessage &&
        lhs.item.recommendedViewer == rhs.item.recommendedViewer
    }

    var body: some View {
        SelectableRow(isSelected: isSelected, insets: rowInsets) {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(isSelected ? selectedTextColor : secondaryTextColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    if let statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onPinToggle {
                let title = (item.file.pinned ?? false) ? "Unpin" : "Pin"
                Button(title) {
                    onPinToggle()
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete {
                Button("Delete") {
                    onDelete()
                }
                .tint(.red)
            }
        }
        #endif
    }

    private var iconName: String {
        if item.file.category == "folder" {
            return folderIconName(for: displayName)
        }
        if item.file.mimeOriginal.lowercased().contains("video/youtube") {
            return "video"
        }
        if item.file.category == "presentations" {
            return "rectangle.on.rectangle.angled"
        }
        if item.file.category == "reports" {
            return "chart.line.text.clipboard"
        }
        switch item.recommendedViewer {
        case "viewer_pdf":
            return "doc.richtext"
        case "viewer_json":
            return "tablecells"
        case "viewer_video":
            return "video"
        case "image_original":
            return "photo"
        case "audio_original":
            return "waveform"
        case "viewer_presentation":
            return "rectangle.on.rectangle.angled"
        case "text_original", "ai_md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private var statusText: String? {
        let status = item.job.status ?? ""
        if status.isEmpty || status == "ready" {
            return nil
        }
        return ingestionStatusLabel(for: item.job) ?? "Processing"
    }

    private var statusTextColor: Color {
        if isFailed {
            return .orange
        }
        return secondaryTextColor
    }

    private var isProcessing: Bool {
        let status = item.job.status ?? ""
        return !status.isEmpty && !["ready", "failed", "canceled"].contains(status)
    }

    private var isFailed: Bool {
        (item.job.status ?? "") == "failed"
    }

    private var displayName: String {
        let name = stripFileExtension(item.file.filenameOriginal)
        if item.file.mimeOriginal.lowercased() == "video/youtube", name.lowercased() == "youtube video" {
            return "YouTube Video"
        }
        return name
    }

    private func folderIconName(for name: String) -> String {
        switch name.lowercased() {
        case "documents":
            return "doc.text"
        case "images":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        case "spreadsheets":
            return "tablecells"
        case "presentations":
            return "rectangle.on.rectangle.angled"
        case "reports":
            return "chart.line.text.clipboard"
        default:
            return "folder"
        }
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = item.file.category == "folder" ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}

public struct WebsitesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        WebsitesPanelView(viewModel: environment.websitesViewModel)
    }
}

private struct WebsitesPanelView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchQuery: String = ""
    @State private var hasLoaded = false
    @State private var isArchiveExpanded = false
    @State private var selection: String? = nil
    @State private var listAppeared = false
    @State private var isNewWebsitePresented = false
    @State private var newWebsiteUrl: String = ""
    @State private var saveErrorMessage: String? = nil
    @State private var archiveHeight: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            websitesPanelContentWithArchive
            #else
            content
            #endif
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.active?.id
            }
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.active?.id) { _, newValue in
            selection = newValue
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
        .alert("Save a website", isPresented: $isNewWebsitePresented) {
            TextField("example.com", text: $newWebsiteUrl)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    saveWebsite()
                }
            Button(viewModel.isSavingWebsite ? "Saving..." : "Save") {
                saveWebsite()
            }
            .disabled(viewModel.isSavingWebsite || !WebsiteURLValidator.isValid(newWebsiteUrl))
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                newWebsiteUrl = ""
            }
        }
        .alert("Unable to save website", isPresented: isSaveErrorPresented) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Failed to save website. Please try again.")
        }
        .onReceive(environment.$shortcutActionEvent.compactMap { $0 }) { event in
            guard event.section == .websites else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                newWebsiteUrl = ""
                isNewWebsitePresented = true
            case .navigateList(let direction):
                navigateWebsitesList(direction: direction)
            default:
                break
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Websites") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newWebsiteUrl = ""
                        isNewWebsitePresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add website")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search websites", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load() }
            }
        } else if searchQuery.trimmed.isEmpty && viewModel.items.isEmpty && viewModel.pendingWebsite == nil {
            SidebarPanelPlaceholder(title: "No websites yet.")
        } else if !searchQuery.trimmed.isEmpty {
            List {
                if let pending = viewModel.pendingWebsite {
                    Section("Adding") {
                        PendingWebsiteRow(pending: pending, useListStyling: true)
                    }
                }
                Section("Results") {
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        } else {
            List {
                if !pinnedItemsSorted.isEmpty || !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                    Section("Pinned") {
                        if pinnedItemsSorted.isEmpty {
                            Text("No pinned websites")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(pinnedItemsSorted.enumerated()), id: \.element.id) { index, item in
                                websiteListRow(item: item, index: index)
                            }
                        }
                    }

                    Section("Websites") {
                        if mainItems.isEmpty && viewModel.pendingWebsite == nil {
                            Text("No websites saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if let pending = viewModel.pendingWebsite {
                                PendingWebsiteRow(pending: pending, useListStyling: true)
                            }
                            ForEach(Array(mainItems.enumerated()), id: \.element.id) { index, item in
                                websiteListRow(item: item, index: index)
                            }
                        }
                    }
                }
#if !os(macOS)
                Section {
                    DisclosureGroup(
                        isExpanded: $isArchiveExpanded,
                        content: {
                            if archivedItems.isEmpty {
                                Text("No archived websites")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                                    websiteListRow(item: item, index: index, allowArchive: false)
                                }
                            }
                        },
                        label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    )
                    .listRowBackground(rowBackground)
                }
#endif
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var websitesPanelContentWithArchive: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load() }
            }
        } else if searchQuery.trimmed.isEmpty && viewModel.items.isEmpty && viewModel.pendingWebsite == nil {
            SidebarPanelPlaceholder(title: "No websites yet.")
        } else if !searchQuery.trimmed.isEmpty {
            List {
                if let pending = viewModel.pendingWebsite {
                    Section("Adding") {
                        PendingWebsiteRow(pending: pending, useListStyling: true)
                    }
                }
                Section("Results") {
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        } else {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    websitesListView
                        .frame(height: max(0, proxy.size.height - archiveHeight))
                    websitesArchiveSection
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(ArchiveHeightKey.self) { newValue in
                    if abs(newValue - archiveHeight) > 0.5 {
                        archiveHeight = newValue
                    }
                }
            }
        }
    }

    private var websitesListView: some View {
        List {
            if !pinnedItemsSorted.isEmpty || !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                Section("Pinned") {
                    if pinnedItemsSorted.isEmpty {
                        Text("No pinned websites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(pinnedItemsSorted.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }

                Section("Websites") {
                    if mainItems.isEmpty && viewModel.pendingWebsite == nil {
                        Text("No websites saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if let pending = viewModel.pendingWebsite {
                            PendingWebsiteRow(pending: pending, useListStyling: true)
                        }
                        ForEach(Array(mainItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.load()
        }
    }

    private func open(item: WebsiteItem) {
        selection = item.id
        Task { await viewModel.selectWebsite(id: item.id) }
    }

    private func navigateWebsitesList(direction: ShortcutListDirection) {
        let ids = websitesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = selection ?? viewModel.active?.id
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        let nextId = ids[nextIndex]
        if let item = viewModel.items.first(where: { $0.id == nextId }) {
            open(item: item)
        }
    }

    private func websitesNavigationItems() -> [String] {
        if !searchQuery.trimmed.isEmpty {
            return filteredItems.map { $0.id }
        }
        return pinnedItemsSorted.map { $0.id } + mainItems.map { $0.id }
    }

    @ViewBuilder
    private func websiteListRow(
        item: WebsiteItem,
        index: Int,
        useListStyling: Bool = true,
        allowArchive: Bool = true
    ) -> some View {
        let row = WebsiteRow(
            item: item,
            isSelected: selection == item.id,
            useListStyling: useListStyling
        )
        .staggeredAppear(index: index, isActive: listAppeared)
        .onTapGesture { open(item: item) }

        #if os(macOS)
        row
        #else
        row
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if allowArchive {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: true) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.blue)
                } else {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: false) }
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await viewModel.deleteWebsite(id: item.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        #endif
    }

    private var pinnedItemsSorted: [WebsiteItem] {
        pinnedItems.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private var pinnedItems: [WebsiteItem] {
        viewModel.items.filter { $0.pinned && !$0.archived }
    }

    private var mainItems: [WebsiteItem] {
        viewModel.items.filter { !$0.pinned && !$0.archived }
    }

    private var archivedItems: [WebsiteItem] {
        viewModel.items.filter { $0.archived }
    }

    private var filteredItems: [WebsiteItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.title.lowercased().contains(needle) ||
            item.domain.lowercased().contains(needle) ||
            item.url.lowercased().contains(needle)
        }
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var websitesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if archivedItems.isEmpty {
                        Text("No archived websites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                                    websiteListRow(item: item, index: index, useListStyling: false, allowArchive: false)
                                }
                            }
                        }
                        .frame(maxHeight: 650)
                    }
                },
                label: {
                    Label("Archive", systemImage: "archivebox")
                        .font(.subheadline)
                }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(panelBackground)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ArchiveHeightKey.self, value: proxy.size.height)
            }
        )
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isSaveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func saveWebsite() {
        let raw = newWebsiteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = WebsiteURLValidator.normalizedCandidate(raw) else {
            saveErrorMessage = "Enter a valid URL."
            return
        }
        newWebsiteUrl = ""
        isNewWebsitePresented = false
        Task {
            let saved = await viewModel.saveWebsite(url: normalized.absoluteString)
            if saved {
                environment.notesViewModel.clearSelection()
                environment.ingestionViewModel.clearSelection()
            } else {
                saveErrorMessage = viewModel.saveErrorMessage ?? "Failed to save website. Please try again."
            }
        }
    }
}

private struct PendingWebsiteRow: View, Equatable {
    let pending: WebsitesViewModel.PendingWebsiteItem
    let useListStyling: Bool

    var body: some View {
        SelectableRow(
            isSelected: false,
            insets: rowInsets,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.title)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                    Text(formatDomain(pending.domain))
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = DesignTokens.Spacing.sm
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}

private struct WebsiteRow: View, Equatable {
    let item: WebsiteItem
    let isSelected: Bool
    let useListStyling: Bool
    private let titleText: String
    private let domainText: String

    init(item: WebsiteItem, isSelected: Bool, useListStyling: Bool = true) {
        self.item = item
        self.isSelected = isSelected
        self.useListStyling = useListStyling
        self.titleText = item.title.isEmpty ? item.url : item.title
        self.domainText = WebsiteRow.formatDomain(item.domain)
    }

    static func == (lhs: WebsiteRow, rhs: WebsiteRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.useListStyling == rhs.useListStyling &&
        lhs.item.id == rhs.item.id &&
        lhs.item.title == rhs.item.title &&
        lhs.item.url == rhs.item.url &&
        lhs.item.domain == rhs.item.domain &&
        lhs.item.pinned == rhs.item.pinned &&
        lhs.item.pinnedOrder == rhs.item.pinnedOrder &&
        lhs.item.archived == rhs.item.archived &&
        lhs.item.updatedAt == rhs.item.updatedAt
    }

    var body: some View {
        SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(isSelected ? selectedTextColor : secondaryTextColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                        .lineLimit(1)
                    Text(domainText)
                        .font(.caption)
                        .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private static func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var selectedSecondaryText: Color {
        DesignTokens.Colors.textSecondary
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = DesignTokens.Spacing.sm
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}

private struct ArchiveHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
