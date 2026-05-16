import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ConversationsPanel

public struct ConversationsPanel: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var localSearchQuery: String = ""
    private let searchQuery: Binding<String>?

    public init(searchQuery: Binding<String>? = nil) {
        self.searchQuery = searchQuery
    }

    public var body: some View {
        ConversationsPanelView(
            viewModel: environment.chatViewModel,
            searchQuery: searchQuery ?? $localSearchQuery
        )
    }
}
struct ConversationsPanelView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: ChatViewModel
    @Binding var searchQuery: String
    @EnvironmentObject var environment: AppEnvironment
    @State var searchResults: [Conversation]?
    @State var searchErrorMessage: String?
    @State var isSearchLoading: Bool = false
    @State var searchTask: Task<Void, Never>?
    @FocusState var isSearchFocused: Bool
    @State var renameConversationId: String?
    @State var renameValue: String = ""
    @State var deleteConversationId: String?
    @State var deleteConversationTitle: String = ""
    @State var exportDocument: PlainTextFileDocument?
    @State var exportFilename: String = "Chat.txt"
    @State var isExporting: Bool = false
    @Environment(\.colorScheme) var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch listPresentationState {
                case .loading:
                    SidebarListSkeleton(rowCount: 8, showSubtitle: true)
                case .retry(let loadErrorMessage):
                    SidebarPanelPlaceholder(
                        title: "Unable to load chats",
                        subtitle: loadErrorMessage,
                        actionTitle: "Retry",
                        style: .error
                    ) {
                        Task { await viewModel.loadConversations(force: true) }
                    }
                case .search:
                    if isSearchLoading && filteredGroups.isEmpty {
                        SidebarListSkeleton(rowCount: 3, showSubtitle: false)
                    } else if filteredGroups.isEmpty {
                        let searchEmptyState = EmptyStateContent.noResults(subtitle: searchErrorMessage)
                        SidebarPanelPlaceholder(
                            title: searchEmptyState.title,
                            subtitle: searchEmptyState.subtitle,
                            style: searchErrorMessage == nil ? .standard : .error,
                            icon: searchEmptyState.icon
                        )
                    } else {
                        conversationsList
                    }
                case .empty:
                    let emptyState = EmptyStateContent.noContentYet(
                        title: "No conversations",
                        subtitle: "Start a new chat to begin.",
                        icon: AppIcon.Domain.chat
                    )
                    EmptyStateView(
                        title: emptyState.title,
                        subtitle: emptyState.subtitle,
                        systemImage: emptyState.systemImage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PlatformTokens.sidebarPanelBackground)
                case .content:
                    conversationsList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .sidebarPanelScaffoldBackground()
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
        .deleteConfirmationAlert(
            title: "Delete conversation",
            isPresented: isDeleteDialogPresented,
            message: deleteDialogTitle,
            confirmAsDefaultAction: true,
            onConfirm: {
                let targetId = deleteConversationId
                clearDeleteTarget()
                Task {
                    if let id = targetId {
                        await viewModel.deleteConversation(id: id)
                    }
                }
            },
            onCancel: clearDeleteTarget
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onChange(of: searchQuery) { _, newValue in
            updateConversationSearch(query: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .chat else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                Task { await viewModel.startNewConversation() }
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
