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
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter,
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
                additionalSpacingBefore: additionalSpacingBefore,
                additionalSpacingAfter: additionalSpacingAfter,
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
}
