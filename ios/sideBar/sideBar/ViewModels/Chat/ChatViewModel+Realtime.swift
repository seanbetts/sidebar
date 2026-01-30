import Combine
import sideBarShared
import Foundation

// MARK: - ChatViewModel+Realtime

extension ChatViewModel {
    func handleNoteCreate(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        cache.remove(key: CacheKeys.notesTree)
        notesStore?.invalidateNote(id: id)
        refreshNotesTree()
    }

    func handleNoteUpdate(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        cache.remove(key: CacheKeys.notesTree)
        notesStore?.invalidateNote(id: id)
        refreshNotesTree()
    }

    func handleNoteDelete(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        cache.remove(key: CacheKeys.notesTree)
        notesStore?.invalidateNote(id: id)
        refreshNotesTree()
    }

    func handleNotePinned(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        cache.remove(key: CacheKeys.notesTree)
        notesStore?.invalidateNote(id: id)
        refreshNotesTree()
    }

    func handleNoteMoved(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        cache.remove(key: CacheKeys.notesTree)
        notesStore?.invalidateNote(id: id)
        refreshNotesTree()
    }

    func handleWebsiteSaved(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
        refreshWebsitesList()
    }

    func handleWebsitePinned(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
        refreshWebsitesList()
    }

    func handleWebsiteArchived(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
        refreshWebsitesList()
    }

    func handleWebsiteDeleted(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
        refreshWebsitesList()
    }

    func handleIngestionUpdated(_ event: ChatStreamEvent) {
        let fileId = stringValue(from: event.data, key: "file_id")
        cache.invalidateList(listKey: CacheKeys.ingestionList, detailKey: CacheKeys.ingestionMeta, id: fileId)
        refreshIngestionList(fileId: fileId)
    }

    func refreshNotesTree() {
        guard let notesStore else {
            return
        }
        Task {
            try? await notesStore.loadTree(force: true)
        }
    }

    func refreshWebsitesList() {
        guard let websitesStore else {
            return
        }
        Task {
            try? await websitesStore.loadList(force: true)
        }
    }

    func refreshIngestionList(fileId: String?) {
        guard let ingestionStore else {
            return
        }
        Task {
            try? await ingestionStore.loadList(force: true)
            if let fileId, ingestionStore.activeMeta?.file.id == fileId {
                try? await ingestionStore.loadMeta(fileId: fileId, force: true)
            }
        }
    }

    func handleThemeSet(_ event: ChatStreamEvent) {
        guard let themeRaw = stringValue(from: event.data, key: "theme"),
              let mode = ThemeMode(rawValue: themeRaw) else {
            return
        }
        themeManager.mode = mode
    }

    func handlePromptPreview(_ event: ChatStreamEvent) {
        let systemPrompt = stringValue(from: event.data, key: "system_prompt")
        let firstMessagePrompt = stringValue(from: event.data, key: "first_message_prompt")
        promptPreview = ChatPromptPreview(systemPrompt: systemPrompt, firstMessagePrompt: firstMessagePrompt)
    }

    func handleToolStart(_ event: ChatStreamEvent) {
        guard let name = stringValue(from: event.data, key: "name") else {
            return
        }
        clearActiveToolTask?.cancel()
        activeTool = ChatActiveTool(name: name, status: .running, startedAt: self.clock())
    }

    func handleToolEnd(_ event: ChatStreamEvent) {
        guard let name = stringValue(from: event.data, key: "name") else {
            return
        }
        let statusRaw = stringValue(from: event.data, key: "status")
        let status = statusRaw == ToolActivityStatus.error.rawValue ? ToolActivityStatus.error : ToolActivityStatus.success
        activeTool = ChatActiveTool(name: name, status: status, startedAt: activeTool?.startedAt ?? self.clock())
        if status == .error {
            markNeedsNewline()
        }
        clearActiveToolTask?.cancel()
        clearActiveToolTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            await MainActor.run {
                if self?.activeTool?.name == name {
                    self?.activeTool = nil
                }
            }
        }
    }

    func markNeedsNewline() {
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: true,
                timestamp: message.timestamp,
                error: message.error
            )
        }
    }

    func updateMessage(id: String, transform: (Message) -> Message) {
        messages = messages.map { message in
            guard message.id == id else {
                return message
            }
            return transform(message)
        }
        syncMessagesToStore(conversationId: streamingConversationId ?? selectedConversationId)
    }

    func upsertToolCall(existing: [ToolCall]?, newValue: ToolCall) -> [ToolCall] {
        var updated = existing ?? []
        if let index = updated.firstIndex(where: { $0.id == newValue.id }) {
            updated[index] = newValue
        } else {
            updated.append(newValue)
        }
        return updated
    }

    func toolCallFromEvent(_ event: ChatStreamEvent, includeResult: Bool) -> ToolCall? {
        guard let payload = dictionaryValue(from: event.data) else {
            return nil
        }
        guard let id = payload["id"] as? String else {
            return nil
        }
        let name = payload["name"] as? String ?? "Tool"
        let statusRaw = payload["status"] as? String
        let status = ToolStatus(rawValue: statusRaw ?? ToolStatus.pending.rawValue) ?? .pending
        let parameters = dictionaryToAnyCodable(payload["parameters"])
        let result = includeResult ? anyCodableValue(payload["result"]) : nil
        return ToolCall(id: id, name: name, parameters: parameters, status: status, result: result)
    }

    func dictionaryValue(from data: AnyCodable?) -> [String: Any]? {
        data?.value as? [String: Any]
    }

    func stringValue(from data: AnyCodable?, key: String) -> String? {
        guard let payload = dictionaryValue(from: data) else {
            return nil
        }
        return payload[key] as? String
    }

    func anyCodableValue(_ value: Any?) -> AnyCodable? {
        guard let value else {
            return nil
        }
        return AnyCodable(value)
    }

    func dictionaryToAnyCodable(_ value: Any?) -> [String: AnyCodable] {
        guard let dict = value as? [String: Any] else {
            return [:]
        }
        return dict.mapValues { AnyCodable($0) }
    }

    func persistMessage(conversationId: String, message: Message) async {
        do {
            let updated = try await conversationsAPI.addMessage(
                conversationId: conversationId,
                message: ConversationMessageCreate(
                    id: message.id,
                    role: message.role.rawValue,
                    content: message.content,
                    status: message.status.rawValue,
                    timestamp: message.timestamp,
                    toolCalls: message.toolCalls?.map { AnyCodable($0) },
                    error: message.error
                )
            )
            await MainActor.run { [chatStore] in
                chatStore.upsertConversation(updated)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func isoTimestamp(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    func generateConversationTitleIfNeeded(conversationId: String) async {
        guard let conversation = chatStore.conversations.first(where: { $0.id == conversationId }) else {
            return
        }
        guard !conversation.titleGenerated else {
            return
        }
        guard !generatingTitleIds.contains(conversationId) else {
            return
        }
        guard messages.count == 2 else {
            return
        }
        generatingTitleIds.insert(conversationId)
        defer { generatingTitleIds.remove(conversationId) }
        do {
            let response = try await chatAPI.generateTitle(conversationId: conversationId)
            await MainActor.run { [chatStore] in
                chatStore.updateConversationTitle(
                    id: conversationId,
                    title: response.title,
                    titleGenerated: response.fallback == false
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    func prefixForToken(message: Message, token: String) -> String {
        guard message.needsNewline == true,
              !message.content.isEmpty,
              !message.content.hasSuffix("\n"),
              !token.hasPrefix("\n") else {
            return ""
        }
        return "\n\n"
    }

    var activeStreamingMessageId: String? {
        if let currentStreamMessageId {
            return currentStreamMessageId
        }
        return messages.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
    }
}
