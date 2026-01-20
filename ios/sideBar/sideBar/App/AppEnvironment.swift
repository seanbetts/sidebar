import Foundation
import Combine
import os
#if os(iOS)
import UIKit
#endif

@MainActor
public final class AppEnvironment: ObservableObject {
    #if os(iOS)
    public static weak var shared: AppEnvironment?
    #endif
    public let container: ServiceContainer
    public var themeManager: ThemeManager
    public let chatStore: ChatStore
    public let notesStore: NotesStore
    public let websitesStore: WebsitesStore
    public let ingestionStore: IngestionStore
    public let tasksStore: TasksStore
    public let scratchpadStore: ScratchpadStore
    public let toastCenter: ToastCenter
    public let chatViewModel: ChatViewModel
    public let notesViewModel: NotesViewModel
    public let notesEditorViewModel: NotesEditorViewModel
    public let ingestionViewModel: IngestionViewModel
    public let websitesViewModel: WebsitesViewModel
    public let memoriesViewModel: MemoriesViewModel
    public let settingsViewModel: SettingsViewModel
    public let weatherViewModel: WeatherViewModel
    private let realtimeClient: RealtimeClient
    public let configError: EnvironmentConfigLoadError?
    private let networkMonitor: NetworkMonitor
    public let biometricMonitor: BiometricMonitor

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var isOffline: Bool = false
    @Published public var commandSelection: AppSection? = nil
    @Published public var sessionExpiryWarning: Date?
    @Published public private(set) var signOutEvent: UUID?
    @Published public var activeSection: AppSection? = nil
    @Published public var isNotesEditing: Bool = false {
        didSet {
            #if os(iOS)
            UIMenuSystem.main.setNeedsRebuild()
            #endif
        }
    }
    @Published public var shortcutActionEvent: ShortcutActionEvent?
    private var cancellables = Set<AnyCancellable>()

    public init(container: ServiceContainer, configError: EnvironmentConfigLoadError? = nil) {
        #if DEBUG
        let logger = Logger(subsystem: "sideBar", category: "Startup")
        let initStart = CFAbsoluteTimeGetCurrent()
        func logStep(_ name: String, _ start: CFAbsoluteTime) {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("\(name, privacy: .public) took \(elapsedMs, privacy: .public)ms")
        }
        #endif

        #if DEBUG
        let storeStart = CFAbsoluteTimeGetCurrent()
        #endif
        self.container = container
        self.themeManager = ThemeManager()
        self.chatStore = ChatStore(
            conversationsAPI: container.conversationsAPI,
            cache: container.cacheClient
        )
        self.notesStore = NotesStore(api: container.notesAPI, cache: container.cacheClient)
        self.websitesStore = WebsitesStore(api: container.websitesAPI, cache: container.cacheClient)
        self.ingestionStore = IngestionStore(api: container.ingestionAPI, cache: container.cacheClient)
        self.tasksStore = TasksStore()
        self.scratchpadStore = ScratchpadStore()
        self.toastCenter = ToastCenter()
        self.chatViewModel = ChatViewModel(
            chatAPI: container.chatAPI,
            conversationsAPI: container.conversationsAPI,
            ingestionAPI: container.ingestionAPI,
            cache: container.cacheClient,
            notesStore: notesStore,
            websitesStore: websitesStore,
            ingestionStore: ingestionStore,
            themeManager: themeManager,
            streamClient: container.makeChatStreamClient(handler: nil),
            chatStore: chatStore,
            toastCenter: toastCenter,
            scratchpadStore: scratchpadStore
        )
        let temporaryStore = TemporaryFileStore.shared
        self.notesViewModel = NotesViewModel(
            api: container.notesAPI,
            store: notesStore,
            toastCenter: toastCenter
        )
        self.notesEditorViewModel = NotesEditorViewModel(
            api: container.notesAPI,
            notesStore: notesStore,
            notesViewModel: notesViewModel,
            toastCenter: toastCenter
        )
        self.ingestionViewModel = IngestionViewModel(
            api: container.ingestionAPI,
            store: ingestionStore,
            temporaryStore: temporaryStore,
            uploadManager: IngestionUploadManager(config: container.apiClient.config)
        )
        self.websitesViewModel = WebsitesViewModel(api: container.websitesAPI, store: websitesStore)
        self.memoriesViewModel = MemoriesViewModel(api: container.memoriesAPI, cache: container.cacheClient)
        self.settingsViewModel = SettingsViewModel(
            settingsAPI: container.settingsAPI,
            skillsAPI: container.skillsAPI,
            cache: container.cacheClient
        )
        self.weatherViewModel = WeatherViewModel(api: container.weatherAPI)
        self.realtimeClient = container.makeRealtimeClient(handler: nil)
        self.networkMonitor = NetworkMonitor()
        self.biometricMonitor = BiometricMonitor()
        self.configError = configError
        self.isAuthenticated = container.authSession.accessToken != nil
        #if os(iOS)
        AppEnvironment.shared = self
        #endif
        #if DEBUG
        logStep("Stores + view models", storeStart)
        #endif

        #if DEBUG
        let subscriptionsStart = CFAbsoluteTimeGetCurrent()
        #endif
        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            authAdapter.$accessToken
                .sink { [weak self] _token in
                    self?.refreshAuthState()
                }
                .store(in: &cancellables)

            authAdapter.$authError
                .compactMap { $0 }
                .sink { [weak self, weak authAdapter] event in
                    self?.toastCenter.show(message: event.message)
                    authAdapter?.clearAuthError()
                }
                .store(in: &cancellables)

            authAdapter.$sessionExpiryWarning
                .sink { [weak self] warning in
                    DispatchQueue.main.async {
                        self?.sessionExpiryWarning = warning
                    }
                }
                .store(in: &cancellables)
        }

        settingsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        chatViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesEditorViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        websitesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ingestionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        weatherViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        networkMonitor.$isOffline
            .removeDuplicates()
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
                if isOffline == false {
                    self?.refreshOnReconnect()
                }
            }
            .store(in: &cancellables)
        #if DEBUG
        logStep("Subscriptions", subscriptionsStart)
        #endif

        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
        observeSelectionChanges()
        if isAuthenticated {
            biometricMonitor.startMonitoring()
        }
        #if DEBUG
        logStep("Realtime + monitors", initStart)
        #endif
    }

    #if os(iOS)
    public var activeShortcutContexts: Set<ShortcutContext> {
        var contexts: Set<ShortcutContext> = [.universal]
        if let activeSection {
            contexts.insert(ShortcutContext.from(section: activeSection))
        }
        if isNotesEditing {
            contexts.insert(.notesEditing)
        }
        return contexts
    }

    public func emitShortcutAction(_ action: ShortcutAction) {
        shortcutActionEvent = ShortcutActionEvent(action: action, section: activeSection)
    }
    #endif

    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
            chatStore.reset()
            notesStore.reset()
            websitesStore.reset()
            ingestionStore.reset()
            tasksStore.reset()
            notesViewModel.clearSelection()
            websitesViewModel.clearSelection()
            ingestionViewModel.clearSelection()
            sessionExpiryWarning = nil
        }
        if isAuthenticated {
            biometricMonitor.startMonitoring()
        } else {
            biometricMonitor.stopMonitoring()
        }
        realtimeClientStopStart()
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        sessionExpiryWarning = nil
        await container.authSession.signOut()
        refreshAuthState()
    }

    public func consumeExtensionEvents() async {
        let events = ExtensionEventStore.shared.consumeEvents()
        guard !events.isEmpty else { return }
        guard isAuthenticated else { return }
        let websiteEvents = events.filter { $0.type == .websiteSaved }
        guard !websiteEvents.isEmpty else { return }
        for event in websiteEvents {
            if let url = event.websiteUrl {
                websitesViewModel.showPendingFromExtension(url: url)
            }
        }
    }

    private func realtimeClientStopStart() {
        guard let userId = container.authSession.userId, isAuthenticated else {
            realtimeClient.stop()
            return
        }
        let token = container.authSession.accessToken
        Task {
            await realtimeClient.start(userId: userId, accessToken: token)
        }
    }

    private func observeSelectionChanges() {
        notesViewModel.$selectedNoteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonNoteSelections()
            }
            .store(in: &cancellables)

        websitesViewModel.$selectedWebsiteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonWebsiteSelections()
            }
            .store(in: &cancellables)

        ingestionViewModel.$selectedFileId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonFileSelections()
            }
            .store(in: &cancellables)
    }

    private func clearNonNoteSelections() {
        websitesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonWebsiteSelections() {
        notesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonFileSelections() {
        notesViewModel.clearSelection()
        websitesViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func refreshOnReconnect() {
        guard isAuthenticated else {
            return
        }
        Task {
            await chatViewModel.refreshConversations(silent: true)
            await chatViewModel.refreshActiveConversation(silent: true)
            await notesViewModel.loadTree()
            await websitesViewModel.load()
            await ingestionViewModel.load()
        }
    }
}

extension AppEnvironment: RealtimeEventHandler {
    public func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) {
        let title = payload.record?.title ?? payload.oldRecord?.title
        if title == ScratchpadConstants.title {
            scratchpadStore.bump()
            return
        }
        Task {
            await notesViewModel.applyRealtimeEvent(payload)
        }
    }

    public func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        Task {
            await websitesViewModel.applyRealtimeEvent(payload)
        }
    }

    public func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyIngestedFileEvent(payload)
        }
    }

    public func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyFileJobEvent(payload)
        }
    }
}
