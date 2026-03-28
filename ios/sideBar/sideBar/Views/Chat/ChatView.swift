import SwiftUI
import sideBarShared
import UniformTypeIdentifiers
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - ChatView

public struct ChatView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        ChatDetailView(viewModel: environment.chatViewModel)
            #if !os(macOS)
            .navigationTitle(chatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if !isPhone {
                            Button {
                                Task {
                                    await environment.chatViewModel.startNewConversation()
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("New chat")
                        }
                        if isPhone {
                            Button {
                                environment.emitShortcutAction(.openScratchpad)
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scratchpad")
                        }
                    }
                }
            }
            #endif
            .task {
                environment.chatViewModel.startAutoRefresh()
            }
            .onDisappear {
                environment.chatViewModel.stopAutoRefresh()
            }
    }

    private var chatTitle: String {
        guard isCompact,
              let selectedId = environment.chatViewModel.selectedConversationId,
              let conversation = environment.chatViewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "Chat"
        }
        return conversation.title
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}

private struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draftMessage: String = ""
    private let contentMaxWidth: CGFloat = ChatLayout.maxContentWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workspaceColumn) private var workspaceColumn
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var inputMeasuredHeight: CGFloat = 0
    @State private var inputResetToken = UUID()
    @State private var attachmentsHeight: CGFloat = 0
    @State private var isFileImporterPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !isCompact {
                    ChatHeaderView(viewModel: viewModel)
                    Divider()
                }
                if viewModel.isLoadingMessages {
                    LoadingView(message: "Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.selectedConversationId == nil {
                    if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                        LoadingView(message: "Loading chats…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyView()
                    }
                } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                    PlaceholderView(
                        title: "Unable to load chat",
                        subtitle: environment.isNetworkAvailable ? errorMessage : "This chat isn't available offline yet.",
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedConversationId else { return }
                        Task { await viewModel.loadConversation(id: selectedId) }
                    }
                } else if !environment.isNetworkAvailable, !viewModel.hasCachedSelectedConversation {
                    PlaceholderView(
                        title: "Unable to load chat",
                        subtitle: "This chat isn't available offline yet.",
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedConversationId else { return }
                        Task { await viewModel.loadConversation(id: selectedId) }
                    }
                } else if viewModel.messages.isEmpty {
                    EmptyView()
                } else {
                    ChatMessageListView(
                        viewModel: viewModel,
                        bottomInset: messageListBottomInset,
                        assistantDisplayName: assistantDisplayName
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                attachmentsContainer
                ChatInputBar(
                    text: $draftMessage,
                    measuredHeight: $inputMeasuredHeight,
                    resetToken: inputResetToken,
                    isEnabled: canSendMessages,
                    isSendEnabled: canSendMessages && !viewModel.hasPendingAttachments,
                    onSend: handleSend,
                    onAttach: {
                        guard canSendMessages else { return }
                        isFileImporterPresented = true
                    }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.matches(
                    section: .chat,
                    workspacePane: workspaceColumn.workspacePane
                  ) else { return }
            switch event.action {
            case .sendMessage:
                if !viewModel.isStreaming {
                    handleSend()
                }
            case .attachFile:
                guard canSendMessages else { return }
                isFileImporterPresented = true
            default:
                break
            }
        }
        .onChange(of: inputMeasuredHeight) { oldValue, newValue in
            ChatStreamingDebugTrace.log(
                "chatView.inputMeasuredHeight",
                details: [
                    "old=\(Int(oldValue.rounded()))",
                    "new=\(Int(newValue.rounded()))",
                    "bottomInset=\(Int(messageListBottomInset.rounded()))",
                    "streaming=\(viewModel.isStreaming)"
                ].joined(separator: " ")
            )
        }
        .onChange(of: attachmentsHeight) { oldValue, newValue in
            ChatStreamingDebugTrace.log(
                "chatView.attachmentsHeight",
                details: [
                    "old=\(Int(oldValue.rounded()))",
                    "new=\(Int(newValue.rounded()))",
                    "bottomInset=\(Int(messageListBottomInset.rounded()))",
                    "streaming=\(viewModel.isStreaming)"
                ].joined(separator: " ")
            )
        }
        .onChange(of: viewModel.isStreaming) { oldValue, newValue in
            ChatStreamingDebugTrace.log(
                "chatView.isStreaming",
                details: [
                    "old=\(oldValue)",
                    "new=\(newValue)",
                    "messageCount=\(viewModel.messages.count)",
                    "streamMessage=\(ChatStreamingDebugTrace.shortID(viewModel.currentStreamMessageId))",
                    "inputMeasuredHeight=\(Int(inputMeasuredHeight.rounded()))",
                    "bottomInset=\(Int(messageListBottomInset.rounded()))"
                ].joined(separator: " ")
            )
        }
    }

    private var messageListBottomInset: CGFloat {
        max(inputMeasuredHeight, inputBarMinHeight) + attachmentsHeight + 40
    }

    private var inputBarMinHeight: CGFloat {
        #if os(macOS)
        return 84
        #else
        return 46
        #endif
    }

    private var canSendMessages: Bool {
        !viewModel.isStreaming && environment.isNetworkAvailable
    }

    private var assistantDisplayName: String {
        environment.settingsViewModel.assistantDisplayName
    }

    private func handleSend() {
        let message = draftMessage.trimmed
        guard !message.isEmpty else {
            return
        }
        ChatStreamingDebugTrace.log(
            "chatView.handleSend",
            details: [
                "messageChars=\(message.count)",
                "inputMeasuredHeight=\(Int(inputMeasuredHeight.rounded()))",
                "attachmentsHeight=\(Int(attachmentsHeight.rounded()))",
                "bottomInset=\(Int(messageListBottomInset.rounded()))"
            ].joined(separator: " ")
        )
        draftMessage = ""
        inputMeasuredHeight = 0
        inputResetToken = UUID()
        Task {
            await viewModel.sendMessage(text: message)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addAttachments(urls: urls)
        case .failure:
            environment.toastCenter.show(message: "Failed to attach file")
        }
    }

    private var attachmentsContainer: some View {
        VStack(spacing: 8) {
            if !viewModel.pendingAttachments.isEmpty {
                PendingAttachmentsView(
                    attachments: viewModel.pendingAttachments,
                    onRetry: { viewModel.retryAttachment(id: $0) },
                    onDelete: { viewModel.deleteAttachment(id: $0) },
                    onCancel: { viewModel.cancelAttachment(id: $0) }
                )
            }
            if !viewModel.readyAttachments.isEmpty {
                ReadyAttachmentsView(
                    attachments: viewModel.readyAttachments,
                    onRemove: { viewModel.removeReadyAttachment(id: $0) }
                )
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AttachmentHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(AttachmentHeightPreferenceKey.self) { height in
            attachmentsHeight = height
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}
