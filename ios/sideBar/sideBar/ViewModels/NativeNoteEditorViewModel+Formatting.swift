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
            let typingState = inlineFormattingState(
                from: selection.typingAttributes(in: attributedContent)
            )
            if typingState.contains(formatting) {
                return true
            }
            return inheritedFormattingStateAtInsertionPoint().contains(formatting)
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
        guard let blockInfo = blockInfoContainingSelectionStart(in: document),
              let style = NoteTextStyle(blockType: blockInfo.block.type) else {
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
        attributedContent = updatedContent
        selection = selection(from: selectionSnapshot, in: updatedContent)
    }

    @discardableResult
    func handleReturnKey() -> Bool {
        guard !isReadOnly else { return false }
        guard case .insertionPoint = selection.indices(in: attributedContent) else { return false }

        let document = currentPersistenceSnapshot().document
        guard let blockInfo = blockInfoContainingSelectionStart(in: document) else { return false }

        let blockText = blockPlainText(blockInfo.block)
        let selectionOffset = max(
            0,
            min(
                selectionStartCharacterOffset(in: attributedContent) - blockInfo.range.lowerBound,
                blockText.count
            )
        )

        let mutation: ReturnKeyMutation?
        switch blockInfo.block.type {
        case .title, .heading, .subheading, .paragraph:
            mutation = splitTextStyleBlock(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset
            )
        case .codeBlock:
            mutation = mutateCodeBlockReturn(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset,
                blockText: blockText
            )
        default:
            mutation = nil
        }

        guard let mutation else { return false }
        applyDocumentMutation(
            mutation.document,
            insertionCharacterOffset: mutation.insertionOffset,
            typingBlockType: mutation.typingBlockType
        )
        return true
    }

    func toggleFormatting(_ formatting: NoteFormatting) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let enabled = !inlineFormattingState(
                from: selection.typingAttributes(in: attributedContent)
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
        guard !nonEmptyRanges.isEmpty else {
            transformSelectionAttributes { attrs in
                var state = inlineFormattingState(from: attrs)
                state.set(formatting, enabled: enabled)
                applyInlineFormattingState(state, to: &attrs)
                attrs.paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                    baseFontSize: baseFontSize
                )
            }
            return
        }

        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var updatedSelection = selection
        attributedContent.transformAttributes(in: &updatedSelection) { attrs in
            var state = inlineFormattingState(from: attrs)
            state.set(formatting, enabled: enabled)
            applyInlineFormattingState(state, to: &attrs)
            attrs.paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize
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

    private func inheritedFormattingStateAtInsertionPoint() -> InlineFormattingState {
        let insertionIndex: AttributedString.Index?
        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            insertionIndex = index
        case .ranges(let ranges):
            insertionIndex = ranges.ranges.first?.lowerBound
        }

        guard let insertionIndex,
              insertionIndex > attributedContent.startIndex else {
            return .plain
        }

        let previousIndex = attributedContent.index(beforeCharacter: insertionIndex)
        let previousRange = previousIndex..<insertionIndex
        let runSnapshots = formattingRunSnapshots(in: attributedContent, within: previousRange)
        return runSnapshots.first?.state ?? .plain
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

    private struct DocumentBlockInfo {
        let index: Int
        let block: NotesSemanticDocument.Block
        let range: Range<Int>
        let coverageRange: Range<Int>
    }

    private func documentBlockInfos(in document: NotesSemanticDocument) -> [DocumentBlockInfo] {
        var infos: [DocumentBlockInfo] = []
        var cursor = 0

        for (index, block) in document.blocks.enumerated() {
            let blockText = NotesSemanticDocumentProjection.plainText(
                from: NotesSemanticDocument(blocks: [block])
            )
            let range = cursor..<(cursor + blockText.count)
            let coverageUpperBound = index < document.blocks.count - 1
                ? cursor + blockText.count + 1
                : cursor + blockText.count
            infos.append(
                DocumentBlockInfo(
                    index: index,
                    block: block,
                    range: range,
                    coverageRange: cursor..<coverageUpperBound
                )
            )
            cursor = coverageUpperBound
        }

        return infos
    }

    private func blockInfoContainingSelectionStart(
        in document: NotesSemanticDocument
    ) -> DocumentBlockInfo? {
        let infos = documentBlockInfos(in: document)
        guard let lastInfo = infos.last else { return nil }
        let offset = selectionStartCharacterOffset(in: attributedContent)

        if offset >= lastInfo.coverageRange.upperBound {
            return lastInfo
        }

        return infos.first { info in
            if info.coverageRange.isEmpty {
                return offset == info.coverageRange.lowerBound
            }
            return info.coverageRange.contains(offset)
        }
    }

    private func touchedBlockInfos(
        in document: NotesSemanticDocument
    ) -> [DocumentBlockInfo] {
        let infos = documentBlockInfos(in: document)
        guard !infos.isEmpty else { return [] }

        var touchedIndexes = Set<Int>()
        let selectionRanges = selectionCharacterRanges(in: attributedContent)

        for selectionRange in selectionRanges {
            if selectionRange.isEmpty {
                if let blockInfo = blockInfoContainingSelectionStart(in: document) {
                    touchedIndexes.insert(blockInfo.index)
                }
                continue
            }

            for info in infos where rangesOverlap(selectionRange, info.coverageRange) {
                touchedIndexes.insert(info.index)
            }
        }

        return infos.filter { touchedIndexes.contains($0.index) }
    }

    private func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private func applyDocumentMutation(
        _ document: NotesSemanticDocument,
        insertionCharacterOffset: Int,
        typingBlockType: NotesSemanticDocument.BlockType
    ) {
        let previousContent = attributedContent
        let previousSelection = selection
        var updatedContent = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        constrainEditorDocument(&updatedContent)
        attributedContent = updatedContent
        let insertionIndex = index(forCharacterOffset: insertionCharacterOffset, in: updatedContent)
        selection = AttributedTextSelection(range: insertionIndex..<insertionIndex)
        applyTypingAttributes(for: typingBlockType)
        handleContentChange(previous: previousContent)
        if selection != previousSelection {
            handleSelectionChange()
        }
    }

    private func splitTextStyleBlock(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int
    ) -> ReturnKeyMutation {
        let split = splitInlineSegments(blockInfo.block.content, at: selectionOffset)
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = .init(
            type: blockInfo.block.type,
            content: normalizedInlineSegments(split.leading),
            checked: blockInfo.block.checked
        )
        updatedBlocks.insert(
            .paragraph(normalizedInlineSegments(split.trailing)),
            at: blockInfo.index + 1
        )
        let insertionOffset = blockInfo.range.lowerBound + inlineTextLength(split.leading) + 1
        return ReturnKeyMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: insertionOffset,
            typingBlockType: .paragraph
        )
    }

    private func mutateCodeBlockReturn(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int,
        blockText: String
    ) -> ReturnKeyMutation {
        var updatedBlocks = document.blocks
        if selectionOffset == blockText.count, blockText.hasSuffix("\n") {
            updatedBlocks.insert(
                .paragraph([.init(text: "", marks: [])]),
                at: blockInfo.index + 1
            )
            let insertionOffset = blockInfo.range.lowerBound + blockText.count + 1
            return ReturnKeyMutation(
                document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
                insertionOffset: insertionOffset,
                typingBlockType: .paragraph
            )
        }

        let stringIndex = blockText.index(blockText.startIndex, offsetBy: selectionOffset)
        let updatedText = String(blockText[..<stringIndex]) + "\n" + String(blockText[stringIndex...])
        updatedBlocks[blockInfo.index] = .init(
            type: .codeBlock,
            content: [.init(text: updatedText, marks: [])],
            checked: blockInfo.block.checked
        )
        return ReturnKeyMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: blockInfo.range.lowerBound + selectionOffset + 1,
            typingBlockType: .codeBlock
        )
    }

}
