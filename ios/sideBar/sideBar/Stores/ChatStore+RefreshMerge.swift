import Foundation

extension ChatStore {
    func syncConversationDetails(with incoming: [Conversation], persist: Bool) {
        let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        for (id, detail) in conversationDetails {
            guard let conversation = incomingByID[id] else {
                continue
            }
            let updated = conversationDetail(detail, syncedWith: conversation)
            guard updated.title != detail.title
                || updated.titleGenerated != detail.titleGenerated
                || updated.createdAt != detail.createdAt
                || updated.updatedAt != detail.updatedAt
                || updated.messageCount != detail.messageCount
                || updated.firstMessage != detail.firstMessage
                || updated.isArchived != detail.isArchived else {
                continue
            }
            _ = id
            upsertConversationDetail(updated, persist: persist)
        }
    }

    func conversationDetail(
        _ detail: ConversationWithMessages,
        syncedWith conversation: Conversation
    ) -> ConversationWithMessages {
        ConversationWithMessages(
            id: detail.id,
            title: conversation.title,
            titleGenerated: conversation.titleGenerated,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messageCount: conversation.messageCount,
            firstMessage: conversation.firstMessage,
            isArchived: conversation.isArchived,
            messages: detail.messages
        )
    }
}
