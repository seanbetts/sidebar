import Foundation
import SwiftUI

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
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .chat else { return }
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

    private var filteredGroups: [ConversationGroup] {
        let query = searchQuery.trimmed
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
        let trimmed = conversation.title.trimmed
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
