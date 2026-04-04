import sideBarShared
import Foundation

// MARK: - ChatViewModel+StreamingFinalize
extension ChatViewModel {
    // swiftlint:disable:next function_body_length
    func finalizeStreaming(
        status: MessageStatus,
        streamError: String? = nil,
        errorDetails: String? = nil
    ) {
        logFinalizeStart(status: status, streamError: streamError, errorDetails: errorDetails)
        var finalizedStatus = status
        var finalizedStreamError = streamError
        var finalizedErrorDetails = errorDetails
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
                content: message.content,
                status: status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: streamError?.trimmedOrNil ?? message.error,
                errorDetails: errorDetails?.trimmedOrNil ?? message.errorDetails
            )
        }
        if shouldSuppressCurrentStreamErrors && status == .error {
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
        logFinalizeEnd(messageId: messageId, status: finalizedStatus)
        syncMessagesToStore(
            conversationId: streamingConversationId ?? selectedConversationId,
            persist: true
        )
        if let conversationId = streamingConversationId ?? selectedConversationId {
            Task { [weak self] in
                if finalizedStatus == .complete {
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
        currentStreamMessageVisibility = nil
        currentAssistantInitiatedStreamSuppressesErrors = false
        processAssistantInitiatedStreamsIfPossible()
    }

    private func updateFinalizedMessage(
        id: String,
        status: MessageStatus,
        streamError: String?,
        errorDetails: String?
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
                error: streamError?.trimmedOrNil ?? message.error,
                errorDetails: errorDetails?.trimmedOrNil ?? message.errorDetails
            )
        }
    }

    private func shouldPersistAssistantMessage(_ message: Message) -> Bool {
        if message.content.trimmedOrNil != nil {
            return true
        }
        return !(message.toolCalls?.isEmpty ?? true)
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
            presentation: presentation,
            status: status,
            messageId: messageId
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
        presentation: ChatStreamErrorPresentation,
        status: MessageStatus,
        messageId: String
    ) -> Bool {
        if status == .complete || presentation.category == .emptyResponse {
            return isRetryReplayFinalization(for: messageId)
        }
        return status == .error
    }

    private func isRetryReplayFinalization(for messageId: String) -> Bool {
        guard retryStateBeforeReplay != nil else {
            return false
        }
        return latestRetrySource?.assistantMessageID == messageId
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

    private func logFinalizeStart(
        status: MessageStatus,
        streamError: String?,
        errorDetails: String?
    ) {
        ChatStreamingDebugTrace.log(
            "stream.finalize.begin",
            details: [
                "requestedStatus=\(status.rawValue)",
                "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId ?? selectedConversationId))",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(activeStreamingMessageId))",
                "hadStreamError=\((streamError?.trimmedOrNil) != nil)",
                "hadErrorDetails=\((errorDetails?.trimmedOrNil) != nil)"
            ].joined(separator: " ")
        )
    }

    private func logFinalizeEnd(messageId: String, status: MessageStatus) {
        ChatStreamingDebugTrace.log(
            "stream.finalize.end",
            details: [
                "finalStatus=\(status.rawValue)",
                "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId ?? selectedConversationId))",
                ChatStreamingDebugTrace.summarizeMessage(messages.first(where: { $0.id == messageId })),
                "retryable=\(latestRetryableAssistantMessageID == messageId)"
            ].joined(separator: " ")
        )
    }
}
