import Foundation
import OSLog

// MARK: - ChatViewModel+StreamingErrors
private let chatStreamLogger = Logger(subsystem: "sideBar", category: "ChatStreaming")

extension ChatViewModel {
    static let unexpectedStreamEndMessage = "The response stream ended unexpectedly. Please try again."

    var shouldSuppressCurrentStreamErrors: Bool {
        currentStreamMessageVisibility == .hidden
            && currentAssistantInitiatedStreamSuppressesErrors
    }

    func makeVoidEventHandler(
        _ action: @escaping (ChatViewModel) -> () -> Void
    ) -> (ChatStreamEvent) -> Void {
        { [weak self] _ in
            guard let self else {
                return
            }
            action(self)()
        }
    }

    func makeEventHandler(
        _ action: @escaping (ChatViewModel) -> (ChatStreamEvent) -> Void
    ) -> (ChatStreamEvent) -> Void {
        { [weak self] event in
            guard let self else {
                return
            }
            action(self)(event)
        }
    }

    func handleUnexpectedStreamEndIfNeeded() {
        guard currentStreamMessageId != nil, didReceiveTerminalStreamEvent == false else {
            return
        }
        let fallbackMessage = Self.unexpectedStreamEndMessage
        chatStreamLogger.error(
            """
            Stream ended without terminal event conversationId=\(self.streamingConversationId ?? "nil", privacy: .public) \
            assistantMessageId=\(self.currentStreamMessageId ?? "nil", privacy: .public)
            """
        )
        if shouldUseGlobalStreamErrorSurface(status: .error),
           !shouldSuppressCurrentStreamErrors {
            errorMessage = fallbackMessage
        }
        finalizeStreaming(status: .error, streamError: fallbackMessage)
    }

    func logStreamRequestFailure(_ mappedError: String) {
        chatStreamLogger.error(
            """
            Stream request failed conversationId=\(self.streamingConversationId ?? "nil", privacy: .public) \
            assistantMessageId=\(self.currentStreamMessageId ?? "nil", privacy: .public) \
            error=\(mappedError, privacy: .public)
            """
        )
    }

    func logTerminalStreamError(_ rawError: String?) {
        chatStreamLogger.error(
            """
            Stream emitted terminal error conversationId=\(self.streamingConversationId ?? "nil", privacy: .public) \
            assistantMessageId=\(self.currentStreamMessageId ?? "nil", privacy: .public) \
            error=\(rawError ?? "nil", privacy: .public)
            """
        )
    }

    func shouldSurfaceCurrentStreamError(status: MessageStatus) -> Bool {
        guard let messageId = activeStreamingMessageId else {
            return true
        }
        return !shouldTreatToolOnlyFailureAsComplete(
            messageId: messageId,
            status: status
        )
    }

    func shouldUseGlobalStreamErrorSurface(status: MessageStatus) -> Bool {
        guard activeStreamingMessageId == nil else {
            return false
        }
        return shouldSurfaceCurrentStreamError(status: status)
    }
}
