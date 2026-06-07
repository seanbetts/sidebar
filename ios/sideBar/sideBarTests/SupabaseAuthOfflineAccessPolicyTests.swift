import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthOfflineAccessPolicyTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        super.tearDown()
    }

    func testMissingAuthTimestampSeedsOnceForLegacyStoredCredentials() throws {
        let store = makeAuthStore()
        let token = "sensitive-access-token"
        let userId = "sensitive-user-id"
        try store.saveAccessToken(token)
        try store.saveUserId(userId)
        let diagnostics = RecordingAuthDiagnostics()
        let adapter = makeAdapter(
            stateStore: store,
            userDefaults: makeUserDefaults(),
            diagnostics: diagnostics
        )

        XCTAssertTrue(adapter.canRestoreOfflineSession)

        let seededTimestamp = try store.loadAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp)
        XCTAssertNotNil(seededTimestamp)
        XCTAssertEqual(
            try store.loadAuthMetadataValue(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted),
            "true"
        )
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seeded"
        })
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue(userId))

        XCTAssertTrue(adapter.canRestoreOfflineSession)
        XCTAssertEqual(
            try store.loadAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp),
            seededTimestamp
        )
        let seedEvents = diagnostics.snapshot().filter {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seeded"
        }
        XCTAssertEqual(seedEvents.count, 1)
    }

    func testMissingAuthTimestampAfterLegacyMigrationDoesNotRestoreOfflineSession() throws {
        let store = makeAuthStore()
        let token = "sensitive-access-token"
        let userId = "sensitive-user-id"
        try store.saveAccessToken(token)
        try store.saveUserId(userId)
        try store.saveAuthMetadataValue(
            "true",
            forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted
        )
        let diagnostics = RecordingAuthDiagnostics()
        let adapter = makeAdapter(
            stateStore: store,
            userDefaults: makeUserDefaults(),
            diagnostics: diagnostics
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertFalse(adapter.restoreOfflineSession())

        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "missing_timestamp_after_migration"
        })
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp))
        XCTAssertFalse(diagnostics.containsSensitiveValue(token))
        XCTAssertFalse(diagnostics.containsSensitiveValue(userId))
    }

    private func makeAdapter(
        stateStore: AuthStateStore,
        userDefaults: UserDefaults,
        diagnostics: AuthDiagnosticsRecording
    ) -> SupabaseAuthAdapter {
        SupabaseAuthAdapter(
            authClient: FakeSupabaseAuthClient(),
            stateStore: stateStore,
            startAuthStateTask: false,
            userDefaults: userDefaults,
            diagnostics: diagnostics
        )
    }

    private func makeAuthStore() -> KeychainAuthStateStore {
        KeychainAuthStateStore(
            service: "sideBar.AuthOfflineAccessPolicyTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let isolated = TestIsolation.makeUserDefaults(prefix: "SupabaseAuthOfflineAccessPolicyTests")
        isolatedDefaults.append(isolated)
        return isolated.defaults
    }
}
