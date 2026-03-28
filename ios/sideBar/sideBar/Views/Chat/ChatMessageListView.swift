import SwiftUI

struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    let bottomInset: CGFloat
    let assistantDisplayName: String
    @State private var shouldScrollToBottom = false
    @State private var visibleMessageCount: Int = 40
    @State private var isAutoLoadingMore = false
    @State private var streamingAutoScrollTask: Task<Void, Never>?
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
                ChatStreamingDebugTrace.log(
                    "chatList.scrollChange",
                    details: [
                        "selectedChanged=\(oldToken.selectedConversationId != newToken.selectedConversationId)",
                        "messageCount=\(oldToken.messageCount)->\(newToken.messageCount)",
                        "lastChanged=\(oldToken.lastMessageSignature != newToken.lastMessageSignature)",
                        "activeToolChanged=\(oldToken.activeToolSignature != newToken.activeToolSignature)",
                        "bottomInset=\(Int(oldToken.bottomInset.rounded()))->\(Int(newToken.bottomInset.rounded()))",
                        "shouldScrollToBottom=\(shouldScrollToBottom)",
                        "streaming=\(viewModel.isStreaming)"
                    ].joined(separator: " ")
                )
                if oldToken.selectedConversationId != newToken.selectedConversationId {
                    visibleMessageCount = pageSize
                    isAutoLoadingMore = false
                    shouldScrollToBottom = true
                    scrollToBottom(proxy: proxy, animated: false)
                    scheduleDeferredBottomScroll(proxy: proxy)
                    shouldScrollToBottom = false
                    return
                }

                if oldToken.messageCount != newToken.messageCount {
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
                startStreamingAutoScrollLoopIfNeeded(proxy: proxy)
                scrollToBottom(proxy: proxy, animated: false)
                scheduleDeferredBottomScroll(proxy: proxy)
            }
            .onDisappear {
                stopStreamingAutoScrollLoop()
            }
            .onChange(of: viewModel.currentStreamMessageId) { _, newValue in
                stopStreamingAutoScrollLoop()
                guard newValue != nil else {
                    return
                }
                startStreamingAutoScrollLoopIfNeeded(proxy: proxy)
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
        ChatStreamingDebugTrace.log(
            "chatList.scrollToBottom",
            details: [
                "animated=\(animated)",
                "streaming=\(viewModel.isStreaming)",
                "messageCount=\(viewModel.messages.count)",
                "streamMessage=\(ChatStreamingDebugTrace.shortID(viewModel.currentStreamMessageId))"
            ].joined(separator: " ")
        )
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
            ChatStreamingDebugTrace.log(
                "chatList.scheduleDeferredBottomScroll",
                details: "messageCount=\(viewModel.messages.count)"
            )
            await Task.yield()
            scrollToBottom(proxy: proxy, animated: false)
            try? await Task.sleep(nanoseconds: 200_000_000)
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func startStreamingAutoScrollLoopIfNeeded(proxy: ScrollViewProxy) {
        guard streamingAutoScrollTask == nil else {
            return
        }
        ChatStreamingDebugTrace.log(
            "chatList.streamingAutoScroll.start",
            details: [
                "messageCount=\(viewModel.messages.count)",
                "streamMessage=\(ChatStreamingDebugTrace.shortID(viewModel.currentStreamMessageId))"
            ].joined(separator: " ")
        )
        let pollIntervalNanoseconds = UInt64(ChatStreamingAutoScrollController().throttleSeconds * 1_000_000_000)
        streamingAutoScrollTask = Task { @MainActor in
            var lastSignature = ChatStreamingContentSignature(message: viewModel.messages.last)
            while !Task.isCancelled {
                guard viewModel.isStreaming else {
                    break
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                if Task.isCancelled {
                    return
                }
                let nextSignature = ChatStreamingContentSignature(message: viewModel.messages.last)
                guard nextSignature != lastSignature else {
                    continue
                }
                ChatStreamingDebugTrace.log(
                    "chatList.streamingAutoScroll.tick",
                    details: [
                        "message=\(nextSignature.id)",
                        "contentCount=\(lastSignature.contentCount)->\(nextSignature.contentCount)",
                        "status=\(lastSignature.status.rawValue)->\(nextSignature.status.rawValue)"
                    ].joined(separator: " ")
                )
                lastSignature = nextSignature
                scrollToBottom(proxy: proxy, animated: false)
            }
            streamingAutoScrollTask = nil
        }
    }

    private func stopStreamingAutoScrollLoop() {
        if streamingAutoScrollTask != nil {
            ChatStreamingDebugTrace.log("chatList.streamingAutoScroll.stop")
        }
        streamingAutoScrollTask?.cancel()
        streamingAutoScrollTask = nil
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
