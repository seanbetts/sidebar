import Foundation
import sideBarShared

extension ChatViewModel {
    var targetMessageIdForToolActionEvent: String? {
        activeStreamingMessageId ?? activeToolActionMessageId
    }

    func toolActions(for messageId: String) -> [ChatToolAction] {
        toolActionsByMessageId[messageId] ?? []
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
        toolActionsByMessageId.first { _, actions in
            actions.contains { $0.id == id }
        }?.key
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
