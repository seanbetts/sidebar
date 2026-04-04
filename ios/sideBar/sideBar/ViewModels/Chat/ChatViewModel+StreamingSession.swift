import Foundation
import sideBarShared

extension ChatViewModel {
    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        streamingConversationId = request.conversationId ?? selectedConversationId
        currentStreamMessageVisibility = request.messageVisibility
        didReceiveTerminalStreamEvent = false
        ChatStreamingDebugTrace.log(
            "viewModel.stream.start",
            details: [
                "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId))",
                "selected=\(ChatStreamingDebugTrace.shortID(selectedConversationId))",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(request.assistantMessageId))",
                "messageChars=\(request.message.count)"
            ].joined(separator: " ")
        )
        do {
            try await streamClient.connect(request: request)
            ChatStreamingDebugTrace.log(
                "viewModel.stream.connectReturned",
                details: [
                    "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId))",
                    "assistantMessage=\(ChatStreamingDebugTrace.shortID(currentStreamMessageId))",
                    "receivedTerminal=\(didReceiveTerminalStreamEvent)"
                ].joined(separator: " ")
            )
            handleUnexpectedStreamEndIfNeeded()
        } catch is CancellationError {
            ChatStreamingDebugTrace.log(
                "viewModel.stream.cancelled",
                details: [
                    "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId))",
                    "assistantMessage=\(ChatStreamingDebugTrace.shortID(currentStreamMessageId))"
                ].joined(separator: " ")
            )
            restoreRetryStateAfterInterruptedReplayIfNeeded()
        } catch {
            let mappedError = ErrorMapping.message(for: error)
            let presentation = ErrorMapping.chatStreamPresentation(
                from: String(describing: error),
                fallbackUserMessage: mappedError
            )
            ChatStreamingDebugTrace.log(
                "viewModel.stream.error",
                details: [
                    "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId))",
                    "assistantMessage=\(ChatStreamingDebugTrace.shortID(currentStreamMessageId))",
                    "mappedError=\(mappedError)"
                ].joined(separator: " ")
            )
            logStreamRequestFailure(mappedError)
            if !shouldSuppressCurrentStreamErrors {
                errorMessage = presentation.userMessage
                toastCenter?.show(message: presentation.userMessage)
            }
            finalizeStreaming(
                status: .error,
                streamError: presentation.userMessage,
                errorDetails: presentation.details
            )
        }
        isStreaming = false
    }

    public func stopStream() {
        ChatStreamingDebugTrace.log(
            "viewModel.stream.stop",
            details: [
                "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId))",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(currentStreamMessageId))"
            ].joined(separator: " ")
        )
        streamClient.disconnect()
        restoreRetryStateAfterInterruptedReplayIfNeeded()
        clearTypingRevealState(flushDisplayedContent: false)
        didReceiveTerminalStreamEvent = false
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
        currentStreamMessageVisibility = nil
        currentAssistantInitiatedStreamSuppressesErrors = false
        processAssistantInitiatedStreamsIfPossible()
    }

    public func beginStreamingMessage(assistantMessageId: String) {
        currentStreamMessageId = assistantMessageId
        ChatStreamingDebugTrace.log(
            "viewModel.stream.beginMessage",
            details: [
                "conversation=\(ChatStreamingDebugTrace.shortID(streamingConversationId ?? selectedConversationId))",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(assistantMessageId))",
                ChatStreamingDebugTrace.summarizeMessage(messages.first(where: { $0.id == assistantMessageId }))
            ].joined(separator: " ")
        )
        guard typingRevealEnabled else {
            return
        }
        let startingContent = messages.first(where: { $0.id == assistantMessageId })?.content ?? ""
        typingRevealTargetsByMessageId = [assistantMessageId: startingContent]
    }
}
