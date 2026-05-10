import Foundation
import sideBarShared

// MARK: - ChatViewModel+StreamingSnapshots
extension ChatViewModel {
    func applySelectionIfNeeded(using items: [Conversation]) {
        guard !items.isEmpty else {
            return
        }
        guard let selectedId = selectedConversationId else {
            return
        }
        guard items.contains(where: { $0.id == selectedId }) else {
            return
        }
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
        guard currentLast.id == incomingLast.id,
              currentLast.status == incomingLast.status else {
            return false
        }
        if currentLast.content == incomingLast.content {
            return true
        }
        return messagesDifferOnlyBySyntheticToolNewline(currentLast, incomingLast)
            || messagesDifferOnlyBySyntheticToolNewline(incomingLast, currentLast)
    }

    func applyPendingLocalMessageUpdates(to incoming: [Message]) -> [Message] {
        guard !pendingLocalMessageUpdatesById.isEmpty else {
            return incoming
        }
        var updated = incoming
        for (messageId, pendingMessage) in pendingLocalMessageUpdatesById {
            guard let index = updated.firstIndex(where: { $0.id == messageId }) else {
                continue
            }
            if messagePersistenceSignature(updated[index]) == messagePersistenceSignature(pendingMessage) {
                pendingLocalMessageUpdatesById[messageId] = nil
                continue
            }
            updated[index] = pendingMessage
        }
        return updated
    }

    private func messagesDifferOnlyBySyntheticToolNewline(_ local: Message, _ server: Message) -> Bool {
        guard local.role == .assistant,
              server.role == .assistant,
              local.status == .complete,
              server.status == .complete,
              local.content.count == server.content.count + 2,
              local.needsNewline == false,
              server.needsNewline == nil,
              local.error == server.error,
              local.errorDetails == server.errorDetails,
              toolCallSnapshotSignature(local.toolCalls) == toolCallSnapshotSignature(server.toolCalls) else {
            return false
        }

        return removingSingleSyntheticToolNewline(from: local.content, matching: server.content)
    }

    private func removingSingleSyntheticToolNewline(from content: String, matching expected: String) -> Bool {
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: "\n\n", range: searchRange) {
            var normalized = content
            normalized.removeSubrange(range)
            if normalized == expected {
                return true
            }
            searchRange = range.upperBound..<content.endIndex
        }
        return false
    }

    private func toolCallSnapshotSignature(_ toolCalls: [ToolCall]?) -> String {
        (toolCalls ?? []).map {
            "\($0.id):\($0.name):\($0.status.rawValue):\($0.skillId ?? ""):\($0.iconKey ?? "")"
        }.joined(separator: "|")
    }

    private func messagePersistenceSignature(_ message: Message) -> String {
        [
            message.id,
            message.role.rawValue,
            message.status.rawValue,
            message.timestamp,
            message.content,
            message.error ?? "",
            message.errorDetails ?? "",
            message.needsNewline.map(String.init) ?? "",
            toolCallPersistenceSignature(message.toolCalls)
        ].joined(separator: "\u{241F}")
    }

    private func toolCallPersistenceSignature(_ toolCalls: [ToolCall]?) -> String {
        (toolCalls ?? []).map { toolCall in
            [
                toolCall.id,
                toolCall.name,
                toolCall.status.rawValue,
                toolCall.skillId ?? "",
                toolCall.iconKey ?? "",
                toolCall.confirmationId ?? "",
                toolCall.confirmationSummary ?? "",
                toolCall.confirmationGuardReason ?? "",
                toolCall.confirmationUndoSupported.map(String.init) ?? "",
                toolCall.confirmationExpiresAt ?? ""
            ].joined(separator: "\u{241D}")
        }.joined(separator: "\u{241E}")
    }
}
