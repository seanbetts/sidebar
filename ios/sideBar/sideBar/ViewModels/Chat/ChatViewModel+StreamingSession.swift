import Foundation
import sideBarShared

extension ChatViewModel {
    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        streamingConversationId = request.conversationId ?? selectedConversationId
        didReceiveTerminalStreamEvent = false
        do {
            try await streamClient.connect(request: request)
            handleUnexpectedStreamEndIfNeeded()
        } catch is CancellationError {
            // Stream cancellation is user-initiated; avoid surfacing as an error.
        } catch {
            let mappedError = ErrorMapping.message(for: error)
            let presentation = ErrorMapping.chatStreamPresentation(
                from: String(describing: error),
                fallbackUserMessage: mappedError
            )
            logStreamRequestFailure(mappedError)
            errorMessage = presentation.userMessage
            toastCenter?.show(message: presentation.userMessage)
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
        clearTypingRevealState(flushDisplayedContent: false)
        didReceiveTerminalStreamEvent = false
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
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
