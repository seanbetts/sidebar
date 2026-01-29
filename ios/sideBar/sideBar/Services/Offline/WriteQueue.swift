import Combine
import CoreData
import Foundation

enum WriteOperation: String {
    case create
    case update
    case delete
}

enum WriteEntityType: String {
    case note
    case message
    case website
    case file
    case scratchpad
}

enum WriteQueueStatus: String {
    case pending
    case inProgress
    case failed
}

enum WriteQueueError: Error {
    case missingExecutor
}

protocol WriteQueueExecutor {
    func execute(write: PendingWrite) async throws
}

@MainActor
final class WriteQueue: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isProcessing: Bool = false

    private let container: NSPersistentContainer
    private let networkMonitor: NetworkMonitor
    private let executor: WriteQueueExecutor?
    private let autoProcessEnabled: Bool
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()

    init(
        container: NSPersistentContainer,
        networkMonitor: NetworkMonitor,
        executor: WriteQueueExecutor? = nil,
        autoProcessEnabled: Bool = true
    ) {
        self.container = container
        self.networkMonitor = networkMonitor
        self.executor = executor
        self.autoProcessEnabled = autoProcessEnabled
        loadPendingCount()
        observeNetwork()
    }

    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: T
    ) throws {
        let context = container.viewContext
        let write = PendingWrite(context: context)
        write.id = UUID()
        write.operationType = operation.rawValue
        write.entityType = entityType.rawValue
        write.entityId = entityId
        write.payload = try encoder.encode(payload)
        write.createdAt = Date()
        write.attempts = 0
        write.status = WriteQueueStatus.pending.rawValue

        try context.save()
        pendingCount += 1

        if autoProcessEnabled, executor != nil, !networkMonitor.isOffline {
            Task { [weak self] in
                await self?.processQueue()
            }
        }
    }

    func processQueue() async {
        guard !isProcessing, executor != nil, !networkMonitor.isOffline else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let write = fetchNextPending() {
            await processWrite(write)
            await Task.yield()
        }

        loadPendingCount()
    }

    private func processWrite(_ write: PendingWrite) async {
        let context = container.viewContext
        write.status = WriteQueueStatus.inProgress.rawValue
        write.attempts += 1
        write.lastAttemptAt = Date()
        try? context.save()

        do {
            guard let executor else {
                throw WriteQueueError.missingExecutor
            }
            try await executor.execute(write: write)
            context.delete(write)
            try? context.save()
        } catch {
            let shouldRetry = shouldRetry(write)
            write.status = shouldRetry ? WriteQueueStatus.pending.rawValue : WriteQueueStatus.failed.rawValue
            write.lastError = String(describing: error)
            try? context.save()

            if shouldRetry {
                let delay = backoffDelay(for: Int(write.attempts))
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func shouldRetry(_ write: PendingWrite) -> Bool {
        write.attempts < 5
    }

    private func backoffDelay(for attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16.0)
        return UInt64(seconds * 1_000_000_000)
    }

    private func fetchNextPending() -> PendingWrite? {
        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)]
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

    private func loadPendingCount() {
        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(
            format: "status == %@ OR status == %@",
            WriteQueueStatus.pending.rawValue,
            WriteQueueStatus.failed.rawValue
        )
        pendingCount = (try? container.viewContext.count(for: request)) ?? 0
    }

    private func observeNetwork() {
        networkMonitor.$isOffline
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self, self.autoProcessEnabled else { return }
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            .store(in: &cancellables)
    }
}
