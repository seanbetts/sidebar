import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteKeyboardShortcutKey {
    case bold
    case italic
    case underline
    case bulletList
}

@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteKeyboardShortcutAction: Equatable {
    case formatting(NoteFormatting)
}

@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteKeyboardShortcuts {
    private struct ShortcutBinding {
        let modifiers: EventModifiers
        let action: AttributedNoteKeyboardShortcutAction
    }

    private static let bindings: [AttributedNoteKeyboardShortcutKey: ShortcutBinding] = [
        .bold: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.bold)
        ),
        .italic: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.italic)
        ),
        .underline: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.underline)
        ),
        .bulletList: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.bulletList)
        )
    ]

    static func action(
        for key: AttributedNoteKeyboardShortcutKey,
        modifiers: EventModifiers
    ) -> AttributedNoteKeyboardShortcutAction? {
        guard let binding = bindings[key] else { return nil }
        guard matches(modifiers, expected: binding.modifiers) else { return nil }
        return binding.action
    }

    private static func matches(_ modifiers: EventModifiers, expected: EventModifiers) -> Bool {
        modifiers == expected
    }
}
