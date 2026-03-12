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
        let draftStorage: DraftStorage
        let spotlightIndexer: SpotlightIndexer
    }

    static func buildDependencies(
        container: ServiceContainer,
        isTestMode: Bool,
        widgetDataManager: WidgetDataManager,
        workspaceStateProvider: @escaping () -> WorkspaceState? = { nil }
    ) -> EnvironmentDependencies {
        let core = CoreDependencyBuilder.build(container: container, isTestMode: isTestMode)
        let stores = StoreDependencyBuilder.build(
            container: container,
            core: core,
            widgetDataManager: widgetDataManager
        )
        let viewModels = ViewModelDependencyBuilder.build(
            container: container,
            core: core,
            stores: stores,
            widgetDataManager: widgetDataManager,
            workspaceStateProvider: workspaceStateProvider
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
            draftStorage: core.draftStorage,
            spotlightIndexer: core.spotlightIndexer
        )
    }
}
