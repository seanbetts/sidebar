#if os(macOS)
import XCTest
@testable import sideBar

final class MacWindowFramePersistenceTests: XCTestCase {
    func testGeneratedSwiftUIWindowFrameKeysAreClassifiedAsUnstable() {
        let defaultsDomain = [
            "NSWindow Frame SwiftUI.SceneBridgeReader-1-AppWindow-1": "-2830 233 2264 1276 -3360 -90 3360 1890 ",
            "NSWindow Frame SwiftUI.OtherWindow-1-AppWindow-1": "-2307 216 2009 1477 -3360 -90 3360 1890 ",
            "NSWindow Frame main": "583 213 2344 1426 0 0 3200 1800 ",
            "sideBar.didRequestBadgePermission": true
        ] as [String : Any]

        XCTAssertEqual(
            MacWindowFramePersistence.unstableGeneratedFrameKeys(in: defaultsDomain).sorted(),
            [
                "NSWindow Frame SwiftUI.OtherWindow-1-AppWindow-1",
                "NSWindow Frame SwiftUI.SceneBridgeReader-1-AppWindow-1"
            ]
        )
    }

    func testGeneratedWindowFrameClassifierPreservesStableMainKey() {
        let defaultsDomain = [
            "NSWindow Frame main": "583 213 2344 1426 0 0 3200 1800 ",
            "NSWindow Frame com_apple_SwiftUI_Settings_window": "-1643 702 900 492 -3360 -90 3360 1890 "
        ] as [String : Any]

        XCTAssertEqual(
            MacWindowFramePersistence.unstableGeneratedFrameKeys(in: defaultsDomain),
            []
        )
    }

    func testWindowFrameNeedsRecenteringWhenItDoesNotIntersectAnyVisibleScreen() {
        let windowFrame = CGRect(x: -2280, y: 445, width: 1200, height: 820)
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        XCTAssertTrue(
            MacWindowFramePersistence.windowFrameNeedsRecentering(
                windowFrame,
                visibleScreenFrames: screens
            )
        )
    }

    func testWindowFrameDoesNotNeedRecenteringWhenItIntersectsVisibleScreen() {
        let windowFrame = CGRect(x: 120, y: 160, width: 1200, height: 820)
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        XCTAssertFalse(
            MacWindowFramePersistence.windowFrameNeedsRecentering(
                windowFrame,
                visibleScreenFrames: screens
            )
        )
    }

    func testWindowFrameNeedsPreferredScreenRelocationWhenRestoreMissedAndWindowIsOnOtherScreen() {
        let windowFrame = CGRect(x: -2280, y: 445, width: 1200, height: 820)
        let visibleScreens = [
            CGRect(x: -2560, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        XCTAssertTrue(
            MacWindowFramePersistence.windowFrameNeedsPreferredScreenRelocation(
                windowFrame,
                preferredVisibleScreenFrame: visibleScreens[1],
                visibleScreenFrames: visibleScreens,
                enforcePreferredScreen: true
            )
        )
    }

    func testWindowFrameDoesNotNeedPreferredScreenRelocationWhenPolicyIsNotEnforced() {
        let windowFrame = CGRect(x: -2280, y: 445, width: 1200, height: 820)
        let visibleScreens = [
            CGRect(x: -2560, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        XCTAssertFalse(
            MacWindowFramePersistence.windowFrameNeedsPreferredScreenRelocation(
                windowFrame,
                preferredVisibleScreenFrame: visibleScreens[1],
                visibleScreenFrames: visibleScreens,
                enforcePreferredScreen: false
            )
        )
    }

    func testCenteredFrameUsesVisibleScreenBounds() {
        let windowFrame = CGRect(x: -2280, y: 445, width: 1200, height: 820)
        let visibleScreenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let centered = MacWindowFramePersistence.centeredWindowFrame(
            for: windowFrame,
            in: visibleScreenFrame
        )

        XCTAssertEqual(centered.origin.x, 156, accuracy: 0.5)
        XCTAssertEqual(centered.origin.y, 81, accuracy: 0.5)
        XCTAssertEqual(centered.size.width, 1200, accuracy: 0.5)
        XCTAssertEqual(centered.size.height, 820, accuracy: 0.5)
    }

    func testPreferredVisibleScreenFrameForLateWindowRepairUsesScreenUnderMouse() {
        let visibleScreens = [
            CGRect(x: -2560, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        let preferred = MacWindowFramePersistence.preferredVisibleScreenFrameForLateWindowRepair(
            mouseLocation: CGPoint(x: 300, y: 400),
            screenFrames: visibleScreens,
            mainVisibleScreenFrame: visibleScreens[0]
        )

        XCTAssertEqual(preferred, visibleScreens[1])
    }

    func testPreferredVisibleScreenFrameForLateWindowRepairFallsBackToMainScreen() {
        let visibleScreens = [
            CGRect(x: -2560, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        ]

        let preferred = MacWindowFramePersistence.preferredVisibleScreenFrameForLateWindowRepair(
            mouseLocation: CGPoint(x: 5000, y: 5000),
            screenFrames: visibleScreens,
            mainVisibleScreenFrame: visibleScreens[1]
        )

        XCTAssertEqual(preferred, visibleScreens[1])
    }

    func testSavedWindowFrameIsNotRestoredWhenWindowIsAlreadyVisible() {
        XCTAssertFalse(
            MacWindowFramePersistence.shouldRestoreSavedWindowFrame(
                isVisible: true,
                isKeyWindow: false,
                isMainWindow: false
            )
        )
    }

    func testSavedWindowFrameIsNotRestoredWhenWindowIsAlreadyKeyOrMain() {
        XCTAssertFalse(
            MacWindowFramePersistence.shouldRestoreSavedWindowFrame(
                isVisible: false,
                isKeyWindow: true,
                isMainWindow: false
            )
        )
        XCTAssertFalse(
            MacWindowFramePersistence.shouldRestoreSavedWindowFrame(
                isVisible: false,
                isKeyWindow: false,
                isMainWindow: true
            )
        )
    }

    func testSavedWindowFrameIsRestoredForInactiveHiddenWindow() {
        XCTAssertTrue(
            MacWindowFramePersistence.shouldRestoreSavedWindowFrame(
                isVisible: false,
                isKeyWindow: false,
                isMainWindow: false
            )
        )
    }

    func testSavedWindowFrameParsesRectFromPersistentDomainString() {
        let suiteName = "MacWindowFramePersistenceTests.savedWindowFrameParsesRectFromPersistentDomainString"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.setPersistentDomain(
            [
                "NSWindow Frame main": "428 187 2344 1426 0 0 3200 1800 "
            ],
            forName: suiteName
        )

        let frame = MacWindowFramePersistence.savedWindowFrame(
            autosaveName: "main",
            defaults: defaults,
            bundleIdentifier: suiteName
        )

        XCTAssertEqual(frame, CGRect(x: 428, y: 187, width: 2344, height: 1426))
    }

    func testSavedWindowFrameReturnsNilWhenPersistentValueIsInvalid() {
        let suiteName = "MacWindowFramePersistenceTests.savedWindowFrameReturnsNilWhenPersistentValueIsInvalid"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.setPersistentDomain(
            [
                "NSWindow Frame main": "not a frame"
            ],
            forName: suiteName
        )

        let frame = MacWindowFramePersistence.savedWindowFrame(
            autosaveName: "main",
            defaults: defaults,
            bundleIdentifier: suiteName
        )

        XCTAssertNil(frame)
    }

    func testPersistWindowFrameHelperIsDefined() throws {
        let source = try macWindowFramePersistenceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(source.contains("staticfuncautosaveKey(forautosaveName:String)->String"))
        XCTAssertTrue(source.contains("staticfuncsavedWindowFrame("))
        XCTAssertTrue(source.contains("staticfuncrestoreSavedWindowFrameIfNeeded("))
        XCTAssertTrue(source.contains("window.setFrame(savedFrame,display:false)"))
        XCTAssertTrue(source.contains("staticfuncpersistWindowFrameIfNeeded("))
        XCTAssertTrue(source.contains("window.saveFrame(usingName:autosave)"))
        XCTAssertTrue(source.contains("window.setFrameAutosaveName(autosave)"))
        XCTAssertTrue(source.contains("staticfuncshouldRestoreSavedWindowFrame("))
    }
}

private func macWindowFramePersistenceSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("App")
        .appendingPathComponent("MacWindowFramePersistence.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read MacWindowFramePersistence.swift: \(error)", file: file, line: line)
        throw error
    }
}
#endif
