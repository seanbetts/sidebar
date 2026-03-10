import XCTest
@testable import sideBar

@MainActor
extension AppEnvironmentDeepLinkTests {
    func testPresentMacSettingsTogglesDedicatedModalStateWithoutChangingWorkspaceSelection() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.routeWorkspaceSelection(to: .tasks, source: "test_setup")
        environment.activeSection = .tasks
        environment.focusedSection = .tasks

        environment.presentMacSettings()

        XCTAssertTrue(environment.isMacSettingsPresented)
        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertEqual(environment.activeSection, .tasks)
        XCTAssertEqual(environment.focusedSection, .settings)
        XCTAssertEqual(
            environment.workspaceStore.state.primaryPane.descriptor,
            .builtIn(.tasks)
        )

        environment.dismissMacSettings()

        XCTAssertFalse(environment.isMacSettingsPresented)
        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertEqual(environment.focusedSection, .tasks)
    }

    func testPresentMacSettingsWhenSignedOutDoesNothing() async {
        let environment = requireEnvironment()
        environment.authState = .signedOut
        environment.focusedSection = .notes

        environment.presentMacSettings()

        XCTAssertFalse(environment.isMacSettingsPresented)
        XCTAssertEqual(environment.focusedSection, .notes)
    }

    func testPresentMacSettingsRestoresPreviousFocusedSectionOnDismiss() async {
        let environment = requireEnvironment()
        environment.authState = .active
        environment.activeSection = .tasks
        environment.focusedSection = .notes

        environment.presentMacSettings()
        XCTAssertEqual(environment.focusedSection, .settings)

        environment.dismissMacSettings()

        XCTAssertEqual(environment.focusedSection, .notes)
    }

    func waitForShortcutActionEventToClear(
        _ environment: AppEnvironment,
        timeoutNanoseconds: UInt64 = 500_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if environment.shortcutActionEvent == nil {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        XCTAssertNil(
            environment.shortcutActionEvent,
            "Expected shortcut action event to clear after broadcast.",
            file: file,
            line: line
        )
    }
}
