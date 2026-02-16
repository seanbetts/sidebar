import Foundation

// Internal rollout toggle for rapid fallback during QA.
enum TypingRevealTuning {
    static let enabled = true
    static let frameIntervalNanoseconds: UInt64 = 33_000_000
    static let minimumStep = 1
    static let maximumStep = 20
}

// MARK: - ChatViewModel+TypingReveal

extension ChatViewModel {
    func startTypingRevealLoopIfNeeded() {
        guard TypingRevealTuning.enabled else {
            return
        }
        guard typingRevealTask == nil else {
            return
        }
        typingRevealTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let advanced = self.advanceTypingRevealFrame()
                if !advanced, self.typingRevealTargetsByMessageId.isEmpty {
                    return
                }
                try? await Task.sleep(nanoseconds: TypingRevealTuning.frameIntervalNanoseconds)
            }
        }
    }

    @discardableResult
    func advanceTypingRevealFrame() -> Bool {
        guard TypingRevealTuning.enabled else {
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
        updateMessage(id: messageId, persist: false) { currentMessage in
            Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: nextContent,
                status: currentMessage.status,
                toolCalls: currentMessage.toolCalls,
                needsNewline: currentMessage.needsNewline,
                timestamp: currentMessage.timestamp,
                error: currentMessage.error
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
        let adaptiveStep = max(
            TypingRevealTuning.minimumStep,
            min(TypingRevealTuning.maximumStep, max(remaining / 8, TypingRevealTuning.minimumStep))
        )
        let revealCount = min(target.count, current.count + adaptiveStep)
        let endIndex = target.index(target.startIndex, offsetBy: revealCount)
        return String(target[..<endIndex])
    }

    func flushTypingRevealContent(for messageId: String) {
        guard TypingRevealTuning.enabled,
              let targetContent = typingRevealTargetsByMessageId[messageId] else {
            return
        }
        updateMessage(id: messageId, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: targetContent,
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error
            )
        }
    }

    func clearTypingRevealState(flushDisplayedContent: Bool) {
        if flushDisplayedContent, let messageId = activeStreamingMessageId {
            flushTypingRevealContent(for: messageId)
        }
        typingRevealTargetsByMessageId = [:]
        typingRevealTask?.cancel()
        typingRevealTask = nil
    }
}
