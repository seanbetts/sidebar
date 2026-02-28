import XCTest
@testable import sideBar

extension AppEnvironmentDeepLinkTests {
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

        await waitForShortcutActionEventToClear(environment)
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

    func testShortcutActionRouterOpenSettingsSetsCommandSelection() async {
        let environment = requireEnvironment()
        environment.commandSelection = nil

        let router = ShortcutActionRouter()
        router.handle(.openSettings, environment: environment)

        XCTAssertEqual(environment.commandSelection, .settings)
    }

    func testShortcutActionRouterNavigateSetsCommandSelection() async {
        let environment = requireEnvironment()
        environment.commandSelection = nil

        let router = ShortcutActionRouter()
        router.handle(.navigate(.files), environment: environment)

        XCTAssertEqual(environment.commandSelection, .files)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.files)
        )
    }

    func testShortcutActionRouterNewItemStartsTaskWhenTasksAreActive() async {
        let environment = requireEnvironment()
        environment.activeSection = .tasks
        environment.focusedSection = .tasks
        environment.tasksViewModel.cancelNewTask()

        let router = ShortcutActionRouter()
        router.handle(.newItem, environment: environment)

        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testShortcutActionRouterNewItemEmitsSectionEventForNotes() async {
        let environment = requireEnvironment()
        environment.activeSection = .notes
        environment.focusedSection = .notes

        let router = ShortcutActionRouter()
        router.handle(.newItem, environment: environment)

        XCTAssertEqual(environment.shortcutActionEvent?.action, .newItem)
        XCTAssertEqual(environment.shortcutActionEvent?.section, .notes)
    }
    #endif
}
