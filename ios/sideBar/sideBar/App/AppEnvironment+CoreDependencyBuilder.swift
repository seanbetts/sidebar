import CoreData
import Foundation
import sideBarShared

// swiftlint:disable nesting
extension AppEnvironment {
    struct CoreDependencyBuilder {
        struct Output {
            let persistenceController: PersistenceController
            let themeManager: ThemeManager
            let toastCenter: ToastCenter
            let realtimeClient: RealtimeClient
            let connectivityMonitor: ConnectivityMonitor
            let persistenceContainer: NSPersistentContainer
            let draftStorage: DraftStorage
            let offlineStore: OfflineStore
            let spotlightIndexer: any SpotlightIndexing
            let biometricMonitor: BiometricMonitor
        }

        static func build(
            container: ServiceContainer,
            isTestMode: Bool
        ) -> Output {
            let themeManager = ThemeManager()
            let toastCenter = ToastCenter()
            let realtimeClient = container.makeRealtimeClient(handler: nil)
            let connectivityMonitor = ConnectivityMonitor(
                baseUrl: container.apiClient.config.baseUrl,
                startMonitoring: !isTestMode
            )
            let persistenceController = persistenceController(for: isTestMode)
            let draftStorage = DraftStorage(container: persistenceController.container)
            let offlineStore = OfflineStore(container: persistenceController.container)
            let spotlightIndexer: any SpotlightIndexing = isTestMode ? NoOpSpotlightIndexer() : SpotlightIndexer()
            let biometricMonitor = BiometricMonitor()
            return Output(
                persistenceController: persistenceController,
                themeManager: themeManager,
                toastCenter: toastCenter,
                realtimeClient: realtimeClient,
                connectivityMonitor: connectivityMonitor,
                persistenceContainer: persistenceController.container,
                draftStorage: draftStorage,
                offlineStore: offlineStore,
                spotlightIndexer: spotlightIndexer,
                biometricMonitor: biometricMonitor
            )
        }

        private static func persistenceController(for isTestMode: Bool) -> PersistenceController {
            guard isTestMode else {
                return .shared
            }
            return PersistenceController(inMemory: true)
        }
    }
}
// swiftlint:enable nesting
