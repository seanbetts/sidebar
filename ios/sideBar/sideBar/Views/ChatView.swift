import SwiftUI

public struct ChatView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        #if os(macOS)
        ChatDetailView(viewModel: environment.chatViewModel)
            .task {
                await environment.chatViewModel.loadConversations()
            }
        #else
        if horizontalSizeClass == .compact {
            ChatCompactView(viewModel: environment.chatViewModel)
        } else {
            ChatDetailView(viewModel: environment.chatViewModel)
                .task {
                    await environment.chatViewModel.loadConversations()
                }
        }
        #endif
    }
}

private struct ChatCompactView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.conversations.isEmpty {
                    ChatEmptyStateView(title: "No conversations", subtitle: "Start a chat on another device.")
                } else {
                    List {
                        ForEach(viewModel.groupedConversations) { group in
                            Section(group.title) {
                                ForEach(group.conversations) { conversation in
                                    NavigationLink(value: conversation.id) {
                                        CompactConversationRow(conversation: conversation)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.refreshConversations()
                    }
                }
            }
            .navigationTitle("Chat")
            .task {
                await viewModel.loadConversations()
                if let selected = viewModel.selectedConversationId, path.isEmpty {
                    path = [selected]
                }
            }
            .navigationDestination(for: String.self) { conversationId in
                ChatDetailView(viewModel: viewModel)
                    .task {
                        await viewModel.selectConversation(id: conversationId)
                    }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct CompactConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let preview = conversation.firstMessage, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        guard let date = DateParsing.parseISO8601(conversation.updatedAt) else {
            return conversation.updatedAt
        }
        return DateFormatter.chatListCompact.string(from: date)
    }
}

private struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(viewModel: viewModel)
            Divider()
            if viewModel.isLoadingMessages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selectedConversationId == nil {
                ChatEmptyStateView(title: "Select a conversation", subtitle: "Choose a thread to view messages.")
            } else if viewModel.messages.isEmpty {
                ChatEmptyStateView(title: "No messages", subtitle: "This conversation is empty.")
            } else {
                ChatMessageListView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTitle)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.isStreaming {
                    Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let activeTool = viewModel.activeTool {
                ChatActiveToolBanner(activeTool: activeTool)
            }

            if let promptPreview = viewModel.promptPreview {
                PromptPreviewView(promptPreview: promptPreview)
            }
        }
        .padding(16)
        .background(headerBackground)
    }

    private var selectedTitle: String {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "Chat"
        }
        return conversation.title
    }

    private var subtitle: String? {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return nil
        }
        return "Updated \(formattedDate(conversation.updatedAt))"
    }

    private func formattedDate(_ raw: String) -> String {
        guard let date = DateParsing.parseISO8601(raw) else {
            return raw
        }
        return DateFormatter.chatHeader.string(from: date)
    }

    private var headerBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

private struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let last = viewModel.messages.last else {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                guard let last = viewModel.messages.last else {
                    return
                }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ChatMessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                bubble
                Spacer()
            } else {
                Spacer()
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(message.role == .assistant ? "Assistant" : "You")
                    .font(.caption.weight(.semibold))
                Text(formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MarkdownText(content: message.content)

            if message.status == .error, let error = message.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                ToolCallListView(toolCalls: toolCalls)
            }
        }
        .padding(12)
        .background(bubbleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 520, alignment: message.role == .assistant ? .leading : .trailing)
    }

    private var formattedTimestamp: String {
        guard let date = DateParsing.parseISO8601(message.timestamp) else {
            return message.timestamp
        }
        return DateFormatter.chatTimestamp.string(from: date)
    }

    private var bubbleBackground: Color {
        #if os(macOS)
        return message.role == .assistant
            ? Color(nsColor: .controlBackgroundColor)
            : Color(nsColor: .underPageBackgroundColor)
        #else
        return message.role == .assistant
            ? Color(uiColor: .secondarySystemBackground)
            : Color(uiColor: .systemGray6)
        #endif
    }

    private var bubbleBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
}

private struct MarkdownText: View {
    let content: String

    var body: some View {
        Text(attributedContent)
            .textSelection(.enabled)
            .font(.body)
            .foregroundStyle(.primary)
    }

    private var attributedContent: AttributedString {
        if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .full)) {
            return attributed
        }
        return AttributedString(content)
    }
}

private struct ToolCallListView: View {
    let toolCalls: [ToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tool Calls")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(toolCalls) { toolCall in
                ToolCallRow(toolCall: toolCall)
            }
        }
        .padding(8)
        .background(toolBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct ToolCallRow: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(toolCall.name)
                    .font(.subheadline.weight(.semibold))
                Text(toolCall.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !toolCall.parameters.isEmpty {
                Text(formatJSON(toolCall.parameters.mapValues { $0.value }))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let result = toolCall.result {
                Text(formatJSON(result.value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .pending:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var rowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private func formatJSON(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let output = String(data: data, encoding: .utf8) {
            return output
        }
        return String(describing: value)
    }
}

private struct ChatActiveToolBanner: View {
    let activeTool: ChatActiveTool

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(activeTool.name)
                    .font(.subheadline.weight(.semibold))
                Text(activeTool.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bannerBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch activeTool.status {
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct PromptPreviewView: View {
    let promptPreview: ChatPromptPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let system = promptPreview.systemPrompt, !system.isEmpty {
                Text(system)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let first = promptPreview.firstMessagePrompt, !first.isEmpty {
                Text(first)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(promptBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var promptBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct ChatEmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension DateFormatter {
    static let chatTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let chatListCompact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let chatHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
