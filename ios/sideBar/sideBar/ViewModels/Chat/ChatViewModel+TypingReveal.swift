import Foundation

// MARK: - ChatViewModel+TypingReveal

extension ChatViewModel {
    func startTypingRevealLoopIfNeeded() {
        guard typingRevealEnabled else {
            return
        }
        guard typingRevealTask == nil else {
            return
        }
        ChatStreamingDebugTrace.log(
            "typing.loop.start",
            details: [
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(activeStreamingMessageId))",
                "targets=\(typingRevealTargetsByMessageId.count)",
                "frameNs=\(typingRevealFrameIntervalNanoseconds)",
                "minStep=\(typingRevealMinimumStep)",
                "maxStep=\(typingRevealMaximumStep)"
            ].joined(separator: " ")
        )
        typingRevealTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let advanced = self.advanceTypingRevealFrame()
                if !advanced, self.typingRevealTargetsByMessageId.isEmpty {
                    ChatStreamingDebugTrace.log("typing.loop.finish", details: "reason=noTargets")
                    return
                }
                if self.typingRevealFrameIntervalNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: self.typingRevealFrameIntervalNanoseconds)
                } else {
                    await Task.yield()
                }
            }
        }
    }

    @discardableResult
    func advanceTypingRevealFrame() -> Bool {
        guard typingRevealEnabled else {
            return false
        }
        guard let messageId = activeStreamingMessageId ?? typingRevealTargetsByMessageId.keys.first,
              let targetContent = typingRevealTargetsByMessageId[messageId] else {
            return false
        }
        guard let message = messages.first(where: { $0.id == messageId }) else {
            typingRevealTargetsByMessageId[messageId] = nil
            return false
        }
        let displayedContent = message.content
        guard displayedContent != targetContent else {
            if message.status != .streaming {
                typingRevealTargetsByMessageId[messageId] = nil
            }
            return false
        }

        let nextContent = nextDisplayedContent(current: displayedContent, target: targetContent)
        let backlogBefore = targetContent.count - displayedContent.count
        let backlogAfter = targetContent.count - nextContent.count
        ChatStreamingDebugTrace.log(
            "typing.frame",
            details: [
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(messageId))",
                "displayed=\(displayedContent.count)",
                "target=\(targetContent.count)",
                "revealed=\(max(nextContent.count - displayedContent.count, 0))",
                "backlogBefore=\(backlogBefore)",
                "backlogAfter=\(backlogAfter)"
            ].joined(separator: " ")
        )
        updateMessage(id: messageId, persist: false) { currentMessage in
            Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: nextContent,
                status: currentMessage.status,
                toolCalls: currentMessage.toolCalls,
                needsNewline: currentMessage.needsNewline,
                timestamp: currentMessage.timestamp,
                error: currentMessage.error,
                errorDetails: currentMessage.errorDetails
            )
        }
        return true
    }

    func nextDisplayedContent(current: String, target: String) -> String {
        guard target.hasPrefix(current) else {
            return target
        }
        let remaining = target.count - current.count
        guard remaining > 0 else {
            return target
        }
        let tailFlushThreshold = max(24, typingRevealMinimumStep)
        if remaining <= tailFlushThreshold {
            return target
        }

        let adaptiveStep = max(
            typingRevealMinimumStep,
            min(typingRevealMaximumStep, max(remaining / 3, typingRevealMinimumStep))
        )
        let revealCount = min(target.count, current.count + adaptiveStep)
        let endIndex = target.index(target.startIndex, offsetBy: revealCount)
        return String(target[..<endIndex])
    }

    func flushTypingRevealContent(for messageId: String) {
        guard typingRevealEnabled,
              let targetContent = typingRevealTargetsByMessageId[messageId] else {
            return
        }
        let displayedContentCount = messages.first(where: { $0.id == messageId })?.content.count ?? 0
        ChatStreamingDebugTrace.log(
            "typing.flush",
            details: [
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(messageId))",
                "displayed=\(displayedContentCount)",
                "target=\(targetContent.count)",
                "remaining=\(max(targetContent.count - displayedContentCount, 0))"
            ].joined(separator: " ")
        )
        updateMessage(id: messageId, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: targetContent,
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }

    func clearTypingRevealState(flushDisplayedContent: Bool) {
        ChatStreamingDebugTrace.log(
            "typing.clear",
            details: [
                "flush=\(flushDisplayedContent)",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(activeStreamingMessageId))",
                "targets=\(typingRevealTargetsByMessageId.count)"
            ].joined(separator: " ")
        )
        if flushDisplayedContent, let messageId = activeStreamingMessageId {
            flushTypingRevealContent(for: messageId)
        }
        typingRevealTargetsByMessageId = [:]
        typingRevealTask?.cancel()
        typingRevealTask = nil
    }
}
