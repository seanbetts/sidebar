#if os(iOS)
import XCTest
import UIKit
@testable import sideBar

final class KeyboardShortcutRegistryTests: XCTestCase {
    func testUniversalNavigateShortcutsFollowPrimarySectionOrder() {
        var navigateByInput: [String: AppSection] = [:]
        for shortcut in KeyboardShortcutRegistry.shared.allShortcuts {
            guard case .navigate(let section) = shortcut.action else { continue }
            navigateByInput[shortcut.input] = section
        }

        XCTAssertEqual(navigateByInput["1"], .chat)
        XCTAssertEqual(navigateByInput["2"], .notes)
        XCTAssertEqual(navigateByInput["3"], .tasks)
        XCTAssertEqual(navigateByInput["4"], .websites)
        XCTAssertEqual(navigateByInput["5"], .files)
        XCTAssertEqual(navigateByInput["6"], .skillsStore)
        XCTAssertEqual(navigateByInput.count, AppSection.primaryNavigationSections.count)
    }

    func testNotesContextIncludesEscapeCloseShortcut() {
        let shortcuts = KeyboardShortcutRegistry.shared.shortcuts(for: [.universal, .notes])
        let escapeShortcuts = shortcuts.filter {
            $0.input == UIKeyCommand.inputEscape && $0.modifiers.isEmpty
        }

        XCTAssertEqual(escapeShortcuts.count, 1)
        XCTAssertEqual(escapeShortcuts.first?.action, .closeItem)
        XCTAssertEqual(escapeShortcuts.first?.contexts, [.notes])
    }

    func testChatContextIncludesEscapeCloseShortcut() {
        let shortcuts = KeyboardShortcutRegistry.shared.shortcuts(for: [.universal, .chat])
        let escapeShortcuts = shortcuts.filter {
            $0.input == UIKeyCommand.inputEscape && $0.modifiers.isEmpty
        }

        XCTAssertEqual(escapeShortcuts.count, 1)
        XCTAssertEqual(escapeShortcuts.first?.action, .closeItem)
        XCTAssertEqual(escapeShortcuts.first?.contexts, [.chat])
    }

    func testWebsitesContextIncludesEscapeCloseShortcut() {
        let shortcuts = KeyboardShortcutRegistry.shared.shortcuts(for: [.universal, .websites])
        let escapeShortcuts = shortcuts.filter {
            $0.input == UIKeyCommand.inputEscape && $0.modifiers.isEmpty
        }

        XCTAssertEqual(escapeShortcuts.count, 1)
        XCTAssertEqual(escapeShortcuts.first?.action, .closeItem)
        XCTAssertEqual(escapeShortcuts.first?.contexts, [.websites])
    }
}
#endif
