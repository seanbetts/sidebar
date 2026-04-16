import Combine
import Foundation

@MainActor
protocol SyncableStore {
    func refreshAll() async
}

struct SyncableStoreAdapter: SyncableStore {
    let refresh: () async -> Void

    func refreshAll() async {
        await refresh()
    }
}

@MainActor
final class SyncCoordinator {
    private let connectivityMonitor: ConnectivityMonitor
    private let writeQueue: WriteQueue
    private let stores: [SyncableStore]
    private let isSyncAllowed: () -> Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        connectivityMonitor: ConnectivityMonitor,
        writeQueue: WriteQueue,
        stores: [SyncableStore],
        isSyncAllowed: @escaping () -> Bool = { true }
    ) {
        self.connectivityMonitor = connectivityMonitor
        self.writeQueue = writeQueue
        self.stores = stores
        self.isSyncAllowed = isSyncAllowed
    }

    func start() {
        connectivityMonitor.offlineCapabilityPolicyPublisher
            .map(\.canAttemptServerRead)
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshAll()
                }
            }
            .store(in: &cancellables)
    }

    func refreshAll() async {
        guard isSyncAllowed() else { return }
        let capabilityPolicy = connectivityMonitor.offlineCapabilityPolicy
        guard capabilityPolicy.canAttemptServerRead else { return }
        await writeQueue.processQueue()
        await withTaskGroup(of: Void.self) { group in
            for store in stores {
                group.addTask { @MainActor in
                    await store.refreshAll()
                }
            }
        }
    }
}
