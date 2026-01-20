#if os(iOS)
import UIKit

public struct KeyboardShortcut: Identifiable, Hashable {
    public let id: String
    public let input: String
    public let modifiers: UIKeyModifierFlags
    public let title: String
    public let description: String
    public let action: ShortcutAction
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
