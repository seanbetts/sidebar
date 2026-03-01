import Foundation
import SwiftUI

struct ConversationRow: View, Equatable {
    let conversation: Conversation
    let isSelected: Bool
    private let subtitleText: String

    init(
        conversation: Conversation,
        isSelected: Bool
    ) {
        self.conversation = conversation
        self.isSelected = isSelected
        let formattedDate = ConversationRow.formattedDate(from: conversation.updatedAt)
        let count = conversation.messageCount
        let label = count == 1 ? "1 message" : "\(count) messages"
        self.subtitleText = "\(formattedDate) | \(label)"
    }

    static func == (lhs: ConversationRow, rhs: ConversationRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.conversation.id == rhs.conversation.id &&
        lhs.conversation.title == rhs.conversation.title &&
        lhs.conversation.updatedAt == rhs.conversation.updatedAt &&
        lhs.conversation.messageCount == rhs.conversation.messageCount
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(conversation.title)
                    .appFont(SidebarTypography.primary)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    .lineLimit(1)
                Text(subtitleText)
                    .appFont(SidebarTypography.tertiary)
                    .foregroundStyle(isSelected ? selectedSecondaryText.opacity(0.85) : secondaryTextColor)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var selectedSecondaryText: Color {
        DesignTokens.Colors.textSecondary
    }

    private static func formattedDate(from value: String) -> String {
        guard let date = DateParsing.parseISO8601(value) else {
            return value
        }
        return DateFormatter.chatList.string(from: date)
    }
}

private extension DateFormatter {
    static let chatList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
