import Foundation
import sideBarShared

extension ChatViewModel {
    func makeTransportStreamEventHandlers() -> [ChatStreamEventType: (ChatStreamEvent) -> Void] {
        [
            .token: { [weak self] (event: ChatStreamEvent) in
                self?.appendToken(from: event)
            },
            .toolCall: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolCall(event)
            },
            .toolResult: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolResult(event)
            },
            .complete: { [weak self] (_: ChatStreamEvent) in
                self?.didReceiveTerminalStreamEvent = true
                self?.finalizeStreaming(status: .complete)
            },
            .error: { [weak self] (event: ChatStreamEvent) in
                let payload = self?.dictionaryValue(from: event.data)
                let rawStreamError = self?.stringValue(from: event.data, key: "error")?.trimmedOrNil
                let presentation = ErrorMapping.chatStreamPresentation(
                    fromEventPayload: payload,
                    fallbackUserMessage: "The response hit an error. Please try again."
                )
                self?.logTerminalStreamError(rawStreamError)
                self?.didReceiveTerminalStreamEvent = true
                if self?.shouldUseGlobalStreamErrorSurface(status: .error) == true,
                   self?.shouldSuppressCurrentStreamErrors != true {
                    self?.errorMessage = presentation.userMessage
                }
                self?.finalizeStreaming(
                    status: .error,
                    streamError: presentation.userMessage,
                    errorDetails: presentation.details,
                    assistantContext: presentation.assistantContext,
                    assistantExplanation: presentation.assistantExplanation
                )
            }
        ]
    }

    func makePrimitiveStreamEventHandlers() -> [ChatStreamEventType: (ChatStreamEvent) -> Void] {
        [
            .entityChanged: { [weak self] (event: ChatStreamEvent) in
                self?.handleEntityChanged(event)
            },
            .entityDeleted: { [weak self] (event: ChatStreamEvent) in
                self?.handleEntityDeleted(event)
            },
            .collectionInvalidated: { [weak self] (event: ChatStreamEvent) in
                self?.handleCollectionInvalidated(event)
            },
            .toolConfirmationRequested: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolConfirmationRequested(event)
            },
            .toolConfirmationResolved: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolConfirmationResolved(event)
            },
            .toolStatus: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolStatus(event)
            },
            .undoAvailable: { [weak self] (event: ChatStreamEvent) in
                self?.handleUndoAvailable(event)
            }
        ]
    }

    func makeContentStreamEventHandlers() -> [ChatStreamEventType: (ChatStreamEvent) -> Void] {
        [
            .promptPreview: makeEventHandler(ChatViewModel.handlePromptPreview),
            .workspacePatch: makeEventHandler(ChatViewModel.handleWorkspacePatch)
        ]
    }

    private func handleEntityChanged(_ event: ChatStreamEvent) {
        guard let payload = ChatStreamSyncPayloadParser.parseEntityChanged(event.data) else {
            return
        }
        if handleConversationEntityChanged(payload) {
            return
        }
        if handleNoteEntityChanged(payload) {
            return
        }
        if handleEntityChangedRefreshContext(payload) {
            return
        }
        if handleEntityChangedRefreshAssistantSettings(payload) {
            return
        }
        if handleEntityChangedRefreshScratchpad(payload) {
            return
        }
        if handleEntityChangedRefreshMemories(payload) {
            return
        }
        if handleEntityChangedRefreshOnboardingState(payload) {
            return
        }
    }

    private func handleConversationEntityChanged(_ payload: ChatEntityChangedPayload) -> Bool {
        guard payload.entityType == ChatStreamEntityType.conversation.rawValue else {
            return false
        }
        guard let title = payload.patch?["title"]?.value as? String else {
            return true
        }
        let titleGenerated = payload.patch?["titleGenerated"]?.value as? Bool ?? false
        let updatedAt = payload.patch?["updatedAt"]?.value as? String
        if let existingConversation = chatStore.conversations.first(where: { $0.id == payload.entityId }) {
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
        if let existingDetail = chatStore.conversationDetails[payload.entityId] {
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
            conversationUpdatedAtDates[payload.entityId] = parsed
        }
        return true
    }

    private func handleNoteEntityChanged(_ payload: ChatEntityChangedPayload) -> Bool {
        guard payload.entityType == ChatStreamEntityType.note.rawValue else {
            return false
        }

        if payload.patch?["open_in_workspace"]?.value as? Bool == true {
            onOpenNoteRequested?(payload.entityId)
        }

        refreshContext(for: .notes(noteId: payload.entityId))
        return true
    }

    private func handleEntityChangedRefreshContext(_ payload: ChatEntityChangedPayload) -> Bool {
        switch payload.entityType {
        case ChatStreamEntityType.website.rawValue:
            refreshContext(for: .websites(id: payload.entityId))
            return true
        case ChatStreamEntityType.ingestion.rawValue:
            refreshContext(for: .ingestion(fileId: payload.entityId))
            return true
        default:
            return false
        }
    }

    private func handleEntityChangedRefreshAssistantSettings(_ payload: ChatEntityChangedPayload) -> Bool {
        switch payload.entityType {
        case ChatStreamEntityType.profile.rawValue,
             ChatStreamEntityType.preferences.rawValue,
             ChatStreamEntityType.assistantSettings.rawValue:
            onAssistantSettingsUpdated?(
                AssistantSettingsRealtimeUpdate(
                    assistantIdentity: nil,
                    assistantIdentityMeta: nil,
                    assistantSoul: nil,
                    assistantSoulMeta: nil,
                    requiresRefresh: true
                )
            )
            return true
        default:
            return false
        }
    }

    private func handleEntityChangedRefreshScratchpad(_ payload: ChatEntityChangedPayload) -> Bool {
        guard payload.entityType == ChatStreamEntityType.scratchpad.rawValue else {
            return false
        }
        refreshScratchpad()
        return true
    }

    private func handleEntityChangedRefreshMemories(_ payload: ChatEntityChangedPayload) -> Bool {
        guard payload.entityType == ChatStreamEntityType.memory.rawValue else {
            return false
        }
        refreshMemories()
        return true
    }

    private func handleEntityChangedRefreshOnboardingState(_ payload: ChatEntityChangedPayload) -> Bool {
        guard payload.entityType == ChatStreamEntityType.onboardingState.rawValue else {
            return false
        }
        requestOnboardingStateRefresh()
        return true
    }

    private func handleEntityDeleted(_ event: ChatStreamEvent) {
        guard let payload = ChatStreamSyncPayloadParser.parseEntityDeleted(event.data) else {
            return
        }

        switch payload.entityType {
        case ChatStreamEntityType.website.rawValue:
            refreshContext(for: .websites(id: payload.entityId))
        case ChatStreamEntityType.note.rawValue:
            if onCloseNoteRequested?(payload.entityId) == true {
                noteIdsClosedForUndoReopen.insert(payload.entityId)
            }
            refreshContext(for: .notes(noteId: payload.entityId))
        default:
            break
        }
    }

    private func handleCollectionInvalidated(_ event: ChatStreamEvent) {
        guard let payload = ChatStreamSyncPayloadParser.parseCollectionInvalidated(event.data) else {
            return
        }

        for target in payload.targets {
            handleCollectionInvalidationTarget(target)
        }
        if payload.targets.contains(ChatStreamEntityType.profile.rawValue)
            || payload.targets.contains(ChatStreamEntityType.preferences.rawValue)
            || payload.targets.contains(ChatStreamEntityType.assistantSettings.rawValue) {
            onAssistantSettingsUpdated?(
                AssistantSettingsRealtimeUpdate(
                    assistantIdentity: nil,
                    assistantIdentityMeta: nil,
                    assistantSoul: nil,
                    assistantSoulMeta: nil,
                    requiresRefresh: true
                )
            )
        }
    }

    private func handleCollectionInvalidationTarget(_ target: String) {
        switch target {
        case ChatStreamEntityType.scratchpad.rawValue:
            refreshScratchpad()
        case ChatStreamEntityType.memory.rawValue:
            refreshMemories()
        case ChatStreamEntityType.onboardingState.rawValue:
            requestOnboardingStateRefresh()
        case ChatStreamEntityType.tasks.rawValue:
            onTasksUpdated?()
        case "notes":
            refreshContext(for: .notes(noteId: ""))
        case ChatStreamEntityType.ingestion.rawValue:
            refreshContext(for: .ingestion(fileId: nil))
        case ChatStreamEntityType.website.rawValue:
            refreshContext(for: .websites(id: nil))
        default:
            break
        }
    }

    private func handleToolStatus(_ event: ChatStreamEvent) {
        let payload = ChatStreamSyncPayloadParser.parseToolStatus(event.data)
        guard let payload else {
            return
        }
        clearActiveToolTask?.cancel()
        let statusRaw = payload.status.lowercased()
        let status = statusRaw == ToolActivityStatus.error.rawValue
            ? ToolActivityStatus.error
            : ToolActivityStatus.success
        if statusRaw == ToolActivityStatus.running.rawValue {
            activeTool = ChatActiveTool(name: payload.name, status: .running, startedAt: self.clock())
            return
        }
        activeTool = ChatActiveTool(
            name: payload.name,
            status: status,
            startedAt: activeTool?.startedAt ?? self.clock()
        )
        markNeedsNewline()
        clearActiveToolTask?.cancel()
        clearActiveToolTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_500_000_000)
            } catch {
                return
            }
            if self?.activeTool?.name == payload.name {
                self?.activeTool = nil
            }
        }
    }

    private func handleToolConfirmationRequested(_ event: ChatStreamEvent) {
        let payload = ChatStreamSyncPayloadParser.parseToolConfirmationRequested(event.data)
        let targetMessageId = targetMessageIdForToolActionEvent
        guard let payload,
              let messageId = targetMessageId else {
            return
        }
        let action = ChatToolAction(
            id: payload.confirmationId,
            kind: .confirmation,
            summary: payload.summary,
            toolName: payload.toolName,
            guardReason: payload.guardReason,
            undoSupported: payload.undoSupported,
            expiresAt: payload.expiresAt,
            entityType: nil,
            entityId: nil,
            status: .pending
        )
        upsertToolAction(action, messageId: messageId)
        markNeedsNewline()
    }

    private func handleToolConfirmationResolved(_ event: ChatStreamEvent) {
        let payload = ChatStreamSyncPayloadParser.parseToolConfirmationResolved(event.data)
        guard let payload else {
            return
        }
        updateToolAction(id: payload.confirmationId) { action in
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
                status: payload.decision == .accept ? .accepted : .declined,
                decision: action.decision
            )
        }
    }

    private func handleUndoAvailable(_ event: ChatStreamEvent) {
        guard let payload = ChatStreamSyncPayloadParser.parseUndoAvailable(event.data),
              let messageId = targetMessageIdForToolActionEvent else {
            return
        }
        let action = ChatToolAction(
            id: payload.undoToken,
            kind: .undo,
            summary: payload.summary,
            toolName: nil,
            guardReason: nil,
            undoSupported: false,
            expiresAt: payload.expiresAt,
            entityType: payload.entityType,
            entityId: payload.entityId,
            status: .pending
        )
        upsertToolAction(action, messageId: messageId)
    }
}
