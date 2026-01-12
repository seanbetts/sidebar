import SwiftUI

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
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isScratchpadPresented = false
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !isCompact {
                    ChatHeaderView(viewModel: viewModel)
                    Divider()
                }
                if viewModel.isLoadingMessages {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.selectedConversationId == nil {
                    EmptyView()
                } else if viewModel.messages.isEmpty {
                    ChatEmptyStateView(title: "No messages", subtitle: "This conversation is empty.")
                } else {
                    ChatMessageListView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ChatInputBar(
                text: $draftMessage,
                isEnabled: true
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            #if os(macOS)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .center)
            #endif
        }
        #if !os(macOS)
        .overlay(alignment: .bottomTrailing) {
            if isCompact {
                Button {
                    isScratchpadPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
                .accessibilityLabel("Scratchpad")
                .padding(.trailing, 16)
                .padding(.bottom, inputBarHeight + 24)
            }
        }
        .sheet(isPresented: $isScratchpadPresented) {
            ScratchpadPopoverView(
                api: environment.container.scratchpadAPI,
                cache: environment.container.cacheClient
            )
        }
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 6) {
                headerContent
            }
            .padding(16)
            .frame(minHeight: LayoutMetrics.contentHeaderMinHeight)
            .background(headerBackground)
        } else {
        VStack(alignment: .leading, spacing: 6) {
            headerContent

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
    }

    private var headerContent: some View {
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
    }

    private var selectedTitle: String {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "New Chat"
        }
        return conversation.title
    }

    private var headerBackground: Color {
        DesignTokens.Colors.background
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct ChatMessageListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var shouldScrollToBottom = false
    private let maxContentWidth: CGFloat = 860
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
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
                shouldScrollToBottom = true
            }
            .onChange(of: viewModel.messages.count) { _, _ in
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
            .refreshable {
                await viewModel.refreshConversations()
                await viewModel.refreshActiveConversation()
            }
        }
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
}

private struct ChatMessageRow: View {
    let message: Message
    @Environment(\.colorScheme) private var colorScheme
    private let maxBubbleWidth: CGFloat = 860

    var body: some View {
        bubble
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(message.role == .assistant ? "sideBar" : "You")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(rolePillBackground)
                    .foregroundStyle(rolePillText)
                    .overlay(rolePillBorder)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    copyMessage()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            SideBarMarkdown(text: message.content)
                .frame(maxWidth: .infinity, alignment: .leading)

            if message.status == .error, let error = message.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Text(formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(bubbleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        #if os(macOS)
        .frame(maxWidth: maxBubbleWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        #else
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .center)
        #endif
    }

    private var formattedTimestamp: String {
        guard let date = DateParsing.parseISO8601(message.timestamp) else {
            return message.timestamp
        }
        return DateFormatter.chatTimestamp.string(from: date)
    }

    private var bubbleBackground: Color {
        message.role == .assistant ? DesignTokens.Colors.surface : DesignTokens.Colors.muted
    }

    private var bubbleBorder: Color {
        DesignTokens.Colors.border
    }

    private var rolePillBackground: Color {
        if colorScheme == .dark {
            return message.role == .assistant ? Color.black : Color.white
        }
        return message.role == .assistant ? Color.white : Color.black
    }

    private var rolePillText: Color {
        if colorScheme == .dark {
            return message.role == .assistant ? Color.white : Color.black
        }
        return message.role == .assistant ? Color.black : Color.white
    }

    @ViewBuilder
    private var rolePillBorder: some View {
        if colorScheme == .light, message.role == .assistant {
            Capsule()
                .stroke(pillBorderColor, lineWidth: 1)
        }
    }

    private var pillBorderColor: Color {
        DesignTokens.Colors.border
    }

    private func copyMessage() {
        #if os(iOS)
        UIPasteboard.general.string = message.content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
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
        DesignTokens.Colors.surface
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
        DesignTokens.Colors.surface
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
        DesignTokens.Colors.surface
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
        DesignTokens.Colors.surface
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
    @Environment(\.colorScheme) private var colorScheme
    private let maxInputWidth: CGFloat = 860

    var body: some View {
        ChatInputContainer {
            PlatformChatInputView(
                text: $text,
                measuredHeight: $textHeight,
                isEnabled: isEnabled,
                minHeight: minHeight,
                maxHeight: maxHeight
            )
            .frame(height: computedHeight)
            .modifier(GlassEffectModifier())
        }
        .frame(maxWidth: maxInputWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowRadius * 0.6)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        let color = DesignTokens.Colors.border
        return colorScheme == .dark ? color.opacity(0.95) : color.opacity(0.7)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 6 : 10
    }

    private var computedHeight: CGFloat {
        let clamped = min(max(textHeight, minHeight), maxHeight)
        return clamped
    }

    private var minHeight: CGFloat {
        #if os(macOS)
        return 84
        #else
        return 46
        #endif
    }

    private var maxHeight: CGFloat {
        #if os(macOS)
        return 240
        #else
        return 140
        #endif
    }
}

private struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct ChatInputContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
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

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        let textView = UITextView()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = UIColor.label
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

        containerView.addSubview(textView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(attachButton)
        containerView.addSubview(button)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        let placeholderCenter = placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        placeholderCenter.priority = .defaultHigh

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 44),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -48),
            placeholderLabel.topAnchor.constraint(greaterThanOrEqualTo: textView.topAnchor, constant: 8),
            attachButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            attachButton.widthAnchor.constraint(equalToConstant: 28),
            attachButton.heightAnchor.constraint(equalToConstant: 28),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        placeholderCenter.isActive = true

        context.coordinator.textView = textView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
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
        let tintColor: UIColor = .label
        button.backgroundColor = .clear
        button.tintColor = canSend ? tintColor : UIColor.secondaryLabel
        attachButton.tintColor = UIColor.secondaryLabel
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
    private let controlBarHeight: CGFloat = 44

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        let textView = NSTextView()
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.textColor = .labelColor
        textView.string = text

        let controlBar = NSView()
        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor.clear.cgColor

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
        attachButton.image = NSImage(
            systemSymbolName: "paperclip.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        )

        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "arrow.up.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        )
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.target = context.coordinator
        button.action = #selector(Coordinator.didTapSend)

        containerView.addSubview(textView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(controlBar)
        controlBar.addSubview(attachButton)
        controlBar.addSubview(button)
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: controlBar.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -16),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.height + 2),
            controlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: controlBarHeight),
            attachButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 6),
            attachButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 48),
            attachButton.heightAnchor.constraint(equalToConstant: 48),
            button.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        context.coordinator.textView = textView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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
        let tintColor: NSColor = .labelColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.contentTintColor = canSend ? tintColor : NSColor.secondaryLabelColor
        attachButton.contentTintColor = NSColor.secondaryLabelColor
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            controlBarHeight: controlBarHeight
        )
    }

    private func recalculateHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentHeight = usedRect.height + textView.textContainerInset.height * 2
        let height = min(maxHeight, max(minHeight, contentHeight + controlBarHeight))
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
        private let controlBarHeight: CGFloat
        weak var textView: NSTextView?
        weak var sendButton: NSButton?
        weak var attachButton: NSButton?
        weak var placeholderLabel: NSTextField?

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            controlBarHeight: CGFloat
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.controlBarHeight = controlBarHeight
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
            let contentHeight = usedRect.height + textView.textContainerInset.height * 2
            let height = min(maxHeight, max(minHeight, contentHeight + controlBarHeight))
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
