import Foundation
import sideBarShared

struct ChatRetryStateSnapshot {
    let latestRetrySource: ChatRetrySource?
    let latestRetryableAssistantMessageID: String?
}

struct ChatRetrySource {
    let conversationID: String
    let userMessageID: String
    let userMessageText: String
    let assistantMessageID: String
    let attachments: [ChatAttachment]?
    let openContext: [String: AnyCodable]?
    let currentLocation: String?
    let currentLocationLevels: [String: String]?
    let currentWeather: [String: AnyCodable]?
    let currentTimezone: String?

    init(
        conversationID: String,
        userMessageID: String,
        userMessageText: String,
        assistantMessageID: String,
        attachments: [ChatAttachment]?,
        openContext: [String: AnyCodable]?,
        currentLocation: String?,
        currentLocationLevels: [String: String]?,
        currentWeather: [String: AnyCodable]?,
        currentTimezone: String?
    ) {
        self.conversationID = conversationID
        self.userMessageID = userMessageID
        self.userMessageText = userMessageText
        self.assistantMessageID = assistantMessageID
        self.attachments = attachments
        self.openContext = openContext
        self.currentLocation = currentLocation
        self.currentLocationLevels = currentLocationLevels
        self.currentWeather = currentWeather
        self.currentTimezone = currentTimezone
    }

    init?(request: ChatStreamRequest) {
        guard let conversationID = request.conversationId,
              let userMessageID = request.userMessageId,
              let assistantMessageID = request.assistantMessageId else {
            return nil
        }

        self.init(
            conversationID: conversationID,
            userMessageID: userMessageID,
            userMessageText: request.message,
            assistantMessageID: assistantMessageID,
            attachments: request.attachments,
            openContext: request.openContext,
            currentLocation: request.currentLocation,
            currentLocationLevels: request.currentLocationLevels,
            currentWeather: request.currentWeather,
            currentTimezone: request.currentTimezone
        )
    }

    func replaying(with assistantMessageID: String) -> ChatRetrySource {
        ChatRetrySource(
            conversationID: conversationID,
            userMessageID: userMessageID,
            userMessageText: userMessageText,
            assistantMessageID: assistantMessageID,
            attachments: attachments,
            openContext: openContext,
            currentLocation: currentLocation,
            currentLocationLevels: currentLocationLevels,
            currentWeather: currentWeather,
            currentTimezone: currentTimezone
        )
    }

    var request: ChatStreamRequest {
        ChatStreamRequest(
            message: userMessageText,
            conversationId: conversationID,
            userMessageId: userMessageID,
            assistantMessageId: assistantMessageID,
            openContext: openContext,
            attachments: attachments,
            currentLocation: currentLocation,
            currentLocationLevels: currentLocationLevels,
            currentWeather: currentWeather,
            currentTimezone: currentTimezone
        )
    }
}

extension ChatViewModel {
    func retryLatestFailedTurn() async {
        guard let retrySource = latestRetrySource else {
            clearRetryState()
            return
        }
        if retryInFlightAssistantMessageID != nil {
            return
        }
        guard canRetryMessage(id: retrySource.assistantMessageID) else {
            clearRetryState()
            return
        }

        retryStateBeforeReplay = ChatRetryStateSnapshot(
            latestRetrySource: latestRetrySource,
            latestRetryableAssistantMessageID: latestRetryableAssistantMessageID
        )
        retryInFlightAssistantMessageID = retrySource.assistantMessageID
        latestRetryableAssistantMessageID = nil

        let retryAssistantMessageID = UUID().uuidString
        let retryMessage = Message(
            id: retryAssistantMessageID,
            role: .assistant,
            content: "",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: nextAppendedMessageTimestamp(),
            error: nil
        )
        messages.append(retryMessage)
        beginStreamingMessage(assistantMessageId: retryAssistantMessageID)
        syncMessagesToStore(conversationId: retrySource.conversationID, persist: true)

        latestRetrySource = retrySource.replaying(with: retryAssistantMessageID)
        await startStream(request: latestRetrySource?.request ?? retrySource.request)
    }

    func currentRetryStateSnapshot() -> ChatRetryStateSnapshot {
        retryStateBeforeReplay ?? ChatRetryStateSnapshot(
            latestRetrySource: latestRetrySource,
            latestRetryableAssistantMessageID: latestRetryableAssistantMessageID
        )
    }

    func restoreRetryState(
        _ snapshot: ChatRetryStateSnapshot,
        removingInterruptedAssistantMessageID interruptedAssistantMessageID: String? = nil
    ) {
        removeInterruptedRetryReplayMessage(
            interruptedAssistantMessageID,
            conversationID: snapshot.latestRetrySource?.conversationID
        )
        latestRetrySource = snapshot.latestRetrySource
        latestRetryableAssistantMessageID = snapshot.latestRetryableAssistantMessageID
        retryInFlightAssistantMessageID = nil
        retryStateBeforeReplay = nil
    }

    func restoreRetryStateAfterInterruptedReplayIfNeeded() {
        guard let snapshot = retryStateBeforeReplay else {
            retryInFlightAssistantMessageID = nil
            return
        }
        let interruptedAssistantMessageID = currentStreamMessageId ?? latestRetrySource?.assistantMessageID
        let originalAssistantMessageID = snapshot.latestRetrySource?.assistantMessageID
        restoreRetryState(
            snapshot,
            removingInterruptedAssistantMessageID: interruptedAssistantMessageID == originalAssistantMessageID
                ? nil
                : interruptedAssistantMessageID
        )
    }

    func clearRetryState() {
        latestRetrySource = nil
        latestRetryableAssistantMessageID = nil
        retryInFlightAssistantMessageID = nil
        retryStateBeforeReplay = nil
    }

    private func removeInterruptedRetryReplayMessage(
        _ assistantMessageID: String?,
        conversationID: String?
    ) {
        guard let assistantMessageID else {
            return
        }
        let messageCount = messages.count
        messages.removeAll { $0.id == assistantMessageID }
        guard messages.count != messageCount else {
            return
        }
        clearTypingRevealState(flushDisplayedContent: false)
        currentStreamMessageId = nil
        streamingConversationId = nil
        didReceiveTerminalStreamEvent = false
        syncMessagesToStore(
            conversationId: conversationID ?? selectedConversationId,
            persist: true
        )
    }
}
