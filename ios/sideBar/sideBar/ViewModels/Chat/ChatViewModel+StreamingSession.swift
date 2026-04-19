import Foundation
import sideBarShared

extension ChatViewModel {
    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        streamingConversationId = request.conversationId ?? selectedConversationId
        currentStreamMessageVisibility = request.messageVisibility
        didReceiveTerminalStreamEvent = false
        do {
            try await streamClient.connect(request: request)
            handleUnexpectedStreamEndIfNeeded()
        } catch is CancellationError {
            restoreRetryStateAfterInterruptedReplayIfNeeded()
        } catch {
            let mappedError = ErrorMapping.message(for: error)
            let presentation = ErrorMapping.chatStreamPresentation(
                from: String(describing: error),
                fallbackUserMessage: mappedError
            )
            logStreamRequestFailure(mappedError)
            if !shouldSuppressCurrentStreamErrors {
                errorMessage = presentation.userMessage
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
        guard typingRevealEnabled else {
            return
        }
        let startingContent = messages.first(where: { $0.id == assistantMessageId })?.content ?? ""
        typingRevealTargetsByMessageId = [assistantMessageId: startingContent]
    }
}
