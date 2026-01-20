import Combine
import Foundation
import UniformTypeIdentifiers

extension ChatViewModel {
    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        streamingConversationId = request.conversationId ?? selectedConversationId
        do {
            try await streamClient.connect(request: request)
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }

    public func stopStream() {
        streamClient.disconnect()
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
    }

    public func beginStreamingMessage(assistantMessageId: String) {
        currentStreamMessageId = assistantMessageId
    }

    public func handle(event: ChatStreamEvent) {
        switch event.type {
        case .token:
            appendToken(from: event)
        case .toolCall:
            handleToolCall(event)
        case .toolResult:
            handleToolResult(event)
        case .complete:
            finalizeStreaming(status: .complete)
        case .error:
            errorMessage = "Chat stream error"
            finalizeStreaming(status: .error)
        case .noteCreated:
            handleNoteCreate(event)
        case .noteUpdated:
            handleNoteUpdate(event)
        case .notePinned:
            handleNotePinned(event)
        case .noteMoved:
            handleNoteMoved(event)
        case .noteDeleted:
            handleNoteDelete(event)
        case .websiteSaved:
            handleWebsiteSaved(event)
        case .websitePinned:
            handleWebsitePinned(event)
        case .websiteArchived:
            handleWebsiteArchived(event)
        case .websiteDeleted:
            handleWebsiteDeleted(event)
        case .ingestionUpdated:
            handleIngestionUpdated(event)
        case .themeSet:
            handleThemeSet(event)
        case .scratchpadUpdated:
            cache.remove(key: CacheKeys.scratchpad)
            scratchpadStore?.bump()
        case .scratchpadCleared:
            cache.remove(key: CacheKeys.scratchpad)
            scratchpadStore?.bump()
        case .promptPreview:
            handlePromptPreview(event)
        case .toolStart:
            handleToolStart(event)
        case .toolEnd:
            handleToolEnd(event)
        case .memoryCreated, .memoryUpdated, .memoryDeleted:
            break
        }
    }

    private func applySelectionIfNeeded(using items: [Conversation]) {
        guard !items.isEmpty else {
            return
        }
        if let selectedId = selectedConversationId,
           items.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedConversationId = nil
        messages = []
        promptPreview = nil
        activeTool = nil
    }

    private func reconcileMessages(_ incoming: [Message], for conversationId: String) -> [Message] {
        guard conversationId == streamingConversationId,
              let currentStreamMessageId,
              !incoming.contains(where: { $0.id == currentStreamMessageId }),
              let streamingMessage = messages.first(where: { $0.id == currentStreamMessageId }) else {
            return incoming
        }
        return incoming + [streamingMessage]
    }

    private func isSameMessageSnapshot(current: [Message], incoming: [Message]) -> Bool {
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

    private func cleanupEmptyConversationIfNeeded() async {
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
            errorMessage = error.localizedDescription
        }
    }

    private func clearConversationSelection() {
        stopStream()
        selectedConversationId = nil
        messages = []
        promptPreview = nil
        activeTool = nil
        clearActiveToolTask?.cancel()
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        clearAttachments()
    }

    private func clearAttachments() {
        attachments.removeAll()
        attachmentPollTasks.values.forEach { $0.cancel() }
        attachmentPollTasks = [:]
    }

    private func addAttachment(url: URL) async {
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

    private func uploadAttachment(id: String, url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let mimeType = mimeTypeFor(url: url)
            let fileId = try await ingestionAPI.upload(
                fileData: data,
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

    private func startAttachmentPolling(id: String, fileId: String) {
        attachmentPollTasks[id]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while !Task.isCancelled {
                do {
                    guard let self else { return }
                    let meta = try await ingestionAPI.getMeta(fileId: fileId)
                    let status = meta.job.status ?? "queued"
                    let stage = meta.job.stage
                    let resolvedStatus: ChatAttachmentStatus
                    switch status {
                    case "ready":
                        resolvedStatus = .ready
                    case "failed":
                        resolvedStatus = .failed
                    case "canceled":
                        resolvedStatus = .canceled
                    default:
                        resolvedStatus = .queued
                    }
                    await MainActor.run {
                        self.updateAttachment(id: id) { item in
                            var updated = item
                            updated.status = resolvedStatus
                            updated.stage = stage ?? status
                            return updated
                        }
                    }
                    if resolvedStatus == .ready || resolvedStatus == .failed || resolvedStatus == .canceled {
                        return
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    await MainActor.run {
                        self?.toastCenter?.show(message: "Attachment status failed")
                    }
                    return
                }
            }
        }
        attachmentPollTasks[id] = task
    }

    private func updateAttachment(id: String, update: (ChatAttachmentItem) -> ChatAttachmentItem) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return
        }
        attachments[index] = update(attachments[index])
    }

    private func mimeTypeFor(url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func syncMessagesToStore(conversationId: String?, persist: Bool = false) {
        guard let conversationId else {
            return
        }
        chatStore.updateConversationMessages(
            id: conversationId,
            messages: messages,
            persist: persist
        )
    }

    private func normalizeMessages(_ incoming: [Message]) -> [Message] {
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

    private func appendToken(from event: ChatStreamEvent) {
        guard let token = stringValue(from: event.data, key: "content") else {
            return
        }
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId) { message in
            let prefix = prefixForToken(message: message, token: token)
            let needsNewline = message.needsNewline == true ? false : message.needsNewline
            return Message(
                id: message.id,
                role: message.role,
                content: message.content + prefix + token,
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: needsNewline,
                timestamp: message.timestamp,
                error: message.error
            )
        }
    }

    private func handleToolCall(_ event: ChatStreamEvent) {
        guard let toolCall = toolCallFromEvent(event, includeResult: false) else {
            return
        }
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId) { message in
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

    private func handleToolResult(_ event: ChatStreamEvent) {
        guard let toolCall = toolCallFromEvent(event, includeResult: true) else {
            return
        }
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId) { message in
            let existing = message.toolCalls?.first(where: { $0.id == toolCall.id })
            let merged = ToolCall(
                id: toolCall.id,
                name: toolCall.name,
                parameters: toolCall.parameters.isEmpty ? (existing?.parameters ?? [:]) : toolCall.parameters,
                status: toolCall.status,
                result: toolCall.result ?? existing?.result
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

    private func finalizeStreaming(status: MessageStatus) {
        guard let messageId = activeStreamingMessageId else {
            isStreaming = false
            return
        }
        updateMessage(id: messageId) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: status,
                toolCalls: message.toolCalls,
                needsNewline: message.needsNewline,
                timestamp: message.timestamp,
                error: message.error
            )
        }
        syncMessagesToStore(conversationId: streamingConversationId ?? selectedConversationId, persist: true)
        if let conversationId = streamingConversationId ?? selectedConversationId,
           let assistantMessage = messages.first(where: { $0.id == messageId }) {
            Task { [weak self] in
                await self?.persistMessage(conversationId: conversationId, message: assistantMessage)
                await self?.refreshConversations(silent: true)
                await self?.generateConversationTitleIfNeeded(conversationId: conversationId)
            }
        }
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
    }
}
