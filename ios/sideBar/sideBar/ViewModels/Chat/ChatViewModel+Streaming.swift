import Combine
import sideBarShared
import Foundation
import UniformTypeIdentifiers

// MARK: - ChatViewModel+Streaming
extension ChatViewModel {
    public func handle(event: ChatStreamEvent) {
        if let handler = streamEventHandlers[event.type] {
            handler(event)
        }
    }

    func makeStreamEventHandlers() -> [ChatStreamEventType: (ChatStreamEvent) -> Void] {
        #if DEBUG
        streamEventHandlersBuildCountForTesting += 1
        #endif
        let handlers = makeTransportStreamEventHandlers()
            .merging(makePrimitiveStreamEventHandlers(), uniquingKeysWith: { current, _ in current })
            .merging(makeContentStreamEventHandlers(), uniquingKeysWith: { current, _ in current })
        return handlers
    }

    func cleanupEmptyConversationIfNeeded() async {
        guard let conversationId = selectedConversationId else {
            return
        }
        guard !isStreaming, !isLoadingMessages else {
            return
        }
        guard messages.isEmpty else {
            return
        }
        if let detail = chatStore.conversationDetails[conversationId], detail.messageCount > 0 {
            return
        }
        if let conversation = chatStore.conversations.first(where: { $0.id == conversationId }),
           conversation.messageCount > 0 {
            return
        }
        do {
            _ = try await conversationsAPI.delete(conversationId: conversationId)
            chatStore.removeConversation(id: conversationId)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    func clearConversationSelection() {
        stopStream()
        selectedConversationId = nil
        setDraftConversationActive(false)
        messages = []
        syncDraftContext()
        promptPreview = nil
        activeTool = nil
        clearRetryState()
        clearActiveToolTask?.cancel()
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        clearAttachments()
    }

    func setDraftConversationActive(_ isActive: Bool) {
        guard isDraftConversationActive != isActive else {
            return
        }
        isDraftConversationActive = isActive
    }

    func clearAttachments() {
        attachments.removeAll()
        attachmentPollTasks.values.forEach { $0.cancel() }
        attachmentPollTasks = [:]
    }

    func addAttachment(url: URL) async {
        let id = UUID().uuidString
        let name = url.lastPathComponent
        attachments.append(
            ChatAttachmentItem(
                id: id,
                name: name,
                status: .uploading,
                stage: "uploading",
                fileURL: url
            )
        )
        await uploadAttachment(id: id, url: url)
    }

    func uploadAttachment(id: String, url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let mimeType = mimeTypeFor(url: url)
            if let rejectionMessage = IngestionUploadPolicy.rejectionMessage(
                for: url,
                mimeType: mimeType
            ) {
                updateAttachment(id: id) { item in
                    var updated = item
                    updated.status = .failed
                    updated.stage = "failed"
                    return updated
                }
                toastCenter.show(message: rejectionMessage)
                return
            }
            let fileId = try await ingestionAPI.upload(
                fileURL: url,
                filename: url.lastPathComponent,
                mimeType: mimeType
            )
            updateAttachment(id: id) { item in
                var updated = item
                updated.status = .queued
                updated.stage = "queued"
                updated.fileId = fileId
                return updated
            }
            startAttachmentPolling(id: id, fileId: fileId)
        } catch {
            updateAttachment(id: id) { item in
                var updated = item
                updated.status = .failed
                updated.stage = "failed"
                return updated
            }
            toastCenter.show(message: "Attachment upload failed")
        }
    }

    func startAttachmentPolling(id: String, fileId: String) {
        attachmentPollTasks[id]?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            if self.attachmentPollingInitialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.attachmentPollingInitialDelayNanoseconds)
            }
            while !Task.isCancelled {
                do {
                    let meta = try await ingestionAPI.getMeta(fileId: fileId)
                    let status = meta.job.status ?? "queued"
                    let stage = meta.job.stage
                    let resolvedStatus = attachmentStatus(from: status)
                    if resolvedStatus == .canceled {
                        self.attachmentPollTasks[id] = nil
                        self.attachments.removeAll { $0.id == id }
                        return
                    }
                    self.updateAttachment(id: id) { item in
                        var updated = item
                        updated.status = resolvedStatus
                        updated.stage = stage ?? status
                        return updated
                    }
                    if isTerminalAttachmentStatus(resolvedStatus) {
                        return
                    }
                    if self.attachmentPollingIntervalNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: self.attachmentPollingIntervalNanoseconds)
                    }
                } catch {
                    self.updateAttachment(id: id) { item in
                        var updated = item
                        updated.status = .failed
                        updated.stage = "failed"
                        return updated
                    }
                    self.toastCenter.show(message: "Attachment status failed")
                    return
                }
            }
        }
        attachmentPollTasks[id] = task
    }

    func updateAttachment(id: String, update: (ChatAttachmentItem) -> ChatAttachmentItem) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return
        }
        attachments[index] = update(attachments[index])
    }

    private func attachmentStatus(from status: String) -> ChatAttachmentStatus {
        switch status {
        case "ready":
            return .ready
        case "failed":
            return .failed
        case "canceled":
            return .canceled
        default:
            return .queued
        }
    }

    private func isTerminalAttachmentStatus(_ status: ChatAttachmentStatus) -> Bool {
        status == .ready || status == .failed || status == .canceled
    }

    func mimeTypeFor(url: URL) -> String {
        IngestionUploadPolicy.mimeType(for: url)
    }

    func syncMessagesToStore(conversationId: String?, persist: Bool = true) {
        guard persist, let conversationId else {
            return
        }
        chatStore.updateConversationMessages(
            id: conversationId,
            messages: messages,
            persist: persist
        )
    }

    func normalizeMessages(_ incoming: [Message]) -> [Message] {
        let indexed = incoming.enumerated().map { (offset: $0.offset, message: $0.element) }
        let sorted = indexed.sorted { left, right in
            let leftDate = DateParsing.parseISO8601(left.message.timestamp)
            let rightDate = DateParsing.parseISO8601(right.message.timestamp)
            switch (leftDate, rightDate) {
            case let (lhs?, rhs?):
                if lhs == rhs {
                    return left.offset < right.offset
                }
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.offset < right.offset
            }
        }
        return sorted.map { $0.message }
    }

    func appendToken(from event: ChatStreamEvent) {
        guard let token = stringValue(from: event.data, key: "content") else {
            return
        }
        guard let messageId = targetMessageIdForToolActionEvent else {
            return
        }
        guard let currentMessage = messages.first(where: { $0.id == messageId }) else {
            return
        }
        let currentContent = typingRevealTargetsByMessageId[messageId] ?? currentMessage.content
        let prefix = prefixForToken(
            message: currentMessage,
            token: token,
            currentContent: currentContent
        )
        let appendedText = prefix + token

        guard typingRevealEnabled else {
            updateMessage(id: messageId, persist: false) { message in
                let needsNewline = message.needsNewline == true ? false : message.needsNewline
                return Message(
                    id: message.id,
                    role: message.role,
                    content: message.content + appendedText,
                    status: message.status,
                    toolCalls: message.toolCalls,
                    needsNewline: needsNewline,
                    timestamp: message.timestamp,
                    error: message.error,
                    errorDetails: message.errorDetails
                )
            }
            return
        }

        let existingTarget = typingRevealTargetsByMessageId[messageId] ?? currentMessage.content
        let updatedTarget = existingTarget + appendedText
        typingRevealTargetsByMessageId[messageId] = updatedTarget
        if currentMessage.needsNewline == true {
            updateMessage(id: messageId, persist: false) { message in
                Message(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    status: message.status,
                    toolCalls: message.toolCalls,
                    needsNewline: false,
                    timestamp: message.timestamp,
                    error: message.error,
                    errorDetails: message.errorDetails
                )
            }
        }
        startTypingRevealLoopIfNeeded()
    }

    func handleToolCall(_ event: ChatStreamEvent) {
        let toolCall = toolCallFromEvent(event, includeResult: false)
        let targetMessageId = targetMessageIdForToolActionEvent
        guard let toolCall else {
            return
        }
        guard let messageId = targetMessageId else {
            return
        }
        updateMessage(id: messageId, persist: false) { message in
            let updatedCalls = upsertToolCall(existing: message.toolCalls, newValue: toolCall)
            return Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: updatedCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }

    func handleToolResult(_ event: ChatStreamEvent) {
        let toolCall = toolCallFromEvent(event, includeResult: true)
        guard let toolCall else {
            return
        }
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId, persist: false) { message in
            let existing = message.toolCalls?.first(where: { $0.id == toolCall.id })
            let merged = ToolCall(
                id: toolCall.id,
                name: toolCall.name,
                parameters: toolCall.parameters.isEmpty ? (existing?.parameters ?? [:]) : toolCall.parameters,
                status: toolCall.status,
                result: toolCall.result ?? existing?.result,
                skillId: toolCall.skillId ?? existing?.skillId,
                iconKey: toolCall.iconKey ?? existing?.iconKey,
                confirmationId: toolCall.confirmationId ?? existing?.confirmationId,
                confirmationSummary: toolCall.confirmationSummary ?? existing?.confirmationSummary,
                confirmationGuardReason: toolCall.confirmationGuardReason
                    ?? existing?.confirmationGuardReason,
                confirmationUndoSupported: toolCall.confirmationUndoSupported
                    ?? existing?.confirmationUndoSupported,
                confirmationExpiresAt: toolCall.confirmationExpiresAt
                    ?? existing?.confirmationExpiresAt
            )
            let updatedCalls = upsertToolCall(existing: message.toolCalls, newValue: merged)
            return Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: updatedCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }
}
