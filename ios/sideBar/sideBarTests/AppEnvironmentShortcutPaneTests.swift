import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentShortcutPaneTests: XCTestCase {
    private static var retainedEnvironments: [AppEnvironment] = []

    func testEmitShortcutActionResolvesPrimaryPaneFromWorkspaceState() {
        let environment = makeEnvironment()
        environment.workspaceStore.dispatch(
            .setPrimaryContent(.builtIn(.notes)),
            source: "shortcut_pane_test"
        )
        environment.workspaceStore.dispatch(
            .setSecondaryContent(.builtIn(.chat)),
            source: "shortcut_pane_test"
        )
        environment.activeSection = .notes
        environment.focusedSection = nil
        environment.focusedWorkspacePane = nil

        environment.emitShortcutAction(.deleteItem)

        XCTAssertEqual(environment.shortcutActionEvent?.section, .notes)
        XCTAssertEqual(environment.shortcutActionEvent?.pane, .primary)
    }

    func testEmitShortcutActionPrefersFocusedPaneForDuplicateSection() {
        let environment = makeEnvironment()
        environment.workspaceStore.dispatch(
            .setPrimaryContent(.builtIn(.notes)),
            source: "shortcut_pane_test"
        )
        environment.workspaceStore.dispatch(
            .setSecondaryContent(.builtIn(.notes)),
            source: "shortcut_pane_test"
        )
        environment.activeSection = .notes
        environment.focusedSection = .notes
        environment.focusedWorkspacePane = .secondary

        environment.emitShortcutAction(.deleteItem)

        XCTAssertEqual(environment.shortcutActionEvent?.section, .notes)
        XCTAssertEqual(environment.shortcutActionEvent?.pane, .secondary)
    }

    func testNavigationResetClearsFocusedWorkspacePane() {
        let navigation = NavigationCoordinator()
        navigation.focusedWorkspacePane = .secondary

        navigation.resetForSignOut()

        XCTAssertNil(navigation.focusedWorkspacePane)
    }

    private func makeEnvironment() -> AppEnvironment {
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: ShortcutPaneAuthSession(),
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        Self.retainedEnvironments.append(environment)
        return environment
    }
}

private final class ShortcutPaneAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState = .signedOut

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
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
