import Foundation
import OSLog
import sideBarShared

// MARK: - ChatViewModel+Realtime

extension ChatViewModel {
    private var realtimeLogger: Logger {
        Logger(subsystem: "sideBar", category: "ChatViewModelRealtime")
    }

    func refreshScratchpad() {
        cache.remove(key: CacheKeys.scratchpad)
        scratchpadStore?.bump()
    }

    func refreshMemories() {
        cache.remove(key: CacheKeys.memoriesList)
    }

    func requestOnboardingStateRefresh() {
        onOnboardingStateRefreshRequested?()
    }

    func refreshContext(for target: ContextRefreshTarget) {
        let matchingProviders = contextProviders.filter { $0.matches(target) }
        if matchingProviders.isEmpty {
            invalidateContextCacheFallback(for: target)
            return
        }

        for provider in matchingProviders {
            provider.invalidate(target)
            Task {
                do {
                    try await provider.refresh(target)
                } catch {
                    let errorMessage = error.localizedDescription
                    self.realtimeLogger.error(
                        "Failed to refresh \(provider.name, privacy: .public) after realtime event: \(errorMessage, privacy: .public)"
                    )
                }
            }
        }
    }

    private func invalidateContextCacheFallback(for target: ContextRefreshTarget) {
        switch target {
        case .notes(let noteId):
            cache.remove(key: CacheKeys.notesTree)
            cache.remove(key: CacheKeys.note(id: noteId))
        case .websites(let id):
            cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
        case .ingestion(let fileId):
            cache.invalidateList(listKey: CacheKeys.ingestionList, detailKey: CacheKeys.ingestionMeta, id: fileId)
        }
    }

    func handlePromptPreview(_ event: ChatStreamEvent) {
        let payload = dictionaryValue(from: event.data) ?? [:]
        let preview = PromptPreviewPayloadParser.parseEventPayload(payload)
        promptPreview = preview
        dispatchPromptPreviewToWorkspace(preview)
    }

    func markNeedsNewline() {
        guard let messageId = activeStreamingMessageId else {
            return
        }
        updateMessage(id: messageId, persist: false) { message in
            Message(
                id: message.id,
                role: message.role,
                content: message.content,
                status: message.status,
                toolCalls: message.toolCalls,
                needsNewline: true,
                timestamp: message.timestamp,
                error: message.error,
                errorDetails: message.errorDetails
            )
        }
    }

    func updateMessage(id: String, persist: Bool = true, transform: (Message) -> Message) {
        messages = messages.map { message in
            guard message.id == id else {
                return message
            }
            return transform(message)
        }
        syncMessagesToStore(
            conversationId: streamingConversationId ?? selectedConversationId,
            persist: persist
        )
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
        let skillId = firstStringValue(
            in: payload,
            keys: ["skill_id", "skillId"]
        )
        let iconKey = firstStringValue(
            in: payload,
            keys: ["icon_key", "iconKey"]
        )
        let confirmationId = firstStringValue(
            in: payload,
            keys: ["confirmation_id", "confirmationId"]
        )
        let confirmationSummary = firstStringValue(
            in: payload,
            keys: ["confirmation_summary", "confirmationSummary"]
        )
        let confirmationGuardReason = firstStringValue(
            in: payload,
            keys: ["confirmation_guard_reason", "confirmationGuardReason"]
        )
        let confirmationExpiresAt = firstStringValue(
            in: payload,
            keys: ["confirmation_expires_at", "confirmationExpiresAt"]
        )
        return ToolCall(
            id: id,
            name: name,
            parameters: parameters,
            status: status,
            result: result,
            skillId: skillId,
            iconKey: iconKey,
            confirmationId: confirmationId,
            confirmationSummary: confirmationSummary,
            confirmationGuardReason: confirmationGuardReason,
            confirmationUndoSupported: boolValue(from: event.data, key: "confirmationUndoSupported")
                ?? boolValue(from: event.data, key: "confirmation_undo_supported"),
            confirmationExpiresAt: confirmationExpiresAt
        )
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

    func boolValue(from data: AnyCodable?, key: String) -> Bool? {
        guard let payload = dictionaryValue(from: data) else {
            return nil
        }
        return payload[key] as? Bool
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

    func firstStringValue(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let raw = payload[key] as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    func toolCallPayloads(from toolCalls: [ToolCall]?) -> [AnyCodable]? {
        toolCalls?.map { AnyCodable(toolCallPayload(from: $0)) }
    }

    private func toolCallPayload(from toolCall: ToolCall) -> [String: Any] {
        var payload: [String: Any] = [
            "id": toolCall.id,
            "name": toolCall.name,
            "parameters": toolCall.parameters.mapValues(\.value),
            "status": toolCall.status.rawValue
        ]
        if let result = toolCall.result {
            payload["result"] = result.value
        }
        if let skillId = toolCall.skillId {
            payload["skillId"] = skillId
        }
        if let iconKey = toolCall.iconKey {
            payload["iconKey"] = iconKey
        }
        if let confirmationId = toolCall.confirmationId {
            payload["confirmationId"] = confirmationId
        }
        if let confirmationSummary = toolCall.confirmationSummary {
            payload["confirmationSummary"] = confirmationSummary
        }
        if let confirmationGuardReason = toolCall.confirmationGuardReason {
            payload["confirmationGuardReason"] = confirmationGuardReason
        }
        if let confirmationUndoSupported = toolCall.confirmationUndoSupported {
            payload["confirmationUndoSupported"] = confirmationUndoSupported
        }
        if let confirmationExpiresAt = toolCall.confirmationExpiresAt {
            payload["confirmationExpiresAt"] = confirmationExpiresAt
        }
        return payload
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
                    toolCalls: toolCallPayloads(from: message.toolCalls),
                    error: message.error,
                    errorDetails: message.errorDetails
                )
            )
            chatStore.upsertConversation(updated)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
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
        guard messages.count >= 2 else {
            return
        }
        guard messages.contains(where: { $0.role == .user }),
              messages.contains(where: { $0.role == .assistant }) else {
            return
        }
        generatingTitleIds.insert(conversationId)
        defer { generatingTitleIds.remove(conversationId) }
        do {
            let response = try await chatAPI.generateTitle(conversationId: conversationId)
            chatStore.updateConversationTitle(
                id: conversationId,
                title: response.title,
                titleGenerated: response.fallback == false
            )
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    func prefixForToken(message: Message, token: String, currentContent: String? = nil) -> String {
        let resolvedContent = currentContent ?? message.content
        guard message.needsNewline == true,
              !resolvedContent.isEmpty,
              !resolvedContent.hasSuffix("\n"),
              !token.hasPrefix("\n") else {
            return ""
        }
        return "\n\n"
    }

    var activeStreamingMessageId: String? {
        currentStreamMessageId
            ?? messages.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
    }
}
