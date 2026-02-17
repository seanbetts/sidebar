import Foundation
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
        isCopied ? "checkmark.circle" : "doc.on.doc"
    }

    var accessibilityLabel: String {
        isCopied ? "Copied message" : "Copy message"
    }
}

struct ChatMessageRow: View {
    let message: Message
    let assistantDisplayName: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copyFeedback = ChatMessageCopyFeedbackState()
    @State private var resetCopyFeedbackTask: Task<Void, Never>?
    private let maxBubbleWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth

    var body: some View {
        bubble
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(message.role == .assistant ? assistantDisplayName : "You")
                    .font(DesignTokens.Typography.captionSemibold)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(rolePillBackground)
                    .foregroundStyle(rolePillText)
                    .overlay(rolePillBorder)
                    .clipShape(Capsule())
                Spacer()
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                        ToolCallListView(toolCalls: toolCalls, role: message.role)
                    }
                    Button {
                        copyMessage()
                        showCopyFeedback()
                    } label: {
                        Image(systemName: copyFeedback.iconName)
                            .font(.caption)
                            .foregroundStyle(copyFeedback.isCopied ? copiedIconForeground : .secondary)
                            .padding(DesignTokens.Spacing.xxs)
                            .background(copyFeedback.isCopied ? copiedIconBackground : .clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(showsThinkingPlaceholder)
                    .opacity(showsThinkingPlaceholder ? 0.45 : 1.0)
                    .accessibilityLabel(copyFeedback.accessibilityLabel)
                }
                .animation(Motion.quick(reduceMotion: reduceMotion), value: copyFeedback.isCopied)
            }

            if showsThinkingPlaceholder {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                    Text("Thinking...")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SideBarMarkdown(text: message.content, style: .chat)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsStreamingThinkingFooter {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if message.status == .error, let error = message.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }

            HStack {
                Spacer()
                Text(formattedTimestamp)
                    .font(.caption2)
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
        if colorScheme == .light, message.role == .assistant {
            Capsule()
                .stroke(pillBorderColor, lineWidth: 1)
        }
    }

    private var pillBorderColor: Color {
        DesignTokens.Colors.border
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

    private var showsStreamingThinkingFooter: Bool {
        ChatMessagePresentation.showsStreamingThinkingFooter(for: message)
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
    static func showsThinkingPlaceholder(for message: Message) -> Bool {
        guard isAssistantStreaming(message) else {
            return false
        }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func showsStreamingThinkingFooter(for message: Message) -> Bool {
        isAssistantStreaming(message) && !showsThinkingPlaceholder(for: message)
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
