import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ConversationCopyFormatter {
    static func formattedTranscript(
        title: String,
        messages: [Message],
        assistantName: String
    ) -> String {
        let conversationTitle = title.trimmed.isEmpty ? "Chat" : title.trimmed
        let lines = messages.compactMap { message -> String? in
            let trimmedContent = message.content.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let fallbackError = message.error?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            let text = trimmedContent.isEmpty ? fallbackError : trimmedContent
            guard !text.isEmpty else {
                return nil
            }
            let speaker = message.role == .assistant ? assistantName : "You"
            return "\(speaker):\n\(text)"
        }
        guard !lines.isEmpty else {
            return ""
        }
        return "Chat: \(conversationTitle)\n\n" + lines.joined(separator: "\n\n")
    }
}

extension ConversationsPanelView {
    var header: some View {
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
                                .font(DesignTokens.Typography.labelMd)
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

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var showNewChatButton: Bool {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return true
        }
        #endif
        guard viewModel.selectedConversationId != nil else {
            return false
        }
        return !viewModel.isBlankConversation
    }

    var conversationsList: some View {
        List {
            ForEach(filteredGroups) { group in
                Section(group.title) {
                    ForEach(group.conversations) { conversation in
                        SelectableRow(isSelected: viewModel.selectedConversationId == conversation.id) {
                            ConversationRow(
                                conversation: conversation,
                                isSelected: viewModel.selectedConversationId == conversation.id
                            )
                        }
                        .onTapGesture {
                            Task { await viewModel.selectConversation(id: conversation.id) }
                        }
                        .sidebarListSwipeActions(
                            leadingTitle: "Rename",
                            onLeading: { beginRename(conversation) },
                            onDelete: { presentDelete(conversation) }
                        )
                        .platformContextMenu(items: conversationContextMenuItemsList(for: conversation))
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

    func navigateConversationList(direction: ShortcutListDirection) {
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

    var filteredGroups: [ConversationGroup] {
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

    var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { renameConversationId != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameTarget()
                }
            }
        )
    }

    var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteConversationId != nil },
            set: { isPresented in
                if !isPresented {
                    clearDeleteTarget()
                }
            }
        )
    }

    func beginRename(_ conversation: Conversation) {
        renameConversationId = conversation.id
        renameValue = conversation.title
    }

    func clearRenameTarget() {
        renameConversationId = nil
        renameValue = ""
    }

    func commitRename() {
        let targetId = renameConversationId
        let updatedTitle = renameValue
        clearRenameTarget()
        if let id = targetId {
            Task {
                await viewModel.renameConversation(id: id, title: updatedTitle)
            }
        }
    }

    func presentDelete(_ conversation: Conversation) {
        deleteConversationId = conversation.id
        let trimmed = conversation.title.trimmed
        deleteConversationTitle = trimmed.isEmpty ? "conversation" : trimmed
    }

    func clearDeleteTarget() {
        deleteConversationId = nil
        deleteConversationTitle = ""
    }

    var deleteDialogTitle: String {
        let truncated = truncatedDeleteTitle(deleteConversationTitle)
        return "Delete \"\(truncated)\"?"
    }

    func truncatedDeleteTitle(_ title: String) -> String {
        let maxLength = 32
        guard title.count > maxLength else {
            return title
        }
        let index = title.index(title.startIndex, offsetBy: maxLength)
        return "\(title[..<index])..."
    }

    func conversationContextMenuItemsList(for conversation: Conversation) -> [SidebarMenuItem] {
        [
            .rename {
                beginRename(conversation)
            },
            .copy {
                Task { await copyConversation(conversation) }
            },
            .delete {
                presentDelete(conversation)
            }
        ]
    }

    @MainActor
    private func copyConversation(_ conversation: Conversation) async {
        guard let text = await transcriptText(for: conversation), !text.isEmpty else {
            environment.toastCenter.show(message: "Copy unavailable")
            return
        }
        copyConversationTextToClipboard(text)
    }

    @MainActor
    private func transcriptText(for conversation: Conversation) async -> String? {
        let assistantName = environment.settingsViewModel.assistantDisplayName
        if viewModel.selectedConversationId == conversation.id && !viewModel.messages.isEmpty {
            return ConversationCopyFormatter.formattedTranscript(
                title: conversation.title,
                messages: viewModel.messages,
                assistantName: assistantName
            )
        }

        do {
            try await viewModel.chatStore.loadConversation(id: conversation.id)
        } catch {
            return nil
        }

        guard let detail = viewModel.chatStore.conversationDetails[conversation.id] else {
            return nil
        }
        return ConversationCopyFormatter.formattedTranscript(
            title: detail.title,
            messages: detail.messages,
            assistantName: assistantName
        )
    }

    private func copyConversationTextToClipboard(_ text: String) {
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == text {
                pasteboard.string = ""
            }
            #endif
        }
    }
}
