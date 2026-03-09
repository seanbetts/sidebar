import Combine
import sideBarShared
import Foundation
import UniformTypeIdentifiers

// MARK: - ChatViewModel+Streaming
extension ChatViewModel {
    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        streamingConversationId = request.conversationId ?? selectedConversationId
        do {
            try await streamClient.connect(request: request)
        } catch is CancellationError {
            // Stream cancellation is user-initiated; avoid surfacing as an error.
        } catch {
            let mappedError = ErrorMapping.message(for: error)
            errorMessage = mappedError
            toastCenter?.show(message: mappedError)
            finalizeStreaming(status: .error)
        }
        isStreaming = false
    }

    public func stopStream() {
        streamClient.disconnect()
        clearTypingRevealState(flushDisplayedContent: false)
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
    }

    public func beginStreamingMessage(assistantMessageId: String) {
        currentStreamMessageId = assistantMessageId
        guard TypingRevealTuning.enabled else {
            return
        }
        let startingContent = messages.first(where: { $0.id == assistantMessageId })?.content ?? ""
        typingRevealTargetsByMessageId = [assistantMessageId: startingContent]
    }

    public func handle(event: ChatStreamEvent) {
        if let handler = streamEventHandlers[event.type] {
            handler(event)
        }
    }

    private var streamEventHandlers: [ChatStreamEventType: (ChatStreamEvent) -> Void] {
        let handlers: [ChatStreamEventType: (ChatStreamEvent) -> Void] = [
            .token: { [weak self] (event: ChatStreamEvent) in
                self?.appendToken(from: event)
            },
            .toolCall: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolCall(event)
            },
            .toolResult: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolResult(event)
            },
            .complete: { [weak self] (_: ChatStreamEvent) in
                self?.finalizeStreaming(status: .complete)
            },
            .error: { [weak self] (event: ChatStreamEvent) in
                let streamError = self?.stringValue(from: event.data, key: "error")?.trimmedOrNil
                    ?? "Chat stream error"
                self?.errorMessage = streamError
                self?.toastCenter?.show(message: streamError)
                self?.finalizeStreaming(status: .error, streamError: streamError)
            },
            .noteCreated: { [weak self] (event: ChatStreamEvent) in
                self?.handleNoteCreate(event)
            },
            .noteUpdated: { [weak self] (event: ChatStreamEvent) in
                self?.handleNoteUpdate(event)
            },
            .notePinned: { [weak self] (event: ChatStreamEvent) in
                self?.handleNotePinned(event)
            },
            .noteMoved: { [weak self] (event: ChatStreamEvent) in
                self?.handleNoteMoved(event)
            },
            .noteDeleted: { [weak self] (event: ChatStreamEvent) in
                self?.handleNoteDelete(event)
            },
            .websiteSaved: { [weak self] (event: ChatStreamEvent) in
                self?.handleWebsiteSaved(event)
            },
            .websitePinned: { [weak self] (event: ChatStreamEvent) in
                self?.handleWebsitePinned(event)
            },
            .websiteArchived: { [weak self] (event: ChatStreamEvent) in
                self?.handleWebsiteArchived(event)
            },
            .websiteDeleted: { [weak self] (event: ChatStreamEvent) in
                self?.handleWebsiteDeleted(event)
            },
            .ingestionUpdated: { [weak self] (event: ChatStreamEvent) in
                self?.handleIngestionUpdated(event)
            },
            .themeSet: { [weak self] (event: ChatStreamEvent) in
                self?.handleThemeSet(event)
            },
            .scratchpadUpdated: { [weak self] (_: ChatStreamEvent) in
                self?.refreshScratchpad()
            },
            .scratchpadCleared: { [weak self] (_: ChatStreamEvent) in
                self?.refreshScratchpad()
            },
            .promptPreview: { [weak self] (event: ChatStreamEvent) in
                self?.handlePromptPreview(event)
            },
            .toolStart: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolStart(event)
            },
            .toolEnd: { [weak self] (event: ChatStreamEvent) in
                self?.handleToolEnd(event)
            },
            .memoryCreated: { [weak self] (_: ChatStreamEvent) in self?.refreshMemories() },
            .memoryUpdated: { [weak self] (_: ChatStreamEvent) in self?.refreshMemories() },
            .memoryDeleted: { [weak self] (_: ChatStreamEvent) in self?.refreshMemories() },
            .assistantIdentityUpdated: { [weak self] (event: ChatStreamEvent) in self?.handleAssistantIdentityUpdated(event) },
            .assistantSoulUpdated: { [weak self] (event: ChatStreamEvent) in self?.handleAssistantSoulUpdated(event) },
            .otherPreferencesUpdated: { [weak self] (event: ChatStreamEvent) in self?.handleOtherPreferencesUpdated(event) },
            .workspacePatch: { [weak self] (event: ChatStreamEvent) in self?.handleWorkspacePatch(event) }
        ]
        return handlers
    }

    func applySelectionIfNeeded(using items: [Conversation]) {
        guard !items.isEmpty else {
            return
        }
        if let selectedId = selectedConversationId,
           items.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedConversationId = nil
        clearTypingRevealState(flushDisplayedContent: false)
        messages = []
        promptPreview = nil
        activeTool = nil
    }

    func reconcileMessages(_ incoming: [Message], for conversationId: String) -> [Message] {
        guard conversationId == streamingConversationId,
              let currentStreamMessageId,
              let streamingMessage = messages.first(where: { $0.id == currentStreamMessageId }) else {
            return incoming
        }

        var reconciled = incoming
        if let serverIndex = reconciled.firstIndex(where: { $0.id == currentStreamMessageId }) {
            let serverMessage = reconciled[serverIndex]
            if serverMessage.status != .streaming {
                clearTypingRevealState(flushDisplayedContent: false)
                self.currentStreamMessageId = nil
                self.streamingConversationId = nil
                return reconciled
            }
            let localTargetContent = typingRevealTargetsByMessageId[currentStreamMessageId] ?? streamingMessage.content
            if localTargetContent.count > serverMessage.content.count {
                reconciled[serverIndex] = streamingMessage
            }
            return reconciled
        }

        if reconciled.contains(where: { $0.role == .assistant && $0.status == .streaming }) {
            return reconciled
        }

        return reconciled + [streamingMessage]
    }

    func isSameMessageSnapshot(current: [Message], incoming: [Message]) -> Bool {
        guard current.count == incoming.count else {
            return false
        }
        guard let currentLast = current.last, let incomingLast = incoming.last else {
            return current.isEmpty && incoming.isEmpty
        }
        return currentLast.id == incomingLast.id
            && currentLast.content == incomingLast.content
            && currentLast.status == incomingLast.status
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
        promptPreview = nil
        activeTool = nil
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
            toastCenter?.show(message: "Attachment upload failed")
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
                    self.toastCenter?.show(message: "Attachment status failed")
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
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    func syncMessagesToStore(conversationId: String?, persist: Bool = true) {
        guard let conversationId else {
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
        guard let messageId = activeStreamingMessageId else {
            return
        }
        guard let currentMessage = messages.first(where: { $0.id == messageId }) else {
            return
        }
        let prefix = prefixForToken(message: currentMessage, token: token)
        let appendedText = prefix + token

        guard TypingRevealTuning.enabled else {
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
                    error: message.error
                )
            }
            return
        }

        let existingTarget = typingRevealTargetsByMessageId[messageId] ?? currentMessage.content
        typingRevealTargetsByMessageId[messageId] = existingTarget + appendedText
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
                    error: message.error
                )
            }
        }
        startTypingRevealLoopIfNeeded()
    }

    func handleToolCall(_ event: ChatStreamEvent) {
        guard let toolCall = toolCallFromEvent(event, includeResult: false) else {
            return
        }
        guard let messageId = activeStreamingMessageId else {
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
                error: message.error
            )
        }
    }

    func handleToolResult(_ event: ChatStreamEvent) {
        guard let toolCall = toolCallFromEvent(event, includeResult: true) else {
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
                iconKey: toolCall.iconKey ?? existing?.iconKey
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
                error: message.error
            )
        }
    }

}
