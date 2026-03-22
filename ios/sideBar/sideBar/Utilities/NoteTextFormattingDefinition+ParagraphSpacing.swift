import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NoteTextFormattingDefinition {
    func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter
            )
        }
    }

    func paragraphStyle(
        for range: Range<AttributedString.Index>,
        blockType: NotesSemanticDocument.BlockType,
        noteBlock: String?,
        structuralBoundary: Bool,
        in text: AttributedString
    ) -> NSParagraphStyle {
        if structuralBoundary {
            let previousBlockType = previousBlockType(before: range.lowerBound, in: text)
            let nextBlockType = NoteTextBlockAttribute.blockType(from: noteBlock) ?? blockType
            let boundaryOwner = previousBlockType ?? nextBlockType
            let additionalSpacingAfter: CGFloat
            if previousBlockType == .codeBlock {
                additionalSpacingAfter = NoteTextParagraphMetrics.codeBlockPaddingAfter(
                    baseFontSize: baseFontSize
                )
            } else if nextBlockType == .codeBlock {
                additionalSpacingAfter = NoteTextParagraphMetrics.codeBlockPaddingBefore(
                    baseFontSize: baseFontSize
                )
            } else {
                additionalSpacingAfter = 0
            }
            return paragraphStyle(
                for: boundaryOwner,
                additionalSpacingAfter: additionalSpacingAfter
            )
        }

        let extraSpacingBefore = additionalSpacingBefore(
            for: range,
            blockType: blockType,
            in: text
        )
        let extraSpacingAfter = additionalSpacingAfter(
            for: range,
            blockType: blockType,
            in: text
        )
        if extraSpacingBefore > 0 || extraSpacingAfter > 0 {
            return paragraphStyle(
                for: blockType,
                additionalSpacingBefore: extraSpacingBefore,
                additionalSpacingAfter: extraSpacingAfter
            )
        }
        return paragraphStyle(for: blockType)
    }

    func previousBlockType(
        before index: AttributedString.Index,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType? {
        guard index > text.startIndex else { return nil }
        let previous = text.index(beforeCharacter: index)
        let upper = text.index(afterCharacter: previous)
        return NoteTextBlockResolution.resolvedBlockType(
            for: previous..<upper,
            in: text,
            explicitRawValue: nil
        )
    }

    func nextBlockType(
        after index: AttributedString.Index,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType? {
        guard index < text.endIndex else { return nil }
        let next = text.index(afterCharacter: index)
        return NoteTextBlockAttribute.blockType(from: text[index..<next].runs.first?.noteBlock)
    }

    func additionalSpacingBefore(
        for range: Range<AttributedString.Index>,
        blockType: NotesSemanticDocument.BlockType,
        in text: AttributedString
    ) -> CGFloat {
        guard blockType != .codeBlock,
              containsVisibleCharacters(in: range, text: text),
              isLeadingVisibleRange(range, in: text),
              previousStructuralBoundaryBlockType(before: range.lowerBound, in: text) == .codeBlock else {
            return 0
        }
        return NoteTextParagraphMetrics.codeBlockPaddingAfter(baseFontSize: baseFontSize)
    }

    func additionalSpacingAfter(
        for range: Range<AttributedString.Index>,
        blockType: NotesSemanticDocument.BlockType,
        in text: AttributedString
    ) -> CGFloat {
        guard blockType != .codeBlock,
              containsVisibleCharacters(in: range, text: text),
              isTrailingVisibleRange(range, in: text),
              nextStructuralBoundaryBlockType(after: range.upperBound, in: text) == .codeBlock else {
            return 0
        }
        return NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize)
    }

    func containsVisibleCharacters(
        in range: Range<AttributedString.Index>,
        text: AttributedString
    ) -> Bool {
        text[range].characters.contains { !$0.isNewline }
    }

    func isLeadingVisibleRange(
        _ range: Range<AttributedString.Index>,
        in text: AttributedString
    ) -> Bool {
        var cursor = range.lowerBound
        while cursor > text.startIndex {
            let previous = text.index(beforeCharacter: cursor)
            if isStructuralBoundary(at: previous, in: text) {
                return true
            }
            if !text.characters[previous].isNewline {
                return false
            }
            cursor = previous
        }
        return true
    }

    func isTrailingVisibleRange(
        _ range: Range<AttributedString.Index>,
        in text: AttributedString
    ) -> Bool {
        var cursor = range.upperBound
        while cursor < text.endIndex {
            if isStructuralBoundary(at: cursor, in: text) {
                return true
            }
            if !text.characters[cursor].isNewline {
                return false
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return true
    }

    func previousStructuralBoundaryBlockType(
        before index: AttributedString.Index,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType? {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(beforeCharacter: cursor)
            if isStructuralBoundary(at: previous, in: text) {
                return previousBlockType(before: previous, in: text)
            }
            cursor = previous
        }
        return nil
    }

    func nextStructuralBoundaryBlockType(
        after index: AttributedString.Index,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType? {
        var cursor = index
        while cursor < text.endIndex {
            if isStructuralBoundary(at: cursor, in: text) {
                return nextBlockType(after: cursor, in: text)
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return nil
    }

    func isStructuralBoundary(
        at index: AttributedString.Index,
        in text: AttributedString
    ) -> Bool {
        guard index < text.endIndex else { return false }
        let next = text.index(afterCharacter: index)
        return text[index..<next].runs.first?.noteStructuralBoundary == true
    }
}
