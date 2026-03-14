#if os(iOS)
import Foundation

@available(iOS 26.0, *)
struct NoteFormattingBarConfiguration {
    let isBoldActive: Bool
    let isItalicActive: Bool
    let isUnderlineActive: Bool
    let isStrikethroughActive: Bool
    let isInlineCodeActive: Bool
    let isEnabled: Bool
    let onBoldTap: @MainActor @Sendable () -> Void
    let onItalicTap: @MainActor @Sendable () -> Void
    let onUnderlineTap: @MainActor @Sendable () -> Void
    let onStrikethroughTap: @MainActor @Sendable () -> Void
    let onInlineCodeTap: @MainActor @Sendable () -> Void

    init(
        isBoldActive: Bool,
        isItalicActive: Bool,
        isUnderlineActive: Bool,
        isStrikethroughActive: Bool,
        isInlineCodeActive: Bool = false,
        isEnabled: Bool,
        onBoldTap: @escaping @MainActor @Sendable () -> Void,
        onItalicTap: @escaping @MainActor @Sendable () -> Void,
        onUnderlineTap: @escaping @MainActor @Sendable () -> Void,
        onStrikethroughTap: @escaping @MainActor @Sendable () -> Void,
        onInlineCodeTap: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.isBoldActive = isBoldActive
        self.isItalicActive = isItalicActive
        self.isUnderlineActive = isUnderlineActive
        self.isStrikethroughActive = isStrikethroughActive
        self.isInlineCodeActive = isInlineCodeActive
        self.isEnabled = isEnabled
        self.onBoldTap = onBoldTap
        self.onItalicTap = onItalicTap
        self.onUnderlineTap = onUnderlineTap
        self.onStrikethroughTap = onStrikethroughTap
        self.onInlineCodeTap = onInlineCodeTap
    }

    static let disabled = NoteFormattingBarConfiguration(
        isBoldActive: false,
        isItalicActive: false,
        isUnderlineActive: false,
        isStrikethroughActive: false,
        isEnabled: false,
        onBoldTap: {},
        onItalicTap: {},
        onUnderlineTap: {},
        onStrikethroughTap: {}
    )

    func isActive(_ formatting: NoteFormatting) -> Bool {
        switch formatting {
        case .bold:
            return isBoldActive
        case .italic:
            return isItalicActive
        case .underline:
            return isUnderlineActive
        case .strikethrough:
            return isStrikethroughActive
        case .inlineCode:
            return isInlineCodeActive
        }
    }

    func tapHandler(for formatting: NoteFormatting) -> @MainActor @Sendable () -> Void {
        switch formatting {
        case .bold:
            return onBoldTap
        case .italic:
            return onItalicTap
        case .underline:
            return onUnderlineTap
        case .strikethrough:
            return onStrikethroughTap
        case .inlineCode:
            return onInlineCodeTap
        }
    }
}
#endif
