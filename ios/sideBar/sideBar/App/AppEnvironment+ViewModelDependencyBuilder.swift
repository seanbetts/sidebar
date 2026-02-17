import Foundation
import sideBarShared

// swiftlint:disable nesting
extension AppEnvironment {
    struct ViewModelDependencyBuilder {
        struct Output {
            let chatViewModel: ChatViewModel
            let notesViewModel: NotesViewModel
            let notesEditorViewModel: NotesEditorViewModel
            let ingestionViewModel: IngestionViewModel
            let websitesViewModel: WebsitesViewModel
            let tasksViewModel: TasksViewModel
            let memoriesViewModel: MemoriesViewModel
            let settingsViewModel: SettingsViewModel
            let weatherViewModel: WeatherViewModel
            let currentLocationViewModel: CurrentLocationViewModel
        }

        static func build(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            stores: StoreDependencyBuilder.Output
        ) -> Output {
            let chatViewModel = ChatViewModel(
                network: ChatNetworkCoordinator(
                    chatAPI: container.chatAPI,
                    conversationsAPI: container.conversationsAPI,
                    ingestionAPI: container.ingestionAPI,
                    streamClient: container.makeChatStreamClient(handler: nil),
                    networkStatus: core.connectivityMonitor
                ),
                storage: ChatStorageCoordinator(
                    cache: container.cacheClient,
                    chatStore: stores.chatStore,
                    notesStore: stores.notesStore,
                    websitesStore: stores.websitesStore,
                    ingestionStore: stores.ingestionStore,
                    scratchpadStore: stores.scratchpadStore
                ),
                ui: ChatUICoordinator(
                    themeManager: core.themeManager,
                    toastCenter: core.toastCenter
                )
            )
            let notesViewModel = NotesViewModel(
                api: container.notesAPI,
                store: stores.notesStore,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let notesEditorViewModel = NotesEditorViewModel(
                notesViewModel: notesViewModel,
                draftStorage: core.draftStorage,
                writeQueue: stores.writeQueue,
                networkStatus: core.connectivityMonitor
            )
            let ingestionViewModel = IngestionViewModel(
                api: container.ingestionAPI,
                store: stores.ingestionStore,
                temporaryStore: TemporaryFileStore.shared,
                uploadManager: IngestionUploadManager(config: container.apiClient.config),
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let websitesViewModel = WebsitesViewModel(
                api: container.websitesAPI,
                store: stores.websitesStore,
                ingestionStore: stores.ingestionStore,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let tasksViewModel = TasksViewModel(
                api: container.tasksAPI,
                store: stores.tasksStore,
                toastCenter: core.toastCenter,
                networkStatus: core.connectivityMonitor
            )
            let memoriesViewModel = MemoriesViewModel(
                api: container.memoriesAPI,
                cache: container.cacheClient
            )
            let settingsViewModel = SettingsViewModel(
                settingsAPI: container.settingsAPI,
                skillsAPI: container.skillsAPI,
                cache: container.cacheClient
            )
            let weatherViewModel = WeatherViewModel(api: container.weatherAPI)
            let currentLocationViewModel = CurrentLocationViewModel(
                provider: CoreLocationProvider(),
                labelResolver: CLGeocoderLocationLabelResolver()
            )
            return Output(
                chatViewModel: chatViewModel,
                notesViewModel: notesViewModel,
                notesEditorViewModel: notesEditorViewModel,
                ingestionViewModel: ingestionViewModel,
                websitesViewModel: websitesViewModel,
                tasksViewModel: tasksViewModel,
                memoriesViewModel: memoriesViewModel,
                settingsViewModel: settingsViewModel,
                weatherViewModel: weatherViewModel,
                currentLocationViewModel: currentLocationViewModel
            )
        }
    }
}
// swiftlint:enable nesting
