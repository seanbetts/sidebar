import Foundation
import sideBarShared
import SwiftUI

struct ChatMessageCopyFeedbackState {
    static let resetDelayNanoseconds: UInt64 = 1_500_000_000

    private(set) var isCopied = false

    mutating func markCopied() {
        isCopied = true
    }

    mutating func reset() {
        isCopied = false
    }

    var iconName: String {
        isCopied ? "checkmark.circle.fill" : "doc.on.doc"
    }

    var accessibilityLabel: String {
        isCopied ? "Copied message" : "Copy message"
    }
}

struct ChatMessageRow: View {
    let message: Message
    let assistantDisplayName: String
    let retryHeaderSlotState: ChatRetryHeaderSlotState
    let onRetry: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyFeedback = ChatMessageCopyFeedbackState()
    @State private var resetCopyFeedbackTask: Task<Void, Never>?
    @State private var thinkingText = ChatMessagePresentation.thinkingPlaceholderText
    @State private var isAnimatingThinkingDismissal = false
    @State private var thinkingDismissalTask: Task<Void, Never>?
    private let maxBubbleWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    private let headerPillMinHeight: CGFloat = 22

    var body: some View {
        bubble
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if showsHeaderThinkingIndicator {
                    LoadingIndicatorView(size: 14)
                        .padding(.trailing, DesignTokens.Spacing.xxs)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                Text(message.role == .assistant ? assistantDisplayName : "You")
                    .appFont(.captionSemibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .frame(minHeight: headerPillMinHeight)
                    .background(rolePillBackground)
                    .foregroundStyle(rolePillText)
                    .overlay(rolePillBorder)
                    .clipShape(Capsule())
                Spacer()
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                        ToolCallListView(toolCalls: toolCalls, role: message.role)
                    }
                    if let errorPresentation {
                        ChatErrorPillView(presentation: errorPresentation)
                        if let errorHeaderState, errorHeaderState.occupiesRetryActionSlot {
                            ChatErrorRetryActionView(state: errorHeaderState, onRetry: onRetry)
                        }
                    }
                    Button {
                        copyMessage()
                        showCopyFeedback()
                    } label: {
                        Image(systemName: copyFeedback.iconName)
                            .appFont(.caption)
                            .foregroundStyle(copyFeedback.isCopied ? copiedIconForeground : .secondary)
                            .padding(DesignTokens.Spacing.xxs)
                            .background(copyFeedback.isCopied ? copiedIconBackground : .clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(showsThinkingBody)
                    .opacity(showsThinkingBody ? 0.45 : 1.0)
                    .accessibilityLabel(copyFeedback.accessibilityLabel)
                }
                .animation(Motion.quick(reduceMotion: reduceMotion), value: copyFeedback.isCopied)
            }
            .animation(Motion.quick(reduceMotion: reduceMotion), value: showsHeaderThinkingIndicator)

            if showsThinkingBody {
                Text(thinkingText)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SideBarMarkdown(text: message.content, style: .chat)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !workspaceSurfaceTargets.isEmpty {
                WorkspaceSurfaceInlineActionsBar(targets: workspaceSurfaceTargets)
            }

            HStack {
                Spacer()
                Text(formattedTimestamp)
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
        .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
        .background(bubbleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.mdPlus, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.mdPlus, style: .continuous))
        .frame(maxWidth: maxBubbleWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .onDisappear {
            resetCopyFeedbackTask?.cancel()
            resetCopyFeedbackTask = nil
            thinkingDismissalTask?.cancel()
            thinkingDismissalTask = nil
        }
        .onAppear {
            syncThinkingPlaceholder()
        }
        .onChange(of: messageContentIsEffectivelyEmpty) { wasEmpty, isEmpty in
            handleMessageContentEmptinessChange(from: wasEmpty, to: isEmpty)
        }
        .onChange(of: message.status) { _, newStatus in
            if newStatus != .streaming {
                stopThinkingDismissalAnimation(resetText: true)
            }
        }
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
        Capsule()
            .stroke(pillBorderColor, lineWidth: 1)
    }

    private var pillBorderColor: Color {
        if colorScheme == .light, message.role == .assistant {
            return DesignTokens.Colors.border
        }
        return .clear
    }

    private var copiedIconForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var copiedIconBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var showsThinkingPlaceholder: Bool {
        ChatMessagePresentation.showsThinkingPlaceholder(for: message)
    }

    private var messageContentIsEffectivelyEmpty: Bool {
        ChatMessagePresentation.isContentEffectivelyEmpty(message.content)
    }

    private var showsThinkingBody: Bool {
        showsThinkingPlaceholder || isAnimatingThinkingDismissal
    }

    private var showsHeaderThinkingIndicator: Bool {
        ChatMessagePresentation.showsHeaderThinkingIndicator(for: message)
    }

    private var workspaceSurfaceTargets: [ToolResultWorkspaceSurfaceTarget] {
        guard message.role == .assistant,
              let toolCalls = message.toolCalls,
              !toolCalls.isEmpty else {
            return []
        }
        return ToolResultWorkspaceSurfaceParser.parse(toolCalls: toolCalls)
    }

    private var errorPresentation: ChatStreamErrorPresentation? {
        guard message.status == .error else {
            return nil
        }
        guard message.error?.trimmedOrNil != nil || message.errorDetails?.trimmedOrNil != nil else {
            return nil
        }
        return ErrorMapping.chatStreamPresentation(
            from: message.errorDetails,
            fallbackUserMessage: message.error
        )
    }

    private var errorHeaderState: ChatErrorHeaderState? {
        Self.retryHeaderState(
            message: message,
            retryHeaderSlotState: retryHeaderSlotState
        )
    }

    static func retryHeaderState(
        message: Message,
        retryHeaderSlotState: ChatRetryHeaderSlotState
    ) -> ChatErrorHeaderState? {
        guard message.status == .error,
              message.error?.trimmedOrNil != nil || message.errorDetails?.trimmedOrNil != nil else {
            return nil
        }
        let presentation = ErrorMapping.chatStreamPresentation(
            from: message.errorDetails,
            fallbackUserMessage: message.error
        )
        return ChatErrorHeaderState(
            presentation: presentation,
            slotState: retryHeaderSlotState
        )
    }

    private func handleMessageContentEmptinessChange(from wasEmpty: Bool, to isEmpty: Bool) {
        if message.role == .assistant,
           message.status == .streaming,
           wasEmpty,
           !isEmpty {
            startThinkingDismissalAnimationIfNeeded()
            return
        }

        if isEmpty {
            syncThinkingPlaceholder()
        }
    }

    private func startThinkingDismissalAnimationIfNeeded() {
        guard !isAnimatingThinkingDismissal else {
            return
        }
        isAnimatingThinkingDismissal = true
        thinkingDismissalTask?.cancel()
        thinkingDismissalTask = Task { @MainActor in
            while !thinkingText.isEmpty {
                try? await Task.sleep(nanoseconds: ChatMessagePresentation.thinkingDismissalFrameIntervalNanoseconds)
                if Task.isCancelled {
                    return
                }
                thinkingText.removeLast()
            }
            isAnimatingThinkingDismissal = false
            thinkingText = ChatMessagePresentation.thinkingPlaceholderText
            thinkingDismissalTask = nil
        }
    }

    private func syncThinkingPlaceholder() {
        guard showsThinkingPlaceholder else {
            return
        }
        thinkingText = ChatMessagePresentation.thinkingPlaceholderText
        if isAnimatingThinkingDismissal {
            stopThinkingDismissalAnimation(resetText: true)
        }
    }

    private func stopThinkingDismissalAnimation(resetText: Bool) {
        thinkingDismissalTask?.cancel()
        thinkingDismissalTask = nil
        isAnimatingThinkingDismissal = false
        if resetText {
            thinkingText = ChatMessagePresentation.thinkingPlaceholderText
        }
    }

    private func copyMessage() {
        let text = message.content
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == text {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func showCopyFeedback() {
        copyFeedback.markCopied()
        resetCopyFeedbackTask?.cancel()
        resetCopyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ChatMessageCopyFeedbackState.resetDelayNanoseconds)
            copyFeedback.reset()
            resetCopyFeedbackTask = nil
        }
    }
}

enum ChatMessagePresentation {
    static let thinkingPlaceholderText = "Thinking..."
    static let thinkingDismissalFrameIntervalNanoseconds: UInt64 = 20_000_000

    static func showsThinkingPlaceholder(for message: Message) -> Bool {
        guard isAssistantStreaming(message) else {
            return false
        }
        return isContentEffectivelyEmpty(message.content)
    }

    static func showsHeaderThinkingIndicator(for message: Message) -> Bool {
        isAssistantStreaming(message)
    }

    static func shouldAnimateThinkingDismissal(
        for message: Message,
        previousContent: String,
        newContent: String
    ) -> Bool {
        guard isAssistantStreaming(message) else {
            return false
        }
        return isContentEffectivelyEmpty(previousContent) && !isContentEffectivelyEmpty(newContent)
    }

    static func isContentEffectivelyEmpty(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isAssistantStreaming(_ message: Message) -> Bool {
        message.role == .assistant && message.status == .streaming
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
