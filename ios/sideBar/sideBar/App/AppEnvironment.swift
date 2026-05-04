import Foundation
import sideBarShared
import Combine
import os
#if os(iOS)
import UIKit
#endif
// MARK: - AppEnvironment
public struct AppEnvironmentStorage {
    public static let shared = AppEnvironmentStorage(
        userDefaults: .standard,
        widgetDataManager: .shared,
        extensionEventStore: .shared,
        pendingShareStore: .shared,
        taskBadgeUpdater: LiveTaskBadgeUpdater()
    )
    public let userDefaults: UserDefaults
    public let widgetDataManager: WidgetDataManager
    public let extensionEventStore: ExtensionEventStore
    public let pendingShareStore: PendingShareStore
    public let taskBadgeUpdater: any TaskBadgeUpdating

    public init(
        userDefaults: UserDefaults = .standard,
        widgetDataManager: WidgetDataManager? = nil,
        extensionEventStore: ExtensionEventStore? = nil,
        pendingShareStore: PendingShareStore? = nil,
        taskBadgeUpdater: (any TaskBadgeUpdating)? = nil
    ) {
        self.userDefaults = userDefaults
        self.widgetDataManager = widgetDataManager ?? WidgetDataManager(userDefaults: userDefaults)
        self.extensionEventStore = extensionEventStore ?? ExtensionEventStore(userDefaults: userDefaults)
        self.pendingShareStore = pendingShareStore ?? PendingShareStore(userDefaults: userDefaults)
        self.taskBadgeUpdater = taskBadgeUpdater ?? LiveTaskBadgeUpdater()
    }
}
@MainActor
/// Coordinates app-wide stores, view models, and lifecycle wiring for the signed-in experience.
public final class AppEnvironment: ObservableObject {
    #if os(iOS) || os(macOS)
    /// Shared process-wide environment reference for app and extension handoff paths.
    public static weak var shared: AppEnvironment?
    #endif
    /// Shared service container used to construct API clients and core dependencies.
    public let container: ServiceContainer
    /// Storage namespace used for defaults-backed app, widget, and extension state.
    public let storage: AppEnvironmentStorage
    /// Active theme manager used by settings and rendering flows.
    public var themeManager: ThemeManager
    /// Store backing chat conversations and message state.
    public let chatStore: ChatStore
    /// Store backing notes tree and note content state.
    public let notesStore: NotesStore
    /// Store backing website list and detail state.
    public let websitesStore: WebsitesStore
    /// Store backing ingestion list and metadata state.
    public let ingestionStore: IngestionStore
    /// Store backing task list and count state.
    public let tasksStore: TasksStore
    /// Store backing scratchpad content state.
    public let scratchpadStore: ScratchpadStore
    public let settingsStore: SettingsStore
    public let offlineStore: OfflineStore
    public let toastCenter: ToastCenter
    /// View model coordinating chat UI actions and streaming state.
    public let chatViewModel: ChatViewModel
    /// Runtime boundary for notes list/editor state and notes context routing.
    public let notesRuntime: NotesRuntime
    /// View model coordinating notes list and selection state.
    public let notesViewModel: NotesViewModel
    /// View model coordinating note editor behavior.
    public let notesEditorViewModel: NotesEditorViewModel
    /// View model coordinating ingestion list, uploads, and detail actions.
    public let ingestionViewModel: IngestionViewModel
    /// View model coordinating website list and detail actions.
    public let websitesViewModel: WebsitesViewModel
    /// View model coordinating task list, filters, and operations.
    public let tasksViewModel: TasksViewModel
    /// View model coordinating memories presentation and refresh behavior.
    public let memoriesViewModel: MemoriesViewModel
    /// View model coordinating app settings state.
    public let settingsViewModel: SettingsViewModel
    /// View model coordinating weather presentation state.
    public let weatherViewModel: WeatherViewModel
    /// View model coordinating live device location state.
    public let currentLocationViewModel: CurrentLocationViewModel
    /// Navigation coordinator for cross-feature section and deep-link routing state.
    public let navigation: NavigationCoordinator
    /// Shadow workspace state store used for migration to a unified workspace engine.
    public let workspaceStore: WorkspaceStore
    let workspaceOpenFailureStore: WorkspaceOpenFailureStore
    let persistenceController: PersistenceController
    let realtimeClient: RealtimeClient
    /// Environment configuration loading error captured at startup, when present.
    public let configError: EnvironmentConfigLoadError?
    let connectivityMonitor: ConnectivityMonitor
    /// Biometric monitor used to lock and unlock sensitive content.
    public let biometricMonitor: BiometricMonitor
    /// Queue that persists and replays offline writes.
    public let writeQueue: WriteQueue
    let refreshCoordinator: RefreshCoordinatorType
    let draftStorage: DraftStorage
    let spotlightIndexer: any SpotlightIndexing
    let syncCoordinator: SyncCoordinator

    /// Current authentication state observed by top-level app routing.
    @Published public internal(set) var authState: AuthState = .signedOut
    /// Indicates whether offline mode is active due to write/read connectivity constraints.
    @Published public internal(set) var isOffline: Bool = false
    /// Indicates whether any network path is currently available.
    @Published public internal(set) var isNetworkAvailable: Bool = true
    /// Indicates whether backend services are currently reachable.
    @Published public internal(set) var isServerReachable: Bool = true
    /// Sign-out event token used to trigger downstream reset observers.
    @Published public internal(set) var signOutEvent: UUID?
    /// Tracks whether macOS settings should be presented as an in-window modal.
    @Published public internal(set) var isMacSettingsPresented: Bool = false
    /// Tracks whether the current authenticated session has cleared local biometric protection.
    @Published public internal(set) var isBiometricUnlocked: Bool = false
    /// Tracks device-local push registration and presence state for diagnostics.
    @Published public internal(set) var pushDiagnosticsState = PushLifecycleDiagnosticsState()
    /// Tracks whether a signed-out recovery flow is collecting a new password.
    @Published public internal(set) var passwordResetState: PasswordResetState?
    /// Tracks the login notice shown after a successful password reset.
    @Published public internal(set) var passwordResetSuccessMessage: String?
    /// Optional supporting copy for the signed-out password notice.
    @Published public internal(set) var passwordResetSuccessDetail: String?
    var previousFocusedSectionBeforeMacSettings: AppSection?
    var isConsumingPendingShares: Bool = false
    var queuedProtectedDeepLinks: [URL] = []
    var biometricBackgroundedAt: Date?
    var cancellables = Set<AnyCancellable>()
    var hasPendingForwardedObjectWillChange = false
    var queuedWebsiteReconcileTask: Task<Void, Never>?
    var queuedWebsiteReconcileTrigger = "direct"
    var queuedWebsiteReconcileSavedItemCount: Int?
    var websiteSaveHandoffObserver: AnyObject?
    var widgetTaskCompletionObserver: AnyObject?
    lazy var websiteQueueCoordinator: WebsiteQueueCoordinator = makeWebsiteQueueCoordinator()
    #if os(iOS) || os(macOS)
    var deviceToken: String?
    var lastRegisteredDeviceInstallationId: String?
    var lastRegisteredDeviceToken: String?
    var lastRegisteredUserId: String?
    var inFlightDeviceInstallationId: String?
    var inFlightDeviceToken: String?
    var inFlightDeviceTokenUserId: String?
    var devicePresenceReporter: DevicePresenceReporter?
    var hasConfiguredDevicePresenceReporting = false
    var remoteNotificationRegistrar: (@MainActor @Sendable () -> Void)?
    #endif

    // swiftlint:disable function_body_length
    /// Creates the root app environment and wires all stores, view models, and observers.
    public convenience init(
        container: ServiceContainer,
        storage: AppEnvironmentStorage? = nil,
        configError: EnvironmentConfigLoadError? = nil,
        initialPasswordResetState: PasswordResetState? = nil
    ) {
        self.init(
            container: container,
            storage: storage,
            configError: configError,
            initialPasswordResetState: initialPasswordResetState,
            refreshCoordinator: nil
        )
    }

    init(
        container: ServiceContainer,
        storage: AppEnvironmentStorage? = nil,
        configError: EnvironmentConfigLoadError? = nil,
        initialPasswordResetState: PasswordResetState? = nil,
        refreshCoordinator: RefreshCoordinatorType? = nil
    ) {
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
        let resolvedStorage = storage ?? .shared
        self.container = container
        self.storage = resolvedStorage
        let workspaceStore = WorkspaceStore()
        let workspaceOpenFailureStore = WorkspaceOpenFailureStore()
        let dependencies = Self.buildDependencies(
            container: container,
            isTestMode: isTestMode,
            widgetDataManager: resolvedStorage.widgetDataManager,
            workspaceStateProvider: { workspaceStore.state },
            workspaceOpenFailureProvider: { workspaceOpenFailureStore.latest }
        )
        self.persistenceController = dependencies.persistenceController
        self.themeManager = dependencies.themeManager
        self.chatStore = dependencies.chatStore
        self.notesStore = dependencies.notesStore
        self.websitesStore = dependencies.websitesStore
        self.ingestionStore = dependencies.ingestionStore
        self.tasksStore = dependencies.tasksStore
        self.scratchpadStore = dependencies.scratchpadStore
        self.settingsStore = dependencies.settingsStore
        self.offlineStore = dependencies.offlineStore
        self.toastCenter = dependencies.toastCenter
        self.chatViewModel = dependencies.chatViewModel
        self.notesRuntime = dependencies.notesRuntime
        self.notesViewModel = dependencies.notesViewModel
        self.notesEditorViewModel = dependencies.notesEditorViewModel
        self.ingestionViewModel = dependencies.ingestionViewModel
        self.websitesViewModel = dependencies.websitesViewModel
        self.tasksViewModel = dependencies.tasksViewModel
        self.navigation = NavigationCoordinator()
        self.workspaceStore = workspaceStore
        self.workspaceOpenFailureStore = workspaceOpenFailureStore
        self.memoriesViewModel = dependencies.memoriesViewModel
        self.settingsViewModel = dependencies.settingsViewModel
        self.weatherViewModel = dependencies.weatherViewModel
        self.currentLocationViewModel = dependencies.currentLocationViewModel
        self.realtimeClient = dependencies.realtimeClient
        self.connectivityMonitor = dependencies.connectivityMonitor
        self.biometricMonitor = dependencies.biometricMonitor
        self.writeQueue = dependencies.writeQueue
        let resolvedRefreshCoordinator = refreshCoordinator ?? Self.makeRefreshCoordinator(
            chatViewModel: dependencies.chatViewModel,
            notesViewModel: dependencies.notesViewModel,
            tasksViewModel: dependencies.tasksViewModel,
            websitesViewModel: dependencies.websitesViewModel,
            ingestionViewModel: dependencies.ingestionViewModel
        )
        self.refreshCoordinator = resolvedRefreshCoordinator
        self.draftStorage = dependencies.draftStorage
        self.spotlightIndexer = dependencies.spotlightIndexer
        self.configError = configError
        self.passwordResetState = initialPasswordResetState
        let authSession = container.authSession
        let refreshContextProvider = {
            let canAttemptProtectedServerRead = authSession.authState == .active
                && authSession.authorizationToken != nil
            return Self.makeRefreshContext(
                workspaceState: workspaceStore.state,
                refreshCoordinator: resolvedRefreshCoordinator,
                canAttemptServerRead: dependencies.connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead
                    && canAttemptProtectedServerRead
            )
        }
        self.syncCoordinator = SyncCoordinator(
            connectivityMonitor: dependencies.connectivityMonitor,
            writeQueue: dependencies.writeQueue,
            onReconnectRefresh: { [weak resolvedRefreshCoordinator] in
                guard let resolvedRefreshCoordinator else { return }
                await resolvedRefreshCoordinator.refresh(
                    trigger: .reconnect,
                    context: refreshContextProvider()
                )
            },
            isSyncAllowed: {
                authSession.authState == .active
            }
        )
        self.chatViewModel.workspaceActionDispatcher = { [weak self] action in
            self?.dispatchChatWorkspaceAction(action)
        }
        self.authState = container.authSession.authState
        self.isBiometricUnlocked = (authState == .active || authState == .staleRecoverable) && !isBiometricUnlockEnabled
        #if os(iOS) || os(macOS)
        AppEnvironment.shared = self
        hydratePushDiagnosticsStateFromStorage()
        #endif
        #if os(iOS)
        AppSceneDelegate.flushQueuedDeepLinks(using: self)
        #elseif os(macOS)
        MacAppDelegate.flushQueuedDeepLinks(using: self)
        MacAppDelegate.flushQueuedWebsiteQueueBootstrap(using: self)
        #endif
        #if DEBUG
        logStep("Stores + view models", storeStart)
        #endif

        configureWebsiteSaveHandoffObserver()

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

        configureWidgetTaskCompletionObserver()
        configureRealtimeClient()
        observeSelectionChanges()
        if isAuthenticated {
            biometricMonitor.startMonitoring()
        }
        #if DEBUG
        logStep("Realtime + monitors", initStart)
        #endif
    }
    // swiftlint:enable function_body_length

    deinit {
        if let websiteSaveHandoffObserver {
            WebsiteSaveHandoffNotifier.removeObserver(websiteSaveHandoffObserver)
        }
        if let widgetTaskCompletionObserver {
            WidgetTaskCompletionHandoffNotifier.removeObserver(widgetTaskCompletionObserver)
        }
    }

    /// Indicates whether the current auth state represents a signed-in user.
    public var isAuthenticated: Bool {
        protectedContentReadiness.isAuthenticated
    }

    /// Indicates whether biometric lock is enabled for the current app profile.
    public var isBiometricUnlockEnabled: Bool {
        storage.userDefaults.bool(forKey: AppStorageKeys.biometricUnlockEnabled)
    }

    /// Indicates whether protected signed-in content may be surfaced immediately.
    public var isProtectedContentReady: Bool {
        protectedContentReadiness.canShowProtectedContent
    }

    /// Indicates whether the local biometric gate is currently blocking authenticated content.
    public var isBiometricUnlockRequired: Bool {
        protectedContentReadiness.requiresBiometricUnlock
    }

    /// Current protected-content readiness policy.
    public var protectedContentReadiness: ProtectedContentReadiness {
        ProtectedContentReadiness(
            authState: authState,
            hasAuthorizationToken: container.authSession.authorizationToken != nil,
            isBiometricUnlockEnabled: isBiometricUnlockEnabled,
            isBiometricUnlocked: isBiometricUnlocked
        )
    }

    /// Selected command palette section routed through the navigation coordinator.
    public var commandSelection: AppSection? {
        get { navigation.commandSelection }
        set { navigation.commandSelection = newValue }
    }

    /// Active sidebar section routed through the navigation coordinator.
    public var activeSection: AppSection? {
        get { navigation.activeSection }
        set { navigation.activeSection = newValue }
    }

    /// Most recently interacted section, used for section-scoped keyboard shortcut routing.
    public var focusedSection: AppSection? {
        get { navigation.focusedSection }
        set { navigation.focusedSection = newValue }
    }

    /// Most recently interacted workspace pane, used for pane-scoped shortcut routing.
    public var focusedWorkspacePane: WorkspacePane? {
        get { navigation.focusedWorkspacePane }
        set { navigation.focusedWorkspacePane = newValue }
    }

    /// Presents the dedicated macOS settings modal without changing workspace selection.
    public func presentMacSettings() {
        guard authState != .signedOut else { return }
        if !isMacSettingsPresented {
            previousFocusedSectionBeforeMacSettings = focusedSection ?? activeSection
        }
        isMacSettingsPresented = true
        focusedSection = .settings
    }

    /// Dismisses the dedicated macOS settings modal.
    public func dismissMacSettings() {
        isMacSettingsPresented = false
        if focusedSection == .settings {
            focusedSection = previousFocusedSectionBeforeMacSettings ?? activeSection
        }
        previousFocusedSectionBeforeMacSettings = nil
    }

    /// Indicates whether task-specific keyboard shortcuts should be active.
    public var isTasksFocused: Bool {
        get { navigation.isTasksFocused }
        set {
            navigation.isTasksFocused = newValue
            #if os(iOS)
            UIMenuSystem.main.setNeedsRebuild()
            #endif
        }
    }

    /// Pending deep-link flag indicating a new-task flow should run once routing is ready.
    public var pendingNewTaskDeepLink: Bool {
        get { navigation.pendingNewTaskDeepLink }
        set { navigation.pendingNewTaskDeepLink = newValue }
    }

    /// Pending deep-link flag indicating a new-note flow should run once routing is ready.
    public var pendingNewNoteDeepLink: Bool {
        get { navigation.pendingNewNoteDeepLink }
        set { navigation.pendingNewNoteDeepLink = newValue }
    }

    /// Pending deep-link flag indicating scratchpad should open once routing is ready.
    public var pendingScratchpadDeepLink: Bool {
        get { navigation.pendingScratchpadDeepLink }
        set { navigation.pendingScratchpadDeepLink = newValue }
    }

    public var pendingMorningDigestDeepLink: Bool {
        get { navigation.pendingMorningDigestDeepLink }
        set { navigation.pendingMorningDigestDeepLink = newValue }
    }

    /// Last keyboard shortcut action routed through global shortcut handling.
    public var shortcutActionEvent: ShortcutActionEvent? {
        get { navigation.shortcutActionEvent }
        set { navigation.shortcutActionEvent = newValue }
    }

    /// Active notes detail route identifier used for compact phone navigation.
    public var notesPhoneDetailRouteId: String? {
        get { navigation.notesPhoneDetailRouteId }
        set { navigation.notesPhoneDetailRouteId = newValue }
    }

    /// Active tasks detail route identifier used for compact phone navigation.
    public var tasksPhoneDetailRouteId: String? {
        get { navigation.tasksPhoneDetailRouteId }
        set { navigation.tasksPhoneDetailRouteId = newValue }
    }

    private func makeWebsiteQueueCoordinator() -> WebsiteQueueCoordinator {
        let isTestMode = EnvironmentConfig.isRunningTestsOrPreviews()
        return WebsiteQueueCoordinator(
            hasPendingWork: { [weak self] in
                self?.hasPendingWebsiteCoordinatorWork ?? false
            },
            hasBackgroundContinuationWork: { [weak self] in
                self?.hasPendingWebsiteBackgroundWork ?? false
            },
            canReplayNow: { [weak self] in
                guard let self else { return false }
                return self.authState == .active
                    && self.isProtectedContentReady
                    && !self.connectivityMonitor.isOffline
            },
            replay: { [weak self] in
                await self?.refreshWebsiteQueueHandoff(awaitPendingShareReplay: false)
            },
            scheduleContinuation: { [weak self] in
                guard !isTestMode else { return }
                guard let self, self.hasPendingWebsiteBackgroundWork else { return }
                #if os(iOS)
                AppLaunchDelegate.scheduleWebsiteSaveContinuation()
                #endif
            },
            retryDelay: {
                #if os(macOS)
                .seconds(30)
                #else
                nil
                #endif
            }()
        )
    }

    nonisolated static func shouldBootstrapMacWindowlessWebsiteQueueHost(
        authState: AuthState
    ) -> Bool {
        authState == .active
    }

    func bootstrapMacWindowlessWebsiteQueueHost() {
        #if os(macOS)
        guard Self.shouldBootstrapMacWindowlessWebsiteQueueHost(authState: authState) else { return }
        websiteQueueCoordinator.queueDidChange(trigger: .appDidBecomeActive)
        #endif
    }
}
