import Foundation
import sideBarShared

// swiftlint:disable nesting
extension AppEnvironment {
    struct StoreDependencyBuilder {
        struct Output {
            let chatStore: ChatStore
            let notesStore: NotesStore
            let websitesStore: WebsitesStore
            let ingestionStore: IngestionStore
            let tasksStore: TasksStore
            let scratchpadStore: ScratchpadStore
            let settingsStore: SettingsStore
            let writeQueue: WriteQueue
        }

        static func build(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            widgetDataManager: WidgetDataManager
        ) -> Output {
            let chatStore = ChatStore(
                conversationsAPI: container.conversationsAPI,
                cache: container.cacheClient,
                offlineStore: core.offlineStore,
                networkStatus: core.connectivityMonitor
            )
            let websitesStore = WebsitesStore(
                api: container.websitesAPI,
                cache: container.cacheClient,
                widgetDataManager: widgetDataManager,
                offlineStore: core.offlineStore,
                networkStatus: core.connectivityMonitor
            )
            websitesStore.spotlightIndexer = core.spotlightIndexer
            let ingestionStore = IngestionStore(
                api: container.ingestionAPI,
                cache: container.cacheClient,
                widgetDataManager: widgetDataManager,
                offlineStore: core.offlineStore,
                networkStatus: core.connectivityMonitor
            )
            ingestionStore.spotlightIndexer = core.spotlightIndexer
            let scratchpadStore = ScratchpadStore()
            let tasksStore = TasksStore(
                api: container.tasksAPI,
                cache: container.cacheClient,
                offlineStore: core.offlineStore,
                networkStatus: core.connectivityMonitor
            )
            tasksStore.spotlightIndexer = core.spotlightIndexer
            let notesStore = NotesStore(
                api: container.notesAPI,
                cache: container.cacheClient,
                widgetDataManager: widgetDataManager,
                offlineStore: core.offlineStore,
                networkStatus: core.connectivityMonitor
            )
            notesStore.spotlightIndexer = core.spotlightIndexer
            let settingsStore = SettingsStore(
                settingsAPI: container.settingsAPI,
                cache: container.cacheClient,
                offlineStore: core.offlineStore
            )

            let notesExecutor = NotesWriteQueueExecutor(api: container.notesAPI, store: notesStore)
            let tasksExecutor = TasksWriteQueueExecutor(api: container.tasksAPI, store: tasksStore)
            let websitesExecutor = WebsitesWriteQueueExecutor(api: container.websitesAPI, store: websitesStore)
            let filesExecutor = FilesWriteQueueExecutor(api: container.ingestionAPI, store: ingestionStore)
            let writeQueueExecutor = CompositeWriteQueueExecutor(
                executors: [
                    .note: notesExecutor,
                    .noteFolder: notesExecutor,
                    .task: tasksExecutor,
                    .website: websitesExecutor,
                    .file: filesExecutor
                ]
            )
            let writeQueue = WriteQueue(
                container: core.persistenceContainer,
                connectivityMonitor: core.connectivityMonitor,
                executor: writeQueueExecutor
            )
            notesStore.attachWriteQueue(writeQueue)
            tasksStore.attachWriteQueue(writeQueue)
            websitesStore.attachWriteQueue(writeQueue)
            ingestionStore.attachWriteQueue(writeQueue)

            return Output(
                chatStore: chatStore,
                notesStore: notesStore,
                websitesStore: websitesStore,
                ingestionStore: ingestionStore,
                tasksStore: tasksStore,
                scratchpadStore: scratchpadStore,
                settingsStore: settingsStore,
                writeQueue: writeQueue
            )
        }
    }
}
// swiftlint:enable nesting
