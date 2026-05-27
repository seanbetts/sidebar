import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingSyncCoordinatorTests: XCTestCase {
    func testPayloadRoundTripsWithoutSecrets() throws {
        let payload = OnboardingSyncPayload(
            status: .inProgress,
            providerConnected: "2026-05-27T10:00:00Z",
            profileBasicsSet: nil,
            locationPermission: .granted,
            notificationsPermission: nil
        )

        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try JSONDecoder().decode(OnboardingSyncPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertFalse(json.contains("sk-"))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("token"))
    }

    func testLocalStateStorePersistsCachedOnboardingState() {
        let cache = TestCacheClient()
        let store = OnboardingLocalStateStore(cache: cache)
        let state = OnboardingState.default.withOnboardingStatus(.inProgress)

        store.save(state)

        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(cache.get(key: CacheKeys.onboardingState) as OnboardingState?, state)
    }

    func testCoordinatorReturnsRemoteStateOnSuccessfulSync() async throws {
        let api = MockOnboardingAPI()
        let cache = TestCacheClient()
        let localStore = OnboardingLocalStateStore(cache: cache)
        let response = OnboardingState.default.applying(
            OnboardingSyncPayload(status: .inProgress)
        )
        api.updateResult = .success(response)
        let coordinator = OnboardingSyncCoordinator(
            api: api,
            localStateStore: localStore,
            writeQueue: nil
        )

        let result = await coordinator.sync(
            payload: OnboardingSyncPayload(status: .inProgress),
            fallbackBaseState: .default
        )

        XCTAssertEqual(result, response)
        XCTAssertEqual(localStore.load(), response)
        XCTAssertEqual(api.updates.last?.status, .inProgress)
    }

    func testCoordinatorCachesOptimisticStateWhenRemoteSyncFails() async {
        let api = MockOnboardingAPI()
        api.updateResult = .failure(APIClientError.requestFailed(503))
        let cache = TestCacheClient()
        let localStore = OnboardingLocalStateStore(cache: cache)
        let coordinator = OnboardingSyncCoordinator(
            api: api,
            localStateStore: localStore,
            writeQueue: nil
        )

        let result = await coordinator.sync(
            payload: OnboardingSyncPayload(status: .inProgress),
            fallbackBaseState: .default
        )

        XCTAssertEqual(result.status, .inProgress)
        XCTAssertEqual(localStore.load()?.status, .inProgress)
    }
}
