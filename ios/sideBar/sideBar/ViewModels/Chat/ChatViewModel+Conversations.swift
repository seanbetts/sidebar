import Combine
import Foundation

extension ChatViewModel {
    public func loadConversations(force: Bool = false, silent: Bool = false) async {
        errorMessage = nil
        if !silent {
            isLoadingConversations = true
        }
        do {
            try await chatStore.loadConversations(force: force)
        } catch {
            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        if !silent {
            isLoadingConversations = false
        }
    }

    public func refreshConversations(silent: Bool = false) async {
        await loadConversations(force: true, silent: silent)
    }

    public func refreshActiveConversation(silent: Bool = false) async {
        guard let id = selectedConversationId else {
            return
        }
        await loadConversation(id: id, silent: silent)
    }

    public func startAutoRefresh(intervalSeconds: TimeInterval = 30) {
        refreshTask?.cancel()
        let task = PollingTask(interval: intervalSeconds)
        refreshTask = task
        task.start { [weak self] in
            await self?.refreshConversations(silent: true)
            await self?.refreshActiveConversation(silent: true)
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func sendMessage(text: String) async {
        guard let trimmed = text.trimmedOrNil, !isStreaming else {
            return
        }
        errorMessage = nil
        guard !hasPendingAttachments else {
            return
        }
        let userMessageId = UUID().uuidString
        let assistantMessageId = UUID().uuidString
        let timestamp = Self.isoTimestamp(from: clock())
        let attachmentsForMessage = readyAttachments.compactMap { attachment -> ChatAttachment? in
            guard let fileId = attachment.fileId else { return nil }
            return ChatAttachment(fileId: fileId, filename: attachment.name)
        }

        var conversationId = selectedConversationId
        if conversationId == nil {
            do {
                let conversation = try await conversationsAPI.create(title: "New Chat")
                conversationId = conversation.id
                selectedConversationId = conversation.id
                chatStore.upsertConversation(conversation)
                chatStore.upsertConversationDetail(
                    ConversationWithMessages(
                        id: conversation.id,
                        title: conversation.title,
                        titleGenerated: conversation.titleGenerated,
                        createdAt: conversation.createdAt,
                        updatedAt: conversation.updatedAt,
                        messageCount: conversation.messageCount,
                        firstMessage: conversation.firstMessage,
                        isArchived: conversation.isArchived,
                        messages: []
                    )
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        guard let conversationId else {
            return
        }

        let userMessage = Message(
            id: userMessageId,
            role: .user,
            content: trimmed,
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: timestamp,
            error: nil
        )
        messages.append(userMessage)
        syncMessagesToStore(conversationId: conversationId, persist: true)

        let assistantMessage = Message(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: timestamp,
            error: nil
        )
        messages.append(assistantMessage)
        beginStreamingMessage(assistantMessageId: assistantMessageId)
        syncMessagesToStore(conversationId: conversationId, persist: true)

        Task { [weak self] in
            await self?.persistMessage(
                conversationId: conversationId,
                message: userMessage
            )
        }

        await startStream(
            request: ChatStreamRequest(
                message: trimmed,
                conversationId: conversationId,
                userMessageId: userMessageId,
                attachments: attachmentsForMessage.isEmpty ? nil : attachmentsForMessage
            )
        )
        clearAttachments()
    }

    public func startNewConversation() async {
        guard !isStreaming else {
            return
        }
        errorMessage = nil
        stopStream()
        promptPreview = nil
        activeTool = nil
        clearActiveToolTask?.cancel()
        await cleanupEmptyConversationIfNeeded()
        clearAttachments()
        do {
            let conversation = try await conversationsAPI.create(title: "New Chat")
            selectedConversationId = conversation.id
            userDefaults.set(conversation.id, forKey: AppStorageKeys.lastConversationId)
            messages = []
            chatStore.upsertConversation(conversation)
            chatStore.upsertConversationDetail(
                ConversationWithMessages(
                    id: conversation.id,
                    title: conversation.title,
                    titleGenerated: conversation.titleGenerated,
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    messageCount: conversation.messageCount,
                    firstMessage: conversation.firstMessage,
                    isArchived: conversation.isArchived,
                    messages: []
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeConversation() async {
        guard selectedConversationId != nil else {
            return
        }
        await cleanupEmptyConversationIfNeeded()
        clearConversationSelection()
    }

    public func addAttachments(urls: [URL]) {
        for url in urls {
            Task { [weak self] in
                await self?.addAttachment(url: url)
            }
        }
    }

    public func retryAttachment(id: String) {
        guard let attachment = attachments.first(where: { $0.id == id }),
              let url = attachment.fileURL else {
            toastCenter?.show(message: "Re-upload the file to retry")
            return
        }
        updateAttachment(id: id) { item in
            var updated = item
            updated.status = .uploading
            updated.stage = "uploading"
            updated.fileId = nil
            return updated
        }
        Task { [weak self] in
            await self?.uploadAttachment(id: id, url: url)
        }
    }

    public func deleteAttachment(id: String) {
        guard let attachment = attachments.first(where: { $0.id == id }) else {
            return
        }
        attachmentPollTasks[id]?.cancel()
        attachmentPollTasks[id] = nil
        attachments.removeAll { $0.id == id }
        if let fileId = attachment.fileId {
            Task { [weak self] in
                do {
                    try await self?.ingestionAPI.delete(fileId: fileId)
                } catch {
                    await MainActor.run {
                        self?.toastCenter?.show(message: "Failed to delete attachment")
                    }
                }
            }
        }
    }

    public func removeReadyAttachment(id: String) {
        attachments.removeAll { $0.id == id }
    }

    public func renameConversation(id: String, title: String) async {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else {
            return
        }
        guard let existing = conversations.first(where: { $0.id == id }) else {
            return
        }
        guard existing.title != trimmed else {
            return
        }
        let previousTitle = existing.title
        let previousGenerated = existing.titleGenerated
        chatStore.updateConversationTitle(
            id: id,
            title: trimmed,
            titleGenerated: false
        )
        do {
            let updated = try await conversationsAPI.update(
                conversationId: id,
                updates: ConversationUpdateRequest(title: trimmed, titleGenerated: false, isArchived: nil)
            )
            chatStore.updateConversationTitle(
                id: id,
                title: updated.title,
                titleGenerated: updated.titleGenerated
            )
        } catch {
            chatStore.updateConversationTitle(
                id: id,
                title: previousTitle,
                titleGenerated: previousGenerated
            )
            errorMessage = error.localizedDescription
            toastCenter?.show(message: "Failed to rename conversation")
        }
    }

    public func deleteConversation(id: String) async {
        let wasSelected = selectedConversationId == id
        let existing = chatStore.conversations.first(where: { $0.id == id })
        let existingDetail = chatStore.conversationDetails[id]
        let previousMessages = messages
        let previousPromptPreview = promptPreview
        let previousActiveTool = activeTool
        chatStore.removeConversation(id: id)
        if wasSelected {
            clearConversationSelection()
        }
        do {
            _ = try await conversationsAPI.delete(conversationId: id)
        } catch {
            if let existing {
                chatStore.upsertConversation(existing)
            }
            if let existingDetail {
                chatStore.upsertConversationDetail(existingDetail)
            }
            if wasSelected {
                selectedConversationId = id
                messages = existingDetail?.messages ?? previousMessages
                promptPreview = previousPromptPreview
                activeTool = previousActiveTool
            }
            errorMessage = error.localizedDescription
            toastCenter?.show(message: "Failed to delete conversation")
        }
    }

    public func selectConversation(id: String?) async {
        guard selectedConversationId != id else {
            return
        }
        await cleanupEmptyConversationIfNeeded()
        selectedConversationId = id
        promptPreview = nil
        activeTool = nil
        clearActiveToolTask?.cancel()
        if let id {
            userDefaults.set(id, forKey: AppStorageKeys.lastConversationId)
            await loadConversation(id: id)
        } else {
            messages = []
            promptPreview = nil
        }
    }

    public func loadConversation(id: String, silent: Bool = false) async {
        if !silent {
            errorMessage = nil
            isLoadingMessages = true
        }
        do {
            try await chatStore.loadConversation(id: id)
        } catch {
            if chatStore.conversationDetails[id] == nil {
                errorMessage = error.localizedDescription
            }
        }
        if !silent {
            isLoadingMessages = false
        }
    }
}
