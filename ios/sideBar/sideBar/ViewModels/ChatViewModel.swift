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

    private let chatAPI: ChatAPI
    private let conversationsAPI: ConversationsAPIProviding
    private let cache: CacheClient
    private let themeManager: ThemeManager
    private let streamClient: ChatStreamClient
    private let chatStore: ChatStore
    private let userDefaults: UserDefaults
    private let toastCenter: ToastCenter?
    private let clock: () -> Date

    private var currentStreamMessageId: String?
    private var streamingConversationId: String?
    private var clearActiveToolTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var generatingTitleIds = Set<String>()
    private var cancellables = Set<AnyCancellable>()

    public init(
        chatAPI: ChatAPI,
        conversationsAPI: ConversationsAPIProviding,
        cache: CacheClient,
        themeManager: ThemeManager,
        streamClient: ChatStreamClient,
        chatStore: ChatStore,
        toastCenter: ToastCenter? = nil,
        userDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.chatAPI = chatAPI
        self.conversationsAPI = conversationsAPI
        self.cache = cache
        self.themeManager = themeManager
        self.streamClient = streamClient
        self.chatStore = chatStore
        self.userDefaults = userDefaults
        self.toastCenter = toastCenter
        self.clock = clock
        self.streamClient.handler = self
        self.selectedConversationId = nil

        chatStore.$conversations
            .sink { [weak self] conversations in
                self?.conversations = conversations
                self?.applySelectionIfNeeded(using: conversations)
            }
            .store(in: &cancellables)

        chatStore.$conversationDetails
            .sink { [weak self] details in
                guard let self, let id = self.selectedConversationId,
                      let detail = details[id] else {
                    return
                }
                let incoming = self.normalizeMessages(
                    self.reconcileMessages(detail.messages, for: id)
                )
                if !self.isSameMessageSnapshot(current: self.messages, incoming: incoming) {
                    self.messages = incoming
                }
            }
            .store(in: &cancellables)
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

    public var isBlankConversation: Bool {
        guard let selectedId = selectedConversationId else {
            return false
        }
        guard let conversation = conversations.first(where: { $0.id == selectedId }) else {
            return messages.isEmpty
        }
        return conversation.messageCount == 0 && messages.isEmpty
    }

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
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                await self.refreshConversations(silent: true)
                await self.refreshActiveConversation(silent: true)
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func sendMessage(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else {
            return
        }
        errorMessage = nil
        let userMessageId = UUID().uuidString
        let assistantMessageId = UUID().uuidString
        let timestamp = Self.isoTimestamp(from: clock())

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
                userMessageId: userMessageId
            )
        )
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

    public func renameConversation(id: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
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
