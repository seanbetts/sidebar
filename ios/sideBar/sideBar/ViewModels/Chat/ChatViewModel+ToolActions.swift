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

    func resolveToolConfirmationMetadata(
        messageId: String,
        confirmationId: String,
        decision: ChatToolActionDecision
    ) {
        updateMessage(id: messageId, persist: false) { message in
            guard let toolCalls = message.toolCalls else {
                return message
            }
            var didResolveConfirmation = false
            let resolvedToolCalls = toolCalls.map { toolCall -> ToolCall in
                guard toolCall.confirmationId == confirmationId else {
                    return toolCall
                }
                didResolveConfirmation = true
                guard decision != .decline else {
                    return cancelledToolCall(from: toolCall)
                }
                return ToolCall(
                    id: toolCall.id,
                    name: toolCall.name,
                    parameters: toolCall.parameters,
                    status: toolCall.status,
                    result: toolCall.result,
                    skillId: toolCall.skillId,
                    iconKey: toolCall.iconKey
                )
            }
            guard didResolveConfirmation else {
                return message
            }
            let updated = Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: resolvedToolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
            return updated
        }
    }

    func resolveDeclinedToolConfirmation(
        messageId: String,
        confirmationId: String,
        action: ChatToolAction
    ) {
        let acknowledgement = "Okay, I won't delete this \(action.confirmationObjectName)."
        updateMessage(id: messageId, persist: false) { message in
            let resolvedToolCalls = message.toolCalls?.map { toolCall -> ToolCall in
                toolCall.confirmationId == confirmationId ? cancelledToolCall(from: toolCall) : toolCall
            }
            let updatedContent = message.content.contains(acknowledgement)
                ? message.content
                : message.content.trimmedOrNil == nil
                    ? acknowledgement
                    : "\(message.content)\n\n\(acknowledgement)"
            let updated = Message(
                id: message.id,
                role: message.role,
                content: updatedContent,
                status: message.status,
                toolCalls: resolvedToolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
            return updated
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
                content: messageContent(message.content, confirming: payload),
                status: message.status,
                toolCalls: updatedToolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }

    func confirmationPrompt(for payload: ChatToolConfirmationRequestedPayload) -> String {
        ChatToolAction.confirmationPrompt(for: payload.toolName)
    }

    private func cancelledToolCall(from toolCall: ToolCall) -> ToolCall {
        ToolCall(
            id: toolCall.id,
            name: toolCall.name,
            parameters: toolCall.parameters,
            status: .cancelled,
            result: AnyCodable([
                "success": false,
                "summary": "Cancelled"
            ]),
            skillId: toolCall.skillId,
            iconKey: toolCall.iconKey
        )
    }

    func handleToolAction(_ action: ChatToolAction, decision: ChatToolActionDecision? = nil) {
        switch action.kind {
        case .confirmation:
            guard let decision = decision ?? action.decision else {
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
        updateToolActionHeaderStatus(action, status: .running)
        updateToolAction(id: action.id) { existing in
            toolAction(existing, status: .running, decision: decision)
        }
        Task {
            do {
                activeToolActionMessageId = messageId
                let response = try await chatAPI.resolveToolConfirmation(
                    confirmationId: action.id,
                    decision: decision
                )
                applyToolActionResponse(response)
                await refreshSelectedConversationFromServer()
                updateToolActionHeaderStatus(action, status: .success)
                activeToolActionMessageId = nil
            } catch {
                activeToolActionMessageId = nil
                updateToolAction(id: action.id) { existing in
                    toolAction(existing, status: .failed)
                }
                updateToolActionHeaderStatus(action, status: .error)
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    private func undoToolAction(_ action: ChatToolAction) {
        let messageId = messageId(forToolActionId: action.id)
        updateToolActionHeaderStatus(action, status: .running)
        updateToolAction(id: action.id) { existing in
            toolAction(existing, status: .running)
        }
        Task {
            do {
                _ = try await chatAPI.undoToolAction(undoToken: action.id)
                handleSuccessfulUndo(action, messageId: messageId)
                await refreshSelectedConversationFromServer()
                updateToolActionHeaderStatus(action, status: .success)
            } catch {
                updateToolAction(id: action.id) { existing in
                    toolAction(existing, status: .failed)
                }
                updateToolActionHeaderStatus(action, status: .error)
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    func handleSuccessfulUndo(_ action: ChatToolAction, messageId: String? = nil) {
        updateToolAction(id: action.id) { existing in
            toolAction(existing, status: .undone)
        }
        refreshContextAfterUndo(action)
        reopenNoteAfterUndoIfNeeded(action)
    }

    private func reopenNoteAfterUndoIfNeeded(_ action: ChatToolAction) {
        guard action.entityType == ChatStreamEntityType.note.rawValue,
              let entityId = action.entityId,
              noteIdsClosedForUndoReopen.remove(entityId) != nil else {
            return
        }
        onOpenNoteRequested?(entityId)
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

    func messageId(forToolActionId id: String) -> String? {
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
                  let summary = toolCall.confirmationSummary?.trimmedOrNil,
                  !isExpiredToolConfirmation(toolCall) else {
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

    private func isExpiredToolConfirmation(_ toolCall: ToolCall) -> Bool {
        guard let expiresAt = DateParsing.parseISO8601(toolCall.confirmationExpiresAt) else {
            return false
        }
        return expiresAt <= clock()
    }

    private func toolAction(
        _ action: ChatToolAction,
        status: ChatToolActionStatus,
        decision: ChatToolActionDecision? = nil
    ) -> ChatToolAction {
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
            status: status,
            decision: decision ?? action.decision
        )
    }

    private func updateToolActionHeaderStatus(_ action: ChatToolAction, status: ToolActivityStatus) {
        clearActiveToolTask?.cancel()
        let actionName = headerStatusName(for: action)
        activeTool = ChatActiveTool(
            name: actionName,
            status: status,
            startedAt: status == .running ? clock() : activeTool?.startedAt ?? clock()
        )
        guard status != .running else {
            return
        }
        clearActiveToolTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_500_000_000)
            } catch {
                return
            }
            if self?.activeTool?.name == actionName {
                self?.activeTool = nil
            }
        }
    }

    private func headerStatusName(for action: ChatToolAction) -> String {
        let rawName: String?
        switch action.kind {
        case .confirmation:
            rawName = action.toolName?.trimmedOrNil ?? action.summary.trimmedOrNil
        case .undo:
            rawName = action.summary.trimmedOrNil ?? "Undo"
        }
        let punctuation = CharacterSet(charactersIn: "?.!")
        return (rawName ?? "Tool action")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(punctuation))
            .trimmedOrNil ?? "Tool action"
    }

    private func messageContent(
        _ currentContent: String,
        confirming payload: ChatToolConfirmationRequestedPayload
    ) -> String {
        let prompt = confirmationPrompt(for: payload)
        guard currentContent.trimmedOrNil != nil else {
            return prompt
        }
        guard !currentContent.contains(prompt) else {
            return currentContent
        }
        return "\(currentContent)\n\n\(prompt)"
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

    private func refreshSelectedConversationFromServer() async {
        guard let conversationId = selectedConversationId ?? streamingConversationId else {
            return
        }
        do {
            try await chatStore.loadConversation(id: conversationId, force: true)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}
