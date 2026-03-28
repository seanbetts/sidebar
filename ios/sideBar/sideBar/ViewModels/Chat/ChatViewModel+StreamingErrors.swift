import Foundation
import OSLog

// MARK: - ChatViewModel+StreamingErrors
private let chatStreamLogger = Logger(subsystem: "sideBar", category: "ChatStreaming")

extension ChatViewModel {
    static let unexpectedStreamEndMessage = "The response stream ended unexpectedly. Please try again."

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
        errorMessage = fallbackMessage
        toastCenter?.show(message: fallbackMessage)
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
}
