import Foundation
import sideBarShared

struct ChatStreamingAutoScrollController {
    private(set) var lastAutoScrollAt: Date = .distantPast
    let throttleSeconds: TimeInterval

    init(throttleSeconds: TimeInterval = 0.08) {
        self.throttleSeconds = throttleSeconds
    }

    mutating func reset() {
        lastAutoScrollAt = .distantPast
    }

    mutating func shouldScroll(now: Date) -> Bool {
        guard now.timeIntervalSince(lastAutoScrollAt) >= throttleSeconds else {
            return false
        }
        lastAutoScrollAt = now
        return true
    }
}

struct ScrollChangeToken: Equatable {
    let selectedConversationId: String?
    let messageCount: Int
    let penultimateMessageSignature: ChatMessageScrollSignature
    let lastMessageSignature: ChatMessageScrollSignature
    let activeToolSignature: String
    let bottomInset: CGFloat
}

enum ChatMessageListScrollMode: Equatable {
    case noScroll
    case pinBottomWithAnimation
    case pinBottomWithoutAnimation
}

enum ChatMessageListScrollBehavior {
    static func scrollMode(
        previousMessageCount: Int,
        messageCount: Int,
        previousLastMessage: ChatMessageScrollSignature,
        newPenultimateMessage: ChatMessageScrollSignature,
        newLastMessage: ChatMessageScrollSignature,
        activeToolChanged: Bool
    ) -> ChatMessageListScrollMode {
        guard !activeToolChanged else {
            return .noScroll
        }
        guard messageCount != previousMessageCount else {
            return .noScroll
        }
        guard messageCount > 0 else {
            return .noScroll
        }
        if isRetryAppend(
            previousMessageCount: previousMessageCount,
            messageCount: messageCount,
            previousLastMessage: previousLastMessage,
            newPenultimateMessage: newPenultimateMessage,
            newLastMessage: newLastMessage
        ) {
            return .pinBottomWithoutAnimation
        }
        if isInitialStreamingAssistantAppend(
            previousMessageCount: previousMessageCount,
            messageCount: messageCount,
            previousLastMessage: previousLastMessage,
            newPenultimateMessage: newPenultimateMessage,
            newLastMessage: newLastMessage
        ) {
            return .pinBottomWithoutAnimation
        }
        return .pinBottomWithAnimation
    }

    static func scrollMode(
        previousMessages: [Message],
        messages: [Message],
        activeToolChanged: Bool
    ) -> ChatMessageListScrollMode {
        scrollMode(
            previousMessageCount: previousMessages.count,
            messageCount: messages.count,
            previousLastMessage: ChatMessageScrollSignature(message: previousMessages.last),
            newPenultimateMessage: ChatMessageScrollSignature(message: messages.dropLast().last),
            newLastMessage: ChatMessageScrollSignature(message: messages.last),
            activeToolChanged: activeToolChanged
        )
    }

    static func shouldScrollForLastMessageChange(
        from oldSignature: ChatMessageScrollSignature,
        to newSignature: ChatMessageScrollSignature,
        isStreaming: Bool,
        shouldScrollToBottom: Bool
    ) -> Bool {
        guard !isStreaming else {
            return true
        }
        guard !shouldScrollToBottom else {
            return true
        }
        let changedVisibleContent = oldSignature.id != newSignature.id
            || oldSignature.content != newSignature.content
            || oldSignature.status != newSignature.status
            || oldSignature.visibleWorkspaceTargetsSignature != newSignature.visibleWorkspaceTargetsSignature
            || oldSignature.needsNewline != newSignature.needsNewline
            || oldSignature.error != newSignature.error
        return changedVisibleContent
    }

    static func shouldAnimateLastMessageChange(
        from oldSignature: ChatMessageScrollSignature,
        to newSignature: ChatMessageScrollSignature,
        isStreaming: Bool,
        shouldScrollToBottom: Bool
    ) -> Bool {
        guard !isStreaming, !shouldScrollToBottom else {
            return false
        }
        let isTerminalStreamTransition = oldSignature.id == newSignature.id
            && !oldSignature.id.isEmpty
            && oldSignature.status == .streaming
            && newSignature.status != .streaming
        return !isTerminalStreamTransition
    }

    static func shouldScrollForActiveToolChange() -> Bool {
        false
    }

    static func shouldScheduleDeferredBottomScroll(
        previousMessageCount: Int,
        messageCount: Int,
        scrollMode: ChatMessageListScrollMode
    ) -> Bool {
        guard messageCount > previousMessageCount else {
            return false
        }
        switch scrollMode {
        case .noScroll:
            return false
        case .pinBottomWithAnimation, .pinBottomWithoutAnimation:
            return true
        }
    }

    private static func isRetryAppend(
        previousMessageCount: Int,
        messageCount: Int,
        previousLastMessage: ChatMessageScrollSignature,
        newPenultimateMessage: ChatMessageScrollSignature,
        newLastMessage: ChatMessageScrollSignature
    ) -> Bool {
        guard messageCount == previousMessageCount + 1,
              !previousLastMessage.id.isEmpty,
              previousLastMessage == newPenultimateMessage else {
            return false
        }

        guard previousLastMessage.role == .assistant,
              previousLastMessage.status == .error,
              newLastMessage.role == .assistant,
              newLastMessage.status == .streaming else {
            return false
        }

        return ErrorMapping.chatStreamPresentation(
            from: previousLastMessage.errorDetails,
            fallbackUserMessage: previousLastMessage.error
        ).isRetryable
    }

    private static func isInitialStreamingAssistantAppend(
        previousMessageCount: Int,
        messageCount: Int,
        previousLastMessage: ChatMessageScrollSignature,
        newPenultimateMessage: ChatMessageScrollSignature,
        newLastMessage: ChatMessageScrollSignature
    ) -> Bool {
        guard messageCount == previousMessageCount + 1,
              !previousLastMessage.id.isEmpty,
              previousLastMessage == newPenultimateMessage else {
            return false
        }

        return previousLastMessage.role == .user
            && previousLastMessage.status == .complete
            && newLastMessage.role == .assistant
            && newLastMessage.status == .streaming
    }
}

struct ChatMessageScrollSignature: Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let status: MessageStatus
    let toolCallsSignature: String
    let visibleWorkspaceTargetsSignature: String
    let needsNewline: Bool
    let error: String
    let errorDetails: String

    init(message: Message?) {
        guard let message else {
            id = ""
            role = .assistant
            content = ""
            status = .complete
            toolCallsSignature = ""
            visibleWorkspaceTargetsSignature = ""
            needsNewline = false
            error = ""
            errorDetails = ""
            return
        }
        id = message.id
        role = message.role
        content = message.status == .streaming ? "" : message.content
        status = message.status
        toolCallsSignature = (message.toolCalls ?? []).map {
            "\($0.id):\($0.name):\($0.status.rawValue):\($0.skillId ?? ""):\($0.iconKey ?? "")"
        }.joined(separator: "|")
        visibleWorkspaceTargetsSignature = ChatMessageListScrollBehavior
            .visibleWorkspaceTargetsSignature(for: message.toolCalls)
        needsNewline = message.needsNewline ?? false
        error = message.error ?? ""
        errorDetails = message.errorDetails ?? ""
    }
}

private extension ChatMessageListScrollBehavior {
    static func visibleWorkspaceTargetsSignature(for toolCalls: [ToolCall]?) -> String {
        ToolResultWorkspaceSurfaceParser.parse(toolCalls: toolCalls ?? []).map {
            "\($0.id):\($0.label):\($0.appIcon.rawValue)"
        }.joined(separator: "|")
    }
}

struct ChatStreamingContentSignature: Equatable {
    let id: String
    let contentCount: Int
    let status: MessageStatus

    init(message: Message?) {
        id = message?.id ?? ""
        contentCount = message?.content.count ?? 0
        status = message?.status ?? .complete
    }
}
