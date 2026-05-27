import XCTest
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
}
