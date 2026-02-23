import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentDeepLinkTests: XCTestCase {
    private static var retainedEnvironments: [AppEnvironment] = []

    override func setUp() {
        super.setUp()
        clearWidgetPendingOperations()
        clearExtensionEvents()
        let environment = requireEnvironment()
        resetDeepLinkState(environment)
    }

    override func tearDown() {
        let environment = requireEnvironment()
        resetDeepLinkState(environment)
        clearWidgetPendingOperations()
        clearExtensionEvents()
        super.tearDown()
    }

    func testHandleNotesNewDeepLinkSetsPendingFlagAndSelection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://notes/new")!)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testHandleTasksNewDeepLinkWhenNotFocusedSetsPendingFlag() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
    }

    func testHandleTasksNewDeepLinkWhenFocusedStartsNewTaskImmediately() async {
        let environment = requireEnvironment()
        environment.isTasksFocused = true

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testHandleTasksTodayDeepLinkSelectsTasksSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://tasks/today")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
    }

    func testHandleNotesRootDeepLinkSelectsNotesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://notes")!)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertFalse(environment.pendingNewNoteDeepLink)
    }

    func testHandleWebsitesRootDeepLinkSelectsWebsitesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://websites")!)

        XCTAssertEqual(environment.commandSelection, .websites)
    }

    func testHandleFilesRootDeepLinkSelectsFilesSection() async {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://files")!)

        XCTAssertEqual(environment.commandSelection, .files)
    }

    func testConsumeWidgetAddTaskStartsTaskImmediatelyWhenTasksFocused() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.isTasksFocused = true

        let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .tasks)

        environment.consumeWidgetAddTask()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testConsumeWidgetCompletionsPreservesPendingAddTaskOperation() async {
        let environment = requireEnvironment()

        WidgetDataManager.shared.recordPendingOperation(
            WidgetPendingOperation(itemId: "task-complete", action: TaskWidgetAction.complete),
            for: .tasks
        )
        WidgetDataManager.shared.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew),
            for: .tasks
        )

        // Signed out avoids any server completion sync while validating queue behavior.
        environment.authState = .signedOut
        await environment.consumeWidgetCompletions()

        environment.authState = .active
        environment.isTasksFocused = false
        environment.consumeWidgetAddTask()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
    }

    func testConsumeWidgetAddNoteSetsPendingFlagAndSelection() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .notes)

        environment.consumeWidgetAddNote()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testConsumeExtensionEventsWhenActiveShowsPendingWebsite() async {
        let environment = requireEnvironment()
        environment.authState = .active
        let url = "https://example.com/articles/\(UUID().uuidString)"

        ExtensionEventStore.shared.recordWebsiteSaved(url: url)
        await environment.consumeExtensionEvents()

        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testConsumeExtensionEventsWhenInactivePreservesEvents() async {
        let environment = requireEnvironment()
        let url = "https://www.youtube.com/watch?v=abc123xyzAA"

        environment.authState = .signedOut
        ExtensionEventStore.shared.recordWebsiteSaved(url: url)
        await environment.consumeExtensionEvents()
        XCTAssertNil(environment.websitesViewModel.pendingWebsite)

        environment.authState = .active
        await environment.consumeExtensionEvents()
        XCTAssertEqual(environment.websitesViewModel.pendingWebsite?.url, url)
    }

    func testRefreshAuthStateWhenSessionBecomesActiveConsumesExtensionEvents() {
        let previousSharedEnvironment = AppEnvironment.shared
        defer { AppEnvironment.shared = previousSharedEnvironment }

        let authSession = MutableAuthSession(authState: .stale)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        Self.retainedEnvironments.append(environment)
        resetDeepLinkState(environment)
        environment.authState = .stale

        let url = "https://example.com/articles/\(UUID().uuidString)"
        ExtensionEventStore.shared.recordWebsiteSaved(url: url)

        authSession.authState = .active
        environment.refreshAuthState()

        for _ in 0..<40 where environment.websitesViewModel.pendingWebsite?.url != url {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

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

    func testEmitShortcutActionUsesPlatformPreferredSectionWhenAvailable() async {
        let environment = requireEnvironment()
        environment.activeSection = .notes
        environment.focusedSection = .chat

        environment.emitShortcutAction(.deleteItem)

        #if os(iOS)
        XCTAssertEqual(environment.shortcutActionEvent?.section, .notes)
        #else
        XCTAssertEqual(environment.shortcutActionEvent?.section, .chat)
        #endif
    }

    func testEmitShortcutActionFallsBackToActiveSectionWhenNoFocusedSection() async {
        let environment = requireEnvironment()
        environment.activeSection = .notes
        environment.focusedSection = nil

        environment.emitShortcutAction(.deleteItem)

        XCTAssertEqual(environment.shortcutActionEvent?.section, .notes)
    }

    func testEmitShortcutActionClearsEventAfterBroadcast() async {
        let environment = requireEnvironment()
        environment.activeSection = .tasks
        environment.focusedSection = .tasks

        environment.emitShortcutAction(.newItem)
        XCTAssertEqual(environment.shortcutActionEvent?.action, .newItem)

        await Task.yield()
        await Task.yield()

        XCTAssertNil(environment.shortcutActionEvent)
    }

    func testActiveShortcutContextsPreferPlatformResolutionSection() async {
        let environment = requireEnvironment()
        environment.activeSection = .notes
        environment.focusedSection = .chat
        environment.isTasksFocused = true

        #if os(iOS)
        XCTAssertTrue(environment.activeShortcutContexts.contains(.notes))
        XCTAssertFalse(environment.activeShortcutContexts.contains(.chat))
        #else
        XCTAssertTrue(environment.activeShortcutContexts.contains(.chat))
        XCTAssertFalse(environment.activeShortcutContexts.contains(.notes))
        #endif
    }

    func testActiveShortcutContextsTreatSkillsStoreAsUniversal() async {
        let environment = requireEnvironment()
        environment.activeSection = .skillsStore
        environment.focusedSection = .chat

        #if os(iOS)
        XCTAssertEqual(environment.activeShortcutContexts, [.universal])
        #else
        XCTAssertTrue(environment.activeShortcutContexts.contains(.chat))
        XCTAssertFalse(environment.activeShortcutContexts.contains(.notes))
        #endif
    }

    #if os(iOS)
    func testShortcutActionRouterCloseItemUsesActiveSectionWhenFocusIsStale() async {
        let environment = requireEnvironment()
        environment.activeSection = .websites
        environment.focusedSection = .notes
        environment.websitesViewModel.selectedWebsiteId = "website-1"

        let router = ShortcutActionRouter()
        router.handle(.closeItem, environment: environment)

        XCTAssertNil(environment.websitesViewModel.selectedWebsiteId)
    }
    #endif

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
        environment.skillsStoreSelectedSkillId = "audio-transcribe"
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
            url: "https://example.com"
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
        XCTAssertNil(environment.commandSelection)
        XCTAssertNil(environment.activeSection)
        XCTAssertNil(environment.focusedSection)
        XCTAssertFalse(environment.isTasksFocused)
        XCTAssertNil(environment.shortcutActionEvent)
        XCTAssertEqual(environment.tasksViewModel.selection, .none)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
        XCTAssertEqual(environment.tasksViewModel.searchQuery, "")
        XCTAssertNil(environment.tasksPhoneDetailRouteId)
        XCTAssertNil(environment.skillsStoreSelectedSkillId)
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

    private func clearWidgetPendingOperations() {
        _ = WidgetDataManager.shared.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = WidgetDataManager.shared.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
    }

    private func clearExtensionEvents() {
        _ = ExtensionEventStore.shared.consumeEvents()
    }

    private func requireEnvironment(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        for _ in 0..<20 {
            if let environment = AppEnvironment.shared {
                return environment
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Expected shared app environment", file: file, line: line)
        return AppEnvironment.shared!
    }

    private func resetDeepLinkState(_ environment: AppEnvironment) {
        environment.authState = .signedOut
        environment.commandSelection = nil
        environment.focusedSection = nil
        environment.isTasksFocused = false
        environment.pendingNewTaskDeepLink = false
        environment.pendingNewNoteDeepLink = false
        environment.pendingScratchpadDeepLink = false
        environment.tasksPhoneDetailRouteId = nil
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
        environment.websitesViewModel.pendingWebsite = nil
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

    init(authState: AuthState) {
        self.authState = authState
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
