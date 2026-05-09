import Foundation
import sideBarShared

extension ChatViewModel {
    var targetMessageIdForToolActionEvent: String? {
        activeStreamingMessageId ?? activeToolActionMessageId
    }

    func toolActions(for messageId: String) -> [ChatToolAction] {
        let explicitActions = toolActionsByMessageId[messageId] ?? []
        guard explicitActions.isEmpty,
              let message = messages.first(where: { $0.id == messageId }) else {
            return explicitActions
        }
        return synthesizedToolActions(from: message)
    }

    func upsertToolAction(_ action: ChatToolAction, messageId: String) {
        var actions = toolActionsByMessageId[messageId] ?? []
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
        toolActionsByMessageId[messageId] = actions
    }

    func updateToolAction(id: String, transform: (ChatToolAction) -> ChatToolAction) {
        for (messageId, actions) in toolActionsByMessageId {
            guard let index = actions.firstIndex(where: { $0.id == id }) else {
                continue
            }
            var updatedActions = actions
            updatedActions[index] = transform(actions[index])
            toolActionsByMessageId[messageId] = updatedActions
            return
        }
    }

    func recordToolConfirmation(_ payload: ChatToolConfirmationRequestedPayload, messageId: String) {
        guard let toolCallId = payload.toolCallId else {
            return
        }
        updateMessage(id: messageId, persist: false) { message in
            let updatedToolCalls = message.toolCalls?.map { toolCall in
                guard toolCall.id == toolCallId else {
                    return toolCall
                }
                return ToolCall(
                    id: toolCall.id,
                    name: toolCall.name,
                    parameters: toolCall.parameters,
                    status: toolCall.status,
                    result: toolCall.result,
                    skillId: toolCall.skillId,
                    iconKey: toolCall.iconKey,
                    confirmationId: payload.confirmationId,
                    confirmationSummary: payload.summary,
                    confirmationGuardReason: payload.guardReason,
                    confirmationUndoSupported: payload.undoSupported,
                    confirmationExpiresAt: payload.expiresAt
                )
            }
            return Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: updatedToolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }

    func handleToolAction(_ action: ChatToolAction, decision: ChatToolActionDecision? = nil) {
        switch action.kind {
        case .confirmation:
            guard let decision else {
                return
            }
            resolveToolConfirmation(action, decision: decision)
        case .undo:
            undoToolAction(action)
        }
    }

    private func resolveToolConfirmation(_ action: ChatToolAction, decision: ChatToolActionDecision) {
        guard let messageId = messageId(forToolActionId: action.id) else {
            return
        }
        updateToolAction(id: action.id) { existing in
            toolAction(existing, status: .running)
        }
        Task {
            do {
                activeToolActionMessageId = messageId
                let response = try await chatAPI.resolveToolConfirmation(
                    confirmationId: action.id,
                    decision: decision
                )
                applyToolActionResponse(response)
                activeToolActionMessageId = nil
            } catch {
                activeToolActionMessageId = nil
                updateToolAction(id: action.id) { existing in
                    toolAction(existing, status: .failed)
                }
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    private func undoToolAction(_ action: ChatToolAction) {
        updateToolAction(id: action.id) { existing in
            toolAction(existing, status: .running)
        }
        Task {
            do {
                _ = try await chatAPI.undoToolAction(undoToken: action.id)
                updateToolAction(id: action.id) { existing in
                    toolAction(existing, status: .undone)
                }
                refreshContextAfterUndo(action)
            } catch {
                updateToolAction(id: action.id) { existing in
                    toolAction(existing, status: .failed)
                }
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    private func applyToolActionResponse(_ response: ChatToolActionResponse) {
        for event in response.events {
            applyToolActionResponseEvent(event)
        }
        if let toolResult = response.toolResult {
            applyToolActionResponseEvent(toolResult)
        }
    }

    private func applyToolActionResponseEvent(_ event: ChatToolActionResponseEvent) {
        guard let type = chatStreamEventTypeByName[event.type] else {
            return
        }
        handle(event: ChatStreamEvent(type: type, data: event.data))
    }

    private func messageId(forToolActionId id: String) -> String? {
        if let explicitMessageId = toolActionsByMessageId.first(where: { _, actions in
            actions.contains { $0.id == id }
        })?.key {
            return explicitMessageId
        }
        return messages.first { message in
            synthesizedToolActions(from: message).contains { $0.id == id }
        }?.id
    }

    private func synthesizedToolActions(from message: Message) -> [ChatToolAction] {
        guard let toolCalls = message.toolCalls else {
            return []
        }
        return toolCalls.compactMap { toolCall in
            guard toolCall.status == .pending,
                  let confirmationId = toolCall.confirmationId?.trimmedOrNil,
                  let summary = toolCall.confirmationSummary?.trimmedOrNil else {
                return nil
            }
            return ChatToolAction(
                id: confirmationId,
                kind: .confirmation,
                summary: summary,
                toolName: toolCall.name,
                guardReason: toolCall.confirmationGuardReason,
                undoSupported: toolCall.confirmationUndoSupported ?? false,
                expiresAt: toolCall.confirmationExpiresAt,
                entityType: nil,
                entityId: nil,
                status: .pending
            )
        }
    }

    private func toolAction(_ action: ChatToolAction, status: ChatToolActionStatus) -> ChatToolAction {
        ChatToolAction(
            id: action.id,
            kind: action.kind,
            summary: action.summary,
            toolName: action.toolName,
            guardReason: action.guardReason,
            undoSupported: action.undoSupported,
            expiresAt: action.expiresAt,
            entityType: action.entityType,
            entityId: action.entityId,
            status: status
        )
    }

    private func refreshContextAfterUndo(_ action: ChatToolAction) {
        guard let entityType = action.entityType else {
            return
        }
        switch entityType {
        case ChatStreamEntityType.note.rawValue:
            if let entityId = action.entityId {
                refreshContext(for: .notes(noteId: entityId))
            }
        case ChatStreamEntityType.website.rawValue:
            refreshContext(for: .websites(id: action.entityId))
        case ChatStreamEntityType.ingestion.rawValue:
            refreshContext(for: .ingestion(fileId: action.entityId))
        default:
            break
        }
    }
}
