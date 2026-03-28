import sideBarShared
import Foundation

// MARK: - ChatViewModel+StreamingFinalize
extension ChatViewModel {
    func finalizeStreaming(status: MessageStatus, streamError: String? = nil) {
        guard let messageId = activeStreamingMessageId else {
            clearTypingRevealState(flushDisplayedContent: false)
            didReceiveTerminalStreamEvent = false
            isStreaming = false
            return
        }
        flushTypingRevealContent(for: messageId)
        updateMessage(id: messageId, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: streamError?.trimmedOrNil ?? message.error
            )
        }
        typingRevealTargetsByMessageId[messageId] = nil
        if typingRevealTargetsByMessageId.isEmpty {
            typingRevealTask?.cancel()
            typingRevealTask = nil
        }
        if let assistantMessage = messages.first(where: { $0.id == messageId }),
           !shouldPersistAssistantMessage(assistantMessage) {
            if status == .complete {
                errorMessage = "Assistant returned an empty response. Please try again."
            }
            messages.removeAll { $0.id == messageId }
            syncMessagesToStore(
                conversationId: streamingConversationId ?? selectedConversationId,
                persist: true
            )
            didReceiveTerminalStreamEvent = false
            isStreaming = false
            streamingConversationId = nil
            currentStreamMessageId = nil
            return
        }

        syncMessagesToStore(
            conversationId: streamingConversationId ?? selectedConversationId,
            persist: true
        )
        if let conversationId = streamingConversationId ?? selectedConversationId {
            Task { [weak self] in
                if status == .complete {
                    await self?.generateConversationTitleIfNeeded(conversationId: conversationId)
                }
                await self?.refreshConversations(silent: true)
                await self?.refreshActiveConversation(silent: true)
            }
        }
        didReceiveTerminalStreamEvent = false
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
    }

    private func shouldPersistAssistantMessage(_ message: Message) -> Bool {
        if message.content.trimmedOrNil != nil {
            return true
        }
        return !(message.toolCalls?.isEmpty ?? true)
    }
}
