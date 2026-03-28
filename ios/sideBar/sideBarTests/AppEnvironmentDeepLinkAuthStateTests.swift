import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testRefreshAuthStateWhenSessionBecomesActiveConsumesExtensionEvents() async {
        let previousSharedEnvironment = AppEnvironment.shared
        defer { AppEnvironment.shared = previousSharedEnvironment }

        let authSession = MutableAuthSession(authState: .stale)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, storage: storage)
        retainedEnvironments.append(environment)
        resetDeepLinkState(environment)
        environment.authState = .stale

        let url = "https://example.com/articles/\(UUID().uuidString)"
        storage.extensionEventStore.recordWebsiteSaved(url: url)

        authSession.authState = .active
        environment.refreshAuthState()

        await waitForWebsiteEventSurface(url, in: environment)

        XCTAssertEqual(environment.authState, .active)
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testRefreshAuthStateOnSignOutResetsNavigationViewModelsAndOfflineSnapshots() async {
        let environment = requireEnvironment()
        await environment.container.authSession.signOut()
        primeEnvironmentForSignOutReset(environment)

        environment.refreshAuthState()

        assertAuthAndNavigationStateCleared(environment)
        assertFeatureStateCleared(environment)
        assertStorageStateCleared(environment)
    }

    private func primeEnvironmentForSignOutReset(_ environment: AppEnvironment) {
        environment.authState = .active
        environment.commandSelection = .tasks
        environment.activeSection = .chat
        environment.focusedSection = .files
        environment.shortcutActionEvent = ShortcutActionEvent(action: .openSettings, section: .settings)
        environment.isTasksFocused = true
        environment.pendingNewTaskDeepLink = true
        environment.pendingNewNoteDeepLink = true
        environment.pendingScratchpadDeepLink = true
        environment.tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
        environment.tasksViewModel.updateSearch(query: "follow up")
        environment.tasksViewModel.startNewTask()
        environment.notesViewModel.updateSearch(query: "project")
        environment.websitesViewModel.selectedWebsiteId = "website-1"
        environment.websitesViewModel.panelSearchQuery = "example.com"
        environment.websitesViewModel.errorMessage = "website error"
        environment.websitesViewModel.saveErrorMessage = "save error"
        environment.websitesViewModel.pendingWebsite = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-1",
            title: "Example",
            domain: "example.com",
            url: "https://example.com",
            canonicalURL: "https://example.com",
            source: .directSave
        )
        environment.ingestionViewModel.selectedFileId = "file-1"
        environment.ingestionViewModel.selectedDerivativeKind = "text_original"
        environment.ingestionViewModel.panelSearchQuery = "invoice"
        environment.ingestionViewModel.errorMessage = "ingestion error"
        environment.chatViewModel.selectedConversationId = "conversation-1"
        environment.chatViewModel.messages = [
            Message(
                id: "message-1",
                role: .assistant,
                content: "hi",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-01T00:00:00Z",
                error: nil
            )
        ]
        environment.container.cacheClient.set(
            key: "tests.signout.cache",
            value: SignOutPayload(value: "cache"),
            ttlSeconds: 60
        )
        environment.offlineStore.set(
            key: "tests.signout.reset",
            entityType: "test",
            value: SignOutPayload(value: "value"),
            lastSyncAt: nil
        )
    }

    private func assertAuthAndNavigationStateCleared(_ environment: AppEnvironment) {
        XCTAssertEqual(environment.authState, .signedOut)
        XCTAssertFalse(environment.isAuthenticated)
        XCTAssertFalse(environment.isMacSettingsPresented)
        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.activeSection)
        XCTAssertNil(environment.focusedSection)
        XCTAssertFalse(environment.isTasksFocused)
        XCTAssertNil(environment.shortcutActionEvent)
        XCTAssertEqual(environment.tasksViewModel.selection, .none)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
        XCTAssertEqual(environment.tasksViewModel.searchQuery, "")
        XCTAssertNil(environment.tasksPhoneDetailRouteId)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertFalse(environment.pendingNewNoteDeepLink)
        XCTAssertFalse(environment.pendingScratchpadDeepLink)
    }

    private func assertFeatureStateCleared(_ environment: AppEnvironment) {
        XCTAssertNil(environment.chatViewModel.selectedConversationId)
        XCTAssertTrue(environment.chatViewModel.messages.isEmpty)
        XCTAssertEqual(environment.notesViewModel.searchQuery, "")
        XCTAssertNil(environment.websitesViewModel.selectedWebsiteId)
        XCTAssertEqual(environment.websitesViewModel.panelSearchQuery, "")
        XCTAssertNil(environment.websitesViewModel.errorMessage)
        XCTAssertNil(environment.websitesViewModel.saveErrorMessage)
        XCTAssertNil(environment.websitesViewModel.pendingWebsite)
        XCTAssertNil(environment.ingestionViewModel.selectedFileId)
        XCTAssertNil(environment.ingestionViewModel.selectedDerivativeKind)
        XCTAssertEqual(environment.ingestionViewModel.panelSearchQuery, "")
        XCTAssertNil(environment.ingestionViewModel.errorMessage)
    }

    private func assertStorageStateCleared(_ environment: AppEnvironment) {
        let cachedPayload: SignOutPayload? = environment.container.cacheClient.get(key: "tests.signout.cache")
        XCTAssertNil(cachedPayload)
        let payload: SignOutPayload? = environment.offlineStore.get(
            key: "tests.signout.reset",
            as: SignOutPayload.self
        )
        XCTAssertNil(payload)
    }
}

private struct SignOutPayload: Codable, Equatable {
    let value: String
}

private final class MutableAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(authState: AuthState) {
        self.authState = authState
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {}

    func refreshSessionIfStale() async {}

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
