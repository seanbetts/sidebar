import SwiftUI
import UniformTypeIdentifiers
import Combine

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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New chat")
                    }
                }
            }
            #endif
            .task {
                await environment.chatViewModel.loadConversations()
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
}

private struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draftMessage: String = ""
    private let inputBarHeight: CGFloat = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isScratchpadPresented = false
    #endif
    @State private var inputMeasuredHeight: CGFloat = 0
    @State private var attachmentsHeight: CGFloat = 0
    @State private var isFileImporterPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if environment.isOffline {
                    OfflineBanner()
                }
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
                } else if viewModel.messages.isEmpty {
                    EmptyView()
                } else {
                    ChatMessageListView(viewModel: viewModel, bottomInset: messageListBottomInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                attachmentsContainer
                ChatInputBar(
                    text: $draftMessage,
                    measuredHeight: $inputMeasuredHeight,
                    isEnabled: !viewModel.isStreaming,
                    isSendEnabled: !viewModel.isStreaming && !viewModel.hasPendingAttachments,
                    onSend: handleSend,
                    onAttach: { isFileImporterPresented = true }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.md)
            #if os(macOS)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .center)
            #endif
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .chat else { return }
            switch event.action {
            case .sendMessage:
                if !viewModel.isStreaming {
                    handleSend()
                }
            case .attachFile:
                isFileImporterPresented = true
            default:
                break
            }
        }
        #if !os(macOS)
        .overlay(alignment: .bottomTrailing) {
            if isCompact {
                Button {
                    isScratchpadPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(DesignTokens.Typography.titleLg)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
                .accessibilityLabel("Scratchpad")
                .padding(.trailing, DesignTokens.Spacing.md)
                .padding(.bottom, inputBarHeight + DesignTokens.Spacing.xl)
            }
        }
        .sheet(isPresented: $isScratchpadPresented) {
            ScratchpadPopoverView(
                api: environment.container.scratchpadAPI,
                cache: environment.container.cacheClient,
                scratchpadStore: environment.scratchpadStore
            )
        }
        #endif
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

    private func handleSend() {
        let message = draftMessage.trimmed
        guard !message.isEmpty else {
            return
        }
        draftMessage = ""
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
                    onDelete: { viewModel.deleteAttachment(id: $0) }
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
