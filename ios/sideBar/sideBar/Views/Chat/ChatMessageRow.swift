import Foundation
import SwiftUI

struct ChatMessageRow: View {
    let message: Message
    @Environment(\.colorScheme) private var colorScheme
    private let maxBubbleWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth

    var body: some View {
        bubble
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(message.role == .assistant ? "sideBar" : "You")
                    .font(DesignTokens.Typography.captionSemibold)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
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

            SideBarMarkdown(text: message.content, style: .chat)
                .frame(maxWidth: .infinity, alignment: .leading)

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
