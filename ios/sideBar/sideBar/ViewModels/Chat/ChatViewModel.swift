import Combine
import Foundation

// MARK: - ChatViewModel

/// Central ViewModel for chat functionality, managing conversations, messages, and real-time streaming.
///
/// This ViewModel coordinates between multiple components:
/// - `ChatStore`: Persistent storage for conversations and messages
/// - `ChatStreamClient`: Server-sent events for real-time message streaming
/// - Various APIs: Chat, Conversations, and Ingestion endpoints
///
/// ## Threading
/// All published properties are updated on the main actor. Stream events are processed
/// asynchronously and dispatched to the main thread for UI updates.
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
/// let viewModel = ChatViewModel(chatAPI: api, conversationsAPI: convAPI, ...)
/// await viewModel.loadConversations()
/// await viewModel.selectConversation(id: conversationId)
/// await viewModel.sendMessage(text: "Hello")
/// ```
public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public var conversations: [Conversation] = []
    @Published public var selectedConversationId: String?
    @Published public var messages: [Message] = []
    @Published public var isStreaming: Bool = false
    @Published public var isLoadingConversations: Bool = false
    @Published public var isLoadingMessages: Bool = false
    @Published public var attachments: [ChatAttachmentItem] = []
    @Published public var errorMessage: String?
    @Published public var activeTool: ChatActiveTool?
    @Published public var promptPreview: ChatPromptPreview?

    let chatAPI: ChatAPI
    let conversationsAPI: ConversationsAPIProviding
    let cache: CacheClient
    let ingestionAPI: IngestionAPI
    let notesStore: NotesStore?
    let websitesStore: WebsitesStore?
    let ingestionStore: IngestionStore?
    let themeManager: ThemeManager
    let streamClient: ChatStreamClient
    let chatStore: ChatStore
    let writeQueue: WriteQueue
    let userDefaults: UserDefaults
    let toastCenter: ToastCenter?
    let clock: () -> Date
    let scratchpadStore: ScratchpadStore?

    var currentStreamMessageId: String?
    var streamingConversationId: String?
    var clearActiveToolTask: Task<Void, Never>?
    var refreshTask: PollingTask?
    var generatingTitleIds = Set<String>()
    var cancellables = Set<AnyCancellable>()
    var attachmentPollTasks: [String: Task<Void, Never>] = [:]

    public init(
        chatAPI: ChatAPI,
        conversationsAPI: ConversationsAPIProviding,
        ingestionAPI: IngestionAPI,
        cache: CacheClient,
        notesStore: NotesStore? = nil,
        websitesStore: WebsitesStore? = nil,
        ingestionStore: IngestionStore? = nil,
        themeManager: ThemeManager,
        streamClient: ChatStreamClient,
        chatStore: ChatStore,
        writeQueue: WriteQueue,
        toastCenter: ToastCenter? = nil,
        userDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init,
        scratchpadStore: ScratchpadStore? = nil
    ) {
        self.chatAPI = chatAPI
        self.conversationsAPI = conversationsAPI
        self.cache = cache
        self.ingestionAPI = ingestionAPI
        self.notesStore = notesStore
        self.websitesStore = websitesStore
        self.ingestionStore = ingestionStore
        self.themeManager = themeManager
        self.streamClient = streamClient
        self.chatStore = chatStore
        self.writeQueue = writeQueue
        self.userDefaults = userDefaults
        self.toastCenter = toastCenter
        self.clock = clock
        self.scratchpadStore = scratchpadStore
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

    public var hasPendingAttachments: Bool {
        attachments.contains { $0.status != .ready }
    }

    public var readyAttachments: [ChatAttachmentItem] {
        attachments.readyItems
    }

    public var pendingAttachments: [ChatAttachmentItem] {
        attachments.filter { $0.status != .ready }
    }

}
