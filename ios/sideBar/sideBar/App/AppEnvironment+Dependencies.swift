import Foundation
import sideBarShared

extension AppEnvironment {
    struct EnvironmentDependencies {
        let persistenceController: PersistenceController
        let themeManager: ThemeManager
        let chatStore: ChatStore
        let notesStore: NotesStore
        let websitesStore: WebsitesStore
        let ingestionStore: IngestionStore
        let tasksStore: TasksStore
        let scratchpadStore: ScratchpadStore
        let settingsStore: SettingsStore
        let offlineStore: OfflineStore
        let toastCenter: ToastCenter
        let chatViewModel: ChatViewModel
        let notesRuntime: NotesRuntime
        let notesViewModel: NotesViewModel
        let notesEditorViewModel: NotesEditorViewModel
        let ingestionViewModel: IngestionViewModel
        let websitesViewModel: WebsitesViewModel
        let tasksViewModel: TasksViewModel
        let memoriesViewModel: MemoriesViewModel
        let settingsViewModel: SettingsViewModel
        let weatherViewModel: WeatherViewModel
        let currentLocationViewModel: CurrentLocationViewModel
        let realtimeClient: RealtimeClient
        let connectivityMonitor: ConnectivityMonitor
        let biometricMonitor: BiometricMonitor
        let writeQueue: WriteQueue
        let onboardingSync: OnboardingSyncing
        let draftStorage: DraftStorage
        let spotlightIndexer: any SpotlightIndexing
    }

    static func buildDependencies(
        container: ServiceContainer,
        isTestMode: Bool,
        widgetDataManager: WidgetDataManager,
        workspaceStateProvider: @escaping () -> WorkspaceState? = { nil },
        workspaceOpenFailureProvider: @escaping () -> WorkspaceOpenFailure? = { nil }
    ) -> EnvironmentDependencies {
        let core = CoreDependencyBuilder.build(container: container, isTestMode: isTestMode)
        let stores = StoreDependencyBuilder.build(
            container: container,
            core: core,
            widgetDataManager: widgetDataManager
        )
        let onboardingSync = OnboardingSyncCoordinator(
            api: container.onboardingAPI,
            localStateStore: OnboardingLocalStateStore(cache: container.cacheClient),
            writeQueue: stores.writeQueue
        )
        let viewModels = ViewModelDependencyBuilder.build(
            container: container,
            core: core,
            stores: stores,
            onboardingSync: onboardingSync,
            isTestMode: isTestMode,
            widgetDataManager: widgetDataManager,
            workspaceStateProvider: workspaceStateProvider,
            workspaceOpenFailureProvider: workspaceOpenFailureProvider
        )

        return EnvironmentDependencies(
            persistenceController: core.persistenceController,
            themeManager: core.themeManager,
            chatStore: stores.chatStore,
            notesStore: stores.notesStore,
            websitesStore: stores.websitesStore,
            ingestionStore: stores.ingestionStore,
            tasksStore: stores.tasksStore,
            scratchpadStore: stores.scratchpadStore,
            settingsStore: stores.settingsStore,
            offlineStore: core.offlineStore,
            toastCenter: core.toastCenter,
            chatViewModel: viewModels.chatViewModel,
            notesRuntime: viewModels.notesRuntime,
            notesViewModel: viewModels.notesViewModel,
            notesEditorViewModel: viewModels.notesEditorViewModel,
            ingestionViewModel: viewModels.ingestionViewModel,
            websitesViewModel: viewModels.websitesViewModel,
            tasksViewModel: viewModels.tasksViewModel,
            memoriesViewModel: viewModels.memoriesViewModel,
            settingsViewModel: viewModels.settingsViewModel,
            weatherViewModel: viewModels.weatherViewModel,
            currentLocationViewModel: viewModels.currentLocationViewModel,
            realtimeClient: core.realtimeClient,
            connectivityMonitor: core.connectivityMonitor,
            biometricMonitor: core.biometricMonitor,
            writeQueue: stores.writeQueue,
            onboardingSync: onboardingSync,
            draftStorage: core.draftStorage,
            spotlightIndexer: core.spotlightIndexer
        )
    }
}
