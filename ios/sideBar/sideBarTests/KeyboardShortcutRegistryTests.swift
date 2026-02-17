#if os(iOS)
import XCTest
import UIKit
@testable import sideBar

final class KeyboardShortcutRegistryTests: XCTestCase {
    func testNotesContextIncludesEscapeCloseShortcut() {
        let shortcuts = KeyboardShortcutRegistry.shared.shortcuts(for: [.universal, .notes])
        let escapeShortcuts = shortcuts.filter {
            $0.input == UIKeyCommand.inputEscape && $0.modifiers.isEmpty
        }

        XCTAssertEqual(escapeShortcuts.count, 1)
        XCTAssertEqual(escapeShortcuts.first?.action, .closeItem)
        XCTAssertEqual(escapeShortcuts.first?.contexts, [.notes])
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
