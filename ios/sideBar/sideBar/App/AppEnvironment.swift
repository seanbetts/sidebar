import Foundation
import sideBarShared
import Combine
import os
#if os(iOS)
import UIKit
#endif

// MARK: - AppEnvironment

@MainActor
public final class AppEnvironment: ObservableObject {
    #if os(iOS) || os(macOS)
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
    public let offlineStore: OfflineStore
    public let toastCenter: ToastCenter
    public let chatViewModel: ChatViewModel
    public let notesViewModel: NotesViewModel
    public let notesEditorViewModel: NotesEditorViewModel
    public let ingestionViewModel: IngestionViewModel
    public let websitesViewModel: WebsitesViewModel
    public let tasksViewModel: TasksViewModel
    public let memoriesViewModel: MemoriesViewModel
    public let settingsViewModel: SettingsViewModel
    public let weatherViewModel: WeatherViewModel
    let realtimeClient: RealtimeClient
    public let configError: EnvironmentConfigLoadError?
    let connectivityMonitor: ConnectivityMonitor
    public let biometricMonitor: BiometricMonitor
    public let writeQueue: WriteQueue
    let draftStorage: DraftStorage
    let syncCoordinator: SyncCoordinator

    @Published public internal(set) var isAuthenticated: Bool = false
    @Published public internal(set) var isOffline: Bool = false
    @Published public internal(set) var isNetworkAvailable: Bool = true
    @Published public var commandSelection: AppSection?
    @Published public var sessionExpiryWarning: Date?
    @Published public internal(set) var signOutEvent: UUID?
    @Published public var activeSection: AppSection?
    @Published public var isTasksFocused: Bool = false {
        didSet {
            #if os(iOS)
            UIMenuSystem.main.setNeedsRebuild()
            #endif
        }
    }
    @Published public var pendingNewTaskDeepLink: Bool = false
    @Published public var pendingNewNoteDeepLink: Bool = false
    @Published public var pendingScratchpadDeepLink: Bool = false
    @Published public var shortcutActionEvent: ShortcutActionEvent?
    var cancellables = Set<AnyCancellable>()
    #if os(iOS) || os(macOS)
    var deviceToken: String?
    var lastRegisteredDeviceToken: String?
    var lastRegisteredUserId: String?
    #endif

    public init(container: ServiceContainer, configError: EnvironmentConfigLoadError? = nil) {
        let isTestMode = EnvironmentConfig.isRunningTestsOrPreviews()
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
        let dependencies = Self.buildDependencies(container: container, isTestMode: isTestMode)
        self.themeManager = dependencies.themeManager
        self.chatStore = dependencies.chatStore
        self.notesStore = dependencies.notesStore
        self.websitesStore = dependencies.websitesStore
        self.ingestionStore = dependencies.ingestionStore
        self.tasksStore = dependencies.tasksStore
        self.scratchpadStore = dependencies.scratchpadStore
        self.offlineStore = dependencies.offlineStore
        self.toastCenter = dependencies.toastCenter
        self.chatViewModel = dependencies.chatViewModel
        self.notesViewModel = dependencies.notesViewModel
        self.notesEditorViewModel = dependencies.notesEditorViewModel
        self.ingestionViewModel = dependencies.ingestionViewModel
        self.websitesViewModel = dependencies.websitesViewModel
        self.tasksViewModel = dependencies.tasksViewModel
        self.memoriesViewModel = dependencies.memoriesViewModel
        self.settingsViewModel = dependencies.settingsViewModel
        self.weatherViewModel = dependencies.weatherViewModel
        self.realtimeClient = dependencies.realtimeClient
        self.connectivityMonitor = dependencies.connectivityMonitor
        self.biometricMonitor = dependencies.biometricMonitor
        self.writeQueue = dependencies.writeQueue
        self.draftStorage = dependencies.draftStorage
        self.configError = configError
        self.syncCoordinator = SyncCoordinator(
            connectivityMonitor: dependencies.connectivityMonitor,
            writeQueue: dependencies.writeQueue,
            stores: [
                SyncableStoreAdapter { [weak self] in
                    guard let self else { return }
                    await self.chatViewModel.refreshConversations(silent: true)
                    await self.chatViewModel.refreshActiveConversation(silent: true)
                },
                SyncableStoreAdapter { [weak self] in
                    guard let self else { return }
                    await self.notesViewModel.loadTree()
                    await self.notesViewModel.refreshSelectedNoteIfNeeded()
                },
                SyncableStoreAdapter { [weak self] in
                    await self?.websitesViewModel.load(force: true)
                },
                SyncableStoreAdapter { [weak self] in
                    await self?.ingestionViewModel.load(force: true)
                },
                SyncableStoreAdapter { [weak self] in
                    guard let self else { return }
                    await self.tasksViewModel.load(selection: self.tasksViewModel.selection, force: true)
                    await self.tasksViewModel.loadCounts(force: true)
                    await self.tasksViewModel.refreshWidgetData()
                }
            ],
            isSyncAllowed: { [weak self] in
                self?.isAuthenticated ?? false
            }
        )
        self.isAuthenticated = container.authSession.accessToken != nil
        #if os(iOS) || os(macOS)
        AppEnvironment.shared = self
        #endif
        #if DEBUG
        logStep("Stores + view models", storeStart)
        #endif

        if isTestMode {
            return
        }

        #if DEBUG
        let subscriptionsStart = CFAbsoluteTimeGetCurrent()
        #endif
        configureSubscriptions()
        #if DEBUG
        logStep("Subscriptions", subscriptionsStart)
        #endif

        configureRealtimeClient()
        observeSelectionChanges()
        if isAuthenticated {
            biometricMonitor.startMonitoring()
        }
        #if DEBUG
        logStep("Realtime + monitors", initStart)
        #endif
    }

}
