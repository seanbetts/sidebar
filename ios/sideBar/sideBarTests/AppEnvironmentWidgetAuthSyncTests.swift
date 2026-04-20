import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentWidgetAuthSyncTests: XCTestCase {
    private let widgetAuthKey = "widgetIsAuthenticated"
    private let widgetMigrationKey = "widget_migration_v2"
    private var retainedEnvironments: [AppEnvironment] = []
    private var appSuiteName: String!
    private var widgetSuiteName: String!
    private var appDefaults: UserDefaults!
    private var widgetDefaults: UserDefaults!
    private var pendingShareDirectory: URL!

    override func setUp() {
        super.setUp()
        retainedEnvironments.removeAll()

        appSuiteName = "AppEnvironmentWidgetAuthSyncTests.app.\(UUID().uuidString)"
        widgetSuiteName = "AppEnvironmentWidgetAuthSyncTests.widget.\(UUID().uuidString)"
        appDefaults = UserDefaults(suiteName: appSuiteName)
        widgetDefaults = UserDefaults(suiteName: widgetSuiteName)
        pendingShareDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppEnvironmentWidgetAuthSyncTests.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        if let appDefaults, let appSuiteName {
            appDefaults.removePersistentDomain(forName: appSuiteName)
        }
        if let widgetDefaults, let widgetSuiteName {
            widgetDefaults.removePersistentDomain(forName: widgetSuiteName)
        }
        if let pendingShareDirectory {
            try? FileManager.default.removeItem(at: pendingShareDirectory)
        }
        appSuiteName = nil
        widgetSuiteName = nil
        appDefaults = nil
        widgetDefaults = nil
        pendingShareDirectory = nil
        super.tearDown()
    }

    func testSignedOutStartupSkipsWidgetAuthSyncWhenMirrorIsMissing() {
        let environment = makeEnvironment(authState: .signedOut)

        environment.refreshAuthState()

        XCTAssertNil(widgetDefaults.object(forKey: widgetAuthKey))
        XCTAssertEqual(
            appDefaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool,
            false
        )
    }

    func testSignedOutStartupCorrectsWidgetAuthWhenMirrorShowsAuthenticated() {
        appDefaults.set(true, forKey: AppStorageKeys.widgetAuthStateMirror)
        widgetDefaults.set(true, forKey: widgetAuthKey)
        let environment = makeEnvironment(authState: .signedOut)

        environment.refreshAuthState()

        XCTAssertEqual(widgetDefaults.object(forKey: widgetAuthKey) as? Bool, false)
        XCTAssertEqual(
            appDefaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool,
            false
        )
    }

    func testWidgetBridgeBootstrapRequiresSignedInAuth() {
        XCTAssertFalse(AppEnvironment.shouldBootstrapWidgetBridge(authState: .signedOut))
        XCTAssertTrue(AppEnvironment.shouldBootstrapWidgetBridge(authState: .stale))
        XCTAssertTrue(AppEnvironment.shouldBootstrapWidgetBridge(authState: .active))
    }

    func testSignedInRefreshBootstrapsWidgetBridgeAfterSignedOutStartup() async throws {
        let (environment, authSession) = makeEnvironmentWithSession(authState: .signedOut)

        XCTAssertNil(widgetDefaults.object(forKey: widgetMigrationKey))

        try await authSession.signIn(email: "user@example.com", password: "password")
        environment.refreshAuthState()

        XCTAssertEqual(widgetDefaults.object(forKey: widgetMigrationKey) as? Bool, true)
        XCTAssertEqual(widgetDefaults.object(forKey: widgetAuthKey) as? Bool, true)
        XCTAssertEqual(
            appDefaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool,
            true
        )
    }

    func testSignedInStartupRepairsMissingWidgetAuthStateWhenMirrorShowsAuthenticated() {
        appDefaults.set(true, forKey: AppStorageKeys.widgetAuthStateMirror)
        let environment = makeEnvironment(authState: .active)

        environment.refreshAuthState()

        XCTAssertEqual(widgetDefaults.object(forKey: widgetAuthKey) as? Bool, true)
        XCTAssertEqual(
            appDefaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool,
            true
        )
    }

    func testRecoverableSignedOutRefreshPreservesWidgetSnapshots() {
        widgetDefaults.set(Data("tasks".utf8), forKey: WidgetContentType.tasks.dataKey)
        widgetDefaults.set(true, forKey: widgetAuthKey)
        appDefaults.set(true, forKey: AppStorageKeys.widgetAuthStateMirror)
        appDefaults.set("user-123", forKey: AppStorageKeys.cacheScopeUserId)
        let environment = makeRecoverableSignedOutEnvironment()

        environment.refreshAuthState()

        XCTAssertNotNil(widgetDefaults.data(forKey: WidgetContentType.tasks.dataKey))
        XCTAssertEqual(widgetDefaults.object(forKey: widgetAuthKey) as? Bool, false)
        XCTAssertEqual(
            appDefaults.object(forKey: AppStorageKeys.widgetAuthStateMirror) as? Bool,
            false
        )
        XCTAssertEqual(appDefaults.string(forKey: AppStorageKeys.cacheScopeUserId), "user-123")
    }

    private func makeEnvironment(authState: AuthState) -> AppEnvironment {
        makeEnvironmentWithSession(authState: authState).environment
    }

    private func makeRecoverableSignedOutEnvironment() -> AppEnvironment {
        let storage = AppEnvironmentStorage(
            userDefaults: appDefaults,
            widgetDataManager: WidgetDataManager(userDefaults: widgetDefaults),
            extensionEventStore: ExtensionEventStore(userDefaults: widgetDefaults),
            pendingShareStore: PendingShareStore(
                baseDirectory: pendingShareDirectory,
                userDefaults: widgetDefaults
            )
        )
        let authSession = RecoverableSignedOutAuthSession()
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        return environment
    }

    private func makeEnvironmentWithSession(
        authState: AuthState
    ) -> (environment: AppEnvironment, authSession: PlaceholderAuthSession) {
        let storage = AppEnvironmentStorage(
            userDefaults: appDefaults,
            widgetDataManager: WidgetDataManager(userDefaults: widgetDefaults),
            extensionEventStore: ExtensionEventStore(userDefaults: widgetDefaults),
            pendingShareStore: PendingShareStore(
                baseDirectory: pendingShareDirectory,
                userDefaults: widgetDefaults
            )
        )
        let authSession = PlaceholderAuthSession(authState: authState)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        return (environment, authSession)
    }
}

private final class RecoverableSignedOutAuthSession: AuthSession, OfflineAccessRestoring {
    let accessToken: String? = nil
    let userId: String? = nil
    let authState: AuthState = .signedOut
    let pendingVerificationEmail: String? = nil
    let canRestoreOfflineSession = true

    var authorizationToken: String? {
        nil
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
    }

    func restoreOfflineSession() -> Bool {
        true
    }
}
