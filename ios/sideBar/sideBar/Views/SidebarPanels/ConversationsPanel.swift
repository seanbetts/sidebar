import Foundation
import SwiftUI

// MARK: - ConversationsPanel

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
    @State private var renameConversationId: String?
    @State private var renameValue: String = ""
    @State private var deleteConversationId: String?
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
}
