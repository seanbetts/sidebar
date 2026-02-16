import SwiftUI

struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    let bottomInset: CGFloat
    @State private var shouldScrollToBottom = false
    @State private var visibleMessageCount: Int = 40
    @State private var isAutoLoadingMore = false
    @State private var lastStreamingAutoScrollAt: Date = .distantPast
    private let pageSize: Int = 40
    private let streamingScrollThrottleSeconds: TimeInterval = 0.08
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
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(isAutoLoadingMore)
                            if isAutoLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .onAppear {
                            autoLoadMore(proxy: proxy)
                        }
                    }
                    ForEach(visibleMessages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: max(bottomInset, 1))
                        .id("bottom")
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: ChatLayout.maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: scrollChangeToken) { oldToken, newToken in
                if oldToken.selectedConversationId != newToken.selectedConversationId {
                    visibleMessageCount = pageSize
                    isAutoLoadingMore = false
                    lastStreamingAutoScrollAt = .distantPast
                    shouldScrollToBottom = true
                    scrollToBottom(proxy: proxy, animated: false)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    shouldScrollToBottom = false
                    return
                }

                if oldToken.messageCount != newToken.messageCount {
                    lastStreamingAutoScrollAt = .distantPast
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
                    scrollToBottom(proxy: proxy, animated: !shouldJump)
                    if shouldJump {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                    shouldScrollToBottom = false
                    return
                }

                if oldToken.lastMessageSignature != newToken.lastMessageSignature {
                    if viewModel.isStreaming {
                        let now = Date()
                        if now.timeIntervalSince(lastStreamingAutoScrollAt) >= streamingScrollThrottleSeconds {
                            lastStreamingAutoScrollAt = now
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                        return
                    }
                    scrollToBottom(proxy: proxy, animated: shouldScrollToBottom == false)
                    return
                }

                if oldToken.bottomInset != newToken.bottomInset {
                    scrollToBottom(proxy: proxy, animated: false)
                }
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
            lastMessageSignature: "\(lastMessage?.id ?? ""):\(lastMessage?.content ?? "")",
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
}

private struct ScrollChangeToken: Equatable {
    let selectedConversationId: String?
    let messageCount: Int
    let lastMessageSignature: String
    let bottomInset: CGFloat
}
