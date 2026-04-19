import Foundation
import sideBarShared

// MARK: - ChatViewModel+ConversationRealtime

extension ChatViewModel {
    func handleConversationTitleUpdated(_ event: ChatStreamEvent) {
        guard let payload = dictionaryValue(from: event.data),
              let id = payload["id"] as? String,
              let title = payload["title"] as? String else {
            return
        }

        let titleGenerated = payload["titleGenerated"] as? Bool ?? false
        let updatedAt = payload["updatedAt"] as? String
        if let existingConversation = chatStore.conversations.first(where: { $0.id == id }) {
            chatStore.upsertConversation(
                Conversation(
                    id: existingConversation.id,
                    title: title,
                    titleGenerated: titleGenerated,
                    createdAt: existingConversation.createdAt,
                    updatedAt: updatedAt ?? existingConversation.updatedAt,
                    messageCount: existingConversation.messageCount,
                    firstMessage: existingConversation.firstMessage,
                    isArchived: existingConversation.isArchived
                )
            )
        }

        if let existingDetail = chatStore.conversationDetails[id] {
            chatStore.upsertConversationDetail(
                ConversationWithMessages(
                    id: existingDetail.id,
                    title: title,
                    titleGenerated: titleGenerated,
                    createdAt: existingDetail.createdAt,
                    updatedAt: updatedAt ?? existingDetail.updatedAt,
                    messageCount: existingDetail.messageCount,
                    firstMessage: existingDetail.firstMessage,
                    isArchived: existingDetail.isArchived,
                    messages: existingDetail.messages
                )
            )
        }

        if let updatedAt, let parsed = DateParsing.parseISO8601(updatedAt) {
            conversationUpdatedAtDates[id] = parsed
        }
    }
}
