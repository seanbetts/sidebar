import SwiftUI

struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    let bottomInset: CGFloat
    @State private var shouldScrollToBottom = false
    @State private var visibleMessageCount: Int = 40
    @State private var isAutoLoadingMore = false
    private let pageSize: Int = 40
    private let maxContentWidth: CGFloat = 860
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
                        .padding(.vertical, 4)
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
                .padding(16)
                #if os(macOS)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                #endif
            }
            .task(id: viewModel.selectedConversationId) {
                guard viewModel.selectedConversationId != nil else {
                    return
                }
                shouldScrollToBottom = true
                await Task.yield()
                scrollToBottom(proxy: proxy, animated: false)
                try? await Task.sleep(nanoseconds: 200_000_000)
                scrollToBottom(proxy: proxy, animated: false)
                shouldScrollToBottom = false
            }
            .onChange(of: viewModel.selectedConversationId) { _, _ in
                visibleMessageCount = pageSize
                isAutoLoadingMore = false
                shouldScrollToBottom = true
            }
            .onChange(of: viewModel.messages.count) { oldValue, newValue in
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
            }
            .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                scrollToBottom(proxy: proxy, animated: shouldScrollToBottom == false)
            }
            .onChange(of: bottomInset) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
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
