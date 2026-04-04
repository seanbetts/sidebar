import Foundation

@available(iOS 26.0, macOS 26.0, *)
struct NoteFormattingBarConfiguration {
    let activeTextStyle: NoteTextStyle
    let isTextStyleSectionEnabled: Bool
    let isBodyTextStyleEnabled: Bool
    let isTitleTextStyleEnabled: Bool
    let isHeadingTextStyleEnabled: Bool
    let isSubheadingTextStyleEnabled: Bool
    let isBoldActive: Bool
    let isItalicActive: Bool
    let isUnderlineActive: Bool
    let isStrikethroughActive: Bool
    let isInlineCodeActive: Bool
    let isCodeBlockActive: Bool
    let isCodeBlockEnabled: Bool
    let isUnorderedListActive: Bool
    let isUnorderedListEnabled: Bool
    let isOrderedListActive: Bool
    let isOrderedListEnabled: Bool
    let isChecklistActive: Bool
    let isChecklistEnabled: Bool
    let isBlockquoteActive: Bool
    let isBlockquoteEnabled: Bool
    let isEnabled: Bool
    let onTextStyleSelection: @MainActor @Sendable (NoteTextStyle) -> Void
    let onBoldTap: @MainActor @Sendable () -> Void
    let onItalicTap: @MainActor @Sendable () -> Void
    let onUnderlineTap: @MainActor @Sendable () -> Void
    let onStrikethroughTap: @MainActor @Sendable () -> Void
    let onInlineCodeTap: @MainActor @Sendable () -> Void
    let onCodeBlockTap: @MainActor @Sendable () -> Void
    let onUnorderedListTap: @MainActor @Sendable () -> Void
    let onOrderedListTap: @MainActor @Sendable () -> Void
    let onChecklistTap: @MainActor @Sendable () -> Void
    let onBlockquoteTap: @MainActor @Sendable () -> Void
    let onTitleShortcut: @MainActor @Sendable () -> Void
    let onHeadingShortcut: @MainActor @Sendable () -> Void
    let onSubheadingShortcut: @MainActor @Sendable () -> Void
    let onBodyShortcut: @MainActor @Sendable () -> Void

    init(
        activeTextStyle: NoteTextStyle = .body,
        isTextStyleSectionEnabled: Bool = false,
        isBodyTextStyleEnabled: Bool = false,
        isTitleTextStyleEnabled: Bool = false,
        isHeadingTextStyleEnabled: Bool = false,
        isSubheadingTextStyleEnabled: Bool = false,
        isBoldActive: Bool,
        isItalicActive: Bool,
        isUnderlineActive: Bool,
        isStrikethroughActive: Bool,
        isInlineCodeActive: Bool = false,
        isCodeBlockActive: Bool = false,
        isCodeBlockEnabled: Bool = false,
        isUnorderedListActive: Bool = false,
        isUnorderedListEnabled: Bool = false,
        isOrderedListActive: Bool = false,
        isOrderedListEnabled: Bool = false,
        isChecklistActive: Bool = false,
        isChecklistEnabled: Bool = false,
        isBlockquoteActive: Bool = false,
        isBlockquoteEnabled: Bool = false,
        isEnabled: Bool,
        onTextStyleSelection: @escaping @MainActor @Sendable (NoteTextStyle) -> Void = { _ in },
        onBoldTap: @escaping @MainActor @Sendable () -> Void,
        onItalicTap: @escaping @MainActor @Sendable () -> Void,
        onUnderlineTap: @escaping @MainActor @Sendable () -> Void,
        onStrikethroughTap: @escaping @MainActor @Sendable () -> Void,
        onInlineCodeTap: @escaping @MainActor @Sendable () -> Void = {},
        onCodeBlockTap: @escaping @MainActor @Sendable () -> Void = {},
        onUnorderedListTap: @escaping @MainActor @Sendable () -> Void = {},
        onOrderedListTap: @escaping @MainActor @Sendable () -> Void = {},
        onChecklistTap: @escaping @MainActor @Sendable () -> Void = {},
        onBlockquoteTap: @escaping @MainActor @Sendable () -> Void = {},
        onTitleShortcut: @escaping @MainActor @Sendable () -> Void = {},
        onHeadingShortcut: @escaping @MainActor @Sendable () -> Void = {},
        onSubheadingShortcut: @escaping @MainActor @Sendable () -> Void = {},
        onBodyShortcut: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.activeTextStyle = activeTextStyle
        self.isTextStyleSectionEnabled = isTextStyleSectionEnabled
        self.isBodyTextStyleEnabled = isBodyTextStyleEnabled
        self.isTitleTextStyleEnabled = isTitleTextStyleEnabled
        self.isHeadingTextStyleEnabled = isHeadingTextStyleEnabled
        self.isSubheadingTextStyleEnabled = isSubheadingTextStyleEnabled
        self.isBoldActive = isBoldActive
        self.isItalicActive = isItalicActive
        self.isUnderlineActive = isUnderlineActive
        self.isStrikethroughActive = isStrikethroughActive
        self.isInlineCodeActive = isInlineCodeActive
        self.isCodeBlockActive = isCodeBlockActive
        self.isCodeBlockEnabled = isCodeBlockEnabled
        self.isUnorderedListActive = isUnorderedListActive
        self.isUnorderedListEnabled = isUnorderedListEnabled
        self.isOrderedListActive = isOrderedListActive
        self.isOrderedListEnabled = isOrderedListEnabled
        self.isChecklistActive = isChecklistActive
        self.isChecklistEnabled = isChecklistEnabled
        self.isBlockquoteActive = isBlockquoteActive
        self.isBlockquoteEnabled = isBlockquoteEnabled
        self.isEnabled = isEnabled
        self.onTextStyleSelection = onTextStyleSelection
        self.onBoldTap = onBoldTap
        self.onItalicTap = onItalicTap
        self.onUnderlineTap = onUnderlineTap
        self.onStrikethroughTap = onStrikethroughTap
        self.onInlineCodeTap = onInlineCodeTap
        self.onCodeBlockTap = onCodeBlockTap
        self.onUnorderedListTap = onUnorderedListTap
        self.onOrderedListTap = onOrderedListTap
        self.onChecklistTap = onChecklistTap
        self.onBlockquoteTap = onBlockquoteTap
        self.onTitleShortcut = onTitleShortcut
        self.onHeadingShortcut = onHeadingShortcut
        self.onSubheadingShortcut = onSubheadingShortcut
        self.onBodyShortcut = onBodyShortcut
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

    func canApplyTextStyle(_ style: NoteTextStyle) -> Bool {
        guard isEnabled, isTextStyleSectionEnabled else { return false }
        switch style {
        case .body:
            return isBodyTextStyleEnabled
        case .title:
            return isTitleTextStyleEnabled
        case .heading:
            return isHeadingTextStyleEnabled
        case .subheading:
            return isSubheadingTextStyleEnabled
        }
    }

    func selectTextStyle(_ style: NoteTextStyle) {
        guard canApplyTextStyle(style) else { return }
        onTextStyleSelection(style)
    }
}
