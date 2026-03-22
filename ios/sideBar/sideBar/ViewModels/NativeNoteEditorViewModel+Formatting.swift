@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private struct ReturnKeyMutation {
        let document: NotesSemanticDocument
        let insertionOffset: Int
        let typingBlockType: NotesSemanticDocument.BlockType
    }

    struct InlineFormattingState: Equatable {
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var strikethrough: Bool = false
        var inlineCode: Bool = false

        static let plain = InlineFormattingState()

        func contains(_ formatting: NoteFormatting) -> Bool {
            switch formatting {
            case .bold:
                return bold
            case .italic:
                return italic
            case .underline:
                return underline
            case .strikethrough:
                return strikethrough
            case .inlineCode:
                return inlineCode
            }
        }

        mutating func set(_ formatting: NoteFormatting, enabled: Bool) {
            switch formatting {
            case .bold:
                bold = enabled
            case .italic:
                italic = enabled
            case .underline:
                underline = enabled
            case .strikethrough:
                strikethrough = enabled
            case .inlineCode:
                inlineCode = enabled
            }
        }
    }

    func constrainedEditorDocument(from source: AttributedString) -> AttributedString {
        var normalized = source
        constrainEditorDocument(&normalized)
        return normalized
    }

    func constrainEditorDocument(_ text: inout AttributedString) {
        NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&text)
    }

    func isFormattingActive(_ formatting: NoteFormatting) -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            return inlineFormattingState(
                from: typingAttributesForInsertion(in: attributedContent)
            ).contains(formatting)
        }

        return nonEmptyRanges.allSatisfy { range in
            rangeHasFormatting(range, formatting: formatting)
        }
    }

    func setFormatting(_ formatting: NoteFormatting, enabled: Bool) {
        guard !isReadOnly else { return }
        applyFormattingMutation(formatting, enabled: enabled)
    }

    func activeTextStyleAtSelectionStart() -> NoteTextStyle {
        let document = currentPersistenceSnapshot().document
        guard let blockType = semanticBlockTypeAtSelectionStart(in: document),
              let style = NoteTextStyle(blockType: blockType) else {
            return .body
        }
        return style
    }

    func isTextStyleSectionEnabled() -> Bool {
        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        guard !touchedBlocks.isEmpty else { return false }
        return touchedBlocks.allSatisfy { NoteTextStyle(blockType: $0.block.type) != nil }
    }

    func isCodeBlockActive() -> Bool {
        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        guard !touchedBlocks.isEmpty else { return false }
        return touchedBlocks.allSatisfy { $0.block.type == .codeBlock }
    }

    func canApplyCodeBlock() -> Bool {
        guard !isReadOnly else { return false }
        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        guard !touchedBlocks.isEmpty else { return false }
        return touchedBlocks.allSatisfy(canToggleCodeBlock(for:))
    }

    func canApplyTextStyle(_ style: NoteTextStyle) -> Bool {
        guard !isReadOnly else { return false }
        guard isTextStyleSectionEnabled() else { return false }
        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        guard !touchedBlocks.isEmpty else { return false }
        if touchedBlocks.contains(where: { $0.index == 0 }) {
            return style == .title
        }
        return true
    }

    func semanticBlockTypeAtSelectionStart(
        in document: NotesSemanticDocument
    ) -> NotesSemanticDocument.BlockType? {
        blockInfoContainingSelectionStart(in: document)?.block.type
    }

    func setTextStyle(_ style: NoteTextStyle) {
        guard canApplyTextStyle(style) else { return }

        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var didMutate = false
        var updatedBlocks = document.blocks

        for blockInfo in touchedBlocks {
            let block = updatedBlocks[blockInfo.index]
            guard block.type != style.blockType else { continue }
            updatedBlocks[blockInfo.index] = .init(
                type: style.blockType,
                content: block.content,
                checked: block.checked
            )
            didMutate = true
        }

        guard didMutate else { return }

        let updatedDocument = NotesSemanticDocument(
            version: document.version,
            blocks: updatedBlocks
        )

        var updatedContent = NotesAttributedDocumentCodec.attributedString(
            from: updatedDocument,
            baseFontSize: baseFontSize
        )
        constrainEditorDocument(&updatedContent)
        requestViewportPreservationOnNextProgrammaticRender()
        attributedContent = updatedContent
        selection = selection(from: selectionSnapshot, in: updatedContent)
    }

    func toggleCodeBlock() {
        guard canApplyCodeBlock() else { return }

        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        let targetType: NotesSemanticDocument.BlockType = isCodeBlockActive() ? .paragraph : .codeBlock
        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var didMutate = false
        var updatedBlocks = document.blocks

        for blockInfo in touchedBlocks {
            let block = updatedBlocks[blockInfo.index]
            guard block.type != targetType else { continue }
            updatedBlocks[blockInfo.index] = .init(
                type: targetType,
                content: block.content,
                checked: block.checked
            )
            didMutate = true
        }

        guard didMutate else { return }

        let updatedDocument = NotesSemanticDocument(
            version: document.version,
            blocks: updatedBlocks
        )

        var updatedContent = NotesAttributedDocumentCodec.attributedString(
            from: updatedDocument,
            baseFontSize: baseFontSize
        )
        constrainEditorDocument(&updatedContent)
        requestViewportPreservationOnNextProgrammaticRender()
        attributedContent = updatedContent
        selection = selection(from: selectionSnapshot, in: updatedContent)
    }

    func toggleFormatting(_ formatting: NoteFormatting) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let enabled = !inlineFormattingState(
                from: typingAttributesForInsertion(in: attributedContent)
            ).contains(formatting)
            applyFormattingMutation(formatting, enabled: enabled)
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            !rangeHasFormatting(range, formatting: formatting)
        }
        applyFormattingMutation(formatting, enabled: shouldEnable)
    }

    private func applyFormattingMutation(
        _ formatting: NoteFormatting,
        enabled: Bool
    ) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        let fallbackBlockType = blockInfoContainingSelectionStart(
            in: currentPersistenceSnapshot().document
        )?.block.type ?? .paragraph
        guard !nonEmptyRanges.isEmpty else {
            transformSelectionAttributes { attrs in
                var state = inlineFormattingState(from: attrs)
                state.set(formatting, enabled: enabled)
                let blockType = NoteTextBlockResolution.resolvedBlockType(
                    explicitRawValue: attrs.noteBlock,
                    semanticFallback: fallbackBlockType
                ) ?? fallbackBlockType
                applySemanticTypingAttributes(
                    blockType: blockType,
                    inlineState: state,
                    to: &attrs
                )
            }
            return
        }

        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var updatedSelection = selection
        requestViewportPreservationOnNextProgrammaticRender()
        attributedContent.transformAttributes(in: &updatedSelection) { attrs in
            var state = inlineFormattingState(from: attrs)
            state.set(formatting, enabled: enabled)
            let blockType = NoteTextBlockResolution.resolvedBlockType(
                explicitRawValue: attrs.noteBlock,
                semanticFallback: fallbackBlockType
            ) ?? fallbackBlockType
            applySemanticTypingAttributes(
                blockType: blockType,
                inlineState: state,
                to: &attrs
            )
        }
        selection = selection(from: selectionSnapshot, in: attributedContent)
    }

    private func rangeHasFormatting(
        _ range: Range<AttributedString.Index>,
        formatting: NoteFormatting
    ) -> Bool {
        let runSnapshots = formattingRunSnapshots(in: attributedContent, within: range)
        guard !runSnapshots.isEmpty else { return false }
        return runSnapshots.allSatisfy { $0.state.contains(formatting) }
    }

    private func formattingRunSnapshots(in text: AttributedString) -> [FormattingRunSnapshot] {
        text.runs.compactMap { run in
            snapshot(for: run, in: text)
        }
    }

    private func formattingRunSnapshots(
        in text: AttributedString,
        within range: Range<AttributedString.Index>
    ) -> [FormattingRunSnapshot] {
        text[range].runs.compactMap { run in
            snapshot(for: run, in: text)
        }
    }

    private func snapshot(
        for run: AttributedString.Runs.Run,
        in text: AttributedString
    ) -> FormattingRunSnapshot? {
        guard !run.range.isEmpty else { return nil }
        let lower = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
        let upper = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
        return FormattingRunSnapshot(
            range: lower..<upper,
            state: inlineFormattingState(from: run)
        )
    }

    private struct FormattingRunSnapshot {
        let range: Range<Int>
        let state: InlineFormattingState
    }

    func canToggleCodeBlock(for blockInfo: DocumentBlockInfo) -> Bool {
        guard blockInfo.index != 0 else { return false }
        switch blockInfo.block.type {
        case .title, .paragraph, .heading, .subheading, .codeBlock:
            return true
        default:
            return false
        }
    }
}
