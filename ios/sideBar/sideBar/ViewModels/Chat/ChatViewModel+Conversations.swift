import Combine
import sideBarShared
import Foundation

// MARK: - ChatViewModel+Conversations

extension ChatViewModel {
    func ensureActiveConversationForOutgoingStream() async throws -> String {
        var conversationId = selectedConversationId
        if conversationId != nil {
            setDraftConversationActive(false)
        }
        if conversationId == nil {
            let pendingConversation = beginPendingConversation()
            do {
                let conversation = try await conversationsAPI.create(title: "New Chat")
                finalizePendingConversation(pendingConversation, with: conversation)
                conversationId = conversation.id
            } catch {
                rollbackPendingConversation(pendingConversation)
                throw error
            }
        }

        guard let conversationId else {
            throw APIClientError.unknown
        }
        return conversationId
    }

    public func startFeatureDiscovery(for feature: OnboardingDiscoveryFeature) async {
        let previousConversationId = selectedConversationId
        await startNewConversation()
        guard let conversationId = selectedConversationId else {
            return
        }
        guard previousConversationId == nil || conversationId != previousConversationId else {
            return
        }
        await sendMessage(text: feature.kickoffPrompt)
    }

    public func searchConversations(query: String, limit: Int = 50) async throws -> [Conversation] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return [] }
        let response = try await conversationsAPI.search(query: trimmed, limit: limit)
        return response.filter { $0.isArchived != true }
    }

    public func loadConversations(force: Bool = false, silent: Bool = false) async {
        ContentListReadRecovery.begin(hasVisibleContent: !conversations.isEmpty)
            .apply(errorMessage: &errorMessage, loadState: &conversationsLoadState)
        if !silent { isLoadingConversations = true }
        do {
            try await chatStore.loadConversations(force: force)
            ContentListReadRecovery.success()
                .apply(errorMessage: &errorMessage, loadState: &conversationsLoadState)
        } catch {
            if let failureTransition = ContentListReadRecovery.failure(
                error: error,
                hasVisibleContent: !conversations.isEmpty
            ) {
                failureTransition.apply(errorMessage: &errorMessage, loadState: &conversationsLoadState)
            }
        }
        if !silent { isLoadingConversations = false }
    }

    public func refreshConversations(silent: Bool = false) async {
        await loadConversations(force: true, silent: silent)
    }

    public func refreshActiveConversation(silent: Bool = false) async {
        guard let id = selectedConversationId else {
            return
        }
        await loadConversation(id: id, force: true, silent: silent)
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

    public func sendMessage(text: String, clearDraftOnDispatch: Bool = false) async {
        guard let trimmed = text.trimmedOrNil, !isStreaming else {
            return
        }
        errorMessage = nil
        guard !hasPendingAttachments else {
            return
        }
        clearRetryState()
        let userMessageId = UUID().uuidString
        let assistantMessageId = UUID().uuidString
        let timestamp = nextAppendedMessageTimestamp()
        let attachmentsForMessage = readyAttachments.compactMap { attachment -> ChatAttachment? in
            guard let fileId = attachment.fileId else { return nil }
            return ChatAttachment(fileId: fileId, filename: attachment.name)
        }
        let draftSourceKey = currentDraftKey
        let draftSourceText = draftText

        let conversationId: String
        do {
            conversationId = try await ensureActiveConversationForOutgoingStream()
        } catch {
            errorMessage = ErrorMapping.message(for: error)
            return
        }
        let draftSendContext = beginDraftSendTransition(
            clearDraftOnDispatch: clearDraftOnDispatch,
            sourceKey: draftSourceKey,
            sourceDraftText: draftSourceText,
            conversationId: conversationId
        )

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

        let requestContext = requestContextProvider?()
        let request = ChatStreamRequest(
            message: trimmed,
            conversationId: conversationId,
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            openContext: requestContext?.openContext,
            attachments: attachmentsForMessage.isEmpty ? nil : attachmentsForMessage,
            currentLocation: requestContext?.currentLocation,
            currentLocationLevels: requestContext?.currentLocationLevels,
            currentWeather: requestContext?.currentWeather,
            currentTimezone: requestContext?.currentTimezone
        )
        latestRetrySource = ChatRetrySource(request: request)
        await startStream(
            request: request
        )
        restoreDraftAfterFailedSendIfNeeded(draftSendContext, assistantMessageId: assistantMessageId)
        clearAttachments()
    }

    public func openDraftConversation() async {
        guard !isStreaming else {
            return
        }
        errorMessage = nil
        stopStream()
        promptPreview = nil
        activeTool = nil
        clearActiveToolTask?.cancel()
        await cleanupEmptyConversationIfNeeded()
        selectedConversationId = nil
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        messages = []
        setDraftConversationActive(true)
        syncDraftContext()
        clearRetryState()
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
        let pendingConversation = beginPendingConversation()
        do {
            let conversation = try await conversationsAPI.create(title: "New Chat")
            finalizePendingConversation(pendingConversation, with: conversation)
            clearRetryState()
        } catch {
            rollbackPendingConversation(pendingConversation)
            errorMessage = ErrorMapping.message(for: error)
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

    private func beginPendingConversation() -> Conversation {
        let now = ISO8601DateFormatter().string(from: Date())
        let pending = Conversation(
            id: "pending-\(UUID().uuidString)",
            title: "New Chat",
            titleGenerated: false,
            createdAt: now,
            updatedAt: now,
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        selectedConversationId = pending.id
        setDraftConversationActive(false)
        messages = []
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        syncDraftContext()
        chatStore.upsertConversation(pending, persist: false)
        chatStore.upsertConversationDetail(
            ConversationWithMessages(
                id: pending.id,
                title: pending.title,
                titleGenerated: pending.titleGenerated,
                createdAt: pending.createdAt,
                updatedAt: pending.updatedAt,
                messageCount: pending.messageCount,
                firstMessage: pending.firstMessage,
                isArchived: pending.isArchived,
                messages: []
            ),
            persist: false
        )
        conversations = chatStore.conversations
        return pending
    }

    private func finalizePendingConversation(_ pending: Conversation, with conversation: Conversation) {
        let pendingDraftKey = ChatDraftController.draftKey(for: pending.id)
        chatStore.removeConversation(id: pending.id, persist: false)
        selectedConversationId = conversation.id
        setDraftConversationActive(false)
        userDefaults.set(conversation.id, forKey: AppStorageKeys.lastConversationId)
        messages = []
        draftController.migrateDraft(from: pendingDraftKey, to: currentDraftKey)
        draftText = draftController.currentDraftText
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
        conversations = chatStore.conversations
    }

    private func rollbackPendingConversation(_ pending: Conversation) {
        let pendingDraftKey = ChatDraftController.draftKey(for: pending.id)
        chatStore.removeConversation(id: pending.id, persist: false)
        selectedConversationId = nil
        setDraftConversationActive(true)
        messages = []
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        draftController.migrateDraft(from: pendingDraftKey, to: currentDraftKey)
        draftText = draftController.currentDraftText
        conversations = chatStore.conversations
    }

    public func retryAttachment(id: String) {
        guard let attachment = attachments.first(where: { $0.id == id }),
              let url = attachment.fileURL else {
            toastCenter.show(message: "Re-upload the file to retry")
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
                    self?.toastCenter.show(message: "Failed to delete attachment")
                }
            }
        }
    }

    public func cancelAttachment(id: String) {
        guard let attachment = attachments.first(where: { $0.id == id }) else {
            return
        }
        attachmentPollTasks[id]?.cancel()
        attachmentPollTasks[id] = nil
        attachments.removeAll { $0.id == id }
        guard let fileId = attachment.fileId else {
            return
        }
        Task { [weak self] in
            do {
                try await self?.ingestionAPI.cancel(fileId: fileId)
            } catch {
                self?.toastCenter.show(message: "Failed to cancel attachment")
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
            errorMessage = ErrorMapping.message(for: error)
            toastCenter.show(message: "Failed to rename conversation")
        }
    }

    public func deleteConversation(id: String) async {
        let wasSelected = selectedConversationId == id
        let existing = chatStore.conversations.first(where: { $0.id == id })
        let existingDetail = chatStore.conversationDetails[id]
        let previousMessages = messages
        let previousPromptPreview = promptPreview
        let previousActiveTool = activeTool
        let previousRetryState = currentRetryStateSnapshot()
        let draftKey = ChatDraftController.draftKey(for: id)
        chatStore.removeConversation(id: id)
        if wasSelected {
            clearConversationSelection()
        }
        do {
            _ = try await conversationsAPI.delete(conversationId: id)
            draftController.clearDraft(for: draftKey)
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
                restoreRetryState(previousRetryState)
            }
            errorMessage = ErrorMapping.message(for: error)
            toastCenter.show(message: "Failed to delete conversation")
        }
    }

    public func selectConversation(id: String?) async {
        guard selectedConversationId != id || isDraftConversationActive else {
            return
        }
        await cleanupEmptyConversationIfNeeded()
        selectedConversationId = id
        setDraftConversationActive(false)
        syncDraftContext()
        promptPreview = nil
        activeTool = nil
        clearActiveToolTask?.cancel()
        if let id {
            userDefaults.set(id, forKey: AppStorageKeys.lastConversationId)
            messages = []
            await loadConversation(id: id)
        } else {
            messages = []
            promptPreview = nil
        }
    }

    public func loadConversation(id: String, force: Bool = false, silent: Bool = false) async {
        errorMessage = nil
        if !silent {
            isLoadingMessages = true
        }
        if !networkStatus.offlineCapabilityPolicy.canAttemptServerRead,
           !chatStore.hasCachedConversation(id: id) {
            errorMessage = "This chat isn't available offline yet."
            if !silent {
                isLoadingMessages = false
            }
            return
        }
        do {
            try await chatStore.loadConversation(id: id, force: force)
        } catch {
            if chatStore.conversationDetails[id] == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
        if !silent {
            isLoadingMessages = false
        }
    }

    func nextAppendedMessageTimestamp() -> String {
        let currentDate = clock()
        guard let latestMessageDate = messages.compactMap({ DateParsing.parseISO8601($0.timestamp) }).max() else {
            return Self.isoTimestamp(from: currentDate)
        }

        if currentDate > latestMessageDate {
            return Self.isoTimestamp(from: currentDate)
        }

        return Self.isoTimestamp(from: latestMessageDate.addingTimeInterval(0.001))
    }
}
