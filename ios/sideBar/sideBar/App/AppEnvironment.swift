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
    public let navigation: NavigationCoordinator
    let realtimeClient: RealtimeClient
    public let configError: EnvironmentConfigLoadError?
    let connectivityMonitor: ConnectivityMonitor
    public let biometricMonitor: BiometricMonitor
    public let writeQueue: WriteQueue
    let draftStorage: DraftStorage
    let spotlightIndexer: SpotlightIndexer
    let syncCoordinator: SyncCoordinator

    @Published public internal(set) var authState: AuthState = .signedOut
    @Published public internal(set) var isOffline: Bool = false
    @Published public internal(set) var isNetworkAvailable: Bool = true
    @Published public internal(set) var isServerReachable: Bool = true
    @Published public internal(set) var signOutEvent: UUID?
    var cancellables = Set<AnyCancellable>()
    #if os(iOS) || os(macOS)
    var deviceToken: String?
    var lastRegisteredDeviceToken: String?
    var lastRegisteredUserId: String?
    #endif

    // swiftlint:disable:next function_body_length
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
        self.navigation = NavigationCoordinator()
        self.memoriesViewModel = dependencies.memoriesViewModel
        self.settingsViewModel = dependencies.settingsViewModel
        self.weatherViewModel = dependencies.weatherViewModel
        self.realtimeClient = dependencies.realtimeClient
        self.connectivityMonitor = dependencies.connectivityMonitor
        self.biometricMonitor = dependencies.biometricMonitor
        self.writeQueue = dependencies.writeQueue
        self.draftStorage = dependencies.draftStorage
        self.spotlightIndexer = dependencies.spotlightIndexer
        self.configError = configError
        let chatViewModel = dependencies.chatViewModel
        let notesViewModel = dependencies.notesViewModel
        let websitesViewModel = dependencies.websitesViewModel
        let ingestionViewModel = dependencies.ingestionViewModel
        let tasksViewModel = dependencies.tasksViewModel
        let authSession = container.authSession
        self.syncCoordinator = SyncCoordinator(
            connectivityMonitor: dependencies.connectivityMonitor,
            writeQueue: dependencies.writeQueue,
            stores: [
                SyncableStoreAdapter { [weak chatViewModel] in
                    guard let chatViewModel else { return }
                    await chatViewModel.refreshConversations(silent: true)
                    await chatViewModel.refreshActiveConversation(silent: true)
                },
                SyncableStoreAdapter { [weak notesViewModel] in
                    guard let notesViewModel else { return }
                    await notesViewModel.loadTree()
                    await notesViewModel.refreshSelectedNoteIfNeeded()
                },
                SyncableStoreAdapter { [weak websitesViewModel] in
                    await websitesViewModel?.load(force: true)
                },
                SyncableStoreAdapter { [weak ingestionViewModel] in
                    await ingestionViewModel?.load(force: true)
                },
                SyncableStoreAdapter { [weak tasksViewModel] in
                    guard let tasksViewModel else { return }
                    await tasksViewModel.load(selection: tasksViewModel.selection, force: true)
                    await tasksViewModel.loadCounts(force: true)
                    await tasksViewModel.refreshWidgetData()
                }
            ],
            isSyncAllowed: {
                authSession.authState == .active
            }
        )
        self.authState = container.authSession.authState
        #if os(iOS) || os(macOS)
        AppEnvironment.shared = self
        #endif
        #if os(iOS)
        AppSceneDelegate.flushQueuedDeepLinks(using: self)
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

    public var isAuthenticated: Bool {
        authState != .signedOut
    }

    public var commandSelection: AppSection? {
        get { navigation.commandSelection }
        set { navigation.commandSelection = newValue }
    }

    public var activeSection: AppSection? {
        get { navigation.activeSection }
        set { navigation.activeSection = newValue }
    }

    public var isTasksFocused: Bool {
        get { navigation.isTasksFocused }
        set {
            navigation.isTasksFocused = newValue
            #if os(iOS)
            UIMenuSystem.main.setNeedsRebuild()
            #endif
        }
    }

    public var pendingNewTaskDeepLink: Bool {
        get { navigation.pendingNewTaskDeepLink }
        set { navigation.pendingNewTaskDeepLink = newValue }
    }

    public var pendingNewNoteDeepLink: Bool {
        get { navigation.pendingNewNoteDeepLink }
        set { navigation.pendingNewNoteDeepLink = newValue }
    }

    public var pendingScratchpadDeepLink: Bool {
        get { navigation.pendingScratchpadDeepLink }
        set { navigation.pendingScratchpadDeepLink = newValue }
    }

    public var shortcutActionEvent: ShortcutActionEvent? {
        get { navigation.shortcutActionEvent }
        set { navigation.shortcutActionEvent = newValue }
    }

    public var tasksPhoneDetailRouteId: String? {
        get { navigation.tasksPhoneDetailRouteId }
        set { navigation.tasksPhoneDetailRouteId = newValue }
    }
}
