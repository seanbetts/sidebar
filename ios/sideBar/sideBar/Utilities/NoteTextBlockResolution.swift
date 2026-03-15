import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextBlockResolution {
    static func resolvedBlockType(
        for run: AttributedString.Runs.Run,
        in text: AttributedString,
        semanticFallback: NotesSemanticDocument.BlockType? = nil
    ) -> NotesSemanticDocument.BlockType {
        if let explicit = NoteTextBlockAttribute.blockType(from: run.noteBlock) {
            return explicit
        }
        if let semanticFallback {
            return semanticFallback
        }
        if let lineOwnedBlockType = lineOwnedBlockType(for: run, in: text) {
            return lineOwnedBlockType
        }
        return positionalFallback(for: run, in: text)
    }

    static func resolvedBlockType(
        explicitRawValue: String?,
        semanticFallback: NotesSemanticDocument.BlockType? = nil
    ) -> NotesSemanticDocument.BlockType? {
        if let explicit = NoteTextBlockAttribute.blockType(from: explicitRawValue) {
            return explicit
        }
        return semanticFallback
    }

    static func resolvedDecodedBlockType(
        explicitBlockType: NotesSemanticDocument.BlockType?,
        hasExistingBlocks: Bool
    ) -> NotesSemanticDocument.BlockType {
        guard hasExistingBlocks else {
            switch explicitBlockType {
            case .none, .title, .paragraph, .heading, .subheading:
                return .title
            case .some(let explicitBlockType):
                return explicitBlockType
            }
        }
        return explicitBlockType ?? .paragraph
    }

    private static func lineOwnedBlockType(
        for run: AttributedString.Runs.Run,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType? {
        let lineRange = lineRange(containing: run.range, in: text)
        for lineRun in text[lineRange].runs {
            if let explicit = NoteTextBlockAttribute.blockType(from: lineRun.noteBlock) {
                return explicit
            }
        }
        return nil
    }

    private static func positionalFallback(
        for run: AttributedString.Runs.Run,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType {
        let prefix = text[text.startIndex..<run.range.lowerBound]
        return prefix.characters.contains(where: \.isNewline) ? .paragraph : .title
    }

    private static func lineRange(
        containing range: Range<AttributedString.Index>,
        in text: AttributedString
    ) -> Range<AttributedString.Index> {
        var lower = range.lowerBound
        while lower > text.startIndex {
            let previous = text.index(beforeCharacter: lower)
            if text.characters[previous].isNewline {
                lower = previous
                break
            }
            lower = previous
        }

        var upper = range.upperBound
        while upper < text.endIndex {
            if text.characters[upper].isNewline {
                break
            }
            upper = text.index(afterCharacter: upper)
        }

        return lower..<upper
    }
}
