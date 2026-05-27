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
            let pendingSecretStore = SettingsPendingSecretStore()
            let pendingAssetStore = SettingsPendingAssetStore()
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
            let settingsStore = makeSettingsStore(
                container: container,
                core: core,
                pendingSecretStore: pendingSecretStore,
                pendingAssetStore: pendingAssetStore
            )
            let writeQueue = makeWriteQueue(
                container: container,
                core: core,
                notesStore: notesStore,
                tasksStore: tasksStore,
                websitesStore: websitesStore,
                ingestionStore: ingestionStore,
                settingsStore: settingsStore,
                pendingSecretStore: pendingSecretStore,
                pendingAssetStore: pendingAssetStore
            )

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

        private static func makeWriteQueue(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            notesStore: NotesStore,
            tasksStore: TasksStore,
            websitesStore: WebsitesStore,
            ingestionStore: IngestionStore,
            settingsStore: SettingsStore,
            pendingSecretStore: SettingsPendingSecretStore,
            pendingAssetStore: SettingsPendingAssetStore
        ) -> WriteQueue {
            let notesExecutor = NotesWriteQueueExecutor(api: container.notesAPI, store: notesStore)
            let tasksExecutor = TasksWriteQueueExecutor(api: container.tasksAPI, store: tasksStore)
            let websitesExecutor = WebsitesWriteQueueExecutor(api: container.websitesAPI, store: websitesStore)
            let filesExecutor = FilesWriteQueueExecutor(api: container.ingestionAPI, store: ingestionStore)
            let settingsExecutor = SettingsWriteQueueExecutor(
                api: container.settingsAPI,
                store: settingsStore,
                pendingSecretStore: pendingSecretStore,
                pendingAssetStore: pendingAssetStore
            )
            let onboardingExecutor = OnboardingWriteQueueExecutor(
                api: container.onboardingAPI,
                localStateStore: OnboardingLocalStateStore(cache: container.cacheClient)
            )
            let writeQueue = WriteQueue(
                container: core.persistenceContainer,
                connectivityMonitor: core.connectivityMonitor,
                executor: CompositeWriteQueueExecutor(
                    executors: [
                        .note: notesExecutor,
                        .noteFolder: notesExecutor,
                        .task: tasksExecutor,
                        .website: websitesExecutor,
                        .file: filesExecutor,
                        .settings: settingsExecutor,
                        .onboarding: onboardingExecutor
                    ]
                )
            )
            notesStore.attachWriteQueue(writeQueue)
            tasksStore.attachWriteQueue(writeQueue)
            websitesStore.attachWriteQueue(writeQueue)
            ingestionStore.attachWriteQueue(writeQueue)
            settingsStore.attachWriteQueue(writeQueue)
            return writeQueue
        }

        private static func makeSettingsStore(
            container: ServiceContainer,
            core: CoreDependencyBuilder.Output,
            pendingSecretStore: SettingsPendingSecretStore,
            pendingAssetStore: SettingsPendingAssetStore
        ) -> SettingsStore {
            SettingsStore(
                settingsAPI: container.settingsAPI,
                cache: container.cacheClient,
                offlineStore: core.offlineStore,
                pendingSecretStore: pendingSecretStore,
                pendingAssetStore: pendingAssetStore,
                currentAuthUserIdProvider: {
                    ViewModelDependencyBuilder.settingsRequestUserId(
                        authSession: container.authSession,
                        requireAuthorization: false
                    )
                }
            )
        }
    }
}
// swiftlint:enable nesting
