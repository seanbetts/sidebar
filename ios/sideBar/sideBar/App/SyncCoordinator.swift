import Combine
import Foundation

@MainActor
final class SyncCoordinator {
    private let connectivityMonitor: ConnectivityMonitor
    private let writeQueue: WriteQueue
    private let onReconnectRefresh: () async -> Void
    private let isSyncAllowed: () -> Bool
    private let scheduleBackgroundWriteQueueFlush: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        connectivityMonitor: ConnectivityMonitor,
        writeQueue: WriteQueue,
        onReconnectRefresh: @escaping () async -> Void,
        isSyncAllowed: @escaping () -> Bool = { true },
        scheduleBackgroundWriteQueueFlush: @escaping () -> Void = {}
    ) {
        self.connectivityMonitor = connectivityMonitor
        self.writeQueue = writeQueue
        self.onReconnectRefresh = onReconnectRefresh
        self.isSyncAllowed = isSyncAllowed
        self.scheduleBackgroundWriteQueueFlush = scheduleBackgroundWriteQueueFlush
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
        if await writeQueue.hasPendingWritesNeedingFlush() {
            scheduleBackgroundWriteQueueFlush()
        }
        await onReconnectRefresh()
    }
}
