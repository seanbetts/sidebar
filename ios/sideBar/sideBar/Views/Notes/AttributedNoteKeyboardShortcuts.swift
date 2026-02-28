import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteKeyboardShortcutKey {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case promoteHeading
    case demoteHeading
    case orderedList
    case bulletList
    case taskList
    case blockquote
    case codeBlock
    case horizontalRule
    case suppressUnderline
}

@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteKeyboardShortcutAction: Equatable {
    case formatting(MarkdownFormatting)
    case suppressSystemUnderline
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
        .strikethrough: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.strikethrough)
        ),
        .inlineCode: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.inlineCode)
        ),
        .promoteHeading: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.promoteHeading)
        ),
        .demoteHeading: ShortcutBinding(
            modifiers: [.command],
            action: .formatting(.demoteHeading)
        ),
        .orderedList: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.orderedList)
        ),
        .bulletList: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.bulletList)
        ),
        .taskList: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.taskList)
        ),
        .blockquote: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.blockquote)
        ),
        .codeBlock: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.codeBlock)
        ),
        .horizontalRule: ShortcutBinding(
            modifiers: [.command, .shift],
            action: .formatting(.horizontalRule)
        ),
        .suppressUnderline: ShortcutBinding(
            modifiers: [.command],
            action: .suppressSystemUnderline
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
