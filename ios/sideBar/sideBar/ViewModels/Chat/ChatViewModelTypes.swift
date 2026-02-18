import Foundation

struct ChatNetworkCoordinator {
    let chatAPI: ChatAPI
    let conversationsAPI: ConversationsAPIProviding
    let ingestionAPI: IngestionAPI
    let streamClient: ChatStreamClient
    let networkStatus: any NetworkStatusProviding
}

enum ContextRefreshTarget {
    case notes(noteId: String)
    case websites(id: String?)
    case ingestion(fileId: String?)
}

protocol ContextProvider {
    var name: String { get }
    func matches(_ target: ContextRefreshTarget) -> Bool
    func invalidate(_ target: ContextRefreshTarget)
    func refresh(_ target: ContextRefreshTarget) async throws
}

struct NotesContextProvider: ContextProvider {
    let cache: CacheClient
    let notesStore: NotesStore

    var name: String { "notes" }

    func matches(_ target: ContextRefreshTarget) -> Bool {
        if case .notes = target {
            return true
        }
        return false
    }

    func invalidate(_ target: ContextRefreshTarget) {
        guard case let .notes(noteId) = target else { return }
        cache.remove(key: CacheKeys.notesTree)
        notesStore.invalidateNote(id: noteId)
    }

    func refresh(_ target: ContextRefreshTarget) async throws {
        guard case .notes = target else { return }
        try await notesStore.loadTree(force: true)
    }
}

struct WebsitesContextProvider: ContextProvider {
    let cache: CacheClient
    let websitesStore: WebsitesStore

    var name: String { "websites" }

    func matches(_ target: ContextRefreshTarget) -> Bool {
        if case .websites = target {
            return true
        }
        return false
    }

    func invalidate(_ target: ContextRefreshTarget) {
        guard case let .websites(id) = target else { return }
        cache.invalidateList(listKey: CacheKeys.websitesList, detailKey: CacheKeys.websiteDetail, id: id)
    }

    func refresh(_ target: ContextRefreshTarget) async throws {
        guard case .websites = target else { return }
        try await websitesStore.loadList(force: true)
    }
}

struct IngestionContextProvider: ContextProvider {
    let cache: CacheClient
    let ingestionStore: IngestionStore

    var name: String { "files" }

    func matches(_ target: ContextRefreshTarget) -> Bool {
        if case .ingestion = target {
            return true
        }
        return false
    }

    func invalidate(_ target: ContextRefreshTarget) {
        guard case let .ingestion(fileId) = target else { return }
        cache.invalidateList(listKey: CacheKeys.ingestionList, detailKey: CacheKeys.ingestionMeta, id: fileId)
    }

    func refresh(_ target: ContextRefreshTarget) async throws {
        guard case let .ingestion(fileId) = target else { return }
        try await ingestionStore.loadList(force: true)
        if let fileId, ingestionStore.activeMeta?.file.id == fileId {
            try await ingestionStore.loadMeta(fileId: fileId, force: true)
        }
    }
}

struct ChatStorageCoordinator {
    let cache: CacheClient
    let chatStore: ChatStore
    let scratchpadStore: ScratchpadStore?
    let contextProviders: [any ContextProvider]

    init(
        cache: CacheClient,
        chatStore: ChatStore,
        notesStore: NotesStore? = nil,
        websitesStore: WebsitesStore? = nil,
        ingestionStore: IngestionStore? = nil,
        scratchpadStore: ScratchpadStore? = nil,
        contextProviders: [any ContextProvider]? = nil
    ) {
        self.cache = cache
        self.chatStore = chatStore
        self.scratchpadStore = scratchpadStore
        if let contextProviders {
            self.contextProviders = contextProviders
            return
        }
        var providers: [any ContextProvider] = []
        if let notesStore {
            providers.append(NotesContextProvider(cache: cache, notesStore: notesStore))
        }
        if let websitesStore {
            providers.append(WebsitesContextProvider(cache: cache, websitesStore: websitesStore))
        }
        if let ingestionStore {
            providers.append(IngestionContextProvider(cache: cache, ingestionStore: ingestionStore))
        }
        self.contextProviders = providers
    }
}

struct ChatUICoordinator {
    let themeManager: ThemeManager
    let toastCenter: ToastCenter?
    let userDefaults: UserDefaults
    let clock: () -> Date
    let onAssistantSettingsUpdated: ((AssistantSettingsRealtimeUpdate) -> Void)?

    init(
        themeManager: ThemeManager,
        toastCenter: ToastCenter? = nil,
        userDefaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init,
        onAssistantSettingsUpdated: ((AssistantSettingsRealtimeUpdate) -> Void)? = nil
    ) {
        self.themeManager = themeManager
        self.toastCenter = toastCenter
        self.userDefaults = userDefaults
        self.clock = clock
        self.onAssistantSettingsUpdated = onAssistantSettingsUpdated
    }
}

struct AssistantSettingsRealtimeUpdate {
    let assistantIdentity: AssistantIdentitySettings?
    let assistantIdentityMeta: AgentFieldMeta?
    let assistantSoul: AssistantSoulSettings?
    let assistantSoulMeta: AgentFieldMeta?
    let requiresRefresh: Bool
}

/// Represents ChatActiveTool.
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

/// Defines ToolActivityStatus.
public enum ToolActivityStatus: String {
    case running
    case success
    case error
}

/// Represents a structured prompt section summary.
public struct ChatPromptSection: Equatable {
    public let id: String
    public let title: String
    public let source: String
    public let chars: Int

    public init(id: String, title: String, source: String, chars: Int) {
        self.id = id
        self.title = title
        self.source = source
        self.chars = chars
    }
}

/// Represents prompt report metrics for a single prompt document.
public struct ChatPromptReportDocument: Equatable {
    public let totalChars: Int
    public let maxChars: Int
    public let truncated: Bool
    public let sections: [ChatPromptSection]

    public init(totalChars: Int, maxChars: Int, truncated: Bool, sections: [ChatPromptSection]) {
        self.totalChars = totalChars
        self.maxChars = maxChars
        self.truncated = truncated
        self.sections = sections
    }
}

/// Represents prompt diagnostics for both prompt documents.
public struct ChatPromptReport: Equatable {
    public let systemPrompt: ChatPromptReportDocument?
    public let firstMessagePrompt: ChatPromptReportDocument?

    public init(
        systemPrompt: ChatPromptReportDocument?,
        firstMessagePrompt: ChatPromptReportDocument?
    ) {
        self.systemPrompt = systemPrompt
        self.firstMessagePrompt = firstMessagePrompt
    }
}

/// Represents ChatPromptPreview.
public struct ChatPromptPreview: Equatable {
    public let systemPrompt: String?
    public let firstMessagePrompt: String?
    public let systemPromptSections: [ChatPromptSection]
    public let firstMessagePromptSections: [ChatPromptSection]
    public let promptReport: ChatPromptReport?

    public init(
        systemPrompt: String?,
        firstMessagePrompt: String?,
        systemPromptSections: [ChatPromptSection] = [],
        firstMessagePromptSections: [ChatPromptSection] = [],
        promptReport: ChatPromptReport? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.firstMessagePrompt = firstMessagePrompt
        self.systemPromptSections = systemPromptSections
        self.firstMessagePromptSections = firstMessagePromptSections
        self.promptReport = promptReport
    }
}

/// Represents ConversationGroup.
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
