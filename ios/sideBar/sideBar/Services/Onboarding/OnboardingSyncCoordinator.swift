import Foundation
import OSLog

/// Synchronizes onboarding progress with optimistic local fallback support.
@MainActor public protocol OnboardingSyncing: AnyObject {
    func sync(
        payload: OnboardingSyncPayload,
        fallbackBaseState: OnboardingState
    ) async -> OnboardingState
    func cachedState() -> OnboardingState?
    func cacheRemoteState(_ state: OnboardingState)
}

@MainActor
final class OnboardingSyncCoordinator: OnboardingSyncing {
    private let api: any OnboardingProviding
    private let localStateStore: OnboardingLocalStateStore
    private weak var writeQueue: WriteQueue?
    private let logger = Logger(subsystem: "sideBar", category: "Onboarding")

    init(
        api: any OnboardingProviding,
        localStateStore: OnboardingLocalStateStore,
        writeQueue: WriteQueue?
    ) {
        self.api = api
        self.localStateStore = localStateStore
        self.writeQueue = writeQueue
    }

    func cachedState() -> OnboardingState? {
        localStateStore.load()
    }

    func cacheRemoteState(_ state: OnboardingState) {
        localStateStore.save(state)
    }

    func sync(
        payload: OnboardingSyncPayload,
        fallbackBaseState: OnboardingState
    ) async -> OnboardingState {
        let optimistic = (localStateStore.load() ?? fallbackBaseState).applying(payload)
        localStateStore.save(optimistic)

        do {
            let state = try await api.updateOnboarding(payload.update)
            localStateStore.save(state)
            return state
        } catch {
            logger.notice("Queued onboarding sync retry after update failure")
            await enqueueRetry(payload)
            return optimistic
        }
    }

    private func enqueueRetry(_ payload: OnboardingSyncPayload) async {
        guard let writeQueue else { return }

        do {
            try await writeQueue.enqueue(
                operation: .update,
                entityType: .onboarding,
                entityId: payload.entityId,
                payload: payload
            )
        } catch {
            logger.error("Failed to enqueue onboarding sync retry: \(error.localizedDescription, privacy: .public)")
        }
    }
}
