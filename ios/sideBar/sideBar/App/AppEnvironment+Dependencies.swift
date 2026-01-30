import Foundation
import sideBarShared

extension AppEnvironment {
    struct EnvironmentDependencies {
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
        let notesViewModel: NotesViewModel
        let notesEditorViewModel: NotesEditorViewModel
        let ingestionViewModel: IngestionViewModel
        let websitesViewModel: WebsitesViewModel
        let tasksViewModel: TasksViewModel
        let memoriesViewModel: MemoriesViewModel
        let settingsViewModel: SettingsViewModel
        let weatherViewModel: WeatherViewModel
        let realtimeClient: RealtimeClient
        let connectivityMonitor: ConnectivityMonitor
        let biometricMonitor: BiometricMonitor
        let writeQueue: WriteQueue
        let draftStorage: DraftStorage
    }

    static func buildDependencies(
        container: ServiceContainer,
        isTestMode: Bool
    ) -> EnvironmentDependencies {
        let themeManager = ThemeManager()
        let toastCenter = ToastCenter()
        let realtimeClient = container.makeRealtimeClient(handler: nil)
        let chatStore = ChatStore(conversationsAPI: container.conversationsAPI, cache: container.cacheClient)
        let websitesStore = WebsitesStore(api: container.websitesAPI, cache: container.cacheClient)
        let ingestionStore = IngestionStore(api: container.ingestionAPI, cache: container.cacheClient)
        let tasksStore = TasksStore(api: container.tasksAPI, cache: container.cacheClient)
        let scratchpadStore = ScratchpadStore()
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: container.apiClient.config.baseUrl,
            startMonitoring: !isTestMode
        )
        let biometricMonitor = BiometricMonitor()
        let persistenceController = isTestMode
            ? PersistenceController(inMemory: true)
            : PersistenceController.shared
        let draftStorage = DraftStorage(container: persistenceController.container)
        let offlineStore = OfflineStore(container: persistenceController.container)
        let notesStore = NotesStore(
            api: container.notesAPI,
            cache: container.cacheClient,
            offlineStore: offlineStore,
            networkStatus: connectivityMonitor
        )
        let notesExecutor = NotesWriteQueueExecutor(api: container.notesAPI, store: notesStore)
        let writeQueueExecutor = CompositeWriteQueueExecutor(executors: [.note: notesExecutor])
        let writeQueue = WriteQueue(
            container: persistenceController.container,
            connectivityMonitor: connectivityMonitor,
            executor: writeQueueExecutor
        )
        notesStore.attachWriteQueue(writeQueue)
        let chatViewModel = ChatViewModel(
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
            networkStatus: connectivityMonitor,
            toastCenter: toastCenter,
            scratchpadStore: scratchpadStore
        )
        let temporaryStore = TemporaryFileStore.shared
        let notesViewModel = NotesViewModel(
            api: container.notesAPI,
            store: notesStore,
            toastCenter: toastCenter,
            networkStatus: connectivityMonitor
        )
        let notesEditorViewModel = NotesEditorViewModel(
            notesViewModel: notesViewModel,
            draftStorage: draftStorage,
            writeQueue: writeQueue,
            networkStatus: connectivityMonitor
        )
        let ingestionViewModel = IngestionViewModel(
            api: container.ingestionAPI,
            store: ingestionStore,
            temporaryStore: temporaryStore,
            uploadManager: IngestionUploadManager(config: container.apiClient.config)
        )
        let websitesViewModel = WebsitesViewModel(api: container.websitesAPI, store: websitesStore)
        let tasksViewModel = TasksViewModel(api: container.tasksAPI, store: tasksStore, toastCenter: toastCenter)
        let memoriesViewModel = MemoriesViewModel(api: container.memoriesAPI, cache: container.cacheClient)
        let settingsViewModel = SettingsViewModel(
            settingsAPI: container.settingsAPI,
            skillsAPI: container.skillsAPI,
            cache: container.cacheClient
        )
        let weatherViewModel = WeatherViewModel(api: container.weatherAPI)
        return EnvironmentDependencies(
            themeManager: themeManager,
            chatStore: chatStore,
            notesStore: notesStore,
            websitesStore: websitesStore,
            ingestionStore: ingestionStore,
            tasksStore: tasksStore,
            scratchpadStore: scratchpadStore,
            offlineStore: offlineStore,
            toastCenter: toastCenter,
            chatViewModel: chatViewModel,
            notesViewModel: notesViewModel,
            notesEditorViewModel: notesEditorViewModel,
            ingestionViewModel: ingestionViewModel,
            websitesViewModel: websitesViewModel,
            tasksViewModel: tasksViewModel,
            memoriesViewModel: memoriesViewModel,
            settingsViewModel: settingsViewModel,
            weatherViewModel: weatherViewModel,
            realtimeClient: realtimeClient,
            connectivityMonitor: connectivityMonitor,
            biometricMonitor: biometricMonitor,
            writeQueue: writeQueue,
            draftStorage: draftStorage
        )
    }
}
