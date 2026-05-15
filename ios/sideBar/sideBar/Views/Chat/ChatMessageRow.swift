import Foundation
import sideBarShared
import SwiftUI

enum ChatMessageCopyFeedbackForegroundStyle: Equatable {
    case secondary
    case primary
}

struct ChatMessageCopyFeedbackState {
    static let resetDelayNanoseconds: UInt64 = 1_500_000_000

    private(set) var isCopied = false

    mutating func markCopied() {
        isCopied = true
    }

    mutating func reset() {
        isCopied = false
    }

    var appIcon: AppIcon {
        isCopied ? AppIcon.State.successCircle : AppIcon.Action.copy
    }

    var accessibilityLabel: String {
        isCopied ? "Copied message" : "Copy message"
    }

    var foregroundStyle: ChatMessageCopyFeedbackForegroundStyle {
        isCopied ? .primary : .secondary
    }

    var usesContrastingBackground: Bool {
        false
    }
}

struct ChatMessageRow: View {
    let message: Message
    let assistantDisplayName: String
    let retryHeaderSlotState: ChatRetryHeaderSlotState
    let toolActions: [ChatToolAction]
    let onRetry: () -> Void
    let onToolAction: (ChatToolAction, ChatToolActionDecision?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyFeedback = ChatMessageCopyFeedbackState()
    @State private var resetCopyFeedbackTask: Task<Void, Never>?
    @State private var thinkingText = ChatMessagePresentation.thinkingPlaceholderText
    @State private var isAnimatingThinkingDismissal = false
    @State private var thinkingDismissalTask: Task<Void, Never>?
    @State private var showCompletionIndicator = false
    @State private var completionIndicatorTask: Task<Void, Never>?
    private let maxBubbleWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    private let headerPillMinHeight: CGFloat = 22
    private var lookupToken: String { Self.lookupToken(for: message.content) }

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
                } else if showCompletionIndicator {
                    SuccessCheckBadge(size: 14, symbolSize: 8)
                        .padding(.trailing, DesignTokens.Spacing.xxs)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                MetadataPill(message.role == .assistant ? assistantDisplayName : "You")
                    .frame(minHeight: headerPillMinHeight)
                    .layoutPriority(1)
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
                        Image(appIcon: copyFeedback.appIcon)
                            .appFont(.caption)
                            .foregroundStyle(copyFeedbackForeground)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: headerPillMinHeight, height: headerPillMinHeight)
                    }
                    .buttonStyle(.plain)
                    .disabled(showsThinkingBody)
                    .opacity(showsThinkingBody ? 0.45 : 1.0)
                    .accessibilityLabel(copyFeedback.accessibilityLabel)
                }
                .animation(Motion.quick(reduceMotion: reduceMotion), value: copyFeedback.isCopied)
            }
            .animation(Motion.quick(reduceMotion: reduceMotion), value: showsHeaderThinkingIndicator)
            .animation(Motion.quick(reduceMotion: reduceMotion), value: showCompletionIndicator)

            if showsThinkingBody {
                Text(thinkingText)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SideBarMarkdown(text: renderedMessageContent, style: .chat)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("chat-message-content-\(message.id)-\(lookupToken)")
                    .accessibilityLabel(renderedMessageContent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !toolActions.isEmpty {
                ChatToolActionListView(
                    actions: toolActions,
                    onAction: onToolAction
                )
            }

            if !workspaceSurfaceTargets.isEmpty {
                WorkspaceSurfaceInlineActionsBar(targets: workspaceSurfaceTargets)
            }
            if !workspaceOpenEntityTargets.isEmpty {
                WorkspaceOpenEntityInlineActionsBar(targets: workspaceOpenEntityTargets)
            }

            HStack {
                Spacer()
                Text(formattedTimestamp)
                    .appFont(.caption)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-message-row-\(message.id)-\(lookupToken)")
        .accessibilityValue(renderedMessageContent)
        .onDisappear {
            resetCopyFeedbackTask?.cancel()
            resetCopyFeedbackTask = nil
            thinkingDismissalTask?.cancel()
            thinkingDismissalTask = nil
            completionIndicatorTask?.cancel()
            completionIndicatorTask = nil
        }
        .onAppear {
            syncThinkingPlaceholder()
        }
        .onChange(of: messageContentIsEffectivelyEmpty) { wasEmpty, isEmpty in
            handleMessageContentEmptinessChange(from: wasEmpty, to: isEmpty)
        }
        .onChange(of: message.status) { oldStatus, newStatus in
            if newStatus != .streaming {
                stopThinkingDismissalAnimation(resetText: true)
            }
            handleMessageStatusChange(from: oldStatus, to: newStatus)
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

    private var copyFeedbackForeground: Color {
        switch copyFeedback.foregroundStyle {
        case .secondary:
            return .secondary
        case .primary:
            return Color.primary
        }
    }

    private var showsThinkingPlaceholder: Bool {
        ChatMessagePresentation.showsThinkingPlaceholder(for: message)
    }
    private var renderedMessageContent: String {
        guard message.role == .assistant, messageContentIsEffectivelyEmpty else {
            return message.content
        }
        return toolActions.first { $0.kind == .confirmation }?.confirmationPrompt ?? message.content
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

    private var workspaceOpenEntityTargets: [ToolResultWorkspaceOpenEntityTarget] {
        guard message.role == .assistant,
              let toolCalls = message.toolCalls,
              !toolCalls.isEmpty else {
            return []
        }
        return ToolResultWorkspaceOpenEntityParser.parse(toolCalls: toolCalls)
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
        if ChatMessagePresentation.shouldAnimateThinkingDismissal(
            for: message,
            previousContent: wasEmpty ? "" : "content",
            newContent: isEmpty ? "" : "content",
            reduceMotion: reduceMotion
        ) {
            startThinkingDismissalAnimationIfNeeded()
            return
        }

        if isEmpty {
            syncThinkingPlaceholder()
        } else {
            stopThinkingDismissalAnimation(resetText: true)
        }
    }

    private func handleMessageStatusChange(from oldStatus: MessageStatus, to newStatus: MessageStatus) {
        guard oldStatus != newStatus else {
            return
        }

        guard newStatus == .complete,
              ChatMessagePresentation.showsCompletionIndicator(for: message) else {
            hideCompletionIndicator()
            return
        }

        showCompletionIndicator = true
        completionIndicatorTask?.cancel()
        completionIndicatorTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: ChatMessagePresentation.completionIndicatorDisplayNanoseconds
            )
            showCompletionIndicator = false
            completionIndicatorTask = nil
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

    private func hideCompletionIndicator() {
        completionIndicatorTask?.cancel()
        completionIndicatorTask = nil
        showCompletionIndicator = false
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

    private static func lookupToken(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "lookup-\(String(format: "%016llx", hash))"
    }
}

enum ChatMessagePresentation {
    static let thinkingPlaceholderText = "Thinking..."
    static let thinkingDismissalFrameIntervalNanoseconds: UInt64 = 20_000_000
    static let completionIndicatorDisplayNanoseconds: UInt64 = 1_500_000_000

    static func showsThinkingPlaceholder(for message: Message) -> Bool {
        guard isAssistantStreaming(message) else {
            return false
        }
        return isContentEffectivelyEmpty(message.content)
    }

    static func showsHeaderThinkingIndicator(for message: Message) -> Bool {
        isAssistantStreaming(message)
    }

    static func showsCompletionIndicator(for message: Message) -> Bool {
        message.role == .assistant &&
            message.status == .complete &&
            !isContentEffectivelyEmpty(message.content)
    }

    static func shouldAnimateThinkingDismissal(
        for message: Message,
        previousContent: String,
        newContent: String,
        reduceMotion: Bool
    ) -> Bool {
        guard !reduceMotion else {
            return false
        }
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
}
