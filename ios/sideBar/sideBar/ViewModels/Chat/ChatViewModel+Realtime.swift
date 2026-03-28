import Combine
import sideBarShared
import Foundation
import OSLog

private enum DecodedRealtimeField<Value> {
    case missing
    case value(Value?)
    case invalid

    var decodedValue: Value? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }

    var isInvalid: Bool {
        if case .invalid = self {
            return true
        }
        return false
    }
}

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

    func handleAssistantIdentityUpdated(_ event: ChatStreamEvent) {
        guard let payload = dictionaryValue(from: event.data) else {
            onAssistantSettingsUpdated?(
                AssistantSettingsRealtimeUpdate(
                    assistantIdentity: nil,
                    assistantIdentityMeta: nil,
                    assistantSoul: nil,
                    assistantSoulMeta: nil,
                    requiresRefresh: true
                )
            )
            return
        }
        let hasIdentityPayload = payload.keys.contains("assistant_identity")
            || payload.keys.contains("assistant_identity_meta")
        let identity = decodeRealtimeField(
            payload["assistant_identity"],
            as: AssistantIdentitySettings.self
        )
        let meta = decodeRealtimeField(
            payload["assistant_identity_meta"],
            as: AgentFieldMeta.self
        )
        onAssistantSettingsUpdated?(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: identity.decodedValue,
                assistantIdentityMeta: meta.decodedValue,
                assistantSoul: nil,
                assistantSoulMeta: nil,
                requiresRefresh: !hasIdentityPayload || identity.isInvalid || meta.isInvalid
            )
        )
    }

    func handleAssistantSoulUpdated(_ event: ChatStreamEvent) {
        guard let payload = dictionaryValue(from: event.data) else {
            onAssistantSettingsUpdated?(
                AssistantSettingsRealtimeUpdate(
                    assistantIdentity: nil,
                    assistantIdentityMeta: nil,
                    assistantSoul: nil,
                    assistantSoulMeta: nil,
                    requiresRefresh: true
                )
            )
            return
        }
        let hasSoulPayload = payload.keys.contains("assistant_soul")
            || payload.keys.contains("assistant_soul_meta")
        let soul = decodeRealtimeField(
            payload["assistant_soul"],
            as: AssistantSoulSettings.self
        )
        let meta = decodeRealtimeField(
            payload["assistant_soul_meta"],
            as: AgentFieldMeta.self
        )
        onAssistantSettingsUpdated?(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: nil,
                assistantIdentityMeta: nil,
                assistantSoul: soul.decodedValue,
                assistantSoulMeta: meta.decodedValue,
                requiresRefresh: !hasSoulPayload || soul.isInvalid || meta.isInvalid
            )
        )
    }

    func handleNoteCreate(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        refreshContext(for: .notes(noteId: id))
    }

    func handleNoteUpdate(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        refreshContext(for: .notes(noteId: id))
    }

    func handleNoteDelete(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        refreshContext(for: .notes(noteId: id))
    }

    func handleNotePinned(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        refreshContext(for: .notes(noteId: id))
    }

    func handleNoteMoved(_ event: ChatStreamEvent) {
        guard let id = stringValue(from: event.data, key: "id") else {
            return
        }
        refreshContext(for: .notes(noteId: id))
    }

    func handleWebsiteSaved(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        refreshContext(for: .websites(id: id))
    }

    func handleWebsitePinned(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        refreshContext(for: .websites(id: id))
    }

    func handleWebsiteArchived(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        refreshContext(for: .websites(id: id))
    }

    func handleWebsiteDeleted(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        refreshContext(for: .websites(id: id))
    }

    func handleIngestionUpdated(_ event: ChatStreamEvent) {
        let fileId = stringValue(from: event.data, key: "file_id")
        refreshContext(for: .ingestion(fileId: fileId))
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

    func handleThemeSet(_ event: ChatStreamEvent) {
        guard let themeRaw = stringValue(from: event.data, key: "theme"),
              let mode = ThemeMode(rawValue: themeRaw) else {
            return
        }
        themeManager.mode = mode
    }

    func handlePromptPreview(_ event: ChatStreamEvent) {
        let payload = dictionaryValue(from: event.data) ?? [:]
        let preview = PromptPreviewPayloadParser.parseEventPayload(payload)
        promptPreview = preview
        dispatchPromptPreviewToWorkspace(preview)
    }

    func handleOtherPreferencesUpdated(_ event: ChatStreamEvent) {
        if let weatherUnit = stringValue(from: event.data, key: "weather_unit"),
           weatherUnit == "celsius" || weatherUnit == "fahrenheit" {
            UserDefaults.standard.set(
                weatherUnit == "fahrenheit",
                forKey: AppStorageKeys.weatherUsesFahrenheit
            )
        }

        if let biometricUnlockEnabled = boolValue(
            from: event.data,
            key: "biometric_unlock_enabled"
        ) {
            UserDefaults.standard.set(
                biometricUnlockEnabled,
                forKey: AppStorageKeys.biometricUnlockEnabled
            )
        }
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
        markNeedsNewline()
        clearActiveToolTask?.cancel()
        clearActiveToolTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self?.activeTool?.name == name {
                self?.activeTool = nil
            }
        }
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
        var previousMessage: Message?
        var updatedMessage: Message?
        messages = messages.map { message in
            guard message.id == id else {
                return message
            }
            previousMessage = message
            let transformed = transform(message)
            updatedMessage = transformed
            return transformed
        }
        ChatStreamingDebugTrace.log(
            "message.update",
            details: [
                "persist=\(persist)",
                "before={\(ChatStreamingDebugTrace.summarizeMessage(previousMessage))}",
                "after={\(ChatStreamingDebugTrace.summarizeMessage(updatedMessage))}"
            ].joined(separator: " ")
        )
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
        return ToolCall(
            id: id,
            name: name,
            parameters: parameters,
            status: status,
            result: result,
            skillId: skillId,
            iconKey: iconKey
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

    private func decodeRealtimeField<T: Decodable>(
        _ value: Any?,
        as type: T.Type
    ) -> DecodedRealtimeField<T> {
        guard let value else {
            return .missing
        }
        if value is NSNull {
            return .value(nil)
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            return .invalid
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return .value(try decoder.decode(type, from: data))
        } catch {
            return .invalid
        }
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
        guard messages.count == 2 else {
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
