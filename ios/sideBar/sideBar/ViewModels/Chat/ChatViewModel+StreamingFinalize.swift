import sideBarShared
import Foundation

// MARK: - ChatViewModel+StreamingFinalize
extension ChatViewModel {
    // swiftlint:disable:next function_body_length
    func finalizeStreaming(
        status: MessageStatus,
        streamError: String? = nil,
        errorDetails: String? = nil,
        assistantContext _: String? = nil,
        assistantExplanation: String? = nil
    ) {
        var finalizedStatus = status
        var finalizedStreamError = streamError
        var finalizedErrorDetails = errorDetails
        let trimmedAssistantExplanation = assistantExplanation?.trimmedOrNil
        guard let messageId = activeStreamingMessageId else {
            clearTypingRevealState(flushDisplayedContent: false)
            didReceiveTerminalStreamEvent = false
            isStreaming = false
            currentStreamMessageVisibility = nil
            currentAssistantInitiatedStreamSuppressesErrors = false
            processAssistantInitiatedStreamsIfPossible()
            return
        }
        flushTypingRevealContent(for: messageId)
        updateMessage(id: messageId, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content.trimmedOrNil == nil
                    ? (trimmedAssistantExplanation ?? message.content)
                    : message.content,
                status: status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: streamError?.trimmedOrNil ?? message.error,
                errorDetails: errorDetails?.trimmedOrNil ?? message.errorDetails
            )
        }
        if shouldTreatToolOnlyFailureAsComplete(messageId: messageId, status: finalizedStatus) {
            finalizedStatus = .complete
            finalizedStreamError = nil
            finalizedErrorDetails = nil
            errorMessage = nil
            updateFinalizedMessage(
                id: messageId,
                status: finalizedStatus,
                streamError: nil,
                errorDetails: nil,
                preserveExistingErrorState: false
            )
        }
        if shouldSuppressCurrentStreamErrors && finalizedStatus == .error {
            clearRetryState()
            discardAssistantMessage(id: messageId)
            return
        }
        typingRevealTargetsByMessageId[messageId] = nil
        if typingRevealTargetsByMessageId.isEmpty {
            typingRevealTask?.cancel()
            typingRevealTask = nil
        }
        if let emptyResponseResolution = resolveEmptyAssistantResponseIfNeeded(
            messageId: messageId,
            status: finalizedStatus,
            streamError: finalizedStreamError,
            errorDetails: finalizedErrorDetails
        ) {
            switch emptyResponseResolution {
            case .preserve(let presentation):
                finalizedStatus = .error
                finalizedStreamError = presentation.userMessage
                finalizedErrorDetails = presentation.details
                errorMessage = presentation.userMessage
                updateFinalizedMessage(
                    id: messageId,
                    status: finalizedStatus,
                    streamError: finalizedStreamError,
                    errorDetails: finalizedErrorDetails
                )
            case .discard:
                clearRetryState()
                if status == .complete && !shouldSuppressCurrentStreamErrors {
                    errorMessage = "Assistant returned an empty response. Please try again."
                }
                discardAssistantMessage(id: messageId)
                return
            }
        }

        updateRetryStateAfterFinalize(
            messageId: messageId,
            status: finalizedStatus,
            streamError: finalizedStreamError,
            errorDetails: finalizedErrorDetails
        )
        syncMessagesToStore(
            conversationId: streamingConversationId ?? selectedConversationId,
            persist: true
        )
        schedulePostFinalizeRefresh(
            conversationId: streamingConversationId ?? selectedConversationId,
            finalizedStatus: finalizedStatus
        )
        if finalizedStatus == .complete {
            errorMessage = nil
        }
        didReceiveTerminalStreamEvent = false
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
        currentStreamMessageVisibility = nil
        currentAssistantInitiatedStreamSuppressesErrors = false
        processAssistantInitiatedStreamsIfPossible()
    }

    private func updateFinalizedMessage(
        id: String,
        status: MessageStatus,
        streamError: String?,
        errorDetails: String?,
        preserveExistingErrorState: Bool = true
    ) {
        updateMessage(id: id, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: preserveExistingErrorState
                    ? (streamError?.trimmedOrNil ?? message.error)
                    : streamError?.trimmedOrNil,
                errorDetails: preserveExistingErrorState
                    ? (errorDetails?.trimmedOrNil ?? message.errorDetails)
                    : errorDetails?.trimmedOrNil
            )
        }
    }

    private func schedulePostFinalizeRefresh(
        conversationId: String?,
        finalizedStatus: MessageStatus
    ) {
        guard let conversationId else {
            return
        }
        Task { [weak self] in
            if finalizedStatus == .complete {
                await self?.generateConversationTitleIfNeeded(conversationId: conversationId)
            }
            await self?.refreshConversations(silent: true)
            await self?.refreshActiveConversation(silent: true)
        }
    }

    private func shouldPersistAssistantMessage(_ message: Message) -> Bool {
        if message.content.trimmedOrNil != nil {
            return true
        }
        return !(message.toolCalls?.isEmpty ?? true)
    }

    func shouldTreatToolOnlyFailureAsComplete(
        messageId: String,
        status: MessageStatus
    ) -> Bool {
        guard status == .error,
              let assistantMessage = messages.first(where: { $0.id == messageId }),
              assistantMessage.content.trimmedOrNil == nil,
              let toolCalls = assistantMessage.toolCalls,
              !toolCalls.isEmpty else {
            return false
        }
        return toolCalls.allSatisfy { $0.status == .success }
    }

    private enum EmptyAssistantResponseResolution {
        case preserve(ChatStreamErrorPresentation)
        case discard
    }

    private func resolveEmptyAssistantResponseIfNeeded(
        messageId: String,
        status: MessageStatus,
        streamError: String?,
        errorDetails: String?
    ) -> EmptyAssistantResponseResolution? {
        guard let assistantMessage = messages.first(where: { $0.id == messageId }),
              !shouldPersistAssistantMessage(assistantMessage) else {
            return nil
        }
        guard let presentation = emptyAssistantPresentation(
            for: status,
            streamError: streamError,
            errorDetails: errorDetails
        ) else {
            return .discard
        }
        guard shouldPreserveEmptyAssistantFailure(
            status: status
        ) else {
            return .discard
        }
        return .preserve(presentation)
    }

    private func discardAssistantMessage(id: String) {
        typingRevealTargetsByMessageId[id] = nil
        if typingRevealTargetsByMessageId.isEmpty {
            typingRevealTask?.cancel()
            typingRevealTask = nil
        }
        clearTypingRevealState(flushDisplayedContent: false)
        messages.removeAll { $0.id == id }
        syncMessagesToStore(
            conversationId: streamingConversationId ?? selectedConversationId,
            persist: true
        )
        didReceiveTerminalStreamEvent = false
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
        currentStreamMessageVisibility = nil
        currentAssistantInitiatedStreamSuppressesErrors = false
        processAssistantInitiatedStreamsIfPossible()
    }

    private func emptyAssistantPresentation(
        for status: MessageStatus,
        streamError: String?,
        errorDetails: String?
    ) -> ChatStreamErrorPresentation? {
        if status == .complete {
            return ErrorMapping.chatStreamPresentation(
                from: "Assistant response ended before any text was received."
            )
        }

        guard streamError?.trimmedOrNil != nil || errorDetails?.trimmedOrNil != nil else {
            return nil
        }

        return ErrorMapping.chatStreamPresentation(
            from: errorDetails ?? streamError,
            fallbackUserMessage: streamError
        )
    }

    private func shouldPreserveEmptyAssistantFailure(
        status: MessageStatus
    ) -> Bool {
        status == .error || status == .complete
    }

    private func updateRetryStateAfterFinalize(
        messageId: String,
        status: MessageStatus,
        streamError: String?,
        errorDetails: String?
    ) {
        defer {
            retryInFlightAssistantMessageID = nil
            retryStateBeforeReplay = nil
        }

        guard status == .error else {
            clearRetryState()
            return
        }

        let presentation = ErrorMapping.chatStreamPresentation(
            from: errorDetails ?? streamError,
            fallbackUserMessage: streamError
        )
        guard presentation.isRetryable,
              latestRetrySource?.assistantMessageID == messageId else {
            clearRetryState()
            return
        }

        latestRetryableAssistantMessageID = messageId
    }
}
