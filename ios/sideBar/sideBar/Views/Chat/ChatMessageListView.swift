import SwiftUI

struct ChatStreamingAutoScrollController {
    private(set) var lastAutoScrollAt: Date = .distantPast
    let throttleSeconds: TimeInterval

    init(throttleSeconds: TimeInterval = 0.08) {
        self.throttleSeconds = throttleSeconds
    }

    mutating func reset() {
        lastAutoScrollAt = .distantPast
    }

    mutating func shouldScroll(now: Date) -> Bool {
        guard now.timeIntervalSince(lastAutoScrollAt) >= throttleSeconds else {
            return false
        }
        lastAutoScrollAt = now
        return true
    }
}

struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    let bottomInset: CGFloat
    let assistantDisplayName: String
    @State private var shouldScrollToBottom = false
    @State private var visibleMessageCount: Int = 40
    @State private var isAutoLoadingMore = false
    @State private var streamingAutoScrollController = ChatStreamingAutoScrollController()
    private let pageSize: Int = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if hasMoreMessages {
                        VStack(spacing: 6) {
                            Button {
                                loadMoreMessages(proxy: proxy)
                            } label: {
                                Text(isAutoLoadingMore ? "Loading earlier messages…" : "Load earlier messages")
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(isAutoLoadingMore)
                            if isAutoLoadingMore {
                                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                            }
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .onAppear {
                            autoLoadMore(proxy: proxy)
                        }
                    }
                    ForEach(visibleMessages) { message in
                        ChatMessageRow(
                            message: message,
                            assistantDisplayName: assistantDisplayName,
                            retryHeaderSlotState: retryHeaderSlotState(for: message),
                            onRetry: retryLatestFailedTurn
                        )
                            .id(message.id)
                    }
                    chatBottomAnchor
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: ChatLayout.maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: scrollChangeToken) { oldToken, newToken in
                if oldToken.selectedConversationId != newToken.selectedConversationId {
                    visibleMessageCount = pageSize
                    isAutoLoadingMore = false
                    streamingAutoScrollController.reset()
                    shouldScrollToBottom = true
                    scrollToBottom(proxy: proxy, animated: false)
                    scheduleDeferredBottomScroll(proxy: proxy)
                    shouldScrollToBottom = false
                    return
                }

                if oldToken.messageCount != newToken.messageCount {
                    streamingAutoScrollController.reset()
                    let oldValue = oldToken.messageCount
                    let newValue = newToken.messageCount
                    if oldValue == 0 {
                        visibleMessageCount = min(pageSize, newValue)
                    } else if visibleMessageCount >= oldValue {
                        visibleMessageCount = newValue
                    } else if visibleMessageCount > newValue {
                        visibleMessageCount = newValue
                    }
                    let shouldJump = shouldScrollToBottom
                    if !shouldJump {
                        scrollToBottom(
                            proxy: proxy,
                            mode: ChatMessageListScrollBehavior.scrollMode(
                                previousMessageCount: oldToken.messageCount,
                                messageCount: newToken.messageCount,
                                previousLastMessage: oldToken.lastMessageSignature,
                                newPenultimateMessage: newToken.penultimateMessageSignature,
                                newLastMessage: newToken.lastMessageSignature,
                                activeToolChanged: false
                            )
                        )
                    } else {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    if shouldJump {
                        scheduleDeferredBottomScroll(proxy: proxy)
                    }
                    shouldScrollToBottom = false
                    return
                }

                if oldToken.lastMessageSignature != newToken.lastMessageSignature {
                    if viewModel.isStreaming {
                        if streamingAutoScrollController.shouldScroll(now: Date()) {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                        return
                    }
                    guard ChatMessageListScrollBehavior.shouldScrollForLastMessageChange(
                        from: oldToken.lastMessageSignature,
                        to: newToken.lastMessageSignature,
                        isStreaming: viewModel.isStreaming,
                        shouldScrollToBottom: shouldScrollToBottom
                    ) else {
                        return
                    }
                    scrollToBottom(
                        proxy: proxy,
                        animated: ChatMessageListScrollBehavior.shouldAnimateLastMessageChange(
                            from: oldToken.lastMessageSignature,
                            to: newToken.lastMessageSignature,
                            isStreaming: viewModel.isStreaming,
                            shouldScrollToBottom: shouldScrollToBottom
                        )
                    )
                    return
                }

                if oldToken.activeToolSignature != newToken.activeToolSignature {
                    guard ChatMessageListScrollBehavior.shouldScrollForActiveToolChange() else {
                        return
                    }
                    scrollToBottom(proxy: proxy, animated: false)
                    return
                }

                if oldToken.bottomInset != newToken.bottomInset {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
                scheduleDeferredBottomScroll(proxy: proxy)
            }
            .refreshable {
                await viewModel.refreshConversations()
                await viewModel.refreshActiveConversation()
            }
        }
    }

    private var visibleMessages: [Message] {
        let total = viewModel.messages.count
        guard total > visibleMessageCount else {
            return viewModel.messages
        }
        return Array(viewModel.messages.suffix(visibleMessageCount))
    }

    private var hasMoreMessages: Bool {
        viewModel.messages.count > visibleMessageCount
    }

    private var scrollChangeToken: ScrollChangeToken {
        let lastMessage = viewModel.messages.last
        return ScrollChangeToken(
            selectedConversationId: viewModel.selectedConversationId,
            messageCount: viewModel.messages.count,
            penultimateMessageSignature: ChatMessageScrollSignature(message: viewModel.messages.dropLast().last),
            lastMessageSignature: ChatMessageScrollSignature(message: lastMessage),
            activeToolSignature: viewModel.activeTool.map { "\($0.name):\($0.status.rawValue)" } ?? "",
            bottomInset: bottomInset
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(Motion.quick(reduceMotion: reduceMotion)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            return
        }
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, mode: ChatMessageListScrollMode) {
        switch mode {
        case .noScroll:
            return
        case .pinBottomWithAnimation:
            scrollToBottom(proxy: proxy, animated: true)
        case .pinBottomWithoutAnimation:
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scheduleDeferredBottomScroll(proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            scrollToBottom(proxy: proxy, animated: false)
            try? await Task.sleep(nanoseconds: 200_000_000)
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func loadMoreMessages(proxy: ScrollViewProxy) {
        loadMoreMessages(proxy: proxy) {}
    }

    private func autoLoadMore(proxy: ScrollViewProxy) {
        guard hasMoreMessages, !isAutoLoadingMore else {
            return
        }
        isAutoLoadingMore = true
        loadMoreMessages(proxy: proxy) {
            isAutoLoadingMore = false
        }
    }

    private func loadMoreMessages(proxy: ScrollViewProxy, completion: @escaping () -> Void) {
        guard hasMoreMessages else {
            completion()
            return
        }
        let anchorId = visibleMessages.first?.id
        visibleMessageCount = min(viewModel.messages.count, visibleMessageCount + pageSize)
        guard let anchorId else {
            completion()
            return
        }
        Task { @MainActor in
            await Task.yield()
            if reduceMotion {
                proxy.scrollTo(anchorId, anchor: .top)
            } else {
                withAnimation(Motion.quick(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(anchorId, anchor: .top)
                }
            }
            completion()
        }
    }

    @ViewBuilder
    private var chatBottomAnchor: some View {
        if shouldExposeBottomAnchorForUITests {
            Color.clear
                .frame(height: max(bottomInset, 1))
                .id("bottom")
                .accessibilityElement()
                .accessibilityIdentifier("chat-scroll-bottom-anchor")
        } else {
            Color.clear
                .frame(height: max(bottomInset, 1))
                .id("bottom")
        }
    }

    private var shouldExposeBottomAnchorForUITests: Bool {
        ProcessInfo.processInfo.environment["SIDEBAR_UI_TEST_EXPOSE_CHAT_SCROLL_ANCHOR"] == "1"
    }

    private func retryHeaderSlotState(for message: Message) -> ChatRetryHeaderSlotState {
        ChatRetryHeaderSlotState.resolve(
            messageID: message.id,
            latestRetryableAssistantMessageID: viewModel.latestRetryableAssistantMessageID,
            retryInFlightAssistantMessageID: viewModel.retryInFlightAssistantMessageID
        )
    }

    private func retryLatestFailedTurn() {
        Task {
            await viewModel.retryLatestFailedTurn()
        }
    }
}

private struct ScrollChangeToken: Equatable {
    let selectedConversationId: String?
    let messageCount: Int
    let penultimateMessageSignature: ChatMessageScrollSignature
    let lastMessageSignature: ChatMessageScrollSignature
    let activeToolSignature: String
    let bottomInset: CGFloat
}

enum ChatMessageListScrollMode: Equatable {
    case noScroll
    case pinBottomWithAnimation
    case pinBottomWithoutAnimation
}

enum ChatMessageListScrollBehavior {
    static func scrollMode(
        previousMessageCount: Int,
        messageCount: Int,
        previousLastMessage: ChatMessageScrollSignature,
        newPenultimateMessage: ChatMessageScrollSignature,
        newLastMessage: ChatMessageScrollSignature,
        activeToolChanged: Bool
    ) -> ChatMessageListScrollMode {
        guard !activeToolChanged else {
            return .noScroll
        }
        guard messageCount != previousMessageCount else {
            return .noScroll
        }
        guard messageCount > 0 else {
            return .noScroll
        }
        if isRetryAppend(
            previousMessageCount: previousMessageCount,
            messageCount: messageCount,
            previousLastMessage: previousLastMessage,
            newPenultimateMessage: newPenultimateMessage,
            newLastMessage: newLastMessage
        ) {
            return .pinBottomWithoutAnimation
        }
        return .pinBottomWithAnimation
    }

    static func scrollMode(
        previousMessages: [Message],
        messages: [Message],
        activeToolChanged: Bool
    ) -> ChatMessageListScrollMode {
        scrollMode(
            previousMessageCount: previousMessages.count,
            messageCount: messages.count,
            previousLastMessage: ChatMessageScrollSignature(message: previousMessages.last),
            newPenultimateMessage: ChatMessageScrollSignature(message: messages.dropLast().last),
            newLastMessage: ChatMessageScrollSignature(message: messages.last),
            activeToolChanged: activeToolChanged
        )
    }

    static func shouldScrollForLastMessageChange(
        from oldSignature: ChatMessageScrollSignature,
        to newSignature: ChatMessageScrollSignature,
        isStreaming: Bool,
        shouldScrollToBottom: Bool
    ) -> Bool {
        guard !isStreaming else {
            return true
        }
        guard !shouldScrollToBottom else {
            return true
        }
        let changedVisibleContent = oldSignature.id != newSignature.id
            || oldSignature.content != newSignature.content
            || oldSignature.status != newSignature.status
            || oldSignature.needsNewline != newSignature.needsNewline
            || oldSignature.error != newSignature.error
        return changedVisibleContent
    }

    static func shouldAnimateLastMessageChange(
        from oldSignature: ChatMessageScrollSignature,
        to newSignature: ChatMessageScrollSignature,
        isStreaming: Bool,
        shouldScrollToBottom: Bool
    ) -> Bool {
        guard !isStreaming, !shouldScrollToBottom else {
            return false
        }
        let isTerminalStreamTransition = oldSignature.id == newSignature.id
            && !oldSignature.id.isEmpty
            && oldSignature.status == .streaming
            && newSignature.status != .streaming
        return !isTerminalStreamTransition
    }

    static func shouldScrollForActiveToolChange() -> Bool {
        false
    }

    private static func isRetryAppend(
        previousMessageCount: Int,
        messageCount: Int,
        previousLastMessage: ChatMessageScrollSignature,
        newPenultimateMessage: ChatMessageScrollSignature,
        newLastMessage: ChatMessageScrollSignature
    ) -> Bool {
        guard messageCount == previousMessageCount + 1,
              !previousLastMessage.id.isEmpty,
              previousLastMessage == newPenultimateMessage else {
            return false
        }

        guard previousLastMessage.role == .assistant,
              previousLastMessage.status == .error,
              newLastMessage.role == .assistant,
              newLastMessage.status == .streaming else {
            return false
        }

        return ErrorMapping.chatStreamPresentation(
            from: previousLastMessage.errorDetails,
            fallbackUserMessage: previousLastMessage.error
        ).isRetryable
    }
}

struct ChatMessageScrollSignature: Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let status: MessageStatus
    let toolCallsSignature: String
    let needsNewline: Bool
    let error: String
    let errorDetails: String

    init(message: Message?) {
        guard let message else {
            id = ""
            role = .assistant
            content = ""
            status = .complete
            toolCallsSignature = ""
            needsNewline = false
            error = ""
            errorDetails = ""
            return
        }
        id = message.id
        role = message.role
        content = message.content
        status = message.status
        toolCallsSignature = (message.toolCalls ?? []).map {
            "\($0.id):\($0.name):\($0.status.rawValue):\($0.skillId ?? ""):\($0.iconKey ?? "")"
        }.joined(separator: "|")
        needsNewline = message.needsNewline ?? false
        error = message.error ?? ""
        errorDetails = message.errorDetails ?? ""
    }
}
