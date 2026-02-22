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
    static func loadErrorMessageForEmptyState(
        searchQuery: String,
        conversations: [Conversation],
        errorMessage: String?
    ) -> String? {
        guard searchQuery.trimmed.isEmpty else {
            return nil
        }
        guard conversations.isEmpty else {
            return nil
        }
        guard let errorMessage = errorMessage?.trimmedOrNil else {
            return nil
        }
        return errorMessage
    }

    var listLoadErrorMessage: String? {
        Self.loadErrorMessageForEmptyState(
            searchQuery: searchQuery,
            conversations: viewModel.conversations,
            errorMessage: viewModel.errorMessage
        )
    }

    static func conversationMatchesSearchQuery(_ normalizedQuery: String, conversation: Conversation) -> Bool {
        SearchTextMatcher.contains(
            normalizedQuery: normalizedQuery,
            in: [conversation.title, conversation.firstMessage ?? ""]
        )
    }

    var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Chat") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if showNewChatButton && !isCompactPhone {
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
        .background(panelHeaderBackground())
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isCompactPhone: Bool {
        isCompact && isPhone
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var showNewChatButton: Bool {
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

    func updateConversationSearch(query rawQuery: String) {
        searchTask?.cancel()
        searchTask = nil
        searchErrorMessage = nil

        let trimmed = rawQuery.trimmed
        guard !trimmed.isEmpty else {
            isSearchLoading = false
            searchResults = nil
            return
        }

        guard !viewModel.networkStatus.isOffline else {
            isSearchLoading = false
            searchResults = nil
            return
        }

        isSearchLoading = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await viewModel.searchConversations(query: trimmed, limit: 100)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = results
                    searchErrorMessage = nil
                    isSearchLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = nil
                    searchErrorMessage = error.localizedDescription
                    isSearchLoading = false
                }
            }
        }
    }

    var filteredGroups: [ConversationGroup] {
        let query = SearchTextMatcher.normalizedQuery(searchQuery)
        guard !query.isEmpty else {
            return viewModel.groupedConversations
        }
        let source = searchResults ?? viewModel.conversations
        let filtered = source
            .filter { conversation in
                Self.conversationMatchesSearchQuery(query, conversation: conversation)
            }
            .sorted { lhs, rhs in
                let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
                let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
                return leftDate > rightDate
            }
        guard !filtered.isEmpty else {
            return []
        }
        return [ConversationGroup(id: "search", title: "Results", conversations: filtered)]
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
            .copyTranscript {
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
