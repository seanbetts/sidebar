import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteKeyboardShortcutsTests: XCTestCase {
    func testInlineFormattingShortcutsMapToToolbarActions() {
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
            key: .strikethrough,
            modifiers: [.command, .shift],
            expected: .formatting(.strikethrough)
        )
        assertShortcut(
            key: .inlineCode,
            modifiers: [.command],
            expected: .formatting(.inlineCode)
        )
    }

    func testHeadingShortcutsMapToToolbarActions() {
        assertShortcut(
            key: .promoteHeading,
            modifiers: [.command],
            expected: .formatting(.promoteHeading)
        )
        assertShortcut(
            key: .demoteHeading,
            modifiers: [.command],
            expected: .formatting(.demoteHeading)
        )
    }

    func testBlockShortcutsMapToToolbarActions() {
        assertShortcut(
            key: .bulletList,
            modifiers: [.command, .shift],
            expected: .formatting(.bulletList)
        )
        assertShortcut(
            key: .orderedList,
            modifiers: [.command, .shift],
            expected: .formatting(.orderedList)
        )
        assertShortcut(
            key: .taskList,
            modifiers: [.command, .shift],
            expected: .formatting(.taskList)
        )
        assertShortcut(
            key: .blockquote,
            modifiers: [.command, .shift],
            expected: .formatting(.blockquote)
        )
        assertShortcut(
            key: .codeBlock,
            modifiers: [.command, .shift],
            expected: .formatting(.codeBlock)
        )
        assertShortcut(
            key: .horizontalRule,
            modifiers: [.command, .shift],
            expected: .formatting(.horizontalRule)
        )
    }

    func testCommandUSuppressesSystemUnderlineShortcut() {
        assertShortcut(
            key: .suppressUnderline,
            modifiers: [.command],
            expected: .suppressSystemUnderline
        )
    }

    func testShortcutsRequireExpectedModifierCombination() {
        assertNoShortcut(key: .bold, modifiers: [])
        assertNoShortcut(key: .bulletList, modifiers: [.command])
        assertNoShortcut(key: .horizontalRule, modifiers: [.command, .control])
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
