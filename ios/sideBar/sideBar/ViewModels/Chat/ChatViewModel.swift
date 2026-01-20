import Combine
import Foundation


public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public private(set) var conversations: [Conversation] = []
    @Published public private(set) var selectedConversationId: String? = nil
    @Published public private(set) var messages: [Message] = []
    @Published public private(set) var isStreaming: Bool = false
    @Published public private(set) var isLoadingConversations: Bool = false
    @Published public private(set) var isLoadingMessages: Bool = false
    @Published public private(set) var attachments: [ChatAttachmentItem] = []
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var activeTool: ChatActiveTool? = nil
    @Published public private(set) var promptPreview: ChatPromptPreview? = nil

    private let chatAPI: ChatAPI
    private let conversationsAPI: ConversationsAPIProviding
    private let cache: CacheClient
    private let ingestionAPI: IngestionAPI
    private let notesStore: NotesStore?
    private let websitesStore: WebsitesStore?
    private let ingestionStore: IngestionStore?
    private let themeManager: ThemeManager
    private let streamClient: ChatStreamClient
    private let chatStore: ChatStore
    private let userDefaults: UserDefaults
    private let toastCenter: ToastCenter?
    private let clock: () -> Date
    private let scratchpadStore: ScratchpadStore?

    private var currentStreamMessageId: String?
    private var streamingConversationId: String?
    private var clearActiveToolTask: Task<Void, Never>?
    private var refreshTask: PollingTask?
    private var generatingTitleIds = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var attachmentPollTasks: [String: Task<Void, Never>] = [:]

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
