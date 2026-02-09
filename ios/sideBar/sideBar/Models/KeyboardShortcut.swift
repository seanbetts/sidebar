#if os(iOS)
import UIKit

/// Represents a keyboard shortcut struct.
public struct KeyboardShortcut: Identifiable, Hashable {
    /// The id value.
    public let id: String
    /// The input value.
    public let input: String
    /// The modifiers value.
    public let modifiers: UIKeyModifierFlags
    /// The title value.
    public let title: String
    /// The description value.
    public let description: String
    /// The action value.
    public let action: ShortcutAction
    /// The contexts value.
    public let contexts: Set<ShortcutContext>

    public init(
        input: String,
        modifiers: UIKeyModifierFlags = .command,
        title: String,
        description: String,
        action: ShortcutAction,
        contexts: Set<ShortcutContext>
    ) {
        self.input = input
        self.modifiers = modifiers
        self.title = title
        self.description = description
        self.action = action
        self.contexts = contexts
        self.id = "\(input)|\(modifiers.rawValue)|\(title)"
    }

    /// The symbol value.
    public var symbol: String {
        let modifierSymbols: [String] = [
            modifiers.contains(.control) ? "⌃" : nil,
            modifiers.contains(.alternate) ? "⌥" : nil,
            modifiers.contains(.shift) ? "⇧" : nil,
            modifiers.contains(.command) ? "⌘" : nil
        ].compactMap { $0 }

        let keySymbol: String
        switch input {
        case UIKeyCommand.inputUpArrow:
            keySymbol = "↑"
        case UIKeyCommand.inputDownArrow:
            keySymbol = "↓"
        case UIKeyCommand.inputLeftArrow:
            keySymbol = "←"
        case UIKeyCommand.inputRightArrow:
            keySymbol = "→"
        case UIKeyCommand.inputEscape:
            keySymbol = "⎋"
        case UIKeyCommand.inputDelete:
            keySymbol = "⌫"
        case "\r":
            keySymbol = "↩"
        case " ":
            keySymbol = "Space"
        default:
            keySymbol = input.uppercased()
        }
        return (modifierSymbols + [keySymbol]).joined()
    }

    /// The key signature value.
    public var keySignature: String {
        "\(input)|\(modifiers.rawValue)"
    }

    public static func == (lhs: KeyboardShortcut, rhs: KeyboardShortcut) -> Bool {
        lhs.input == rhs.input
            && lhs.modifiers.rawValue == rhs.modifiers.rawValue
            && lhs.title == rhs.title
            && lhs.description == rhs.description
            && lhs.action == rhs.action
            && lhs.contexts == rhs.contexts
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(input)
        hasher.combine(modifiers.rawValue)
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(action)
        hasher.combine(contexts)
    }
}
#endif
