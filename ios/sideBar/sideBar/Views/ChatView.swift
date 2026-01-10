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
                environment.chatViewModel.startAutoRefresh()
            }
            .onDisappear {
                environment.chatViewModel.stopAutoRefresh()
            }
        #else
        if horizontalSizeClass == .compact {
            ChatCompactView(viewModel: environment.chatViewModel)
        } else {
            ChatDetailView(viewModel: environment.chatViewModel)
                .task {
                    await environment.chatViewModel.loadConversations()
                    environment.chatViewModel.startAutoRefresh()
                }
                .onDisappear {
                    environment.chatViewModel.stopAutoRefresh()
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
                viewModel.startAutoRefresh()
                if let selected = viewModel.selectedConversationId, path.isEmpty {
                    path = [selected]
                }
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
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
            Text(subtitleText)
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

    private var subtitleText: String {
        let count = conversation.messageCount
        let label = count == 1 ? "1 message" : "\(count) messages"
        return "\(formattedDate) | \(label)"
    }
}

private struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draftMessage: String = ""
    private let inputBarHeight: CGFloat = 60

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ChatHeaderView(viewModel: viewModel)
                Divider()
                if viewModel.isLoadingMessages {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.selectedConversationId == nil {
                    EmptyView()
                } else if viewModel.messages.isEmpty {
                    ChatEmptyStateView(title: "No messages", subtitle: "This conversation is empty.")
                } else {
                    ChatMessageListView(viewModel: viewModel)
                        .padding(.bottom, inputBarHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ChatInputBar(
                text: $draftMessage,
                isEnabled: true
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

private struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        .frame(minHeight: LayoutMetrics.contentHeaderMinHeight)
        .background(headerBackground)
    }

    private var selectedTitle: String {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "New Chat"
        }
        return conversation.title
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
            .refreshable {
                await viewModel.refreshConversations()
                await viewModel.refreshActiveConversation()
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
            .padding(10)
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

private struct ChatInputBar: View {
    @Binding var text: String
    let isEnabled: Bool

    @State private var textHeight: CGFloat = 0
    private let minHeight: CGFloat = 46
    private let maxHeight: CGFloat = 140

    var body: some View {
        PlatformChatInputView(
            text: $text,
            measuredHeight: $textHeight,
            isEnabled: isEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        .frame(height: computedHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
    }

    private var shadowColor: Color {
        Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.4)
        #else
        return Color(uiColor: .separator).opacity(0.4)
        #endif
    }

    private var computedHeight: CGFloat {
        let clamped = min(max(textHeight, minHeight), maxHeight)
        return clamped
    }
}

private struct PlatformChatInputView: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        #if os(iOS)
        ChatInputUIKitView(
            text: $text,
            measuredHeight: $measuredHeight,
            isEnabled: isEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        #else
        ChatInputAppKitView(
            text: $text,
            measuredHeight: $measuredHeight,
            isEnabled: isEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        #endif
    }
}

#if os(iOS)
private struct ChatInputUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = 16

        let textView = UITextView()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 44, bottom: 4, right: 48)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let placeholderLabel = UILabel()
        placeholderLabel.text = "Ask Anything..."
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = UIColor.secondaryLabel
        placeholderLabel.numberOfLines = 1

        let attachButton = UIButton(type: .system)
        attachButton.setImage(UIImage(systemName: "paperclip.circle.fill"), for: .normal)
        attachButton.clipsToBounds = true

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTapSend), for: .touchUpInside)

        effectView.contentView.addSubview(textView)
        effectView.contentView.addSubview(placeholderLabel)
        effectView.contentView.addSubview(attachButton)
        effectView.contentView.addSubview(button)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        let placeholderCenter = placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        placeholderCenter.priority = .defaultHigh

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 44),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -48),
            placeholderLabel.topAnchor.constraint(greaterThanOrEqualTo: textView.topAnchor, constant: 8),
            attachButton.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -10),
            attachButton.widthAnchor.constraint(equalToConstant: 28),
            attachButton.heightAnchor.constraint(equalToConstant: 28),
            button.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        placeholderCenter.isActive = true

        context.coordinator.textView = textView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return effectView
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        guard let textView = context.coordinator.textView,
              let button = context.coordinator.sendButton,
              let attachButton = context.coordinator.attachButton,
              let placeholderLabel = context.coordinator.placeholderLabel else {
            return
        }
        if textView.text != text {
            textView.text = text
        }
        textView.isEditable = isEnabled
        let canSend = isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        button.isEnabled = canSend
        button.alpha = canSend ? 1.0 : 0.45
        let tintColor: UIColor
        if uiView.traitCollection.userInterfaceStyle == .dark {
            tintColor = .white
        } else {
            tintColor = .black
        }
        button.backgroundColor = .clear
        button.tintColor = canSend ? tintColor : UIColor.systemGray3
        attachButton.tintColor = tintColor
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight, minHeight: minHeight, maxHeight: maxHeight)
    }

    private func recalculateHeight(for textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let height = min(maxHeight, max(minHeight, size.height))
        if measuredHeight != height {
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        weak var textView: UITextView?
        weak var sendButton: UIButton?
        weak var attachButton: UIButton?
        weak var placeholderLabel: UILabel?

        init(text: Binding<String>, measuredHeight: Binding<CGFloat>, minHeight: CGFloat, maxHeight: CGFloat) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.minHeight = minHeight
            self.maxHeight = maxHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            placeholderLabel?.isHidden = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            let height = min(maxHeight, max(minHeight, size.height))
            if measuredHeight.wrappedValue != height {
                measuredHeight.wrappedValue = height
            }
        }

        @objc func didTapSend() {
        }
    }
}
#endif

#if os(macOS)
private struct ChatInputAppKitView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .withinWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16

        let textView = NSTextView()
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.string = text

        let placeholderLabel = NSTextField(labelWithString: "Ask Anything...")
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.isBordered = false
        placeholderLabel.isEditable = false
        placeholderLabel.lineBreakMode = .byTruncatingTail

        let attachButton = NSButton()
        attachButton.bezelStyle = .regularSquare
        attachButton.isBordered = false
        attachButton.image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: nil)

        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil)
        button.wantsLayer = true
        button.layer?.cornerRadius = 14
        button.target = context.coordinator
        button.action = #selector(Coordinator.didTapSend)

        effectView.addSubview(textView)
        effectView.addSubview(placeholderLabel)
        effectView.addSubview(attachButton)
        effectView.addSubview(button)
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        let placeholderCenter = placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        placeholderCenter.priority = .defaultHigh

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: effectView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 44),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -48),
            placeholderLabel.topAnchor.constraint(greaterThanOrEqualTo: textView.topAnchor, constant: 8),
            attachButton.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),
            attachButton.widthAnchor.constraint(equalToConstant: 28),
            attachButton.heightAnchor.constraint(equalToConstant: 28),
            button.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        placeholderCenter.isActive = true

        context.coordinator.textView = textView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        guard let textView = context.coordinator.textView,
              let button = context.coordinator.sendButton,
              let attachButton = context.coordinator.attachButton,
              let placeholderLabel = context.coordinator.placeholderLabel else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        let canSend = isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        button.isEnabled = canSend
        button.alphaValue = canSend ? 1.0 : 0.45
        let tintColor: NSColor
        if nsView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            tintColor = .white
        } else {
            tintColor = .black
        }
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.contentTintColor = canSend ? tintColor : NSColor.systemGray
        attachButton.contentTintColor = tintColor
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight, minHeight: minHeight, maxHeight: maxHeight)
    }

    private func recalculateHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = min(maxHeight, max(minHeight, usedRect.height + textView.textContainerInset.height * 2))
        if measuredHeight != height {
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        weak var textView: NSTextView?
        weak var sendButton: NSButton?
        weak var attachButton: NSButton?
        weak var placeholderLabel: NSTextField?

        init(text: Binding<String>, measuredHeight: Binding<CGFloat>, minHeight: CGFloat, maxHeight: CGFloat) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.minHeight = minHeight
            self.maxHeight = maxHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            placeholderLabel?.isHidden = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = min(maxHeight, max(minHeight, usedRect.height + textView.textContainerInset.height * 2))
            if measuredHeight.wrappedValue != height {
                measuredHeight.wrappedValue = height
            }
        }

        @objc func didTapSend() {
        }
    }
}
#endif

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
        formatter.timeStyle = .none
        return formatter
    }()

    static let chatHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
