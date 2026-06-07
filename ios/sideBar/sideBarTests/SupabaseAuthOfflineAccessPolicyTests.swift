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

    func testAuthDiagnosticEventAllowsLegacyTimestampSeedFailedReason() {
        let event = AuthDiagnosticsEvent(
            name: "offline_access_window",
            metadata: ["reason": "legacy_timestamp_seed_failed"]
        )

        XCTAssertEqual(event.metadata["reason"], "legacy_timestamp_seed_failed")
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

    func testLegacyTimestampSeedFailsClosedWhenTimestampWriteFails() throws {
        let store = FailingMetadataAuthStateStore(failingSaveKey: AppStorageKeys.lastAuthTimestamp)
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        let diagnostics = RecordingAuthDiagnostics()
        let adapter = makeAdapter(
            stateStore: store,
            userDefaults: makeUserDefaults(),
            diagnostics: diagnostics
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp))
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted))
        XCTAssertFalse(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seeded"
        })
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seed_failed"
        })
    }

    func testLegacyTimestampSeedFailsClosedWhenMigrationMarkerWriteFails() throws {
        let store = FailingMetadataAuthStateStore(
            failingSaveKey: AppStorageKeys.authTimestampLegacyMigrationCompleted
        )
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        let diagnostics = RecordingAuthDiagnostics()
        let adapter = makeAdapter(
            stateStore: store,
            userDefaults: makeUserDefaults(),
            diagnostics: diagnostics
        )

        XCTAssertFalse(adapter.canRestoreOfflineSession)
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp))
        XCTAssertNil(try store.loadAuthMetadataValue(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted))
        XCTAssertFalse(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seeded"
        })
        XCTAssertTrue(diagnostics.snapshot().contains {
            $0.name == "offline_access_window" &&
                $0.metadata["reason"] == "legacy_timestamp_seed_failed"
        })
    }

    func testClearPersistedAuthStateClearsFallbackMarkerAfterStoreFailure() throws {
        let defaults = makeUserDefaults()
        defaults.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.lastAuthTimestamp)
        defaults.set(true, forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
        let store = FailingClearAuthStateStore()

        XCTAssertThrowsError(try SupabaseAuthRecovery.clearPersistedAuthState(
            stateStore: store,
            userDefaults: defaults
        ))
        XCTAssertNil(defaults.object(forKey: AppStorageKeys.lastAuthTimestamp))
        XCTAssertNil(defaults.object(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted))
    }

    func testSignOutClearsFallbackMigrationMarker() async throws {
        let defaults = makeUserDefaults()
        defaults.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.lastAuthTimestamp)
        defaults.set(true, forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
        let store = InMemoryAuthStateStore()
        try store.saveAccessToken("token")
        try store.saveUserId("user")
        let adapter = makeAdapter(
            stateStore: store,
            userDefaults: defaults,
            diagnostics: RecordingAuthDiagnostics()
        )

        await adapter.signOut()

        XCTAssertNil(defaults.object(forKey: AppStorageKeys.lastAuthTimestamp))
        XCTAssertNil(defaults.object(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted))
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

private final class FailingClearAuthStateStore: AuthStateStore {
    private enum StoreError: Error {
        case clearFailed
    }

    func saveAccessToken(_ token: String?) throws {
        _ = token
    }

    func saveUserId(_ userId: String?) throws {
        _ = userId
    }

    func loadAccessToken() throws -> String? {
        nil
    }

    func loadUserId() throws -> String? {
        nil
    }

    func clear() throws {
        throw StoreError.clearFailed
    }
}

private final class FailingMetadataAuthStateStore: AuthStateStore, AuthMetadataStore {
    private enum StoreError: Error {
        case saveFailed
    }

    private let failingSaveKey: String
    private var accessToken: String?
    private var userId: String?
    private var metadata: [String: String] = [:]

    init(failingSaveKey: String) {
        self.failingSaveKey = failingSaveKey
    }

    func saveAccessToken(_ token: String?) throws {
        accessToken = token
    }

    func saveUserId(_ userId: String?) throws {
        self.userId = userId
    }

    func loadAccessToken() throws -> String? {
        accessToken
    }

    func loadUserId() throws -> String? {
        userId
    }

    func clear() throws {
        accessToken = nil
        userId = nil
    }

    func saveAuthMetadataValue(_ value: String?, forKey key: String) throws {
        if key == failingSaveKey {
            throw StoreError.saveFailed
        }
        metadata[key] = value
    }

    func loadAuthMetadataValue(forKey key: String) throws -> String? {
        metadata[key]
    }

    func removeAuthMetadataValue(forKey key: String) throws {
        metadata.removeValue(forKey: key)
    }
}
