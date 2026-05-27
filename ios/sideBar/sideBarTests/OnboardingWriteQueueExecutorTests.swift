import XCTest
@testable import sideBar

@MainActor
final class OnboardingWriteQueueExecutorTests: XCTestCase {
    func testExecutorReplaysOnboardingPayloadAndCachesResponse() async throws {
        let api = MockOnboardingAPI()
        let cache = TestCacheClient()
        let localStore = OnboardingLocalStateStore(cache: cache)
        let response = OnboardingState.default.applying(
            OnboardingSyncPayload(status: .inProgress, providerConnected: "2026-05-27T10:00:00Z")
        )
        api.updateResult = .success(response)
        let executor = OnboardingWriteQueueExecutor(api: api, localStateStore: localStore)
        let payload = OnboardingSyncPayload(
            status: .inProgress,
            providerConnected: "2026-05-27T10:00:00Z"
        )
        let record = PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.update.rawValue,
            entityType: WriteEntityType.onboarding.rawValue,
            entityId: payload.entityId,
            payload: try JSONEncoder().encode(payload),
            serverSnapshot: nil,
            attempts: 0
        )

        try await executor.execute(write: record)

        XCTAssertEqual(api.updates.last?.status, .inProgress)
        XCTAssertEqual(api.updates.last?.providerConnected, "2026-05-27T10:00:00Z")
        XCTAssertEqual(localStore.load(), response)
    }
}
