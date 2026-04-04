import Foundation
import sideBarShared

extension ChatViewModel {
    struct AssistantInitiatedStreamOptions {
        let instruction: String
        let suppressErrors: Bool
    }

    func enqueueAssistantInitiatedStream(
        _ options: AssistantInitiatedStreamOptions
    ) {
        pendingAssistantInitiatedStreams.append(options)
        processAssistantInitiatedStreamsIfPossible()
    }

    func processAssistantInitiatedStreamsIfPossible() {
        guard assistantInitiatedStreamTask == nil else {
            return
        }
        guard !isStreaming else {
            return
        }
        guard !pendingAssistantInitiatedStreams.isEmpty else {
            return
        }

        let options = pendingAssistantInitiatedStreams.removeFirst()
        assistantInitiatedStreamTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.assistantInitiatedStreamTask = nil
                self.processAssistantInitiatedStreamsIfPossible()
            }
            await self.sendAssistantInitiatedStream(options)
        }
    }

    func sendAssistantInitiatedStream(
        _ options: AssistantInitiatedStreamOptions
    ) async {
        let conversationId: String
        do {
            conversationId = try await ensureActiveConversationForOutgoingStream()
        } catch {
            return
        }

        let assistantMessageId = UUID().uuidString
        let assistantMessage = Message(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: nextAppendedMessageTimestamp(),
            error: nil
        )
        messages.append(assistantMessage)
        beginStreamingMessage(assistantMessageId: assistantMessageId)
        syncMessagesToStore(conversationId: conversationId, persist: true)

        let requestContext = requestContextProvider?()
        let request = ChatStreamRequest(
            message: options.instruction,
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            messageVisibility: .hidden,
            openContext: requestContext?.openContext,
            currentLocation: requestContext?.currentLocation,
            currentLocationLevels: requestContext?.currentLocationLevels,
            currentWeather: requestContext?.currentWeather,
            currentTimezone: requestContext?.currentTimezone
        )
        currentAssistantInitiatedStreamSuppressesErrors = options.suppressErrors
        await startStream(request: request)
    }
}
