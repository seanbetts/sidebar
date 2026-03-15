import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModel {
    public func canApplyFormattingCommands() -> Bool {
        currentNoteId != nil && attachedNativeEditorViewModel != nil && !isReadOnly && isEditingNote
    }

    public func isFormattingActive(_ formatting: NoteFormatting) -> Bool {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return false }
        return nativeEditorViewModel.isFormattingActive(formatting)
    }

    public func setFormatting(_ formatting: NoteFormatting, enabled: Bool) {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.setFormatting(formatting, enabled: enabled)
        finalizeNativeEditorMutation(
            nativeEditorViewModel,
            previousContent: previousContent,
            previousSelection: previousSelection
        )
    }

    public func toggleFormatting(_ formatting: NoteFormatting) {
        guard canApplyFormattingCommands() else { return }
        setFormatting(formatting, enabled: !isFormattingActive(formatting))
    }

    public func activeTextStyle() -> NoteTextStyle {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return .body }
        return nativeEditorViewModel.activeTextStyle()
    }

    public func isTextStyleSectionEnabled() -> Bool {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return false }
        return nativeEditorViewModel.isTextStyleSectionEnabled()
    }

    public func canApplyTextStyle(_ style: NoteTextStyle) -> Bool {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return false }
        return nativeEditorViewModel.canApplyTextStyle(style)
    }

    public func setTextStyle(_ style: NoteTextStyle) {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.setTextStyle(style)
        finalizeNativeEditorMutation(
            nativeEditorViewModel,
            previousContent: previousContent,
            previousSelection: previousSelection
        )
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModel {
    var noteFormattingBarConfiguration: NoteFormattingBarConfiguration {
        .init(
            activeTextStyle: activeTextStyle(),
            isTextStyleSectionEnabled: isTextStyleSectionEnabled(),
            isBodyTextStyleEnabled: canApplyTextStyle(.body),
            isTitleTextStyleEnabled: canApplyTextStyle(.title),
            isHeadingTextStyleEnabled: canApplyTextStyle(.heading),
            isSubheadingTextStyleEnabled: canApplyTextStyle(.subheading),
            isBoldActive: isFormattingActive(.bold),
            isItalicActive: isFormattingActive(.italic),
            isUnderlineActive: isFormattingActive(.underline),
            isStrikethroughActive: isFormattingActive(.strikethrough),
            isInlineCodeActive: isFormattingActive(.inlineCode),
            isEnabled: canApplyFormattingCommands(),
            onTextStyleSelection: { [weak self] in self?.setTextStyle($0) },
            onBoldTap: { [weak self] in self?.toggleFormatting(.bold) },
            onItalicTap: { [weak self] in self?.toggleFormatting(.italic) },
            onUnderlineTap: { [weak self] in self?.toggleFormatting(.underline) },
            onStrikethroughTap: { [weak self] in self?.toggleFormatting(.strikethrough) },
            onInlineCodeTap: { [weak self] in self?.toggleFormatting(.inlineCode) },
            onTitleShortcut: { [weak self] in self?.setTextStyle(.title) },
            onHeadingShortcut: { [weak self] in self?.setTextStyle(.heading) },
            onSubheadingShortcut: { [weak self] in self?.setTextStyle(.subheading) },
            onBodyShortcut: { [weak self] in self?.setTextStyle(.body) }
        )
    }
}
