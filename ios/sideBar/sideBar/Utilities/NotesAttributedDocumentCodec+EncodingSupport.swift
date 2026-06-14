import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func blockMarker(
        for blockType: NotesSemanticDocument.BlockType
    ) -> String? {
        switch blockType {
        case .title,
             .paragraph,
             .heading,
             .subheading,
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

    static func blockFont(
        baseFontSize: CGFloat,
        blockType: NotesSemanticDocument.BlockType,
        bold: Bool,
        italic: Bool,
        inlineCode: Bool = false
    ) -> Font {
        noteEditorInlineFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: bold,
            italic: italic,
            inlineCode: inlineCode
        )
    }

    static func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        previousBlockType: NotesSemanticDocument.BlockType? = nil,
        nextBlockType: NotesSemanticDocument.BlockType? = nil,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0,
        includesBlockSpacing: Bool = true
    ) -> NSParagraphStyle {
        NoteBlockLayout.paragraphStyle(
            for: blockType,
            context: NoteBlockLayoutContext(
                baseFontSize: baseFontSize,
                previousBlockType: previousBlockType,
                nextBlockType: nextBlockType,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter
            ),
            includesBlockSpacing: includesBlockSpacing
        )
    }
}
