import Combine
import Foundation


/// Manages chat state, streaming, and conversation coordination.
public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public var conversations: [Conversation] = []
    @Published public var selectedConversationId: String? = nil
    @Published public var messages: [Message] = []
    @Published public var isStreaming: Bool = false
    @Published public var isLoadingConversations: Bool = false
    @Published public var isLoadingMessages: Bool = false
    @Published public var attachments: [ChatAttachmentItem] = []
    @Published public var errorMessage: String? = nil
    @Published public var activeTool: ChatActiveTool? = nil
    @Published public var promptPreview: ChatPromptPreview? = nil

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
