import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModel {
    func noteFormattingBarConfiguration(
        for nativeEditorViewModel: NativeNoteEditorViewModel?
    ) -> NoteFormattingBarConfiguration {
        .init(
            activeTextStyle: activeTextStyle(nativeEditorViewModel),
            isTextStyleSectionEnabled: isTextStyleSectionEnabled(nativeEditorViewModel),
            isBodyTextStyleEnabled: canApplyTextStyle(.body, nativeEditorViewModel),
            isTitleTextStyleEnabled: canApplyTextStyle(.title, nativeEditorViewModel),
            isHeadingTextStyleEnabled: canApplyTextStyle(.heading, nativeEditorViewModel),
            isSubheadingTextStyleEnabled: canApplyTextStyle(.subheading, nativeEditorViewModel),
            isBoldActive: isFormattingActive(.bold, nativeEditorViewModel),
            isItalicActive: isFormattingActive(.italic, nativeEditorViewModel),
            isUnderlineActive: isFormattingActive(.underline, nativeEditorViewModel),
            isStrikethroughActive: isFormattingActive(.strikethrough, nativeEditorViewModel),
            isInlineCodeActive: isFormattingActive(.inlineCode, nativeEditorViewModel),
            isCodeBlockActive: isCodeBlockActive(nativeEditorViewModel),
            isCodeBlockEnabled: canApplyCodeBlock(nativeEditorViewModel),
            isUnorderedListActive: isListActive(.unorderedList, nativeEditorViewModel),
            isUnorderedListEnabled: canApplyList(.unorderedList, nativeEditorViewModel),
            isOrderedListActive: isListActive(.orderedList, nativeEditorViewModel),
            isOrderedListEnabled: canApplyList(.orderedList, nativeEditorViewModel),
            isChecklistActive: isListActive(.checklist, nativeEditorViewModel),
            isChecklistEnabled: canApplyList(.checklist, nativeEditorViewModel),
            isBlockquoteActive: isListActive(.blockquote, nativeEditorViewModel),
            isBlockquoteEnabled: canApplyList(.blockquote, nativeEditorViewModel),
            isDividerActive: isDividerActive(nativeEditorViewModel),
            isDividerEnabled: canInsertDivider(nativeEditorViewModel),
            isEnabled: canApplyFormattingCommands(nativeEditorViewModel),
            onTextStyleSelection: { [weak self] in self?.setTextStyle($0) },
            onBoldTap: { [weak self] in self?.toggleFormatting(.bold) },
            onItalicTap: { [weak self] in self?.toggleFormatting(.italic) },
            onUnderlineTap: { [weak self] in self?.toggleFormatting(.underline) },
            onStrikethroughTap: { [weak self] in self?.toggleFormatting(.strikethrough) },
            onInlineCodeTap: { [weak self] in self?.toggleFormatting(.inlineCode) },
            onCodeBlockTap: { [weak self] in self?.toggleCodeBlock() },
            onUnorderedListTap: { [weak self] in self?.toggleList(.unorderedList) },
            onOrderedListTap: { [weak self] in self?.toggleList(.orderedList) },
            onChecklistTap: { [weak self] in self?.toggleList(.checklist) },
            onBlockquoteTap: { [weak self] in self?.toggleList(.blockquote) },
            onDividerTap: { [weak self] in self?.insertDivider() },
            onTitleShortcut: { [weak self] in self?.setTextStyle(.title) },
            onHeadingShortcut: { [weak self] in self?.setTextStyle(.heading) },
            onSubheadingShortcut: { [weak self] in self?.setTextStyle(.subheading) },
            onBodyShortcut: { [weak self] in self?.setTextStyle(.body) }
        )
    }

    public func canApplyFormattingCommands() -> Bool {
        canApplyFormattingCommands(attachedNativeEditorViewModel)
    }

    func canApplyFormattingCommands(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        currentNoteId != nil && nativeEditorViewModel != nil && !isReadOnly && isEditingNote
    }

    public func isFormattingActive(_ formatting: NoteFormatting) -> Bool {
        isFormattingActive(formatting, attachedNativeEditorViewModel)
    }

    func isFormattingActive(
        _ formatting: NoteFormatting,
        _ nativeEditorViewModel: NativeNoteEditorViewModel?
    ) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
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
        activeTextStyle(attachedNativeEditorViewModel)
    }

    func activeTextStyle(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> NoteTextStyle {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return .body }
        return nativeEditorViewModel.activeTextStyle()
    }

    public func isTextStyleSectionEnabled() -> Bool {
        isTextStyleSectionEnabled(attachedNativeEditorViewModel)
    }

    func isTextStyleSectionEnabled(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.isTextStyleSectionEnabled()
    }

    public func canApplyTextStyle(_ style: NoteTextStyle) -> Bool {
        canApplyTextStyle(style, attachedNativeEditorViewModel)
    }

    func canApplyTextStyle(
        _ style: NoteTextStyle,
        _ nativeEditorViewModel: NativeNoteEditorViewModel?
    ) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.canApplyTextStyle(style)
    }

    public func isCodeBlockActive() -> Bool {
        isCodeBlockActive(attachedNativeEditorViewModel)
    }

    func isCodeBlockActive(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.isCodeBlockActive()
    }

    public func canApplyCodeBlock() -> Bool {
        canApplyCodeBlock(attachedNativeEditorViewModel)
    }

    func canApplyCodeBlock(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.canApplyCodeBlock()
    }

    public func isDividerActive() -> Bool {
        isDividerActive(attachedNativeEditorViewModel)
    }

    func isDividerActive(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.isDividerActive()
    }

    public func canInsertDivider() -> Bool {
        canInsertDivider(attachedNativeEditorViewModel)
    }

    func canInsertDivider(_ nativeEditorViewModel: NativeNoteEditorViewModel?) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.canInsertDivider()
    }

    public func isListActive(_ listType: NotesSemanticDocument.BlockType) -> Bool {
        isListActive(listType, attachedNativeEditorViewModel)
    }

    func isListActive(
        _ listType: NotesSemanticDocument.BlockType,
        _ nativeEditorViewModel: NativeNoteEditorViewModel?
    ) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.isListActive(listType)
    }

    public func canApplyList(_ listType: NotesSemanticDocument.BlockType) -> Bool {
        canApplyList(listType, attachedNativeEditorViewModel)
    }

    func canApplyList(
        _ listType: NotesSemanticDocument.BlockType,
        _ nativeEditorViewModel: NativeNoteEditorViewModel?
    ) -> Bool {
        guard let nativeEditorViewModel,
              canApplyFormattingCommands(nativeEditorViewModel) else { return false }
        return nativeEditorViewModel.canApplyList(listType)
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

    public func toggleCodeBlock() {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.toggleCodeBlock()
        finalizeNativeEditorMutation(
            nativeEditorViewModel,
            previousContent: previousContent,
            previousSelection: previousSelection
        )
    }

    public func toggleList(_ listType: NotesSemanticDocument.BlockType) {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.toggleList(listType)
        finalizeNativeEditorMutation(
            nativeEditorViewModel,
            previousContent: previousContent,
            previousSelection: previousSelection
        )
    }

    public func insertDivider() {
        guard let nativeEditorViewModel = attachedNativeEditorViewModel,
              canApplyFormattingCommands() else { return }
        let previousContent = nativeEditorViewModel.attributedContent
        let previousSelection = nativeEditorViewModel.selection
        nativeEditorViewModel.insertDivider()
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
        noteFormattingBarConfiguration(for: attachedNativeEditorViewModel)
    }
}
