import Foundation

extension ChatStore {
    func mergedConversationDetail(
        _ response: ConversationWithMessages,
        cached: ConversationWithMessages?
    ) -> ConversationWithMessages {
        guard let cached else {
            return response
        }
        let preservedSuffix = preservedTransientFailedTurnSuffix(
            serverMessages: response.messages,
            cachedMessages: cached.messages
        )
        guard !preservedSuffix.isEmpty else {
            return response
        }
        return ConversationWithMessages(
            id: response.id,
            title: response.title,
            titleGenerated: response.titleGenerated,
            createdAt: response.createdAt,
            updatedAt: response.updatedAt,
            messageCount: response.messages.count + preservedSuffix.count,
            firstMessage: response.firstMessage,
            isArchived: response.isArchived,
            messages: response.messages + preservedSuffix
        )
    }

    func fetchConversationDetail(id: String) async throws -> ConversationWithMessages {
        if let inFlightTask = inFlightConversationDetailTasks[id] {
            return try await inFlightTask.value
        }

        let task = Task<ConversationWithMessages, Error> {
            try await conversationsAPI.get(id: id)
        }
        inFlightConversationDetailTasks[id] = task
        defer {
            inFlightConversationDetailTasks[id] = nil
        }
        return try await task.value
    }

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

    private func preservedTransientFailedTurnSuffix(
        serverMessages: [Message],
        cachedMessages: [Message]
    ) -> [Message] {
        guard cachedMessages.count > serverMessages.count else {
            return []
        }
        let serverPrefix = Array(cachedMessages.prefix(serverMessages.count))
        guard refreshMergeMessageSignature(serverPrefix) == refreshMergeMessageSignature(serverMessages) else {
            return []
        }
        let localSuffix = Array(cachedMessages.dropFirst(serverMessages.count))
        switch localSuffix {
        case let suffix where suffix.count == 1:
            guard isFailedAssistantMessage(suffix[0]) else {
                return []
            }
            return suffix
        case let suffix where suffix.count == 2:
            guard isCompletedUserMessage(suffix[0]),
                  isFailedAssistantMessage(suffix[1]) else {
                return []
            }
            return suffix
        default:
            return []
        }
    }

    private func isCompletedUserMessage(_ message: Message) -> Bool {
        message.role == .user && message.status == .complete
    }

    private func isFailedAssistantMessage(_ message: Message) -> Bool {
        message.role == .assistant && message.status == .error
    }

    private func refreshMergeMessageSignature(_ messages: [Message]) -> String {
        messages.map {
            "\($0.id)|\($0.role.rawValue)|\($0.status.rawValue)|\($0.timestamp)|\($0.content)"
        }.joined(separator: "\u{241E}")
    }
}
