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

    func paragraphStyle(for blockType: NotesSemanticDocument.BlockType) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.paragraphStyle(for: blockType, baseFontSize: baseFontSize)
        default:
            return NoteTextParagraphMetrics.paragraphStyle(for: blockType, baseFontSize: baseFontSize)
        }
    }

    func blockPlainText(_ block: NotesSemanticDocument.Block) -> String {
        block.content.map(\.text).joined()
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
}
