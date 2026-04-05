@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func applyTypingAttributes(for blockType: NotesSemanticDocument.BlockType) {
        transformSelectionAttributes { attrs in
            applySemanticTypingAttributes(
                blockType: blockType,
                inlineState: .plain,
                to: &attrs
            )
        }
    }

    func blockMarker(for blockType: NotesSemanticDocument.BlockType) -> String? {
        switch blockType {
        case .title,
             .paragraph,
             .heading,
             .subheading,
             .divider,
             .unorderedList,
             .orderedList,
             .checklist,
             .listItem,
             .blockquote,
             .codeBlock:
            return blockType.rawValue
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return nil
        }
    }

    func canInsertDivider() -> Bool {
        guard !isReadOnly else { return false }
        let document = currentPersistenceSnapshot().document
        return blockInfoContainingSelectionStart(in: document) != nil
    }

    func isDividerActive() -> Bool {
        let document = currentPersistenceSnapshot().document
        let touchedBlocks = touchedBlockInfos(in: document)
        if !touchedBlocks.isEmpty, touchedBlocks.allSatisfy({ $0.block.type == .divider }) {
            return true
        }
        guard case .insertionPoint(let offset) = selectionSnapshot(in: attributedContent),
              let blockInfo = blockInfoContainingCharacterOffset(offset, in: document),
              blockInfo.block.type == .paragraph,
              blockInfo.index > 0,
              blockPlainText(blockInfo.block).isEmpty,
              document.blocks[blockInfo.index - 1].type == .divider,
              offset == blockInfo.range.lowerBound else {
            return false
        }
        return true
    }

    func paragraphStyle(for blockType: NotesSemanticDocument.BlockType) -> NSParagraphStyle {
        switch blockType {
        case .divider:
            return NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize)
        case .unorderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .orderedList:
            let contentIndent = NoteTextParagraphMetrics.orderedListContentIndent(
                baseFontSize: baseFontSize
            )
            let markerIndent = NoteTextParagraphMetrics.orderedListMarkerIndent(
                baseFontSize: baseFontSize
            )
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: contentIndent,
                firstLineHeadIndent: markerIndent,
                tabStops: [
                    NSTextTab(textAlignment: .left, location: contentIndent)
                ],
                defaultTabInterval: contentIndent
            )
        case .blockquote:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.paragraphStyle(for: blockType, baseFontSize: baseFontSize)
        }
    }

    func blockPlainText(_ block: NotesSemanticDocument.Block) -> String {
        NotesSemanticDocumentProjection.plainText(
            from: NotesSemanticDocument(blocks: [block])
        )
    }

    func inlineTextLength(_ content: [NotesSemanticDocument.InlineSegment]) -> Int {
        content.reduce(0) { $0 + $1.text.count }
    }

    func normalizedInlineSegments(
        _ segments: [NotesSemanticDocument.InlineSegment]
    ) -> [NotesSemanticDocument.InlineSegment] {
        segments.isEmpty ? [.init(text: "", marks: [])] : segments
    }

    func splitInlineSegments(
        _ content: [NotesSemanticDocument.InlineSegment],
        at offset: Int
    ) -> (leading: [NotesSemanticDocument.InlineSegment], trailing: [NotesSemanticDocument.InlineSegment]) {
        var remaining = offset
        var leading: [NotesSemanticDocument.InlineSegment] = []
        var trailing: [NotesSemanticDocument.InlineSegment] = []

        for segment in content {
            let textCount = segment.text.count
            guard textCount > 0 else {
                if remaining == 0 {
                    trailing.append(segment)
                } else {
                    leading.append(segment)
                }
                continue
            }

            if remaining <= 0 {
                trailing.append(segment)
                continue
            }

            if remaining >= textCount {
                leading.append(segment)
                remaining -= textCount
                continue
            }

            let splitIndex = segment.text.index(segment.text.startIndex, offsetBy: remaining)
            let leadingText = String(segment.text[..<splitIndex])
            let trailingText = String(segment.text[splitIndex...])
            if !leadingText.isEmpty {
                leading.append(.init(text: leadingText, marks: segment.marks, link: segment.link))
            }
            if !trailingText.isEmpty {
                trailing.append(.init(text: trailingText, marks: segment.marks, link: segment.link))
            }
            remaining = 0
        }

        return (leading, trailing)
    }

    func insertDivider() {
        guard canInsertDivider() else { return }
        let document = currentPersistenceSnapshot().document
        guard let blockInfo = blockInfoContainingSelectionStart(in: document) else { return }

        let replacementBlocks: [NotesSemanticDocument.Block]
        switch blockInfo.block.type {
        case .title, .paragraph, .heading, .subheading, .codeBlock:
            let selectionOffset = max(
                0,
                min(
                    selectionStartCharacterOffset(in: attributedContent) - blockInfo.range.lowerBound,
                    blockPlainText(blockInfo.block).count
                )
            )
            let split = splitInlineSegments(blockInfo.block.content, at: selectionOffset)
            replacementBlocks = dividerReplacementBlocks(
                for: blockInfo.block,
                leadingSegments: split.leading,
                trailingSegments: split.trailing,
                preserveLeadingWhenEmpty: blockInfo.index == 0
            )
        case .divider, .unorderedList, .orderedList, .checklist, .blockquote:
            replacementBlocks = [
                blockInfo.block,
                .init(type: .divider),
                .paragraph([.init(text: "", marks: [])])
            ]
        default:
            return
        }

        var updatedBlocks = document.blocks
        updatedBlocks.replaceSubrange(blockInfo.index...blockInfo.index, with: replacementBlocks)
        let updatedDocument = NotesSemanticDocument(version: document.version, blocks: updatedBlocks)
        let insertionBlockIndex = blockInfo.index + replacementBlocks.count - 1
        let insertionOffset = documentBlockInfos(in: updatedDocument)[insertionBlockIndex].range.lowerBound
        applyDocumentMutation(
            updatedDocument,
            insertionCharacterOffset: insertionOffset,
            typingBlockType: .paragraph
        )
    }

    private func dividerReplacementBlocks(
        for sourceBlock: NotesSemanticDocument.Block,
        leadingSegments: [NotesSemanticDocument.InlineSegment],
        trailingSegments: [NotesSemanticDocument.InlineSegment],
        preserveLeadingWhenEmpty: Bool
    ) -> [NotesSemanticDocument.Block] {
        var blocks: [NotesSemanticDocument.Block] = []
        if preserveLeadingWhenEmpty || !leadingSegments.isEmpty {
            blocks.append(
                .init(
                    type: sourceBlock.type,
                    content: normalizedInlineSegments(leadingSegments),
                    checked: sourceBlock.checked
                )
            )
        }
        blocks.append(.init(type: .divider))
        blocks.append(.paragraph(normalizedInlineSegments(trailingSegments)))
        return blocks
    }
}
