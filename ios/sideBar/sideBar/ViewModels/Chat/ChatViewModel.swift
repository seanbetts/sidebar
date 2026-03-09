import Combine
import Foundation

// MARK: - ChatViewModel

private final class ChatViewModelTeardownBag {
    private let lock = NSLock()
    private var streamClient: (any ChatStreamClient)?
    private var clearActiveToolTask: Task<Void, Never>?
    private var typingRevealTask: Task<Void, Never>?
    private var refreshTask: PollingTask?
    private var attachmentPollTasks: [String: Task<Void, Never>] = [:]

    func setStreamClient(_ streamClient: any ChatStreamClient) {
        lock.lock()
        self.streamClient = streamClient
        lock.unlock()
    }

    func setClearActiveToolTask(_ task: Task<Void, Never>?) {
        lock.lock()
        clearActiveToolTask = task
        lock.unlock()
    }

    func setTypingRevealTask(_ task: Task<Void, Never>?) {
        lock.lock()
        typingRevealTask = task
        lock.unlock()
    }

    func setRefreshTask(_ task: PollingTask?) {
        lock.lock()
        refreshTask = task
        lock.unlock()
    }

    func setAttachmentPollTasks(_ tasks: [String: Task<Void, Never>]) {
        lock.lock()
        attachmentPollTasks = tasks
        lock.unlock()
    }

    deinit {
        lock.lock()
        let streamClient = streamClient
        let clearActiveToolTask = clearActiveToolTask
        let typingRevealTask = typingRevealTask
        let refreshTask = refreshTask
        let attachmentPollTasks = attachmentPollTasks
        lock.unlock()

        streamClient?.disconnect()
        clearActiveToolTask?.cancel()
        typingRevealTask?.cancel()
        refreshTask?.cancel()
        attachmentPollTasks.values.forEach { $0.cancel() }
    }
}

/// Central ViewModel for chat functionality, managing conversations, messages, and real-time streaming.
///
/// This ViewModel coordinates between multiple components:
/// - `ChatStore`: Persistent storage for conversations and messages
/// - `ChatStreamClient`: Server-sent events for real-time message streaming
/// - Various APIs: Chat, Conversations, and Ingestion endpoints
///
/// ## Threading
/// The class is `@MainActor`-isolated. All published properties and mutable state are
/// accessed exclusively on the main actor. Stream events are dispatched to the main actor
/// by the stream client before delivery.
///
/// ## Architecture
/// The ViewModel is split across multiple files for maintainability:
/// - `ChatViewModel.swift`: Core state and initialization
/// - `ChatViewModel+Conversations.swift`: Conversation CRUD operations
/// - `ChatViewModel+Streaming.swift`: Message sending and stream handling
/// - `ChatViewModel+Realtime.swift`: Real-time event processing
///
/// ## Usage
/// ```swift
/// let viewModel = ChatViewModel(
///     network: ChatNetworkCoordinator(
///         chatAPI: chatAPI,
///         conversationsAPI: conversationsAPI,
///         ingestionAPI: ingestionAPI,
///         streamClient: streamClient,
///         networkStatus: connectivityMonitor
///     ),
///     storage: ChatStorageCoordinator(
///         cache: cache,
///         chatStore: chatStore
///     ),
///     ui: ChatUICoordinator(themeManager: themeManager)
/// )
/// await viewModel.loadConversations()
/// await viewModel.selectConversation(id: conversationId)
/// await viewModel.sendMessage(text: "Hello")
/// ```
@MainActor public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public var conversations: [Conversation] = []
    @Published public var selectedConversationId: String?
    @Published public var isDraftConversationActive: Bool = false
    @Published public var messages: [Message] = []
    @Published public var isStreaming: Bool = false
    @Published public var isLoadingConversations: Bool = false
    @Published public var isLoadingMessages: Bool = false
    @Published public var attachments: [ChatAttachmentItem] = []
    @Published public var errorMessage: String?
    @Published public var activeTool: ChatActiveTool?
    @Published public var promptPreview: ChatPromptPreview?

    let network: ChatNetworkCoordinator
    let ui: ChatUICoordinator
    private let cacheClient: CacheClient
    private let chatStoreReference: ChatStore
    private let scratchpadStoreReference: ScratchpadStore?
    private let contextProvidersReference: [any ContextProvider]

    var chatAPI: ChatAPI { network.chatAPI }
    var conversationsAPI: ConversationsAPIProviding { network.conversationsAPI }
    var ingestionAPI: IngestionAPI { network.ingestionAPI }
    var streamClient: ChatStreamClient { network.streamClient }
    var networkStatus: any NetworkStatusProviding { network.networkStatus }

    var cache: CacheClient { cacheClient }
    var chatStore: ChatStore { chatStoreReference }
    var scratchpadStore: ScratchpadStore? { scratchpadStoreReference }
    var contextProviders: [any ContextProvider] { contextProvidersReference }

    var themeManager: ThemeManager { ui.themeManager }
    var toastCenter: ToastCenter? { ui.toastCenter }
    var userDefaults: UserDefaults { ui.userDefaults }
    var clock: () -> Date { ui.clock }
    var attachmentPollingInitialDelayNanoseconds: UInt64 { ui.attachmentPollingInitialDelayNanoseconds }
    var attachmentPollingIntervalNanoseconds: UInt64 { ui.attachmentPollingIntervalNanoseconds }
    var typingRevealEnabled: Bool { ui.typingRevealEnabled }
    var typingRevealFrameIntervalNanoseconds: UInt64 { ui.typingRevealFrameIntervalNanoseconds }
    var typingRevealMinimumStep: Int { ui.typingRevealMinimumStep }
    var typingRevealMaximumStep: Int { ui.typingRevealMaximumStep }
    var onAssistantSettingsUpdated: ((AssistantSettingsRealtimeUpdate) -> Void)? { ui.onAssistantSettingsUpdated }
    var requestContextProvider: (() -> ChatRequestContext?)? { ui.requestContextProvider }
    var workspaceActionDispatcher: ((WorkspaceAction) -> Void)?
    private let teardownBag = ChatViewModelTeardownBag()

    var currentStreamMessageId: String?
    var streamingConversationId: String?
    var clearActiveToolTask: Task<Void, Never>? {
        didSet {
            teardownBag.setClearActiveToolTask(clearActiveToolTask)
        }
    }
    var typingRevealTargetsByMessageId: [String: String] = [:]
    var typingRevealTask: Task<Void, Never>? {
        didSet {
            teardownBag.setTypingRevealTask(typingRevealTask)
        }
    }
    var refreshTask: PollingTask? {
        didSet {
            teardownBag.setRefreshTask(refreshTask)
        }
    }
    var generatingTitleIds = Set<String>()
    var cancellables = Set<AnyCancellable>()
    var attachmentPollTasks: [String: Task<Void, Never>] = [:] {
        didSet {
            teardownBag.setAttachmentPollTasks(attachmentPollTasks)
        }
    }

    init(
        network: ChatNetworkCoordinator,
        storage: ChatStorageCoordinator,
        ui: ChatUICoordinator
    ) {
        self.network = network
        self.ui = ui
        self.cacheClient = storage.cache
        self.chatStoreReference = storage.chatStore
        self.scratchpadStoreReference = storage.scratchpadStore
        self.contextProvidersReference = storage.contextProviders
        self.teardownBag.setStreamClient(network.streamClient)
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

    public var hasCachedSelectedConversation: Bool {
        guard let selectedConversationId else { return false }
        return chatStore.hasCachedConversation(id: selectedConversationId)
    }

    public var hasPendingAttachments: Bool {
        attachments.contains { $0.status != .ready }
    }

    public var readyAttachments: [ChatAttachmentItem] {
        attachments.readyItems
    }

    public var pendingAttachments: [ChatAttachmentItem] {
        attachments.filter { $0.status != .ready && $0.status != .canceled }
    }

    public func reset() {
        stopAutoRefresh()
        stopStream()
        selectedConversationId = nil
        isDraftConversationActive = false
        conversations = []
        messages = []
        isStreaming = false
        isLoadingConversations = false
        isLoadingMessages = false
        attachments = []
        errorMessage = nil
        activeTool = nil
        promptPreview = nil
        generatingTitleIds.removeAll()
        clearActiveToolTask?.cancel()
        clearActiveToolTask = nil
        userDefaults.removeObject(forKey: AppStorageKeys.lastConversationId)
        clearAttachments()
    }

}
