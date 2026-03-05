import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteKeyboardShortcutsTests: XCTestCase {
    func testSupportedFormattingShortcutsMapToToolbarActions() {
        assertShortcut(
            key: .bold,
            modifiers: [.command],
            expected: .formatting(.bold)
        )
        assertShortcut(
            key: .italic,
            modifiers: [.command],
            expected: .formatting(.italic)
        )
        assertShortcut(
            key: .underline,
            modifiers: [.command],
            expected: .formatting(.underline)
        )
    }

    func testShortcutsRequireExpectedModifierCombination() {
        assertNoShortcut(key: .bold, modifiers: [])
        assertNoShortcut(key: .italic, modifiers: [.command, .shift])
        assertNoShortcut(key: .underline, modifiers: [.command, .control])
    }

    private func assertShortcut(
        key: AttributedNoteKeyboardShortcutKey,
        modifiers: EventModifiers,
        expected: AttributedNoteKeyboardShortcutAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            AttributedNoteKeyboardShortcuts.action(for: key, modifiers: modifiers),
            expected,
            file: file,
            line: line
        )
    }

    private func assertNoShortcut(
        key: AttributedNoteKeyboardShortcutKey,
        modifiers: EventModifiers,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(
            AttributedNoteKeyboardShortcuts.action(for: key, modifiers: modifiers),
            file: file,
            line: line
        )
    }
}
