import Foundation

@MainActor
final class OnboardingWriteQueueExecutor: WriteQueueExecutor {
    private let api: any OnboardingProviding
    private let localStateStore: OnboardingLocalStateStore

    init(api: any OnboardingProviding, localStateStore: OnboardingLocalStateStore) {
        self.api = api
        self.localStateStore = localStateStore
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.onboarding.rawValue else {
            return
        }
        let payload = try JSONDecoder().decode(OnboardingSyncPayload.self, from: write.payload)
        let state = try await api.updateOnboarding(payload.update)
        localStateStore.save(state)
    }
}
