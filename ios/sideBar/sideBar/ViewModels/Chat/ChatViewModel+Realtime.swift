import Combine
import Foundation

extension ChatViewModel {
    private func handleNoteCreate(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
        refreshNotesTree()
    }

    private func handleNoteUpdate(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
        refreshNotesTree()
    }

    private func handleNoteDelete(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
        refreshNotesTree()
    }

    private func handleNotePinned(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
        refreshNotesTree()
    }

    private func handleNoteMoved(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
        refreshNotesTree()
    }

    private func handleWebsiteSaved(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        }
        refreshWebsitesList()
    }

    private func handleWebsitePinned(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        }
        refreshWebsitesList()
    }

    private func handleWebsiteArchived(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        }
        refreshWebsitesList()
    }

    private func handleWebsiteDeleted(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        }
        refreshWebsitesList()
    }

    private func handleIngestionUpdated(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.ingestionList)
        let fileId = stringValue(from: event.data, key: "file_id")
        if let fileId {
            cache.remove(key: CacheKeys.ingestionMeta(fileId: fileId))
        }
        refreshIngestionList(fileId: fileId)
    }

    private func refreshNotesTree() {
        guard let notesStore else {
            return
        }
        Task {
            try? await notesStore.loadTree(force: true)
        }
    }

    private func refreshWebsitesList() {
        guard let websitesStore else {
            return
        }
        Task {
            try? await websitesStore.loadList(force: true)
        }
    }

    private func refreshIngestionList(fileId: String?) {
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

    private func handleThemeSet(_ event: ChatStreamEvent) {
        guard let themeRaw = stringValue(from: event.data, key: "theme"),
              let mode = ThemeMode(rawValue: themeRaw) else {
            return
        }
        themeManager.mode = mode
    }

    private func handlePromptPreview(_ event: ChatStreamEvent) {
        let systemPrompt = stringValue(from: event.data, key: "system_prompt")
        let firstMessagePrompt = stringValue(from: event.data, key: "first_message_prompt")
        promptPreview = ChatPromptPreview(systemPrompt: systemPrompt, firstMessagePrompt: firstMessagePrompt)
    }

    private func handleToolStart(_ event: ChatStreamEvent) {
        guard let name = stringValue(from: event.data, key: "name") else {
            return
        }
        clearActiveToolTask?.cancel()
        activeTool = ChatActiveTool(name: name, status: .running, startedAt: clock())
    }

    private func handleToolEnd(_ event: ChatStreamEvent) {
        guard let name = stringValue(from: event.data, key: "name") else {
            return
        }
        let statusRaw = stringValue(from: event.data, key: "status")
        let status = statusRaw == ToolActivityStatus.error.rawValue ? ToolActivityStatus.error : ToolActivityStatus.success
        activeTool = ChatActiveTool(name: name, status: status, startedAt: activeTool?.startedAt ?? clock())
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

    private func markNeedsNewline() {
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

    private func updateMessage(id: String, transform: (Message) -> Message) {
        messages = messages.map { message in
            guard message.id == id else {
                return message
            }
            return transform(message)
        }
        syncMessagesToStore(conversationId: streamingConversationId ?? selectedConversationId)
    }

    private func upsertToolCall(existing: [ToolCall]?, newValue: ToolCall) -> [ToolCall] {
        var updated = existing ?? []
        if let index = updated.firstIndex(where: { $0.id == newValue.id }) {
            updated[index] = newValue
        } else {
            updated.append(newValue)
        }
        return updated
    }

    private func toolCallFromEvent(_ event: ChatStreamEvent, includeResult: Bool) -> ToolCall? {
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

    private func dictionaryValue(from data: AnyCodable?) -> [String: Any]? {
        data?.value as? [String: Any]
    }

    private func stringValue(from data: AnyCodable?, key: String) -> String? {
        guard let payload = dictionaryValue(from: data) else {
            return nil
        }
        return payload[key] as? String
    }

    private func anyCodableValue(_ value: Any?) -> AnyCodable? {
        guard let value else {
            return nil
        }
        return AnyCodable(value)
    }

    private func dictionaryToAnyCodable(_ value: Any?) -> [String: AnyCodable] {
        guard let dict = value as? [String: Any] else {
            return [:]
        }
        return dict.mapValues { AnyCodable($0) }
    }

    private func persistMessage(conversationId: String, message: Message) async {
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

    private static func isoTimestamp(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private func generateConversationTitleIfNeeded(conversationId: String) async {
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

    private func prefixForToken(message: Message, token: String) -> String {
        guard message.needsNewline == true,
              !message.content.isEmpty,
              !message.content.hasSuffix("\n"),
              !token.hasPrefix("\n") else {
            return ""
        }
        return "\n\n"
    }

    private var activeStreamingMessageId: String? {
        if let currentStreamMessageId {
            return currentStreamMessageId
        }
        return messages.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
    }
}
