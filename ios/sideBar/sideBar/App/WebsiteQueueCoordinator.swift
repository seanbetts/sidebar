import Foundation

@MainActor
final class WebsiteQueueCoordinator {
    enum Trigger {
        case handoff
        case authBecameRunnable
        case connectivityRecovered
        case protectedContentReady
        case appDidBecomeActive
        case appDidEnterBackground
        case retryWakeup
    }

    private let hasPendingWork: () async -> Bool
    private let hasBackgroundContinuationWork: () async -> Bool
    private let canReplayNow: () async -> Bool
    private let replay: () async -> Void
    private let scheduleContinuation: () -> Void
    private let retryDelay: Duration?

    private var replayTask: Task<Void, Never>?
    private var retryWakeupTask: Task<Void, Never>?
    private var shouldReplayAgain = false

    init(
        hasPendingWork: @escaping () async -> Bool,
        hasBackgroundContinuationWork: @escaping () async -> Bool,
        canReplayNow: @escaping () async -> Bool,
        replay: @escaping () async -> Void,
        scheduleContinuation: @escaping () -> Void = {},
        retryDelay: Duration? = nil
    ) {
        self.hasPendingWork = hasPendingWork
        self.hasBackgroundContinuationWork = hasBackgroundContinuationWork
        self.canReplayNow = canReplayNow
        self.replay = replay
        self.scheduleContinuation = scheduleContinuation
        self.retryDelay = retryDelay
    }

    func queueDidChange(trigger: Trigger = .handoff) {
        handle(trigger: trigger)
    }

    func authDidBecomeRunnable() {
        handle(trigger: .authBecameRunnable)
    }

    func connectivityDidRecover() {
        handle(trigger: .connectivityRecovered)
    }

    func protectedContentDidBecomeReady() {
        handle(trigger: .protectedContentReady)
    }

    func appDidBecomeActive() {
        handle(trigger: .appDidBecomeActive)
    }

    func appDidEnterBackground() {
        handle(trigger: .appDidEnterBackground)
    }

    func shutdown() {
        replayTask?.cancel()
        replayTask = nil
        retryWakeupTask?.cancel()
        retryWakeupTask = nil
        shouldReplayAgain = false
    }

    private func handle(trigger: Trigger) {
        Task { @MainActor in
            let hasPendingWork = await hasPendingWork()
            guard hasPendingWork else {
                cancelRetryWakeup()
                return
            }

            if trigger == .appDidEnterBackground {
                await scheduleContinuationIfNeeded()
                ensureRetryWakeupIfNeeded()
                return
            }

            let canReplayNow = await canReplayNow()
            guard canReplayNow else {
                await scheduleContinuationIfNeeded()
                ensureRetryWakeupIfNeeded()
                return
            }

            startReplayIfNeeded()
        }
    }

    private func startReplayIfNeeded() {
        guard replayTask == nil else {
            shouldReplayAgain = true
            return
        }

        replayTask = Task { @MainActor [weak self] in
            await self?.runReplayLoop()
        }
    }

    private func runReplayLoop() async {
        while true {
            shouldReplayAgain = false
            await replay()

            if await hasPendingWork() == false {
                cancelRetryWakeup()
                replayTask = nil
                return
            }

            await scheduleContinuationIfNeeded()
            ensureRetryWakeupIfNeeded()

            guard shouldReplayAgain, await canReplayNow() else {
                replayTask = nil
                return
            }
        }
    }

    private func scheduleContinuationIfNeeded() async {
        guard await hasBackgroundContinuationWork() else { return }
        scheduleContinuation()
    }

    private func ensureRetryWakeupIfNeeded() {
        guard let retryDelay, retryWakeupTask == nil else { return }
        retryWakeupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: retryDelay)
            guard let self else { return }
            self.retryWakeupTask = nil
            self.handle(trigger: .retryWakeup)
        }
    }

    private func cancelRetryWakeup() {
        retryWakeupTask?.cancel()
        retryWakeupTask = nil
    }
}
