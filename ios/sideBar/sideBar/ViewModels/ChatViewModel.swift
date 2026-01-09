import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

public struct ChatActiveTool: Equatable {
    public let name: String
    public let status: ToolActivityStatus
    public let startedAt: Date

    public init(name: String, status: ToolActivityStatus, startedAt: Date) {
        self.name = name
        self.status = status
        self.startedAt = startedAt
    }
}

public enum ToolActivityStatus: String {
    case running
    case success
    case error
}

public struct ChatPromptPreview: Equatable {
    public let systemPrompt: String?
    public let firstMessagePrompt: String?

    public init(systemPrompt: String?, firstMessagePrompt: String?) {
        self.systemPrompt = systemPrompt
        self.firstMessagePrompt = firstMessagePrompt
    }
}

public struct ConversationGroup: Identifiable {
    public let id: String
    public let title: String
    public let conversations: [Conversation]

    public init(id: String, title: String, conversations: [Conversation]) {
        self.id = id
        self.title = title
        self.conversations = conversations
    }
}

@MainActor
public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public private(set) var conversations: [Conversation] = []
    @Published public private(set) var selectedConversationId: String? = nil
    @Published public private(set) var messages: [Message] = []
    @Published public private(set) var isStreaming: Bool = false
    @Published public private(set) var isLoadingConversations: Bool = false
    @Published public private(set) var isLoadingMessages: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var activeTool: ChatActiveTool? = nil
    @Published public private(set) var promptPreview: ChatPromptPreview? = nil

    private let conversationsAPI: ConversationsProviding
    private let chatAPI: ChatAPI
    private let cache: CacheClient
    private let themeManager: ThemeManager
    private let streamClient: ChatStreamClient
    private let userDefaults: UserDefaults
    private let clock: () -> Date

    private var currentStreamMessageId: String?
    private var streamingConversationId: String?
    private var hasLoadedConversations = false
    private var clearActiveToolTask: Task<Void, Never>?

    public init(
        conversationsAPI: ConversationsProviding,
        chatAPI: ChatAPI,
        cache: CacheClient,
        themeManager: ThemeManager,
        streamClient: ChatStreamClient,
        userDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.conversationsAPI = conversationsAPI
        self.chatAPI = chatAPI
        self.cache = cache
        self.themeManager = themeManager
        self.streamClient = streamClient
        self.userDefaults = userDefaults
        self.clock = clock
        self.streamClient.handler = self
        self.selectedConversationId = userDefaults.string(forKey: AppStorageKeys.lastConversationId)
    }

    public var groupedConversations: [ConversationGroup] {
        let sorted = conversations.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }

        let now = clock()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let lastWeek = calendar.date(byAdding: .day, value: -7, to: today),
              let lastMonth = calendar.date(byAdding: .day, value: -30, to: today) else {
            return [ConversationGroup(id: "all", title: "Recent", conversations: sorted)]
        }

        var todayItems: [Conversation] = []
        var yesterdayItems: [Conversation] = []
        var weekItems: [Conversation] = []
        var monthItems: [Conversation] = []
        var olderItems: [Conversation] = []

        for conversation in sorted {
            let updated = DateParsing.parseISO8601(conversation.updatedAt) ?? .distantPast
            if updated >= today {
                todayItems.append(conversation)
            } else if updated >= yesterday {
                yesterdayItems.append(conversation)
            } else if updated >= lastWeek {
                weekItems.append(conversation)
            } else if updated >= lastMonth {
                monthItems.append(conversation)
            } else {
                olderItems.append(conversation)
            }
        }

        return [
            ConversationGroup(id: "today", title: "Today", conversations: todayItems),
            ConversationGroup(id: "yesterday", title: "Yesterday", conversations: yesterdayItems),
            ConversationGroup(id: "week", title: "Last 7 Days", conversations: weekItems),
            ConversationGroup(id: "month", title: "Last 30 Days", conversations: monthItems),
            ConversationGroup(id: "older", title: "Older", conversations: olderItems)
        ].filter { !$0.conversations.isEmpty }
    }

    public func loadConversations(force: Bool = false) async {
        errorMessage = nil
        if !force {
            if let cached: [Conversation] = cache.get(key: CacheKeys.conversationsList) {
                conversations = cached
                applySelectionIfNeeded(using: cached)
            }
            if hasLoadedConversations {
                return
            }
        }
        isLoadingConversations = true
        do {
            let response = try await conversationsAPI.list()
            let filtered = response.filter { $0.isArchived != true }
            conversations = filtered
            cache.set(key: CacheKeys.conversationsList, value: filtered, ttlSeconds: CachePolicy.conversationsList)
            hasLoadedConversations = true
            applySelectionIfNeeded(using: filtered)
        } catch {
            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingConversations = false
    }

    public func refreshConversations() async {
        await loadConversations(force: true)
    }

    public func selectConversation(id: String?) async {
        guard selectedConversationId != id else {
            return
        }
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

    public func loadConversation(id: String) async {
        errorMessage = nil
        isLoadingMessages = true
        let cacheKey = CacheKeys.conversation(id: id)
        let cached: ConversationWithMessages? = cache.get(key: cacheKey)
        if let cached {
            messages = reconcileMessages(cached.messages, for: id)
        }
        do {
            let response = try await conversationsAPI.get(id: id)
            messages = reconcileMessages(response.messages, for: id)
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.conversationDetail)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingMessages = false
    }

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
        case .noteDeleted:
            handleNoteDelete(event)
        case .websiteSaved:
            handleWebsiteSaved(event)
        case .websiteDeleted:
            handleWebsiteDeleted(event)
        case .themeSet:
            handleThemeSet(event)
        case .scratchpadUpdated:
            cache.remove(key: CacheKeys.scratchpad)
        case .scratchpadCleared:
            cache.remove(key: CacheKeys.scratchpad)
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
        if let storedId = userDefaults.string(forKey: AppStorageKeys.lastConversationId),
           items.contains(where: { $0.id == storedId }) {
            selectedConversationId = storedId
        } else {
            selectedConversationId = items.first?.id
        }
        if let selectedConversationId {
            Task { [weak self] in
                await self?.loadConversation(id: selectedConversationId)
            }
        }
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
        isStreaming = false
        streamingConversationId = nil
        currentStreamMessageId = nil
    }

    private func handleNoteCreate(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
    }

    private func handleNoteUpdate(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
    }

    private func handleNoteDelete(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.notesTree)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.note(id: id))
        }
    }

    private func handleWebsiteSaved(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        }
    }

    private func handleWebsiteDeleted(_ event: ChatStreamEvent) {
        cache.remove(key: CacheKeys.websitesList)
        if let id = stringValue(from: event.data, key: "id") {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
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
