@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct DocumentBlockInfo {
        let index: Int
        let block: NotesSemanticDocument.Block
        let range: Range<Int>
        let coverageRange: Range<Int>
    }

    struct StructuralReplacementMutation {
        let document: NotesSemanticDocument
        let insertionOffset: Int
        let typingBlockType: NotesSemanticDocument.BlockType
    }

    func shouldHandleStructuralTextReplacement(_ replacementText: String) -> Bool {
        guard !isReadOnly else { return false }
        if replacementText.contains("\n") {
            return true
        }

        guard let selectionRange = primarySelectionCharacterRange(in: attributedContent) else {
            return false
        }
        let document = currentPersistenceSnapshot().document
        if replacementText.isEmpty,
           selectionRange.isEmpty,
           structuralDeleteBackwardMutation(in: document) != nil {
            return true
        }
        return listTypingTriggerMutation(
            in: document,
            selectionRange: selectionRange,
            replacementText: replacementText
        ) != nil
    }

    @discardableResult
    func handleTextReplacement(_ replacementText: String) -> Bool {
        guard shouldHandleStructuralTextReplacement(replacementText) else { return false }

        guard let selectionRange = primarySelectionCharacterRange(in: attributedContent) else { return false }
        let document = currentPersistenceSnapshot().document

        if let mutation = listTypingTriggerMutation(
            in: document,
            selectionRange: selectionRange,
            replacementText: replacementText
        ) {
            applyDocumentMutation(
                mutation.document,
                insertionCharacterOffset: mutation.insertionOffset,
                typingBlockType: mutation.typingBlockType
            )
            return true
        }

        if selectionRange.isEmpty, replacementText == "\n" {
            return handleReturnKey()
        }
        if selectionRange.isEmpty, replacementText.isEmpty {
            return handleDeleteBackwardKey()
        }

        guard let mutation = replacementMutation(
            in: document,
            selectionRange: selectionRange,
            replacementText: replacementText
        ) else { return false }

        applyDocumentMutation(
            mutation.document,
            insertionCharacterOffset: mutation.insertionOffset,
            typingBlockType: mutation.typingBlockType
        )
        return true
    }

    @discardableResult
    func handleDeleteBackwardKey() -> Bool {
        guard !isReadOnly else { return false }
        let document = currentPersistenceSnapshot().document
        guard let mutation = structuralDeleteBackwardMutation(in: document) else {
            return false
        }

        applyDocumentMutation(
            mutation.document,
            insertionCharacterOffset: mutation.insertionOffset,
            typingBlockType: mutation.typingBlockType
        )
        return true
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

        let mutation: StructuralReplacementMutation?
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
        case .unorderedList, .orderedList, .checklist:
            mutation = mutateListReturn(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset,
                blockText: blockText
            )
        case .blockquote:
            mutation = mutateBlockquoteReturn(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset
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

    func documentBlockInfos(in document: NotesSemanticDocument) -> [DocumentBlockInfo] {
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

    func blockInfoContainingSelectionStart(
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

    func touchedBlockInfos(
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

    func applyDocumentMutation(
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

    private func replacementMutation(
        in document: NotesSemanticDocument,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation? {
        guard let startBlockInfo = blockInfoContainingCharacterOffset(
            selectionRange.lowerBound,
            in: document
        ) else { return nil }

        let trailingOffset = selectionRange.isEmpty
            ? selectionRange.lowerBound
            : max(selectionRange.lowerBound, selectionRange.upperBound - 1)
        guard let endBlockInfo = blockInfoContainingCharacterOffset(
            trailingOffset,
            in: document
        ) else { return nil }

        if startBlockInfo.block.type == .codeBlock, startBlockInfo.index == endBlockInfo.index {
            return replaceTextInsideCodeBlock(
                in: document,
                blockInfo: startBlockInfo,
                selectionRange: selectionRange,
                replacementText: replacementText
            )
        }
        if startBlockInfo.index == endBlockInfo.index {
            switch startBlockInfo.block.type {
            case .unorderedList, .orderedList, .checklist:
                return replaceTextInsideListContainer(
                    in: document,
                    blockInfo: startBlockInfo,
                    selectionRange: selectionRange,
                    replacementText: replacementText
                )
            case .blockquote:
                return replaceTextInsideBlockquote(
                    in: document,
                    blockInfo: startBlockInfo,
                    selectionRange: selectionRange,
                    replacementText: replacementText
                )
            default:
                break
            }
        }

        switch startBlockInfo.block.type {
        case .title, .heading, .subheading, .paragraph:
            return replaceTextAcrossTextStyleBlocks(
                in: document,
                startBlockInfo: startBlockInfo,
                endBlockInfo: endBlockInfo,
                selectionRange: selectionRange,
                replacementText: replacementText
            )
        default:
            return nil
        }
    }

    private func splitTextStyleBlock(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int
    ) -> StructuralReplacementMutation {
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
        return StructuralReplacementMutation(
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
    ) -> StructuralReplacementMutation {
        var updatedBlocks = document.blocks
        if selectionOffset == blockText.count, blockText.hasSuffix("\n") {
            updatedBlocks.insert(
                .paragraph([.init(text: "", marks: [])]),
                at: blockInfo.index + 1
            )
            let insertionOffset = blockInfo.range.lowerBound + blockText.count + 1
            return StructuralReplacementMutation(
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
        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: blockInfo.range.lowerBound + selectionOffset + 1,
            typingBlockType: .codeBlock
        )
    }

    private func replaceTextAcrossTextStyleBlocks(
        in document: NotesSemanticDocument,
        startBlockInfo: DocumentBlockInfo,
        endBlockInfo: DocumentBlockInfo,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation {
        let startOffset = max(
            0,
            min(selectionRange.lowerBound - startBlockInfo.range.lowerBound, blockPlainText(startBlockInfo.block).count)
        )
        let endOffset = max(
            0,
            min(selectionRange.upperBound - endBlockInfo.range.lowerBound, blockPlainText(endBlockInfo.block).count)
        )

        let leadingSegments: [NotesSemanticDocument.InlineSegment]
        let trailingSegments: [NotesSemanticDocument.InlineSegment]
        if startBlockInfo.index == endBlockInfo.index {
            let leadingSplit = splitInlineSegments(startBlockInfo.block.content, at: startOffset)
            let trailingSplit = splitInlineSegments(leadingSplit.trailing, at: max(0, endOffset - startOffset))
            leadingSegments = leadingSplit.leading
            trailingSegments = trailingSplit.trailing
        } else {
            leadingSegments = splitInlineSegments(startBlockInfo.block.content, at: startOffset).leading
            trailingSegments = splitInlineSegments(endBlockInfo.block.content, at: endOffset).trailing
        }

        let insertedMarks = inlineMarksForStructuralInsertion()
        let lines = replacementText.components(separatedBy: "\n")
        let firstType = startBlockInfo.block.type
        var replacementBlocks: [NotesSemanticDocument.Block] = []

        var firstContent = leadingSegments
        appendSegmentText(lines.first ?? "", marks: insertedMarks, to: &firstContent)
        if lines.count == 1 {
            appendSegments(trailingSegments, to: &firstContent)
            replacementBlocks.append(
                .init(
                    type: firstType,
                    content: normalizedInlineSegments(firstContent),
                    checked: startBlockInfo.block.checked
                )
            )
        } else {
            replacementBlocks.append(
                .init(
                    type: firstType,
                    content: normalizedInlineSegments(firstContent),
                    checked: startBlockInfo.block.checked
                )
            )
            for middleLine in lines.dropFirst().dropLast() {
                var content: [NotesSemanticDocument.InlineSegment] = []
                appendSegmentText(middleLine, marks: insertedMarks, to: &content)
                replacementBlocks.append(.paragraph(normalizedInlineSegments(content)))
            }

            var lastContent: [NotesSemanticDocument.InlineSegment] = []
            appendSegmentText(lines.last ?? "", marks: insertedMarks, to: &lastContent)
            appendSegments(trailingSegments, to: &lastContent)
            replacementBlocks.append(.paragraph(normalizedInlineSegments(lastContent)))
        }

        var updatedBlocks = Array(document.blocks[..<startBlockInfo.index])
        updatedBlocks.append(contentsOf: replacementBlocks)
        if endBlockInfo.index + 1 < document.blocks.count {
            updatedBlocks.append(contentsOf: document.blocks[(endBlockInfo.index + 1)...])
        }

        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: selectionRange.lowerBound + replacementText.count,
            typingBlockType: lines.count > 1 ? .paragraph : firstType
        )
    }

    private func replaceTextInsideCodeBlock(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation {
        let blockText = blockPlainText(blockInfo.block)
        let startOffset = max(
            0,
            min(selectionRange.lowerBound - blockInfo.range.lowerBound, blockText.count)
        )
        let endOffset = max(
            0,
            min(selectionRange.upperBound - blockInfo.range.lowerBound, blockText.count)
        )
        let startIndex = blockText.index(blockText.startIndex, offsetBy: startOffset)
        let endIndex = blockText.index(blockText.startIndex, offsetBy: endOffset)
        let updatedText = String(blockText[..<startIndex]) + replacementText + String(blockText[endIndex...])

        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = .init(
            type: .codeBlock,
            content: [.init(text: updatedText, marks: [])],
            checked: blockInfo.block.checked
        )

        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: selectionRange.lowerBound + replacementText.count,
            typingBlockType: .codeBlock
        )
    }

}
