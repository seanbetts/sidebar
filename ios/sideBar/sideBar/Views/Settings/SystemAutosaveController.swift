import Combine
import Foundation

@MainActor
final class SystemAutosaveController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var autosaveTask: Task<Int?, Never>?
    private var isFlushRequested = false
    private(set) var isAutosaveSaving = false
    private let delayNs: UInt64
    private var pendingAutosaveSequence: Int?
    private var autosaveSequence: Int = 0
    private var completedAutosaveSequence: Int = 0
    private var hasScheduledSinceLastFlush = false

    init(delayNs: UInt64 = 800_000_000) {
        self.delayNs = delayNs
    }

    func scheduleAutosave(
        hasLoadedDrafts: Bool,
        isSyncingDrafts: Bool,
        isDraftDirty: Bool,
        performSave: @Sendable @escaping () async -> Void
    ) {
        guard hasLoadedDrafts, !isSyncingDrafts, isDraftDirty else { return }
        autosaveTask?.cancel()
        isFlushRequested = false

        autosaveSequence += 1
        pendingAutosaveSequence = autosaveSequence
        hasScheduledSinceLastFlush = true
        let sequence = autosaveSequence

        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return nil }
            guard !isFlushRequested else { return nil }
            await MainActor.run {
                isAutosaveSaving = true
            }
            await performSave()
            await MainActor.run {
                isAutosaveSaving = false
                completedAutosaveSequence = sequence
                pendingAutosaveSequence = nil
                autosaveTask = nil
                hasScheduledSinceLastFlush = false
            }
            return sequence
        }
    }

    func flushPendingAutosave(
        shouldFlush: Bool,
        performSave: @Sendable @escaping () async -> Void
    ) {
        guard shouldFlush else { return }
        guard !isAutosaveSaving else { return }
        guard hasScheduledSinceLastFlush else { return }
        guard let pendingTask = autosaveTask,
              let flushSequence = pendingAutosaveSequence else { return }
        pendingTask.cancel()
        isFlushRequested = true

        Task {
            let savedSequence = await pendingTask.value
            await MainActor.run {
                if savedSequence == flushSequence
                    || completedAutosaveSequence >= flushSequence
                    || isAutosaveSaving {
                    isFlushRequested = false
                    pendingAutosaveSequence = nil
                    autosaveTask = nil
                    hasScheduledSinceLastFlush = false
                    return
                }
                isAutosaveSaving = true
            }
            await performSave()
            await MainActor.run {
                isAutosaveSaving = false
                isFlushRequested = false
                completedAutosaveSequence = flushSequence
                pendingAutosaveSequence = nil
                autosaveTask = nil
                hasScheduledSinceLastFlush = false
            }
        }
    }

    func cancelPendingAutosave() {
        autosaveTask?.cancel()
        pendingAutosaveSequence = nil
        autosaveTask = nil
        hasScheduledSinceLastFlush = false
    }
}
