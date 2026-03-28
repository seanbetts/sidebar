import Foundation
import sideBarShared

// MARK: - ChatViewModel+StreamingSnapshots
extension ChatViewModel {
    func applySelectionIfNeeded(using items: [Conversation]) {
        guard !items.isEmpty else {
            return
        }
        if let selectedId = selectedConversationId,
           items.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedConversationId = nil
        clearTypingRevealState(flushDisplayedContent: false)
        messages = []
        promptPreview = nil
        activeTool = nil
    }

    func reconcileMessages(_ incoming: [Message], for conversationId: String) -> [Message] {
        guard conversationId == streamingConversationId,
              let currentStreamMessageId,
              let streamingMessage = messages.first(where: { $0.id == currentStreamMessageId }) else {
            return incoming
        }

        let localMessages = messages
        let incomingById = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })

        if let serverMessage = incomingById[currentStreamMessageId],
           serverMessage.status != .streaming {
            clearTypingRevealState(flushDisplayedContent: false)
            self.currentStreamMessageId = nil
            self.streamingConversationId = nil
            return incoming
        }

        if incoming.contains(where: { $0.role == .assistant && $0.status == .streaming && $0.id != currentStreamMessageId }) {
            return incoming
        }

        let localTargetContent = typingRevealTargetsByMessageId[currentStreamMessageId] ?? streamingMessage.content
        let reconciledLocalMessages = localMessages.map { localMessage in
            guard let serverMessage = incomingById[localMessage.id] else {
                return localMessage
            }
            guard localMessage.id == currentStreamMessageId else {
                return serverMessage
            }
            if localTargetContent.count > serverMessage.content.count {
                return streamingMessage
            }
            return serverMessage
        }

        let localMessageIds = Set(localMessages.map(\.id))
        let serverOnlyMessages = incoming.filter { !localMessageIds.contains($0.id) }
        return reconciledLocalMessages + serverOnlyMessages
    }

    func isSameMessageSnapshot(current: [Message], incoming: [Message]) -> Bool {
        guard current.count == incoming.count else {
            return false
        }
        guard let currentLast = current.last, let incomingLast = incoming.last else {
            return current.isEmpty && incoming.isEmpty
        }
        return currentLast.id == incomingLast.id
            && currentLast.content == incomingLast.content
            && currentLast.status == incomingLast.status
    }
}
